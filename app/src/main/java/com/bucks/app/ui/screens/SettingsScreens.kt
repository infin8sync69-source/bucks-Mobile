package com.bucks.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Prefs
import com.bucks.app.data.SettingsRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.VOICE_LANGS
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive

/* ---------- reusable rows ---------- */

@Composable fun SettingRow(icon: ImageVector, label: String, detail: String? = null, onClick: () -> Unit) { ListRow(label, detail, leading = { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, trailing = { Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, onClick = onClick); Divider() }
@Composable fun ToggleRow(label: String, detail: String? = null, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(label, style = MaterialTheme.typography.titleMedium); detail?.let { Muted(it) } }; Switch(on, onChange) }
    Divider()
}
/** A titled group of radio choices. */
@Composable fun <T> ChoiceGroup(title: String, detail: String? = null, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Column(Modifier.padding(vertical = 8.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); detail?.let { Muted(it) }
        options.forEach { (v, l) -> Row(Modifier.fillMaxWidth().clickable { onSelect(v) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { RadioButton(v == selected, { onSelect(v) }); Text(l, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 4.dp)) } } }
    Divider()
}

/* ---------- hub ---------- */

/** Settings home. [identity] is the Bucks ID card (cloud) or the demo verification card. */
@Composable
fun SettingsHub(vm: BucksViewModel, identity: @Composable () -> Unit, onOpen: (String) -> Unit, onEditProfile: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val cloud = vm.social.enabled
    var deleteDialog by remember { mutableStateOf(false) }
    SectionTitle("Identity", Modifier.padding(bottom = 10.dp)); identity()
    SectionTitle("Preferences", Modifier.padding(top = 22.dp, bottom = 6.dp))
    SettingRow(Icons.Rounded.Person, "Edit profile", onClick = onEditProfile)
    if (cloud) SettingRow(Icons.Rounded.Sync, "Sync", "Requests, people you may know, synced people") { onOpen(Routes.SYNC) }
    SettingRow(Icons.Rounded.Lock, "Privacy", if (cloud) "Who can message and sync with you, Moments audience, read receipts" else "Available once you're signed in with Bucks online") { if (cloud) onOpen(Routes.SETTINGS_PRIVACY) else showToast("Privacy settings need the online build.") }
    SettingRow(Icons.Rounded.Notifications, "Notifications", "What Bucks tells you about, and quiet hours") { if (cloud) onOpen(Routes.SETTINGS_NOTIFS) else showToast("Notification settings need the online build.") }
    SettingRow(Icons.Rounded.Palette, "Appearance and data", "Theme, text size, motion, media on mobile data") { onOpen(Routes.SETTINGS_APPEARANCE) }
    if (cloud) { SettingRow(Icons.Rounded.Block, "Blocked people") { onOpen(Routes.SETTINGS_BLOCKED) }; SettingRow(Icons.Rounded.Favorite, "Close friends", "Who sees Moments you share with close friends") { onOpen(Routes.SETTINGS_CLOSE) } }
    if (vm.dispatch.enabled) ListRow("Payment QR", "The UPI QR customers pay to after a trip", leading = { Avatar(icon = Icons.Rounded.QrCode2) }, trailing = { Icon(Icons.Rounded.ChevronRight, null) }) { onOpen(Routes.PAYMENT_QR) }
    SectionTitle("Voice and AI", Modifier.padding(top = 22.dp, bottom = 10.dp))
    BucksCard { Text("Voice language", style = MaterialTheme.typography.titleSmall); Row(Modifier.padding(top = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { VOICE_LANGS.forEach { (tag, label) -> Chip(label, selected = s.voiceLang == tag) { vm.setVoiceLang(tag) } } }
        Divider(); Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("Cloud understanding", style = MaterialTheme.typography.titleSmall); Muted(if (vm.cloudEnabled) "Free-form commands are understood by Gemini. Only the command text is sent, never PINs, payments or documents." else "Off. The built-in rules work offline.") }; Icon(if (vm.cloudEnabled) Icons.Rounded.CloudDone else Icons.Rounded.CloudOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
    SectionTitle("About", Modifier.padding(top = 22.dp, bottom = 6.dp))
    SettingRow(Icons.Rounded.Gavel, "Community rules") { showToast("Review only what you actually ordered or booked. Every review needs a reason. One account per person.") }
    SectionTitle("Account", Modifier.padding(top = 22.dp, bottom = 6.dp))
    SettingRow(Icons.Rounded.Logout, "Log out", onClick = onLogout)
    SettingRow(Icons.Rounded.DeleteOutline, "Delete account") { deleteDialog = true }
    if (deleteDialog) AlertDialog(onDismissRequest = { deleteDialog = false }, title = { Text("Delete your account?") },
        text = { Text(if (cloud) "This removes your profile, listings, messages and sign-in from Bucks. It can't be undone." else "This removes your profile, listings, businesses, saved sign-in and identity key from this device. It can't be undone.") },
        confirmButton = { TextButton(onClick = { deleteDialog = false; vm.deleteAccount(); onDeleted() }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deleteDialog = false }) { Text("Cancel") } })
}

/* ---------- pages ---------- */

@Composable
fun PrivacyScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; val saved = social.settings ?: SettingsRow(social.me?.id ?: "")
    var row by remember(saved) { mutableStateOf(saved) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Privacy", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ChoiceGroup("Who can message me", "People on an active trip or order with you can always message you.", listOf("SYNCED" to "People I've synced with", "EVERYONE" to "Everyone", "NOBODY" to "Nobody new"), row.whoCanMessage) { row = row.copy(whoCanMessage = it) }
            ChoiceGroup("Who can send me sync requests", null, listOf("EVERYONE" to "Everyone", "NOBODY" to "Nobody"), row.whoCanSync) { row = row.copy(whoCanSync = it) }
            ChoiceGroup("Default audience for my Moments", "You can change it on each moment.", listOf("SYNCED" to "Synced people", "LOCAL" to "Synced people and neighbours within 5 km", "CLOSE" to "Close friends only"), row.momentsAudience) { row = row.copy(momentsAudience = it) }
            ToggleRow("Read receipts", "Off: nobody sees when you've read, and you don't see it either.", row.readReceipts) { row = row.copy(readReceipts = it) }
            ToggleRow("Show when I'm online", null, row.showOnline) { row = row.copy(showOnline = it) }
            ToggleRow("Suggest me to people nearby", "Off: you won't appear under 'People you may know'.", row.discoverable) { row = row.copy(discoverable = it) }
            Muted("Your phone number is never shown to other users. Drivers and customers see each other's number only during a trip or delivery.", Modifier.padding(top = 12.dp))
            PrimaryButton("Save", Modifier.padding(top = 20.dp), enabled = row != saved) { social.saveSettings(row) }
        }
    }
}

// Keys the notify Edge Function checks (supabase/functions/notify/index.ts, NotifyKey); a missing key means on, except offers.
private val NOTIFY_KEYS = listOf("messages" to "Messages", "sync_requests" to "Sync requests", "moments" to "Moments from synced people", "comments" to "Comments on my posts", "my_orders" to "Updates on orders I place", "my_trips" to "Updates on rides and deliveries I book", "orders" to "New orders for my businesses", "tasks" to "Trips I drive (cancellations, payments)", "offers" to "Offers and deals nearby")

@Composable
fun NotificationsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; val saved = social.settings ?: SettingsRow(social.me?.id ?: "")
    var row by remember(saved) { mutableStateOf(saved) }
    fun on(k: String) = row.notify[k]?.jsonPrimitive?.booleanOrNull ?: (k != "offers")
    fun set(k: String, v: Boolean) { row = row.copy(notify = JsonObject(row.notify + (k to JsonPrimitive(v)))) }
    val quiet = row.quietHours; var qOn by remember(saved) { mutableStateOf(quiet != null) }
    var from by remember(saved) { mutableStateOf(quiet?.get("from")?.jsonPrimitive?.content ?: "22:00") }; var to by remember(saved) { mutableStateOf(quiet?.get("to")?.jsonPrimitive?.content ?: "07:00") }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Notifications", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            NOTIFY_KEYS.forEach { (k, l) -> ToggleRow(l, null, on(k)) { set(k, it) } }
            ToggleRow("Quiet hours", "No sounds or banners between these times. Ride requests still ring while you're online.", qOn) { qOn = it }
            if (qOn) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { BucksField(from, { from = it.take(5) }, "From", "22:00", Modifier.weight(1f)); BucksField(to, { to = it.take(5) }, "To", "07:00", Modifier.weight(1f)) }
            PrimaryButton("Save", Modifier.padding(top = 20.dp)) {
                val q = if (qOn && Regex("^\\d{2}:\\d{2}$").matches(from) && Regex("^\\d{2}:\\d{2}$").matches(to)) JsonObject(mapOf("from" to JsonPrimitive(from), "to" to JsonPrimitive(to))) else null
                social.saveSettings(row.copy(quietHours = q)) }
            Muted("Notifications reach this phone even when Bucks is closed. Quiet hours make them silent; ride, delivery and new-order alerts still ring, because someone is waiting.", Modifier.padding(top = 12.dp))
        }
    }
}

