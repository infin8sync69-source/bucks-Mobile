package com.bucks.app.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.VerificationLevel
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(vm: BucksViewModel, initialTab: String, onMenu: () -> Unit, onMessages: () -> Unit, onProCreate: () -> Unit, onOrder: (String) -> Unit, onRequest: (String) -> Unit, onEditProfile: () -> Unit, onToggleTheme: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, onCreatePost: () -> Unit = {}, onOpen: (String) -> Unit = {}, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val chats by vm.repo.chats.collectAsState(); val people by vm.repo.people.collectAsState(); val communities by vm.repo.communities.collectAsState(); val u = s.user ?: return
    val tabs = listOf("activity" to "Activity", "settings" to "Settings")
    var tab by remember(initialTab) { mutableStateOf(initialTab) }
    // Cloud builds: my real profile and posts (the demo profile writes to the local demo store, which no neighbour ever sees).
    if (tab == "profile") { if (vm.social.enabled) CloudPersonalProfile(vm, onEditProfile, onOpen) else PersonalProfile(vm, onEditProfile, onCreatePost); return }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Account", onMenu = onMenu, unread = vm.unreadCount(chats), onChat = onMessages)
        PrimaryTabRow(selectedTabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0), containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) { tabs.forEach { (k, l) -> Tab(selected = tab == k, onClick = { tab = k }, text = { Text(l, style = MaterialTheme.typography.labelLarge) }) } }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            when (tab) {
                "activity" -> {
                    SectionTitle("Rides", Modifier.padding(bottom = 4.dp))
                    if (s.rides.isEmpty()) Muted("No rides yet. Tap Taxi in Services when you need to go somewhere.") else s.rides.forEach { r -> ListRowCompact(r.kind.icon, r.dest.name, "₹${r.fare} · ${r.status.name.lowercase().replaceFirstChar { it.uppercase() }}" + (r.driver?.let { " · ${it.name}" } ?: "")) }
                    SectionTitle("Orders", Modifier.padding(top = 20.dp, bottom = 4.dp), action = if (vm.social.enabled) "See all" else null, onAction = if (vm.social.enabled) ({ onOpen(Routes.MY_ORDERS) }) else null)
                    if (vm.social.enabled) {
                        LaunchedEffect(vm.social.me?.id) { vm.commerce.refreshMyOrders() }
                        if (vm.commerce.myOrders.isEmpty()) Muted("No orders yet. Search for food, groceries or anything nearby.")
                        else vm.commerce.myOrders.take(5).forEach { o -> ListRowCompact(Icons.Rounded.ShoppingBag, vm.commerce.titleOf(o.listingId), "₹${o.subtotal + if (o.feePaidBy == "BUYER") o.deliveryFee else 0} · ${com.bucks.app.ui.screens.commerce.orderStatusLabel(o.status, o.deliveryMode)}") { onOpen(Routes.cloudOrder(o.id)) } }
                    } else if (s.orders.isEmpty()) Muted("No orders yet. Search for food, groceries or anything nearby.") else s.orders.forEach { o -> ListRowCompact(Icons.Rounded.ShoppingBag, o.providerName, "₹${o.total} · ${o.status.label}") { onOrder(o.id) } }
                    if (vm.social.enabled) { SectionTitle("Jobs", Modifier.padding(top = 20.dp, bottom = 4.dp)); ListRowCompact(Icons.Rounded.Work, "My applications", "Jobs you applied to and where they stand") { onOpen(Routes.MY_APPLICATIONS) } }
                    SectionTitle("Service requests", Modifier.padding(top = 20.dp, bottom = 4.dp))
                    if (s.requests.isEmpty()) Muted("No service requests yet. Search for a plumber, tutor or any skill.") else s.requests.forEach { r -> ListRowCompact(Icons.Rounded.Handyman, r.providerName, "${r.category} · ${r.status.label}") { onRequest(r.id) } }
                }
                else -> SettingsHub(vm, identity = { if (vm.social.enabled) BucksIdCard(vm) { onOpen(Routes.SYNC) } else VerificationCard(vm, u.id, u.verified) }, onOpen = onOpen, onEditProfile = onEditProfile, onLogout = onLogout, onDeleted = onDeleted, showToast = showToast)
            }
        }
    }
}

/** My own profile in cloud builds: name, Bucks ID, synced people and chats from the server, and my posts from the feed. Posting goes through social.post like the Feed tab. */
@Composable
private fun CloudPersonalProfile(vm: BucksViewModel, onEditProfile: () -> Unit, onOpen: (String) -> Unit) {
    val social = vm.social; val s by vm.state.collectAsState(); val u = s.user ?: return; val ctx = LocalContext.current
    val me = social.me
    var compose by remember { mutableStateOf(false) }; var comments by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(me?.id) { if (me != null) { social.refreshFeed(); social.refreshSyncs() } }
    val name = me?.name?.ifBlank { null } ?: u.name; val area = me?.area?.ifBlank { null } ?: u.area; val bio = me?.bio?.ifBlank { null } ?: u.bio
    val mine = social.feed.filter { it.authorId == me?.id }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ProfileCover(initials(name))
        Column(Modifier.padding(horizontal = Gutter, vertical = 10.dp)) {
            Text(name, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)); Muted(me?.let { "Bucks ID ${it.shortCode}" } ?: handleOf(name))
            if (area.isNotBlank()) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" $area") }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Row(Modifier.clickable { onOpen(Routes.SYNC) }, verticalAlignment = Alignment.Bottom) { Text("${social.synced.size}", style = MaterialTheme.typography.titleMedium); Muted(" synced") }
                Row(Modifier.clickable { onOpen(Routes.MESSAGES) }, verticalAlignment = Alignment.Bottom) { Text("${social.inbox.size}", style = MaterialTheme.typography.titleMedium); Muted(" chats") } }
            if (bio.isNotBlank()) Text(bio, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SoftButton("Edit profile", Icons.Rounded.EditNote, onClick = onEditProfile)
                SoftButton("Share", Icons.Rounded.IosShare) { shareText(ctx, "$name on Bucks" + (me?.let { " · Bucks ID ${it.shortCode}" } ?: "") + (if (area.isNotBlank()) " · $area" else "")) } }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
        Row(Modifier.padding(horizontal = Gutter, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name), size = 40)
            Box(Modifier.weight(1f).padding(start = 10.dp).height(40.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { compose = true }.padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) { Muted("Share with your neighbours") }
            IconButton(onClick = { compose = true }, modifier = Modifier.size(48.dp)) { Icon(Icons.Rounded.Add, "Create a post", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
        if (me != null && mine.isEmpty()) Muted("Your recent posts show here. Share a recommendation, a deal or a question above; neighbours see it in their Feed.", Modifier.padding(Gutter))
        mine.forEach { p -> CloudPostCard(vm, p, onVote = { social.vote(p.id, it) }, onComments = { comments = p.id }, onShare = { shareText(ctx, "${p.authorName} on Bucks: ${p.body}") }, onDelete = { social.deletePost(p.id) }) }
        Spacer(Modifier.height(24.dp))
    }
    if (compose) NewPostSheet(vm) { compose = false }
    comments?.let { id -> CloudCommentsSheet(vm, id) { comments = null } }
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

