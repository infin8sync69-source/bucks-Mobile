package com.bucks.app.ui

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.core.content.ContextCompat
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

/** Opens one chat or post attachment full screen (MediaViewer): photos zoom, videos play. Nothing here sends the person to a browser. */
@Composable
fun AttachmentViewer(vm: BucksViewModel, bucket: String, path: String, mime: String, onClose: () -> Unit) =
    MediaViewer(vm, listOf(ViewerMedia.Stored(bucket, path, mime)), onClose = onClose)

/** Downloads an attachment to the cache and opens it with the phone's own app for that type (PDF viewer, Word, …). */
object FileOpener {
    internal suspend fun download(ctx: Context, url: String, name: String): File = withContext(Dispatchers.IO) {
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
    suspend fun share(ctx: Context, social: Social, bucket: String, path: String, mime: String): Boolean =
        runCatching { shareUrl(ctx, social.fileUrl(bucket, path), mime, path.substringAfterLast('/')) }.getOrDefault(false)

    /** The share sheet for a file at a public [url] (a profile picture, a gallery photo). */
    suspend fun shareUrl(ctx: Context, url: String, mime: String, name: String = url.substringAfterLast('/').substringBefore('?')): Boolean = runCatching {
        val file = download(ctx, url, name)
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime.ifBlank { "*/*" }).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    }.getOrDefault(false)
}

/** Saves a photo or video into the phone's gallery (Pictures/Bucks or Movies/Bucks). No permission is needed on Android 10 and newer. */
object MediaSaver {
    suspend fun save(ctx: Context, social: Social, bucket: String, path: String, mime: String): Boolean =
        runCatching { saveUrl(ctx, social.fileUrl(bucket, path), mime, path.substringAfterLast('/')) }.getOrDefault(false)

    /** Saves the photo or video at a public [url] into the gallery. */
    suspend fun saveUrl(ctx: Context, url: String, mime: String, name: String = url.substringAfterLast('/').substringBefore('?')): Boolean = runCatching {
        val video = mime.startsWith("video/")
        val ext = when { mime == "image/png" -> "png"; mime == "image/webp" -> "webp"; mime == "image/gif" -> "gif"; video -> "mp4"; else -> "jpg" }
        val outMime = if (mime.startsWith("image/") || video) mime else "image/jpeg"
        val name = "Bucks_" + java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.ENGLISH).format(java.util.Date()) + "." + ext
        val src = FileOpener.download(ctx, url, name)
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            if (Build.VERSION.SDK_INT >= 29) {
                val cr = ctx.contentResolver
                val coll = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val uri = cr.insert(coll, ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, outMime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, (if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES) + "/Bucks"); put(MediaStore.MediaColumns.IS_PENDING, 1)
                }) ?: error("no gallery")
                cr.openOutputStream(uri)?.use { o -> src.inputStream().use { it.copyTo(o) } } ?: error("no stream")
                cr.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            } else {
                val dir = java.io.File(Environment.getExternalStoragePublicDirectory(if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES), "Bucks").apply { mkdirs() }
                val dest = java.io.File(dir, name); src.copyTo(dest, overwrite = true)
                android.media.MediaScannerConnection.scanFile(ctx, arrayOf(dest.absolutePath), arrayOf(outMime), null)
            }
        }
        true
    }.getOrDefault(false)
}
