package com.bucks.app.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.bucks.app.ui.components.BucksLoader
import com.bucks.app.ui.screens.MomentVideo
import com.bucks.app.ui.screens.SignedImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Opens a chat or post attachment inside Bucks: photos in a full-screen viewer (pinch to zoom, double-tap to reset), videos in the
 * player. Nothing here sends the person to a browser.
 */
@Composable
fun AttachmentViewer(vm: BucksViewModel, bucket: String, path: String, mime: String, onClose: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            if (mime.startsWith("video/")) {
                val url by produceState<String?>(null, path) { value = runCatching { vm.social.fileUrl(bucket, path) }.getOrNull() }
                url?.let { MomentVideo(it, paused = false, modifier = Modifier.fillMaxSize(), loop = true) } ?: BucksLoader(color = Color.White, label = "Loading")
            } else {
                var scale by remember { mutableFloatStateOf(1f) }; var dx by remember { mutableFloatStateOf(0f) }; var dy by remember { mutableFloatStateOf(0f) }
                SignedImage(vm, bucket, path, Modifier.fillMaxSize()
                    .pointerInput(Unit) { detectTapGestures(onDoubleTap = { scale = 1f; dx = 0f; dy = 0f }) }
                    .pointerInput(Unit) { detectTransformGestures { _, pan, zoom, _ -> scale = (scale * zoom).coerceIn(1f, 5f); if (scale > 1f) { dx += pan.x; dy += pan.y } else { dx = 0f; dy = 0f } } }
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = dx; translationY = dy }, ContentScale.Fit)
            }
            Row(Modifier.align(Alignment.TopEnd).statusBarsPadding()) {
                IconButton({ scope.launch { if (!FileOpener.share(ctx, vm.social, bucket, path, mime)) vm.toast("Couldn't share that. Check your connection.") } }) { Icon(Icons.Rounded.Share, "Share", tint = Color.White) }
                IconButton(onClose) { Icon(Icons.Rounded.Close, "Close", tint = Color.White) }
            }
        }
    }
}

/** Downloads an attachment to the cache and opens it with the phone's own app for that type (PDF viewer, Word, …). */
object FileOpener {
    private suspend fun download(ctx: Context, url: String, name: String): File = withContext(Dispatchers.IO) {
        val dir = File(ctx.cacheDir, "opened").apply { mkdirs(); listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 24 * 3600_000L) it.delete() } }
        val f = File(dir, name.replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(80).ifBlank { "file" })
        val c = URL(url).openConnection() as HttpURLConnection
        try { c.connectTimeout = 15_000; c.readTimeout = 30_000; c.inputStream.use { i -> f.outputStream().use { o -> i.copyTo(o) } } } finally { c.disconnect() }
        f
    }

    /** Opens [name] with an app that handles [mime]; false when the phone has no such app or the download failed. */
    suspend fun open(ctx: Context, social: Social, bucket: String, path: String, name: String, mime: String): Boolean = runCatching {
        val file = download(ctx, social.fileUrl(bucket, path), name)
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime.ifBlank { "*/*" }).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    }.getOrDefault(false)

    /** The system share sheet for an attachment (save to Drive, send on WhatsApp…). False when the download failed. */
    suspend fun share(ctx: Context, social: Social, bucket: String, path: String, mime: String): Boolean = runCatching {
        val file = download(ctx, social.fileUrl(bucket, path), path.substringAfterLast('/'))
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime.ifBlank { "*/*" }).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    }.getOrDefault(false)
}
