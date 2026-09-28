package com.bucks.app.ui.screens

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
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Bucks Pro", onBack = onBack)
        if (me == null) { Column(Modifier.padding(Gutter)) { Muted("Your Bucks ID appears once you're signed in and your profile is saved. Check your connection and open this again.") }; return@ContentColumn }
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
                        Text(if (info?.expired == true) " Expired" else " Verified", color = Color.White, style = MaterialTheme.typography.labelMedium)
                    }
                }
                Row(Modifier.padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(56.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).border(2.dp, Color.White.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
                        Text(initials(me.name.ifBlank { s.user?.name ?: "?" }).ifBlank { "?" }, color = Color.White, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold))
                    }
                    Column(Modifier.padding(start = 14.dp).weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(me.name.ifBlank { s.user?.name ?: "" }, color = Color.White, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            if (info?.expired != true) Icon(Icons.Rounded.Verified, "Verified", Modifier.padding(start = 6.dp).size(20.dp), tint = Color(0xFF7CF0C0))
                        }
                        Text(me.area.ifBlank { s.user?.area ?: "" }.substringBefore(',').ifBlank { "Bengaluru" }, color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodyMedium, maxLines = 1)
                    }
                }
                Text("BUCKS ID", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.5.sp), modifier = Modifier.padding(top = 20.dp))
                Text(pretty(me.shortCode), color = Color.White, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = 4.sp, fontFamily = FontFamily.Monospace))
                Text(me.id, color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                HorizontalDivider(Modifier.padding(vertical = 14.dp), color = Color.White.copy(alpha = 0.2f))
                Row {
                    Column(Modifier.weight(1f)) { Text("VALID FROM", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.sp)); Text(info?.validFrom ?: "–", color = Color.White, style = MaterialTheme.typography.titleSmall) }
                    Column(Modifier.weight(1f)) { Text("VALID TILL", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.sp)); Text(info?.validTill ?: "–", color = Color.White, style = MaterialTheme.typography.titleSmall) }
                }
            }
            // Barcode strip under the card: scans with the same scanner as the QR.
            Box(Modifier.fillMaxWidth().padding(top = 12.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(horizontal = 16.dp, vertical = 10.dp)) {
                Image(bar.asImageBitmap(), "Bucks ID barcode", Modifier.fillMaxWidth().height(64.dp), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.None)
            }
            val st = MaterialTheme.status
            // Status in words, with colour and an icon, readable in sunlight.
            Row(Modifier.fillMaxWidth().padding(top = 12.dp).clip(MaterialTheme.shapes.medium).background(when { info == null -> MaterialTheme.colorScheme.surfaceContainer; info.expired -> st.badTint; info.renewable -> st.warnTint; else -> st.goodTint })
                .padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                val c = when { info == null -> MaterialTheme.colorScheme.onSurfaceVariant; info.expired -> st.bad; info.renewable -> st.warn; else -> st.good }
                Icon(if (info?.expired == true) Icons.Rounded.Cancel else Icons.Rounded.Verified, null, tint = c)
                Text(when { info == null -> "Checking validity…"; info.expired -> "Expired on ${info.validTill}"; info.renewable -> "Expires in ${info.daysLeft} day${if (info.daysLeft == 1L) "" else "s"}"; else -> "Active · ${info.daysLeft} days left" },
                    color = c, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f).padding(start = 10.dp))
                if (info != null && info.renewable) SmallButton("Renew") { vm.social.renewBucksId() }
            }
            if (info?.expired == true) Notice("An expired ID can't be used by others to sync with you. Renew it: it takes a second and keeps the same ID.", Modifier.padding(top = 10.dp))

            SectionTitle("Scan to sync", Modifier.padding(top = 20.dp, bottom = 8.dp))
            Box(Modifier.align(Alignment.CenterHorizontally).size(220.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(10.dp)) {
                Image(qr.asImageBitmap(), "Bucks ID QR code", Modifier.fillMaxSize(), filterQuality = FilterQuality.None)
            }
            Muted("Anyone who scans this, or types your ID, can send you a sync request. Your phone number stays private.", Modifier.padding(top = 10.dp).fillMaxWidth(), androidx.compose.ui.text.style.TextAlign.Center)
            Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallButton("Copy ID", Modifier.weight(1f), tonal = true) { copyText(ctx, me.shortCode); vm.toast("Bucks ID copied.") }
                SmallButton("Share", Modifier.weight(1f), tonal = true) { shareText(ctx, "Sync with me on Bucks. My Bucks ID is ${pretty(me.shortCode)}.") }
            }
            PrimaryButton("Scan or enter someone's ID", Modifier.padding(top = 10.dp), onClick = onSync)
        }
    }
}

private fun copyText(ctx: Context, text: String) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Bucks ID", text)) }
