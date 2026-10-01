package com.bucks.app.ui

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID

/** Take a photo or record a video with the phone's own camera app. It needs no camera permission: the camera app does the capture. */
class CameraCapture(val takePhoto: () -> Unit, val recordVideo: () -> Unit)

private class RecordVideo(private val maxBytes: Long) : ActivityResultContract<Uri, Boolean>() {
    override fun createIntent(context: Context, input: Uri): Intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE).apply {
        putExtra(MediaStore.EXTRA_OUTPUT, input); putExtra(MediaStore.EXTRA_DURATION_LIMIT, 30); putExtra(MediaStore.EXTRA_SIZE_LIMIT, maxBytes); putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 0)
        clipData = ClipData.newRawUri("", input); addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    override fun parseResult(resultCode: Int, intent: Intent?) = resultCode == Activity.RESULT_OK
}

/**
 * [onPhoto] / [onVideo] get a content Uri of what was captured (readable with Upload.read). Videos are limited to 30 seconds and
 * [maxVideoBytes]. [onError] hears about a phone with no camera app.
 */
@Composable
fun rememberCamera(maxVideoBytes: Long = 25L * 1024 * 1024, onError: (String) -> Unit, onPhoto: (Uri) -> Unit, onVideo: (Uri) -> Unit): CameraCapture {
    val ctx = LocalContext.current
    var pending by remember { mutableStateOf<Uri?>(null) }
    fun newUri(ext: String): Uri { val dir = File(ctx.cacheDir, "captures").apply { mkdirs(); listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 6 * 3600_000L) it.delete() } }
        return FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", File(dir, UUID.randomUUID().toString() + "." + ext)) }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok -> val u = pending; pending = null; if (ok && u != null) onPhoto(u) }
    val video = rememberLauncherForActivityResult(RecordVideo(maxVideoBytes)) { ok -> val u = pending; pending = null; if (ok && u != null) onVideo(u) }
    return CameraCapture(
        takePhoto = { runCatching { val u = newUri("jpg"); pending = u; photo.launch(u) }.onFailure { onError("No camera app found on this phone.") } },
        recordVideo = { runCatching { val u = newUri("mp4"); pending = u; video.launch(u) }.onFailure { onError("No camera app found on this phone.") } },
    )
}
