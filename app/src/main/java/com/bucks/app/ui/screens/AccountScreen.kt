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
import com.bucks.app.data.VerificationLevel
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.theme.status

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(vm: BucksViewModel, initialTab: String, onMenu: () -> Unit, onMessages: () -> Unit, onProCreate: () -> Unit, onOrder: (String) -> Unit, onRequest: (String) -> Unit, onEditProfile: () -> Unit, onToggleTheme: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, onCreatePost: () -> Unit = {}, onOpen: (String) -> Unit = {}, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val chats by vm.repo.chats.collectAsState(); val people by vm.repo.people.collectAsState(); val communities by vm.repo.communities.collectAsState(); val u = s.user ?: return
    val tabs = listOf("activity" to "Activity", "settings" to "Settings")
    var tab by remember(initialTab) { mutableStateOf(initialTab) }
    if (tab == "profile") { PersonalProfile(vm, onEditProfile, onCreatePost); return }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Account", onMenu = onMenu, unread = vm.unreadCount(chats), onChat = onMessages)
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
                else -> SettingsHub(vm, identity = { if (vm.social.enabled) BucksIdCard(vm) { onOpen(Routes.SYNC) } else VerificationCard(vm, u.id, u.verified) }, onOpen = onOpen, onEditProfile = onEditProfile, onLogout = onLogout, onDeleted = onDeleted, showToast = showToast)
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

