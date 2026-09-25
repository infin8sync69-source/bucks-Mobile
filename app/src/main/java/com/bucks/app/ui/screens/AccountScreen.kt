package com.bucks.app.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.SyncStatus
import com.bucks.app.data.VerificationLevel
import com.bucks.app.ui.VOICE_LANGS
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(vm: BucksViewModel, initialTab: String, onMenu: () -> Unit, onMessages: () -> Unit, onProCreate: () -> Unit, onOrder: (String) -> Unit, onRequest: (String) -> Unit, onEditProfile: () -> Unit, onToggleTheme: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, onCreatePost: () -> Unit = {}, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val chats by vm.repo.chats.collectAsState(); val people by vm.repo.people.collectAsState(); val communities by vm.repo.communities.collectAsState(); val u = s.user ?: return
    val tabs = listOf("activity" to "Activity", "settings" to "Settings")
    var tab by remember(initialTab) { mutableStateOf(initialTab) }
    if (tab == "profile") { PersonalProfile(vm, onEditProfile, onCreatePost); return }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Account", onMenu = onMenu, unread = chats.sumOf { it.unread }, onChat = onMessages)
        PrimaryTabRow(selectedTabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0), containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) { tabs.forEach { (k, l) -> Tab(selected = tab == k, onClick = { tab = k }, text = { Text(l, style = MaterialTheme.typography.labelLarge) }) } }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            when (tab) {
                "activity" -> {
                    SectionTitle("Rides", Modifier.padding(bottom = 4.dp))
                    if (s.rides.isEmpty()) Muted("No rides yet. Tap Taxi in Services when you need to go somewhere.") else s.rides.forEach { r -> ListRowCompact(r.kind.icon, r.dest.name, "₹${r.fare} · ${r.status.name.lowercase().replaceFirstChar { it.uppercase() }}" + (r.driver?.let { " · ${it.name}" } ?: "")) }
                    SectionTitle("Orders", Modifier.padding(top = 20.dp, bottom = 4.dp))
                    if (s.orders.isEmpty()) Muted("No orders yet. Search for food, groceries or anything nearby.") else s.orders.forEach { o -> ListRowCompact(Icons.Rounded.ShoppingBag, o.providerName, "₹${o.total} · ${o.status.label}") { onOrder(o.id) } }
                    SectionTitle("Service requests", Modifier.padding(top = 20.dp, bottom = 4.dp))
                    if (s.requests.isEmpty()) Muted("No service requests yet. Search for a plumber, tutor or any skill.") else s.requests.forEach { r -> ListRowCompact(Icons.Rounded.Handyman, r.providerName, "${r.category} · ${r.status.label}") { onRequest(r.id) } }
                }
                else -> { SectionTitle("Identity", Modifier.padding(bottom = 10.dp)); VerificationCard(vm, u.id, u.verified); Spacer(Modifier.height(22.dp)); SettingsTab(vm, onEditProfile, onToggleTheme, onLogout, onDeleted, showToast) }
            }
        }
    }
}

@Composable
private fun VerificationCard(vm: BucksViewModel, id: String, levels: Set<VerificationLevel>) {
    val ctx = LocalContext.current
    val docPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) vm.grantVerification(VerificationLevel.DOCUMENT) }
    BucksCard {
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Fingerprint, null, tint = MaterialTheme.colorScheme.primary); Column(Modifier.padding(start = 14.dp)) { Text("Your Bucks ID", style = MaterialTheme.typography.titleMedium); Muted("${id.take(8)}…${id.takeLast(4)} · key stored in this phone's secure hardware") } }
        Muted("Every ride, order and review you make is signed with this key. Higher levels make your reviews count in more filters.", Modifier.padding(top = 10.dp))
        Divider()
        VerificationLevel.entries.forEach { lvl -> val ok = lvl in levels
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = if (ok) MaterialTheme.status.good else MaterialTheme.colorScheme.outline)
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(lvl.label, style = MaterialTheme.typography.titleSmall); Muted(lvl.detail) }
                if (!ok) when (lvl) {
                    VerificationLevel.DOCUMENT -> SmallButton("Upload", tonal = true) { docPicker.launch(arrayOf("image/*", "application/pdf")) }
                    VerificationLevel.DEVICE -> SmallButton("Check", tonal = true) { vm.grantVerification(VerificationLevel.DEVICE) }
                    else -> {}
                }
            }
        }
        Muted("Document checks run through a DigiLocker/KYC partner in production; in this build the upload is accepted immediately.", Modifier.padding(top = 10.dp))
    }
}

@Composable private fun StatCard(value: String, label: String, modifier: Modifier) = BucksCard(modifier, padding = 14) { Text(value, style = MaterialTheme.typography.titleLarge); Muted(label) }
@Composable private fun ProfileRow(icon: ImageVector, title: String, sub: String) = BucksCard(Modifier.padding(bottom = 10.dp), padding = 14) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Column(Modifier.padding(start = 14.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(sub) } } }
@Composable private fun ListRowCompact(icon: ImageVector, title: String, sub: String, onClick: (() -> Unit)? = null) { Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(icon = icon, size = 36, tinted = false); Column(Modifier.padding(start = 12.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(sub) } }; Divider() }

