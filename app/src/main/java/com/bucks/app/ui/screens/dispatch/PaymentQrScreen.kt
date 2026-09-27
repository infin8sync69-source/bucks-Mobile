package com.bucks.app.ui.screens.dispatch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.upiPayee
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A driver's payment QR: upload the QR image from their UPI app (or scan a printed one), Bucks reads the
 * `upi://pay?...` link inside it and keeps only that. Riders' apps then open it with the fare filled in.
 */
@Composable
fun PaymentQrScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val d = vm.dispatch; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<String?>(null) }; var reading by remember { mutableStateOf(false) }; var confirmRemove by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (!d.paymentLinkLoaded) d.refreshPaymentLink() }
    fun accept(raw: String) {
        val link = raw.trim()
        if (!link.startsWith("upi://pay", ignoreCase = true)) { vm.toast("That QR isn't a UPI payment code. Use the QR from your UPI app (GPay, PhonePe, Paytm, BHIM)."); return }
        if (upiPayee(link) == null) { vm.toast("That UPI code has no payee address (pa=). Try the QR from your UPI app."); return }
        pending = link
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { u ->
        reading = true
        scope.launch { val raw = withContext(Dispatchers.IO) { runCatching { decodeQrImage(ctx, u) }.getOrNull() }; reading = false
            if (raw == null) vm.toast("Couldn't find a QR code in that picture. Try a clearer photo, or a screenshot of the QR from your UPI app.") else accept(raw) } } }
    val link = d.paymentLink; val payee = link?.let { upiPayee(it) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Payment QR", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            when {
                !d.paymentLinkLoaded -> Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp); Muted("  Checking your payment QR") }
                pending != null -> PendingCard(pending!!, saving = d.busy, onSave = { d.savePaymentLink(pending!!) { pending = null } }, onDiscard = { pending = null })
                link != null -> BucksCard(tint = true) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                        Column(Modifier.padding(start = 12.dp)) { Text("UPI payments are on", style = MaterialTheme.typography.titleMedium); Muted("Payments go to ${payee?.first ?: "you"}${payee?.let { " (${it.second})" } ?: ""}") } }
                    val bmp = remember(link) { qrBitmap(link, 512) }
                    Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp).size(200.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(8.dp)) { Image(bmp.asImageBitmap(), "Your UPI QR", Modifier.fillMaxSize()) }
                    Muted("When a customer taps Pay by UPI after a trip, their app opens with this account and the fare already filled in. You can also show this QR for them to scan.", Modifier.padding(top = 14.dp), TextAlign.Center)
                }
                else -> BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.padding(start = 12.dp)) { Text("No payment QR yet", style = MaterialTheme.typography.titleMedium); Muted("Customers pay you in cash until you add one.") } }
                    Muted("Add the QR from your UPI app and customers can pay the fare by UPI straight after the trip. Bucks keeps only the payment link, not the picture.", Modifier.padding(top = 12.dp))
                }
            }
            if (pending == null && d.paymentLinkLoaded) {
                SectionTitle(if (link != null) "Replace it" else "Add your QR", Modifier.padding(top = 24.dp, bottom = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton(if (reading) "Reading the picture…" else "Upload my UPI QR", enabled = !reading && !d.busy) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                    GhostButton("Scan a printed QR", enabled = !reading && !d.busy) { scanQr(ctx, onResult = { accept(it) }, onError = { vm.toast(it) }) }
                    if (link != null) BadButton("Remove payment QR") { confirmRemove = true }
                }
                SectionTitle("How to get your QR image", Modifier.padding(top = 24.dp, bottom = 6.dp))
                listOf("Open your UPI app: Google Pay, PhonePe, Paytm or BHIM.", "Go to your profile and tap your QR code.", "Save or share the QR as an image to this phone.", "Come back here and tap Upload my UPI QR.").forEachIndexed { i, step ->
                    Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.Top) { Avatar("${i + 1}", size = 24); Text(step, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp)) } }
                Muted("Only UPI payment codes (upi://pay) are accepted. Money goes straight from the customer's app to your bank; Bucks never holds it.", Modifier.padding(top = 12.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    if (confirmRemove) AlertDialog(onDismissRequest = { confirmRemove = false }, title = { Text("Remove your payment QR?") }, text = { Text("Customers will only be able to pay you in cash until you add a QR again.") },
        confirmButton = { TextButton({ confirmRemove = false; d.removePaymentLink() }) { Text("Remove", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmRemove = false }) { Text("Keep it") } })
}

@Composable
private fun PendingCard(link: String, saving: Boolean, onSave: () -> Unit, onDiscard: () -> Unit) {
    val payee = upiPayee(link)
    BucksCard(tint = true) {
        Text("QR read", style = MaterialTheme.typography.titleMedium)
        Text("Payments go to ${payee?.first ?: "?"} (${payee?.second ?: "?"})", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 6.dp))
        Muted("Check the name and UPI ID are yours before saving.", Modifier.padding(top = 4.dp))
        val bmp = remember(link) { qrBitmap(link, 512) }
        Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 14.dp).size(160.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(8.dp)) { Image(bmp.asImageBitmap(), "UPI QR", Modifier.fillMaxSize()) }
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton(if (saving) "Saving…" else "Save", Modifier.weight(1f), enabled = !saving, onClick = onSave)
            SmallButton("Choose another", Modifier.weight(1f), tonal = true, enabled = !saving, onClick = onDiscard)
        }
    }
}

/** Reads the QR code in a picked image with zxing; tries the inverted image too (dark-mode screenshots). Null when there is none. */
private fun decodeQrImage(ctx: Context, uri: Uri): String? {
    val cr = ctx.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
    var sample = 1; while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
    val bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }) } ?: return null
    val w = bmp.width; val h = bmp.height; val px = IntArray(w * h); bmp.getPixels(px, 0, w, 0, 0, w, h)
    val hints = mapOf<DecodeHintType, Any>(DecodeHintType.TRY_HARDER to true, DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
    val reader = MultiFormatReader().apply { setHints(hints) }
    val plain = RGBLuminanceSource(w, h, px)
    for (src in listOf(plain, plain.invert())) {
        val text = runCatching { reader.decodeWithState(BinaryBitmap(HybridBinarizer(src))).text }.getOrNull()
        reader.reset()
        if (!text.isNullOrBlank()) return text
    }
    return null
}
