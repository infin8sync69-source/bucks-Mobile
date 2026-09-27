package com.bucks.app.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
    /** Reads a picked file. Photos are re-encoded as JPEG no larger than [maxPx] on the long side, which keeps chat and moment uploads small on mobile data. */
    fun read(ctx: Context, uri: Uri, maxPx: Int = 1600, quality: Int = 82): Picked? {
        val cr = ctx.contentResolver
        val mime = cr.getType(uri) ?: "application/octet-stream"
        val name = runCatching { cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } }.getOrNull() ?: "file"
        if (mime.startsWith("image/") && mime != "image/gif") {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
            var sample = 1; while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPx) sample *= 2
            val bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
            val scale = maxPx.toFloat() / maxOf(bmp.width, bmp.height)
            val out = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
            val bytes = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
            return Picked(bytes, name.substringBeforeLast('.') + ".jpg", "image/jpeg")
        }
        val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: return null
        return Picked(bytes, name, mime)
    }
}