@Composable
private fun SettingsTab(vm: BucksViewModel, onEditProfile: () -> Unit, onToggleTheme: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val ctx = LocalContext.current
    var deleteDialog by remember { mutableStateOf(false) }
    var linkDialog by remember { mutableStateOf(false) }; var code by remember { mutableStateOf("") }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> uri?.let { u -> runCatching { ctx.contentResolver.openOutputStream(u)?.use { it.write(vm.exportSnapshot().toByteArray()) }; showToast("Backup saved. Open it on another device to restore.") } } }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { u -> runCatching { ctx.contentResolver.openInputStream(u)?.bufferedReader()?.readText() }.getOrNull()?.let { vm.importSnapshot(it) } } }

    SectionTitle("Devices and sync", Modifier.padding(bottom = 10.dp))
    BucksCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(when (s.syncStatus) { SyncStatus.SYNCED -> Icons.Rounded.CloudDone; SyncStatus.SYNCING -> Icons.Rounded.Sync; SyncStatus.OFFLINE -> Icons.Rounded.CloudOff }, null, tint = if (s.syncStatus == SyncStatus.SYNCED) MaterialTheme.status.good else MaterialTheme.colorScheme.onSurfaceVariant)
            Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(when (s.syncStatus) { SyncStatus.SYNCED -> "Everything is in sync"; SyncStatus.SYNCING -> "Syncing…"; SyncStatus.OFFLINE -> "Offline, will sync later" }, style = MaterialTheme.typography.titleMedium); Muted("Last synced ${s.lastSynced} · encrypted backup of your profile and preferences") }
            SmallButton("Sync now", tonal = true, enabled = s.syncStatus != SyncStatus.SYNCING) { vm.syncNow() }
        }
        Divider()
        s.devices.forEach { d -> Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(if (d.thisDevice) Icons.Rounded.Smartphone else Icons.Rounded.Devices, null, tint = MaterialTheme.colorScheme.onSurfaceVariant); Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(d.name + if (d.thisDevice) " (this device)" else "", style = MaterialTheme.typography.titleSmall); Muted(d.lastSeen) }; if (!d.thisDevice) TextButton(onClick = { vm.unlinkDevice(d.id) }) { Text("Unlink") } } }
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SmallButton("Link a device", Modifier.weight(1f)) { linkDialog = true }; SmallButton("Back up", Modifier.weight(1f), tonal = true) { exportLauncher.launch("bucks-backup.json") }; SmallButton("Restore", Modifier.weight(1f), tonal = true) { importLauncher.launch(arrayOf("application/json", "*/*")) } }
    }
    SectionTitle("Voice and AI", Modifier.padding(top = 22.dp, bottom = 10.dp))
    BucksCard { Text("Voice language", style = MaterialTheme.typography.titleSmall); Row(Modifier.padding(top = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { VOICE_LANGS.forEach { (tag, label) -> Chip(label, selected = s.voiceLang == tag) { vm.setVoiceLang(tag) } } }
        Divider(); Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("Cloud understanding", style = MaterialTheme.typography.titleSmall); Muted(if (vm.cloudEnabled) "Free-form commands are understood by Gemini. Only the command text is sent, never PINs, payments or documents." else "Off. Add GEMINI_API_KEY to local.properties to understand free-form commands; the built-in rules work offline.") }; Icon(if (vm.cloudEnabled) Icons.Rounded.CloudDone else Icons.Rounded.CloudOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
    SectionTitle("Preferences", Modifier.padding(top = 22.dp, bottom = 10.dp))
    SettingRow(Icons.Rounded.Person, "Edit profile", onEditProfile)
    SettingRow(Icons.Rounded.Notifications, "Notifications") { showToast("Notification settings") }
    SettingRow(Icons.Rounded.DarkMode, "Appearance", onToggleTheme)
    SettingRow(Icons.Rounded.Lock, "Privacy and data") { showToast("Location is used only while you book or drive. Your number is never shown to other users.") }
    SettingRow(Icons.Rounded.Gavel, "Community rules") { showToast("Review only what you actually ordered or booked. Every review needs a reason.") }
    SectionTitle("Account", Modifier.padding(top = 22.dp, bottom = 10.dp))
    SettingRow(Icons.Rounded.Logout, "Log out", onLogout)
    SettingRow(Icons.Rounded.DeleteOutline, "Delete account") { deleteDialog = true }
    if (deleteDialog) AlertDialog(onDismissRequest = { deleteDialog = false }, title = { Text("Delete your account?") },
        text = { Text("This removes your profile, listings, businesses, saved sign-in and identity key from this device. It can't be undone. Back up first if you want to restore it later.") },
        confirmButton = { TextButton(onClick = { deleteDialog = false; vm.deleteAccount(); onDeleted() }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deleteDialog = false }) { Text("Cancel") } })
    if (linkDialog) AlertDialog(onDismissRequest = { linkDialog = false }, title = { Text("Link a device") }, text = { Column { Muted("Install Bucks on the other device, sign in with the same number, then enter the 6-character code it shows under Settings → Devices."); OutlinedTextField(code, { code = it.take(6) }, modifier = Modifier.padding(top = 12.dp).fillMaxWidth(), singleLine = true, placeholder = { Text("A1B2C3") }); Muted("This device's code: ${s.devices.firstOrNull { it.thisDevice }?.id?.takeLast(6)?.uppercase() ?: "—"}", Modifier.padding(top = 8.dp)) } },
        confirmButton = { TextButton(onClick = { if (vm.linkDevice(code)) { linkDialog = false; code = "" } }) { Text("Link") } }, dismissButton = { TextButton(onClick = { linkDialog = false }) { Text("Cancel") } })
}
@Composable private fun SettingRow(icon: ImageVector, label: String, onClick: () -> Unit) { ListRow(label, leading = { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, trailing = { Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, onClick = onClick); Divider() }
