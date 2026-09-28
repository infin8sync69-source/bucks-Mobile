package com.bucks.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import com.bucks.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Test builds only ([enabled]): finds a newer build of this branch on GitHub Releases ("build-N", published by CI) and
 * installs it through the system installer. Play builds never update themselves (Play policy); they use Play's own updates.
 * Updates only install over the running app when both carry the same signature: see scripts/setup-pilot-signing.sh.
 */
object AppUpdate {
    data class Release(val build: Int, val notes: String, val apkUrl: String, val size: Long, val page: String)

    val enabled: Boolean get() = BuildConfig.SELF_UPDATE
    val currentBuild: Int get() = BuildConfig.BUILD_NUMBER
    private val json = Json { ignoreUnknownKeys = true }

    /** The newest release of this branch that is newer than the installed build, or null. Throws on network errors. */
    suspend fun latest(): Release? = withContext(Dispatchers.IO) {
        val c = URL("https://api.github.com/repos/${BuildConfig.UPDATE_REPO}/releases?per_page=30").openConnection() as HttpURLConnection
        c.connectTimeout = 10_000; c.readTimeout = 15_000
        c.setRequestProperty("Accept", "application/vnd.github+json"); c.setRequestProperty("User-Agent", "Bucks-Android")
        try {
            if (c.responseCode != 200) throw IOException("GitHub answered ${c.responseCode}")
            val all = json.parseToJsonElement(c.inputStream.bufferedReader().use { it.readText() }) as JsonArray
            all.mapNotNull { e -> (e as? JsonObject)?.let(::parse) }.filter { it.build > currentBuild }.maxByOrNull { it.build }
        } finally { c.disconnect() }
    }

    private fun parse(r: JsonObject): Release? {
        fun s(k: String) = r[k]?.jsonPrimitive?.contentOrNull
        if (r["draft"]?.jsonPrimitive?.booleanOrNull == true) return null
        val build = s("tag_name")?.removePrefix("build-")?.toIntOrNull() ?: return null
        // CI names releases "Test build N (branch)": only offer builds of the branch this one came from.
        val branch = BuildConfig.BUILD_BRANCH
        if (branch.isNotBlank() && s("name")?.endsWith("($branch)") != true) return null
        val apk = (r["assets"] as? JsonArray)?.mapNotNull { it as? JsonObject }?.firstOrNull { it["name"]?.jsonPrimitive?.contentOrNull?.endsWith(".apk") == true } ?: return null
        return Release(build, s("body").orEmpty().trim(), apk["browser_download_url"]?.jsonPrimitive?.contentOrNull ?: return null,
            apk["size"]?.jsonPrimitive?.longOrNull ?: 0L, s("html_url").orEmpty())
    }

    /** Downloads the APK into cache/updates (older downloads are removed), reporting 0..1. Checks the size GitHub announced. */
    suspend fun download(ctx: Context, r: Release, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(ctx.cacheDir, "updates").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val out = File(dir, "bucks-${r.build}.apk")
        val c = URL(r.apkUrl).openConnection() as HttpURLConnection   // follows GitHub's redirect to its file host (https -> https)
        c.connectTimeout = 15_000; c.readTimeout = 30_000; c.setRequestProperty("User-Agent", "Bucks-Android")
        try {
            if (c.responseCode != 200) throw IOException("Download failed (${c.responseCode})")
            val total = if (r.size > 0) r.size else c.contentLengthLong
            c.inputStream.use { input -> out.outputStream().use { o ->
                val buf = ByteArray(64 * 1024); var done = 0L
                while (true) { val n = input.read(buf); if (n < 0) break; o.write(buf, 0, n); done += n; if (total > 0) onProgress((done.toFloat() / total).coerceIn(0f, 1f)) }
            } }
            if (r.size > 0 && out.length() != r.size) { out.delete(); throw IOException("The download was incomplete. Try again.") }
            out
        } finally { c.disconnect() }
    }

    /** Android asks once whether Bucks may install apps; until then the install goes to that settings page instead. */
    fun canInstall(ctx: Context) = ctx.packageManager.canRequestPackageInstalls()
    fun openInstallPermission(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    /** Hands the APK to the system installer, which shows its own "Update" confirmation. */
    fun install(ctx: Context, apk: File) {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", apk)
        ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
