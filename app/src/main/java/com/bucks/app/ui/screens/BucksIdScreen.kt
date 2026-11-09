package com.bucks.app.ui.screens

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bucks.app.ui.BucksIdCardInfo
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status

/**
 * My Bucks ID as a card: name, the 8-character ID, the account's UUID, a year of validity, a QR code and a barcode.
 * Anyone who scans either (or types the ID) can send a sync request; the phone number stays private.
 */
@Composable
fun BucksIdScreen(vm: BucksViewModel, onBack: () -> Unit, onSync: () -> Unit) {
    val me = vm.social.me; val ctx = LocalContext.current; val s by vm.state.collectAsState()
    val copiedMsg = stringResource(R.string.g8_bucks_id_copied)
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Bucks Pro", onBack = onBack)
        if (me == null) { Column(Modifier.padding(Gutter)) { Muted(stringResource(R.string.g8_bucks_id_missing)) }; return@ContentColumn }
        val info = BucksIdCardInfo.of(me.idIssuedAt)
        val qr = remember(me.shortCode) { qrBitmap(BucksQr.forBucksId(me.shortCode), 480) }
        val bar = remember(me.shortCode) { barcodeBitmap(BucksQr.forBucksId(me.shortCode)) }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            // The card: natural height (no fixed ratio, so nothing is cut off at large font sizes), brand gradient.
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp))
                .background(Brush.linearGradient(listOf(Color(0xFF8B2CF5), Color(0xFF5B12C8), Color(0xFF3A0A8C)))).padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BucksWordmark(height = 24.dp, color = Color.White)
                    Text(" pro", color = Color.White, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
                    Spacer(Modifier.weight(1f))
                    Row(Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.18f)).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Verified, null, Modifier.size(16.dp), tint = Color.White)
                        Text(" " + if (info?.expired == true) stringResource(R.string.g8_expired) else stringResource(R.string.g8_verified), color = Color.White, style = MaterialTheme.typography.labelMedium)
                    }
                }
                Row(Modifier.padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(56.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).border(2.dp, Color.White.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
                        Text(initials(me.name.ifBlank { s.user?.name ?: "?" }).ifBlank { "?" }, color = Color.White, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold))
                    }
                    Column(Modifier.padding(start = 14.dp).weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(me.name.ifBlank { s.user?.name ?: "" }, color = Color.White, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            if (info?.expired != true) Icon(Icons.Rounded.Verified, stringResource(R.string.g8_verified), Modifier.padding(start = 6.dp).size(20.dp), tint = Color(0xFF7CF0C0))
                        }
                        Text(me.area.ifBlank { s.user?.area ?: "" }.substringBefore(',').ifBlank { "Bengaluru" }, color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodyMedium, maxLines = 1)
                    }
                }
                Text("BUCKS ID", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.5.sp), modifier = Modifier.padding(top = 20.dp))
                Text(pretty(me.shortCode), color = Color.White, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = 4.sp, fontFamily = FontFamily.Monospace))
                Text(me.id, color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                HorizontalDivider(Modifier.padding(vertical = 14.dp), color = Color.White.copy(alpha = 0.2f))
                Row {
                    Column(Modifier.weight(1f)) { Text(stringResource(R.string.g8_valid_from).uppercase(), color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.sp)); Text(info?.validFrom ?: "–", color = Color.White, style = MaterialTheme.typography.titleSmall) }
                    Column(Modifier.weight(1f)) { Text(stringResource(R.string.g8_valid_till).uppercase(), color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.sp)); Text(info?.validTill ?: "–", color = Color.White, style = MaterialTheme.typography.titleSmall) }
                }
            }
            // Barcode strip under the card: scans with the same scanner as the QR.
            Box(Modifier.fillMaxWidth().padding(top = 12.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(horizontal = 16.dp, vertical = 10.dp)) {
                Image(bar.asImageBitmap(), stringResource(R.string.g8_cd_bucks_id_barcode), Modifier.fillMaxWidth().height(64.dp), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.None)
            }
            val st = MaterialTheme.status
            // Status in words, with colour and an icon, readable in sunlight.
            Row(Modifier.fillMaxWidth().padding(top = 12.dp).clip(MaterialTheme.shapes.medium).background(when { info == null -> MaterialTheme.colorScheme.surfaceContainer; info.expired -> st.badTint; info.renewable -> st.warnTint; else -> st.goodTint })
                .padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                val c = when { info == null -> MaterialTheme.colorScheme.onSurfaceVariant; info.expired -> st.bad; info.renewable -> st.warn; else -> st.good }
                Icon(if (info?.expired == true) Icons.Rounded.Cancel else Icons.Rounded.Verified, null, tint = c)
                Text(when { info == null -> stringResource(R.string.g8_checking_validity); info.expired -> stringResource(R.string.g8_expired_on, info.validTill); info.renewable -> pluralStringResource(R.plurals.g8_expires_in_days, info.daysLeft.toInt(), info.daysLeft.toInt()); else -> pluralStringResource(R.plurals.g8_active_days_left, info.daysLeft.toInt(), info.daysLeft.toInt()) },
                    color = c, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f).padding(start = 10.dp))
                if (info != null && info.renewable) SmallButton(stringResource(R.string.g8_renew)) { vm.social.renewBucksId() }
            }
            if (info?.expired == true) Notice(stringResource(R.string.g8_expired_notice), Modifier.padding(top = 10.dp))

            SectionTitle(stringResource(R.string.g8_scan_to_sync), Modifier.padding(top = 20.dp, bottom = 8.dp))
            Box(Modifier.align(Alignment.CenterHorizontally).size(220.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(10.dp)) {
                Image(qr.asImageBitmap(), stringResource(R.string.g8_cd_bucks_id_qr), Modifier.fillMaxSize(), filterQuality = FilterQuality.None)
            }
            Muted(stringResource(R.string.g8_scan_explainer), Modifier.padding(top = 10.dp).fillMaxWidth(), androidx.compose.ui.text.style.TextAlign.Center)
            Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val shareMsg = stringResource(R.string.g8_bucks_id_share, pretty(me.shortCode))
                SmallButton(stringResource(R.string.g8_copy_id), Modifier.weight(1f), tonal = true) { copyText(ctx, me.shortCode); vm.toast(copiedMsg) }
                SmallButton(stringResource(R.string.g8_share), Modifier.weight(1f), tonal = true) { shareText(ctx, shareMsg) }
            }
            PrimaryButton(stringResource(R.string.g8_scan_or_enter_id), Modifier.padding(top = 10.dp), onClick = onSync)
        }
    }
}

private fun copyText(ctx: Context, text: String) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Bucks ID", text)) }
