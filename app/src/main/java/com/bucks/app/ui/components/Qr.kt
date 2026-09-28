package com.bucks.app.ui.components

import android.content.Context
import android.graphics.Bitmap
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/** QR codes Bucks shows and reads. The prefix says what a scanned code is for. */
object BucksQr {
    private const val ID = "bucks:id:"; private const val REC = "bucks:rec:"
    fun forBucksId(code: String) = ID + code.uppercase()
    fun forRecommendation(token: String) = REC + token
    sealed interface Scanned { data class BucksId(val code: String) : Scanned; data class Recommendation(val token: String) : Scanned; data class Upi(val uri: String) : Scanned; data class Other(val raw: String) : Scanned }
    fun parse(raw: String): Scanned = when {
        raw.startsWith(ID) -> Scanned.BucksId(raw.removePrefix(ID).trim().uppercase())
        raw.startsWith(REC) -> Scanned.Recommendation(raw.removePrefix(REC).trim())
        raw.startsWith("upi://pay", ignoreCase = true) -> Scanned.Upi(raw)
        else -> Scanned.Other(raw)
    }
    /** A typed Bucks ID: 8 characters, no I/L/O/U, case-insensitive. */
    fun looksLikeBucksId(s: String) = Regex("^[0-9A-HJKMNP-TV-Z]{8}$").matches(s.trim().uppercase())
}

fun qrBitmap(text: String, size: Int = 640): Bitmap {
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(EncodeHintType.MARGIN to 1))
    val px = IntArray(size * size) { i -> if (m[i % size, i / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    return Bitmap.createBitmap(px, size, size, Bitmap.Config.RGB_565)
}

/** A Code 128 barcode of [text] (the Bucks ID card's strip), black on white, [w] x [h] pixels. */
fun barcodeBitmap(text: String, w: Int = 900, h: Int = 180): Bitmap {
    val m = com.google.zxing.oned.Code128Writer().encode(text, BarcodeFormat.CODE_128, w, h, mapOf(EncodeHintType.MARGIN to 0))
    val px = IntArray(m.width * m.height) { i -> if (m[i % m.width, i / m.width]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    return Bitmap.createBitmap(px, m.width, m.height, Bitmap.Config.RGB_565)
}

/** Opens Google's built-in code scanner (no camera permission or extra screen of our own). */
fun scanQr(ctx: Context, onResult: (String) -> Unit, onError: (String) -> Unit) {
    val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE, Barcode.FORMAT_CODE_128).enableAutoZoom().build()
    val scanner = GmsBarcodeScanning.getClient(ctx, options)
    // The scanner module downloads on first use; ask for it up front so the first scan doesn't fail silently.
    ModuleInstall.getClient(ctx).installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
    scanner.startScan().addOnSuccessListener { b -> b.rawValue?.let(onResult) ?: onError("That code couldn't be read.") }
        .addOnCanceledListener { }
        .addOnFailureListener { onError("The scanner isn't available on this phone yet. Type the code instead.") }
}
