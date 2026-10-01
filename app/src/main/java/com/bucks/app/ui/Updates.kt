package com.bucks.app.ui

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.AppUpdate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.io.File

/**
 * One-tap updates for test builds (see [AppUpdate]). Checks at most every 6 hours on start, or on demand from Settings;
 * "Later" hides a build until a newer one appears or the person checks by hand.
 */
class Updates(private val scope: CoroutineScope, private val toast: (String) -> Unit) {
    var available by mutableStateOf<AppUpdate.Release?>(null); private set
    /** 0..1 while downloading, null otherwise. */
    var progress by mutableStateOf<Float?>(null); private set
    var checking by mutableStateOf(false); private set
    /** The build the person said "Later" to. */
    var dismissed by mutableIntStateOf(-1); private set
    private var downloaded: File? = null
    private var loaded = false

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)
    val showPrompt: Boolean get() = available?.let { it.build != dismissed } == true

    fun check(ctx: Context, manual: Boolean) {
        if (!AppUpdate.enabled) { if (manual) toast("This version updates through the Play Store."); return }
        val sp = prefs(ctx)
        if (!loaded) { dismissed = sp.getInt("dismissed_build", -1); loaded = true }
        if (!manual && System.currentTimeMillis() - sp.getLong("checked_at", 0L) < 6 * 3_600_000L) return
        if (checking) return
        scope.launch {
            checking = true
            try {
                val r = AppUpdate.latest()
                sp.edit().putLong("checked_at", System.currentTimeMillis()).apply()
                available = r
                if (manual) { dismissed = -1; if (r == null) toast("You have the latest build (${AppUpdate.currentBuild}).") }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (manual) toast("Couldn't check for updates. Check your connection and try again.") }
            finally { checking = false }
        }
    }

    fun later(ctx: Context) { val b = available?.build ?: return; dismissed = b; prefs(ctx).edit().putInt("dismissed_build", b).apply() }

    /** Download (once) and open the system installer. The first time, Android asks to allow installs from Bucks. */
    fun update(ctx: Context) {
        val r = available ?: return
        if (progress != null) return
        if (!AppUpdate.canInstall(ctx)) { toast("Allow Bucks to install updates, then come back and tap Update."); AppUpdate.openInstallPermission(ctx); return }
        scope.launch {
            try {
                progress = 0f
                val f = downloaded?.takeIf { it.exists() && it.name == "bucks-${r.build}.apk" } ?: AppUpdate.download(ctx.applicationContext, r) { progress = it }
                downloaded = f
                AppUpdate.install(ctx, f)
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { toast(e.message?.takeIf { it.length < 120 } ?: "The update didn't download. Try again.") }
            finally { progress = null }
        }
    }
}

/** "Build N is ready" with what's new, a one-tap Update (download progress in place) and Later. */
@Composable
fun UpdatePrompt(u: Updates) {
    val r = u.available ?: return
    if (!u.showPrompt) return
    val ctx = LocalContext.current; val p = u.progress
    AlertDialog(onDismissRequest = { if (p == null) u.later(ctx) },
        title = { Text("Update available") },
        text = { Column {
            Text("Build ${r.build} is ready. You have build ${AppUpdate.currentBuild}.", style = MaterialTheme.typography.bodyMedium)
            val notes = r.notes.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.take(6).joinToString("\n")
            if (notes.isNotBlank()) Text(notes, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 10.dp))
            if (p != null) {
                LinearProgressIndicator(progress = { p }, modifier = Modifier.fillMaxWidth().padding(top = 16.dp))
                Text("Downloading ${(p * 100).toInt()}%", style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 6.dp))
            }
        } },
        confirmButton = { TextButton(enabled = p == null, onClick = { u.update(ctx) }) { Text(if (p == null) "Update now" else "Downloading…") } },
        dismissButton = { TextButton(enabled = p == null, onClick = { u.later(ctx) }) { Text("Later") } })
}
