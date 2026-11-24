package com.bucks.app.ai

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.bucks.app.BuildConfig
import com.bucks.app.data.AppLife
import com.bucks.app.data.Backend
import com.bucks.app.data.settingValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Delivery of the Tier 1 intent model (285 MB, never inside the APK).
 *
 * - Off unless the server's `settings` row `intent_tier1_enabled` is 1 (read like the other settings rows; the last value read is
 *   kept so the switch also holds offline). An explicit 0 also deletes a downloaded copy, so the row is a kill switch.
 * - Downloads only on an unmetered network (Wi-Fi), or on mobile data when the person turned that on in Settings > Voice.
 * - Resumes a partial download, checks the SHA-256 ([BuildConfig.INTENT_MODEL_SHA256]) before the file is used, and keeps it in the
 *   app's own files (removed with the app; the app has allowBackup off).
 * - Without the model everything works as before: rules, then classic search.
 */
object IntentModel {
    enum class Status { OFF, WAITING_WIFI, DOWNLOADING, READY, FAILED }

    var status by mutableStateOf(Status.OFF); private set
    /** 0..1 while [Status.DOWNLOADING]. */
    var progress by mutableStateOf(0f); private set
    /** The person allowed the download on mobile data (Settings > Voice). */
    var allowMobileData by mutableStateOf(false); private set

    private const val FLAG = "intent_tier1_enabled"
    private const val PREFS = "intent_model"
    /** Free space wanted beyond the file itself, so the download never fills the phone. */
    private const val SPARE_BYTES = 200L * 1024 * 1024
    private var ctx: Context? = null
    private var job: Job? = null
    private var engine: FunctionGemmaIntentEngine? = null

    private val fileName get() = BuildConfig.INTENT_MODEL_URL.substringAfterLast('/').substringBefore('?').ifBlank { "intent.litertlm" }
    private fun dir(c: Context) = File(c.filesDir, "models").apply { mkdirs() }
    private fun file(c: Context) = File(dir(c), fileName)
    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val configured get() = BuildConfig.INTENT_MODEL_URL.startsWith("https://") && BuildConfig.INTENT_MODEL_SHA256.length == 64

    /** Called once from the Application: restores the last known state without touching the network. */
    fun init(c: Context) {
        ctx = c.applicationContext
        val p = prefs(c); allowMobileData = p.getBoolean("mobileData", false)
        status = when { !configured || !p.getBoolean("enabled", false) -> Status.OFF; file(c).exists() && p.getString("verified", null) == fileName -> Status.READY; else -> Status.WAITING_WIFI }
    }

    /** The engine for [IntentRouter], or null while the model is off or not downloaded and verified. */
    fun engine(): IntentEngine? {
        val c = ctx ?: return null
        if (status != Status.READY) return null
        return engine ?: FunctionGemmaIntentEngine(file(c), c.assets.open("intent_tools.json").bufferedReader().use { it.readText() }, c.cacheDir).also { engine = it }
    }
    /** True when free-form commands can reach the on-device model. */
    val ready get() = status == Status.READY && engine?.broken != true

    fun setAllowMobileData(on: Boolean) { val c = ctx ?: return; allowMobileData = on; prefs(c).edit().putBoolean("mobileData", on).apply(); if (on) refresh() }

    /**
     * Reads the remote switch (cloud builds, signed in) and starts or resumes the download when allowed. Safe to call often:
     * at most one download runs. Called when the app opens and when Settings > Voice is shown.
     */
    fun refresh() {
        val c = ctx ?: return
        if (!configured) { status = Status.OFF; return }
        if (job?.isActive == true) return
        job = AppLife.scope.launch {
            val flag = if (Backend.enabled) runCatching { Backend.settingValue(FLAG) }.getOrNull() else null
            val p = prefs(c)
            if (flag != null) p.edit().putBoolean("enabled", flag >= 1.0).apply()
            if (!p.getBoolean("enabled", false)) {
                if (flag != null) remove(c)   // an explicit 0 is the kill switch
                status = Status.OFF; return@launch
            }
            val f = file(c)
            if (f.exists() && p.getString("verified", null) == fileName) { status = Status.READY; return@launch }
            if (!allowedNetwork(c)) { status = Status.WAITING_WIFI; return@launch }
            status = Status.DOWNLOADING
            status = if (download(c, f)) { p.edit().putString("verified", fileName).apply(); Status.READY } else if (allowedNetwork(c)) Status.FAILED else Status.WAITING_WIFI
        }
    }

    private fun remove(c: Context) {
        engine = null
        dir(c).listFiles()?.forEach { it.delete() }
        prefs(c).edit().remove("verified").apply()
    }

    private fun allowedNetwork(c: Context): Boolean {
        val cm = c.getSystemService(ConnectivityManager::class.java) ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return false
        return allowMobileData || caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    /** Downloads into `<name>.part` (resuming it), checks the SHA-256, then renames. False on any failure; the part file is kept to resume. */
    private suspend fun download(c: Context, dest: File): Boolean = withContext(Dispatchers.IO) {
        // Older models (another file name) go first.
        dir(c).listFiles()?.filter { it.name != dest.name && it.name != dest.name + ".part" }?.forEach { it.delete() }
        val part = File(dest.parentFile, dest.name + ".part")
        runCatching {
            val have = if (part.exists()) part.length() else 0L
            val conn = (URL(BuildConfig.INTENT_MODEL_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000; readTimeout = 30_000
                if (have > 0) setRequestProperty("Range", "bytes=$have-")
            }
            try {
                val code = conn.responseCode
                val resumed = code == HttpURLConnection.HTTP_PARTIAL && have > 0
                if (code != HttpURLConnection.HTTP_OK && !resumed) return@runCatching false
                val total = (if (resumed) have else 0L) + conn.contentLengthLong.coerceAtLeast(0)
                if (total > 0 && dir(c).usableSpace < (total - (if (resumed) have else 0L)) + SPARE_BYTES) return@runCatching false
                val sha = MessageDigest.getInstance("SHA-256")
                if (resumed) FileInputStream(part).use { input -> val buf = ByteArray(1 shl 16); while (true) { val n = input.read(buf); if (n < 0) break; sha.update(buf, 0, n) } }
                var done = if (resumed) have else 0L
                conn.inputStream.use { input -> FileOutputStream(part, resumed).use { out ->
                    val buf = ByteArray(1 shl 16)
                    while (isActive) {
                        // Stop (and resume later) if Wi-Fi went away and mobile data isn't allowed.
                        if (done % (8L shl 20) < buf.size && !allowedNetwork(c)) return@runCatching false
                        val n = input.read(buf); if (n < 0) break
                        out.write(buf, 0, n); sha.update(buf, 0, n); done += n
                        if (total > 0) progress = (done.toFloat() / total).coerceIn(0f, 1f)
                    }
                } }
                val hex = sha.digest().joinToString("") { "%02x".format(it) }
                if (!hex.equals(BuildConfig.INTENT_MODEL_SHA256, ignoreCase = true)) { part.delete(); return@runCatching false }
                dest.delete(); part.renameTo(dest)
            } finally { conn.disconnect() }
        }.getOrDefault(false)
    }
}
