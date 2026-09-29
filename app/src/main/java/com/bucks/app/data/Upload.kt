package com.bucks.app.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.util.UUID

/** A file picked on the phone, ready to upload: bytes, a display name and its type. */
class Picked(val bytes: ByteArray, val name: String, val mime: String) {
    val isImage get() = mime.startsWith("image/")
    val isVideo get() = mime.startsWith("video/")
    /** Unique object name inside a storage folder; keeps the extension so previews and downloads know the type. */
    fun objectName() = UUID.randomUUID().toString().replace("-", "") + "." + (name.substringAfterLast('.', "").lowercase().ifBlank { if (isImage) "jpg" else "bin" })
}

object Upload {
    /** Largest file read into memory (chat allows 25 MB, moments 30 MB); bigger files are refused before they can exhaust memory. */
    const val MAX_READ_BYTES = 32L * 1024 * 1024

    /**
     * Reads a picked file. Photos are turned upright (camera rotation), re-encoded as JPEG no larger than [maxPx] on the long
     * side, which keeps uploads small on mobile data. Returns null when the file can't be opened, isn't a readable image, or is
     * too big to hold in memory.
     */
    fun read(ctx: Context, uri: Uri, maxPx: Int = 1600, quality: Int = 82): Picked? = runCatching {
        val cr = ctx.contentResolver
        val mime = cr.getType(uri) ?: "application/octet-stream"
        val name = runCatching { cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } }.getOrNull() ?: "file"
        val size = runCatching { cr.openAssetFileDescriptor(uri, "r")?.use { it.length } }.getOrNull() ?: -1L
        if (size > MAX_READ_BYTES) return@runCatching null
        if (mime.startsWith("image/") && mime != "image/gif") {
            // Measuring: with inJustDecodeBounds the decoder fills in the size and returns null on purpose, so only the size counts.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: run { if (bounds.outWidth <= 0) return@runCatching null }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@runCatching null
            var sample = 1; while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPx) sample *= 2
            val decoded = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return@runCatching null
            val degrees = runCatching { cr.openInputStream(uri)?.use { s -> when (ExifInterface(s).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90; ExifInterface.ORIENTATION_ROTATE_180 -> 180; ExifInterface.ORIENTATION_ROTATE_270 -> 270; else -> 0 } } }.getOrNull() ?: 0
            val scale = minOf(1f, maxPx.toFloat() / maxOf(decoded.width, decoded.height))
            val bmp = if (scale < 1f || degrees != 0) Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postScale(scale, scale); postRotate(degrees.toFloat()) }, true) else decoded
            val bytes = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
            return@runCatching Picked(bytes, name.substringBeforeLast('.') + ".jpg", "image/jpeg")
        }
        val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: return@runCatching null
        Picked(bytes, name, mime)
    }.getOrNull()
}
