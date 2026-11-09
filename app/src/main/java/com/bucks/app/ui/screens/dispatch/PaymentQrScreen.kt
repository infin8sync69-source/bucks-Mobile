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
import com.bucks.app.R
import androidx.compose.ui.res.stringResource

/**
 * My payment QR, for drivers and shop owners alike: upload the QR image from a UPI app (or scan a printed one), Bucks reads the
 * `upi://pay?...` link inside it and keeps only that. Riders paying a fare and buyers paying a shop order (contact_for_order
 * gives them the owner's link) then open it with the amount filled in.
 */
@Composable
fun PaymentQrScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val d = vm.dispatch; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<String?>(null) }; var reading by remember { mutableStateOf(false) }; var confirmRemove by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (!d.paymentLinkLoaded) d.refreshPaymentLink() }
    val msgNotUpi = stringResource(R.string.g6_qr_not_upi); val msgNoPayee = stringResource(R.string.g6_qr_no_payee); val msgNoQr = stringResource(R.string.g6_qr_not_found)
    fun accept(raw: String) {
        val link = raw.trim()
        if (!link.startsWith("upi://pay", ignoreCase = true)) { vm.toast(msgNotUpi); return }
        if (upiPayee(link) == null) { vm.toast(msgNoPayee); return }
        pending = link
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { u ->
        reading = true
        scope.launch { val raw = withContext(Dispatchers.IO) { runCatching { decodeQrImage(ctx, u) }.getOrNull() }; reading = false
            if (raw == null) vm.toast(msgNoQr) else accept(raw) } } }
    val link = d.paymentLink; val payee = link?.let { upiPayee(it) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g6_qr_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            when {
                !d.paymentLinkLoaded -> Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp); Muted("  " + stringResource(R.string.g6_qr_checking)) }
                pending != null -> PendingCard(pending!!, saving = d.busy, onSave = { d.savePaymentLink(pending!!) { pending = null } }, onDiscard = { pending = null })
                link != null -> BucksCard(tint = true) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                        Column(Modifier.padding(start = 12.dp)) { Text(stringResource(R.string.g6_qr_on), style = MaterialTheme.typography.titleMedium); Muted(if (payee != null) stringResource(R.string.g6_qr_payee, payee.first, payee.second) else stringResource(R.string.g6_qr_payee_you)) } }
                    val bmp = remember(link) { qrBitmap(link, 512) }
                    Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp).size(200.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(8.dp)) { Image(bmp.asImageBitmap(), stringResource(R.string.g6_cd_your_qr), Modifier.fillMaxSize()) }
                    Muted(stringResource(R.string.g6_qr_on_detail), Modifier.padding(top = 14.dp), TextAlign.Center)
                }
                else -> BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.padding(start = 12.dp)) { Text(stringResource(R.string.g6_qr_none), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g6_qr_none_short)) } }
                    Muted(stringResource(R.string.g6_qr_none_detail), Modifier.padding(top = 12.dp))
                }
            }
            if (pending == null && d.paymentLinkLoaded) {
                SectionTitle(if (link != null) stringResource(R.string.g6_qr_replace) else stringResource(R.string.g6_qr_add), Modifier.padding(top = 24.dp, bottom = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrimaryButton(if (reading) stringResource(R.string.g6_qr_reading) else stringResource(R.string.g6_qr_upload), enabled = !reading && !d.busy) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                    GhostButton(stringResource(R.string.g6_qr_scan), enabled = !reading && !d.busy) { scanQr(ctx, onResult = { accept(it) }, onError = { vm.toast(it) }) }
                    if (link != null) BadButton(stringResource(R.string.g6_qr_remove)) { confirmRemove = true }
                }
                SectionTitle(stringResource(R.string.g6_qr_howto), Modifier.padding(top = 24.dp, bottom = 6.dp))
                listOf(stringResource(R.string.g6_qr_step1), stringResource(R.string.g6_qr_step2), stringResource(R.string.g6_qr_step3), stringResource(R.string.g6_qr_step4)).forEachIndexed { i, step ->
                    Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.Top) { Avatar("${i + 1}", size = 24); Text(step, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 10.dp)) } }
                Muted(stringResource(R.string.g6_qr_footer), Modifier.padding(top = 12.dp))
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    if (confirmRemove) AlertDialog(onDismissRequest = { confirmRemove = false }, title = { Text(stringResource(R.string.g6_qr_remove_title)) }, text = { Text(stringResource(R.string.g6_qr_remove_msg)) },
        confirmButton = { TextButton({ confirmRemove = false; d.removePaymentLink() }) { Text(stringResource(R.string.g6_remove), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmRemove = false }) { Text(stringResource(R.string.g6_keep)) } })
}

@Composable
private fun PendingCard(link: String, saving: Boolean, onSave: () -> Unit, onDiscard: () -> Unit) {
    val payee = upiPayee(link)
    BucksCard(tint = true) {
        Text(stringResource(R.string.g6_qr_read), style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.g6_qr_payee, payee?.first ?: "?", payee?.second ?: "?"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 6.dp))
        Muted(stringResource(R.string.g6_qr_check), Modifier.padding(top = 4.dp))
        val bmp = remember(link) { qrBitmap(link, 512) }
        Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 14.dp).size(160.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(8.dp)) { Image(bmp.asImageBitmap(), stringResource(R.string.g6_cd_upi_qr), Modifier.fillMaxSize()) }
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton(if (saving) stringResource(R.string.g6_saving) else stringResource(R.string.g6_save), Modifier.weight(1f), enabled = !saving, onClick = onSave)
            SmallButton(stringResource(R.string.g6_qr_choose_another), Modifier.weight(1f), tonal = true, enabled = !saving, onClick = onDiscard)
        }
    }
}

/** Reads the QR code in a picked image with zxing; tries the inverted image too (dark-mode screenshots). Null when there is none. */
private fun decodeQrImage(ctx: Context, uri: Uri): String? {
    val cr = ctx.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    // A bounds-only decode always returns null (it only fills [bounds]), so check the stream and the size, not its result.
    val head = cr.openInputStream(uri) ?: return null
    head.use { BitmapFactory.decodeStream(it, null, bounds) }
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
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
