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
        BucksTopBar("Bucks ID", onBack = onBack)
        if (me == null) { Column(Modifier.padding(Gutter)) { Muted("Your Bucks ID appears once you're signed in and your profile is saved. Check your connection and open this again.") }; return@ContentColumn }
        val info = BucksIdCardInfo.of(me.idIssuedAt)
        val qr = remember(me.shortCode) { qrBitmap(BucksQr.forBucksId(me.shortCode), 480) }
        val bar = remember(me.shortCode) { barcodeBitmap(BucksQr.forBucksId(me.shortCode)) }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            // The card itself: credit-card proportions, brand gradient.
            Column(Modifier.fillMaxWidth().aspectRatio(1.586f).clip(RoundedCornerShape(20.dp))
                .background(Brush.linearGradient(listOf(Color(0xFF811FF0), Color(0xFF4A0AA6)))).padding(18.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BucksWordmark(height = 22.dp, color = Color.White)
                    Spacer(Modifier.weight(1f))
                    Text("ID CARD", color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 2.sp))
                }
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(52.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).border(2.dp, Color.White.copy(alpha = 0.6f), CircleShape), contentAlignment = Alignment.Center) {
                        Text(initials(me.name.ifBlank { s.user?.name ?: "?" }).ifBlank { "?" }, color = Color.White, style = MaterialTheme.typography.titleMedium)
                    }
                    Column(Modifier.padding(start = 12.dp).weight(1f)) {
                        Text(me.name.ifBlank { s.user?.name ?: "" }, color = Color.White, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
                        Text(me.area.ifBlank { s.user?.area ?: "" }.substringBefore(','), color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                    }
                }
                Text(pretty(me.shortCode), color = Color.White, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 3.sp, fontFamily = FontFamily.Monospace), modifier = Modifier.padding(top = 12.dp))
                Text(me.id, color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), maxLines = 1)
                Row(Modifier.padding(top = 8.dp)) {
                    Column(Modifier.weight(1f)) { Text("VALID FROM", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall); Text(info?.validFrom ?: "–", color = Color.White, style = MaterialTheme.typography.labelLarge) }
                    Column(Modifier.weight(1f)) { Text("VALID TILL", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelSmall); Text(info?.validTill ?: "–", color = Color.White, style = MaterialTheme.typography.labelLarge) }
                }
            }
            // Barcode strip under the card: scans with the same scanner as the QR.
            Box(Modifier.fillMaxWidth().padding(top = 12.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(horizontal = 16.dp, vertical = 10.dp)) {
                Image(bar.asImageBitmap(), "Bucks ID barcode", Modifier.fillMaxWidth().height(64.dp), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.None)
            }
            val st = MaterialTheme.status
            Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                when {
                    info == null -> PillGrey("Validity unknown")
                    info.expired -> PillBad("Expired on ${info.validTill}")
                    info.renewable -> PillWarn("Expires in ${info.daysLeft} day${if (info.daysLeft == 1L) "" else "s"}")
                    else -> PillGood("Valid · ${info.daysLeft} days left")
                }
                Spacer(Modifier.weight(1f))
                if (info != null && info.renewable) SmallButton("Renew for a year") { vm.social.renewBucksId() }
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
