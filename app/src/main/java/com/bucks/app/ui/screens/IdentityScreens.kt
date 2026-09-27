package com.bucks.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bucks.app.data.ProfileRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.shareText

/** "H6VF YWYF": the 8-character Bucks ID split for reading aloud. */
fun pretty(code: String) = code.uppercase().chunked(4).joinToString(" ")

/** The person's Bucks ID as text and QR, with copy, share and "sync with someone". */
@Composable
fun BucksIdCard(vm: BucksViewModel, onSync: () -> Unit) {
    val ctx = LocalContext.current; val me = vm.social.me ?: return
    val qr = remember(me.shortCode) { qrBitmap(BucksQr.forBucksId(me.shortCode), 512) }
    BucksCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.padding(start = 14.dp)) { Text("Your Bucks ID", style = MaterialTheme.typography.titleMedium); Muted("Share it so people can sync with you. Your number stays private.") }
        }
        Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(200.dp).clip(MaterialTheme.shapes.medium).background(androidx.compose.ui.graphics.Color.White).padding(8.dp)) { Image(qr.asImageBitmap(), "Bucks ID QR code", Modifier.fillMaxSize()) }
            Text(pretty(me.shortCode), style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 2.sp), modifier = Modifier.padding(top = 14.dp))
        }
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton("Copy", Modifier.weight(1f), tonal = true) { copy(ctx, me.shortCode); vm.toast("Bucks ID copied.") }
            SmallButton("Share", Modifier.weight(1f), tonal = true) { shareText(ctx, "Sync with me on Bucks. My Bucks ID is ${pretty(me.shortCode)}.") }
            SmallButton("Sync with someone", Modifier.weight(1.4f), onClick = onSync)
        }
    }
}
private fun copy(ctx: Context, text: String) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Bucks ID", text)) }

/** Sync: enter or scan a Bucks ID, answer requests, browse suggestions, manage synced people. */
@Composable
fun SyncScreen(vm: BucksViewModel, onBack: () -> Unit, onOpenChat: (String) -> Unit) {
    val social = vm.social; val ctx = LocalContext.current
    var code by remember { mutableStateOf("") }
    var menuFor by remember { mutableStateOf<ProfileRow?>(null) }
    LaunchedEffect(Unit) { social.refreshSyncs(); social.refreshSuggestions() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Sync", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Label("Bucks ID")
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(8) }, placeholder = { Text("H6VF YWYF") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters), visualTransformation = androidx.compose.ui.text.input.VisualTransformation.None)
                Spacer(Modifier.width(8.dp))
                FilledTonalIconButton(onClick = { scanQr(ctx, onResult = { raw -> when (val s = BucksQr.parse(raw)) { is BucksQr.Scanned.BucksId -> social.syncWithCode(s.code); else -> vm.toast("That isn't a Bucks ID code.") } }, onError = { vm.toast(it) }) }) { Icon(Icons.Rounded.QrCodeScanner, "Scan a Bucks ID") }
            }
            PrimaryButton("Send sync request", Modifier.padding(top = 10.dp), enabled = BucksQr.looksLikeBucksId(code)) { social.syncWithCode(code); code = "" }
            Muted("Sync is two-way: once they accept, you see each other's posts and Moments and can message.", Modifier.padding(top = 8.dp))

            if (social.incoming.isNotEmpty()) {
                SectionTitle("Requests", Modifier.padding(top = 24.dp, bottom = 6.dp))
                social.incoming.forEach { p -> PersonRow(p, trailing = { Row { SmallButton("Accept", tonal = false) { social.acceptSync(p.id) }; Spacer(Modifier.width(6.dp)); SmallButton("Ignore", tonal = true) { social.unsync(p.id) } } }) }
            }
            if (social.suggestions.isNotEmpty()) {
                SectionTitle("People you may know", Modifier.padding(top = 24.dp, bottom = 6.dp))
                social.suggestions.take(8).forEach { s -> Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(s.name), size = 40)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(s.name, style = MaterialTheme.typography.titleMedium); Muted(listOfNotNull(s.area.ifBlank { null }, if (s.mutual > 0) "${s.mutual} mutual" else null, s.distanceM?.let { "${"%.1f".format(it / 1000)} km" }).joinToString(" · ")) }
                    SmallButton("Sync", tonal = true) { social.syncWith(s.id, s.name) }
                }; Divider() }
            }
            SectionTitle("Synced with you", Modifier.padding(top = 24.dp, bottom = 6.dp))
            if (social.synced.isEmpty()) Muted("Nobody yet. Share your Bucks ID or scan a friend's.")
            social.synced.forEach { p -> PersonRow(p, sub = if (p.id in social.closeFriends) "Close friend" else p.area, trailing = {
                Row { FilledTonalIconButton(onClick = { social.openDirect(p.id, onOpenChat) }, modifier = Modifier.size(38.dp)) { Icon(Icons.Rounded.ChatBubbleOutline, "Message", Modifier.size(18.dp)) }
                      IconButton(onClick = { menuFor = p }) { Icon(Icons.Rounded.MoreVert, "More") } } }) }
            Spacer(Modifier.height(24.dp))
        }
    }
    menuFor?.let { p -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text(p.name) }, text = { Column {
            val close = p.id in social.closeFriends
            TextButton({ social.setClose(p.id, !close); menuFor = null }) { Text(if (close) "Remove from close friends" else "Add to close friends") }
            TextButton({ social.unsync(p.id); menuFor = null }) { Text("Unsync") }
            TextButton({ social.block(p.id); menuFor = null }) { Text("Block", color = MaterialTheme.colorScheme.error) }
        } }, confirmButton = { TextButton({ menuFor = null }) { Text("Close") } }) }
}

@Composable
fun PersonRow(p: ProfileRow, sub: String = p.area, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(p.name), size = 40)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(p.name, style = MaterialTheme.typography.titleMedium); Muted(sub.ifBlank { pretty(p.shortCode) }) }
        trailing()
    }
    Divider()
}
