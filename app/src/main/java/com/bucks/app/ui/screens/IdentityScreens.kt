package com.bucks.app.ui.screens

import com.bucks.app.data.Str
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
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
            Column(Modifier.padding(start = 14.dp)) { Text(stringResource(R.string.g7_id_your_id), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g7_id_share_note)) }
        }
        Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(200.dp).clip(MaterialTheme.shapes.medium).background(androidx.compose.ui.graphics.Color.White).padding(8.dp)) { Image(qr.asImageBitmap(), stringResource(R.string.g7_cd_id_qr), Modifier.fillMaxSize()) }
            Text(pretty(me.shortCode), style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 2.sp), modifier = Modifier.padding(top = 14.dp))
        }
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton(stringResource(R.string.g7_id_copy), Modifier.weight(1f), tonal = true) { copy(ctx, me.shortCode); vm.toast(Str.get(R.string.g7_id_copied)) }
            SmallButton(stringResource(R.string.g7_id_share), Modifier.weight(1f), tonal = true) { shareText(ctx, Str.get(R.string.g7_id_share_text, pretty(me.shortCode))) }
            SmallButton(stringResource(R.string.g7_id_sync_someone), Modifier.weight(1.4f), onClick = onSync)
        }
    }
}
private fun copy(ctx: Context, text: String) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Bucks ID", text)) }

/** Sync: enter or scan a Bucks ID, answer requests, browse suggestions, manage synced people. */
@Composable
fun SyncScreen(vm: BucksViewModel, onBack: () -> Unit, onOpenChat: (String) -> Unit) {
    val social = vm.social; val ctx = LocalContext.current
    var code by remember { mutableStateOf("") }
    var menuFor by remember { mutableStateOf<ProfileRow?>(null) }; var linkFor by remember { mutableStateOf<ProfileRow?>(null) }
    LaunchedEffect(Unit) { social.refreshSyncs(); social.refreshSuggestions(); social.refreshLinks() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g7_id_sync), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Label(stringResource(R.string.g7_id_bucks_id))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(8) }, placeholder = { Text("H6VF YWYF") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters), visualTransformation = androidx.compose.ui.text.input.VisualTransformation.None)
                Spacer(Modifier.width(8.dp))
                FilledTonalIconButton(onClick = { scanQr(ctx, onResult = { raw -> when (val s = BucksQr.parse(raw)) { is BucksQr.Scanned.BucksId -> social.syncWithCode(s.code); else -> vm.toast(Str.get(R.string.g7_id_not_code)) } }, onError = { vm.toast(it) }) }) { Icon(Icons.Rounded.QrCodeScanner, stringResource(R.string.g7_cd_id_scan)) }
            }
            PrimaryButton(stringResource(R.string.g7_id_send_request), Modifier.padding(top = 10.dp), enabled = BucksQr.looksLikeBucksId(code)) { social.syncWithCode(code); code = "" }
            Muted(stringResource(R.string.g7_id_sync_note), Modifier.padding(top = 8.dp))

            if (social.incoming.isNotEmpty()) {
                SectionTitle(stringResource(R.string.g7_id_requests), Modifier.padding(top = 24.dp, bottom = 6.dp))
                social.incoming.forEach { p -> PersonRow(p, trailing = { Row { SmallButton(stringResource(R.string.g7_id_accept), tonal = false) { social.acceptSync(p.id) }; Spacer(Modifier.width(6.dp)); SmallButton(stringResource(R.string.g7_id_ignore), tonal = true) { social.unsync(p.id) } } }) }
            }
            if (social.suggestions.isNotEmpty()) {
                SectionTitle(stringResource(R.string.g7_id_may_know), Modifier.padding(top = 24.dp, bottom = 6.dp))
                social.suggestions.take(8).forEach { s -> Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(s.name), size = 40)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(s.name, style = MaterialTheme.typography.titleMedium); Muted(listOfNotNull(s.area.ifBlank { null }, if (s.mutual > 0) pluralStringResource(R.plurals.g7_id_mutual, s.mutual, s.mutual) else null, s.distanceM?.let { stringResource(R.string.g7_dist_km, "%.1f".format(it / 1000)) }).joinToString(" · ")) }
                    SmallButton(stringResource(R.string.g7_id_sync_btn), tonal = true) { social.syncWith(s.id, s.name) }
                }; Divider() }
            }
            SectionTitle(stringResource(R.string.g7_id_synced), Modifier.padding(top = 24.dp, bottom = 6.dp))
            if (social.synced.isEmpty()) Muted(stringResource(R.string.g7_id_synced_empty))
            else Muted(stringResource(R.string.g7_id_contact_hint), Modifier.padding(bottom = 4.dp))
            social.synced.forEach { p -> val link = social.links[p.id]
                PersonRow(p, sub = link?.let { l -> listOfNotNull(l.org.ifBlank { null }, l.phones.firstOrNull(), l.emails.firstOrNull()).joinToString(" · ").ifBlank { null } } ?: if (p.id in social.closeFriends) stringResource(R.string.g7_id_close_friend) else p.area, trailing = {
                Row { link?.phones?.firstOrNull()?.let { num -> IconButton(onClick = { runCatching { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_DIAL, android.net.Uri.parse("tel:" + com.bucks.app.data.PhoneContacts.dialable(num)))) } }, modifier = Modifier.size(38.dp)) { Icon(Icons.Rounded.Call, stringResource(R.string.g7_cd_call_name, p.name), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary) } }
                      FilledTonalIconButton(onClick = { social.openDirect(p.id, onOpenChat) }, modifier = Modifier.size(38.dp)) { Icon(Icons.Rounded.ChatBubbleOutline, stringResource(R.string.g7_cd_message), Modifier.size(18.dp)) }
                      IconButton(onClick = { menuFor = p }) { Icon(Icons.Rounded.MoreVert, stringResource(R.string.g7_cd_more)) } } }) }
            Spacer(Modifier.height(24.dp))
        }
    }
    menuFor?.let { p -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text(p.name) }, text = { Column {
            val close = p.id in social.closeFriends
            TextButton({ linkFor = p; menuFor = null }) { Text(if (social.links.containsKey(p.id)) stringResource(R.string.g7_id_edit_contact) else stringResource(R.string.g7_id_contact)) }
            TextButton({ social.setClose(p.id, !close); menuFor = null }) { Text(if (close) stringResource(R.string.g7_id_remove_close) else stringResource(R.string.g7_id_add_close)) }
            TextButton({ social.unsync(p.id); menuFor = null }) { Text(stringResource(R.string.g7_id_unsync)) }
            TextButton({ social.block(p.id); menuFor = null }) { Text(stringResource(R.string.g7_id_block), color = MaterialTheme.colorScheme.error) }
        } }, confirmButton = { TextButton({ menuFor = null }) { Text(stringResource(R.string.g7_cd_close)) } }) }
    linkFor?.let { p -> ContactLinkSheet(vm, p) { linkFor = null } }
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
