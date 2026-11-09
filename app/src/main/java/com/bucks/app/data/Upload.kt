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
        // Videos: copied into a fresh MP4 without the camera's location tag (photos lose theirs when re-encoded above).
        if (mime.startsWith("video/")) withoutLocation(ctx, uri)?.let { return@runCatching Picked(it, name.substringBeforeLast('.') + ".mp4", "video/mp4") }
        val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: return@runCatching null
        Picked(bytes, name, mime)
    }.getOrNull()

    /**
     * Re-muxes a video's audio and video tracks into a new MP4, unchanged, leaving out its metadata (the GPS location many phone
     * cameras write). Nothing is re-encoded, so it is quick and lossless. Null when the format can't be re-muxed; the caller then
     * uploads the original.
     */
    private fun withoutLocation(ctx: Context, uri: Uri): ByteArray? {
        val out = java.io.File.createTempFile("clean", ".mp4", ctx.cacheDir)
        val ex = android.media.MediaExtractor()
        var mux: android.media.MediaMuxer? = null
        return try {
            ex.setDataSource(ctx, uri, null)
            mux = android.media.MediaMuxer(out.path, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val map = HashMap<Int, Int>(); var maxIn = 1 shl 20
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i); val m = f.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                if (!m.startsWith("video/") && !m.startsWith("audio/")) continue
                if (f.containsKey(android.media.MediaFormat.KEY_MAX_INPUT_SIZE)) maxIn = maxOf(maxIn, f.getInteger(android.media.MediaFormat.KEY_MAX_INPUT_SIZE))
                if (m.startsWith("video/") && f.containsKey("rotation-degrees")) mux.setOrientationHint(f.getInteger("rotation-degrees"))
                ex.selectTrack(i); map[i] = mux.addTrack(f)
            }
            if (map.isEmpty()) return null
            mux.start()
            val buf = java.nio.ByteBuffer.allocate(maxIn); val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                val size = ex.readSampleData(buf, 0); if (size < 0) break
                val track = map[ex.sampleTrackIndex]
                if (track == null) { ex.advance(); continue }
                info.set(0, size, ex.sampleTime, if (ex.sampleFlags and android.media.MediaExtractor.SAMPLE_FLAG_SYNC != 0) android.media.MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                mux.writeSampleData(track, buf, info); ex.advance()
            }
            mux.stop()
            out.readBytes().takeIf { it.size.toLong() <= MAX_READ_BYTES }
        } catch (e: Exception) { null } finally {
            runCatching { mux?.release() }; runCatching { ex.release() }; out.delete()
        }
    }
}