@Composable
fun AppearanceScreen(onBack: () -> Unit) {
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Appearance and data", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ChoiceGroup("Theme", null, Prefs.Theme.entries.map { it to it.label }, Prefs.theme) { Prefs.chooseTheme(it) }
            ChoiceGroup("Text size", null, Prefs.TextSize.entries.map { it to it.label }, Prefs.textSize) { Prefs.chooseTextSize(it) }
            ToggleRow("Reduce motion", "Turns off pulses and other looping animations.", Prefs.reduceMotion) { Prefs.enableReduceMotion(it) }
            ChoiceGroup("Download photos and files", "Applies to chats and Moments on mobile data.", Prefs.MediaDownload.entries.map { it to it.label }, Prefs.mediaDownload) { Prefs.chooseMediaDownload(it) }
            ToggleRow("Data saver", "Lighter maps and smaller images.", Prefs.dataSaver) { Prefs.enableDataSaver(it) }
            ChoiceGroup("App language", "Menus and buttons. Translations are being added; English is complete.", Prefs.LANGUAGES, Prefs.language) { Prefs.chooseLanguage(it) }
        }
    }
}

@Composable
fun BlockedScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; LaunchedEffect(Unit) { social.refreshBlocked() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Blocked people", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (social.blocked.isEmpty()) Muted("Nobody is blocked. Block someone from a chat or their profile.")
            social.blocked.forEach { p -> PersonRow(p, trailing = { SmallButton("Unblock", tonal = true) { social.unblock(p.id) } }) }
        }
    }
}

@Composable
fun CloseFriendsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; LaunchedEffect(Unit) { social.refreshSyncs() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Close friends", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Muted("Moments shared with 'Close friends' are seen only by the people ticked here. They aren't told they're on the list.", Modifier.padding(bottom = 8.dp))
            if (social.synced.isEmpty()) Muted("Sync with people first.")
            social.synced.forEach { p -> val on = p.id in social.closeFriends; PersonRow(p, trailing = { Checkbox(on, { social.setClose(p.id, it) }) }) }
        }
    }
}
