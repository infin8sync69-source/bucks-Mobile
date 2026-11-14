package com.bucks.app.ui.screens

import com.bucks.app.data.Money
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Trust
import com.bucks.app.data.VerificationLevel
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(vm: BucksViewModel, initialTab: String, onMenu: () -> Unit, onMessages: () -> Unit, onProCreate: () -> Unit, onOrder: (String) -> Unit, onRequest: (String) -> Unit, onEditProfile: () -> Unit, onToggleTheme: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, onCreatePost: () -> Unit = {}, onOpen: (String) -> Unit = {}, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val chats by vm.repo.chats.collectAsState(); val people by vm.repo.people.collectAsState(); val communities by vm.repo.communities.collectAsState(); val u = s.user ?: return
    val tabs = listOf("activity" to stringResource(R.string.g5_acct_tab_activity), "settings" to stringResource(R.string.g5_acct_tab_settings))
    var tab by remember(initialTab) { mutableStateOf(initialTab) }
    // Cloud builds: my real profile and posts (the demo profile writes to the local demo store, which no neighbour ever sees).
    if (tab == "profile") { if (vm.social.enabled) CloudPersonalProfile(vm, onEditProfile, onOpen, onMenu, onMessages, vm.unreadCount(chats)) else PersonalProfile(vm, onEditProfile, onCreatePost); return }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g5_acct_title), onMenu = onMenu, unread = vm.unreadCount(chats), onChat = onMessages)
        PrimaryTabRow(selectedTabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0), containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) { tabs.forEach { (k, l) -> Tab(selected = tab == k, onClick = { tab = k }, text = { Text(l, style = MaterialTheme.typography.labelLarge) }) } }
        // Settings is the shared list, edge to edge; the activity tab keeps the page gutter.
        Column(Modifier.verticalScroll(rememberScrollState()).padding(if (tab == "settings" && vm.social.enabled) 0.dp else Gutter)) {
            when (tab) {
                "activity" -> {
                    SectionTitle(stringResource(R.string.g5_acct_rides), Modifier.padding(bottom = 4.dp))
                    if (s.rides.isEmpty()) Muted(stringResource(R.string.g5_acct_no_rides)) else s.rides.forEach { r -> ListRowCompact(r.kind.icon, r.dest.name, r.status.name.lowercase().replaceFirstChar { it.uppercase() }.let { st -> r.driver?.let { stringResource(R.string.g5_acct_ride_line_driver, Money.format(r.fare), st, it.name) } ?: stringResource(R.string.g5_acct_amount_status, Money.format(r.fare), st) }) }
                    SectionTitle(stringResource(R.string.g5_acct_orders), Modifier.padding(top = 20.dp, bottom = 4.dp), action = if (vm.social.enabled) stringResource(R.string.g5_see_all) else null, onAction = if (vm.social.enabled) ({ onOpen(Routes.MY_ORDERS) }) else null)
                    if (vm.social.enabled) {
                        LaunchedEffect(vm.social.me?.id) { vm.commerce.refreshMyOrders() }
                        if (vm.commerce.myOrders.isEmpty()) Muted(stringResource(R.string.g5_acct_no_orders))
                        else vm.commerce.myOrders.take(5).forEach { o -> ListRowCompact(Icons.Rounded.ShoppingBag, vm.commerce.titleOf(o.listingId), stringResource(R.string.g5_acct_amount_status, Money.format(o.subtotal + if (o.feePaidBy == "BUYER") o.deliveryFee else 0), com.bucks.app.ui.screens.commerce.orderStatusLabel(o.status, o.deliveryMode))) { onOpen(Routes.cloudOrder(o.id)) } }
                    } else if (s.orders.isEmpty()) Muted(stringResource(R.string.g5_acct_no_orders)) else s.orders.forEach { o -> ListRowCompact(Icons.Rounded.ShoppingBag, o.providerName, stringResource(R.string.g5_acct_amount_status, Money.format(o.total), o.status.label)) { onOrder(o.id) } }
                    if (vm.social.enabled) { SectionTitle(stringResource(R.string.g5_acct_jobs), Modifier.padding(top = 20.dp, bottom = 4.dp)); ListRowCompact(Icons.Rounded.Work, stringResource(R.string.g5_acct_my_applications), stringResource(R.string.g5_acct_my_applications_sub)) { onOpen(Routes.MY_APPLICATIONS) } }
                    if (vm.social.enabled) { SectionTitle(stringResource(R.string.g5_acct_people), Modifier.padding(top = 20.dp, bottom = 4.dp))
                        ListRowCompact(Icons.Rounded.QrCodeScanner, stringResource(R.string.g5_acct_recommend), stringResource(R.string.g5_acct_recommend_sub)) { onOpen(Routes.RECOMMEND_SCAN) }
                        ListRowCompact(Icons.Rounded.PersonSearch, stringResource(R.string.g5_acct_find_people), stringResource(R.string.g5_acct_find_people_sub)) { onOpen(Routes.DISCOVER) } }
                    SectionTitle(stringResource(R.string.g5_acct_service_requests), Modifier.padding(top = 20.dp, bottom = 4.dp))
                    if (s.requests.isEmpty()) Muted(stringResource(R.string.g5_acct_no_requests)) else s.requests.forEach { r -> ListRowCompact(Icons.Rounded.Handyman, r.providerName, stringResource(R.string.g5_acct_amount_status, r.category, r.status.label)) { onRequest(r.id) } }
                }
                // The Bucks Pro ID card and the payment QR are Pro: they live in the ☰ Bucks Pro menu, not here.
                else -> if (vm.social.enabled) com.bucks.app.ui.social.SettingsList(vm, onOpen, onEditProfile, onLogout, onDeleted)
                else SettingsHub(vm, identity = { VerificationCard(vm, u.id, u.verified) }, onOpen = onOpen, onEditProfile = onEditProfile, onLogout = onLogout, onDeleted = onDeleted, showToast = showToast)
            }
        }
    }
}

/** My own profile in cloud builds: name, Bucks ID, synced people and chats from the server, and my posts from the feed. Posting goes through social.post like the Feed tab. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CloudPersonalProfile(vm: BucksViewModel, onEditProfile: () -> Unit, onOpen: (String) -> Unit, onMenu: () -> Unit, onMessages: () -> Unit, unread: Int) {
    val social = vm.social; val s by vm.state.collectAsState(); val u = s.user ?: return; val ctx = LocalContext.current
    val me = social.me
    var compose by remember { mutableStateOf(false) }; var comments by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(me?.id) { if (me != null) { social.refreshFeed(); social.refreshSyncs() } }
    val name = me?.name?.ifBlank { null } ?: u.name; val area = me?.area?.ifBlank { null } ?: u.area; val bio = me?.bio?.ifBlank { null } ?: u.bio
    val mine = social.feed.filter { it.authorId == me?.id }
    val shareProfile = (me?.let { stringResource(R.string.g5_share_profile_id, name, it.shortCode) } ?: stringResource(R.string.g5_share_profile, name)) + (if (area.isNotBlank()) " · $area" else "")
    val sharePostFmt = stringResource(R.string.g5_share_post)
    Column(Modifier.fillMaxSize()) { BucksTopBar(stringResource(R.string.g5_profile_title), onMenu = onMenu, unread = unread, onChat = onMessages)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ProfileMediaHeader(vm, name, me?.photoUrl, me?.coverUrl, editable = me != null, busy = social.mediaBusy,
            onPick = { slot, picked -> social.setMyPicture(slot, picked) }, onRemove = { social.clearMyPicture(it) })
        Column(Modifier.padding(horizontal = Gutter, vertical = 10.dp)) {
            Text(name, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)); Muted(me?.let { stringResource(R.string.g5_bucks_id_code, it.shortCode) } ?: handleOf(name))
            if (area.isNotBlank()) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" $area") }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Row(Modifier.clickable { onOpen(Routes.SYNC) }, verticalAlignment = Alignment.Bottom) { Text("${social.synced.size}", style = MaterialTheme.typography.titleMedium); Muted(" " + stringResource(R.string.g5_synced_label)) }
                Row(Modifier.clickable { onOpen(Routes.CONTACTS) }, verticalAlignment = Alignment.Bottom) { Icon(Icons.Rounded.Group, null, Modifier.size(18.dp).padding(bottom = 2.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" " + stringResource(R.string.g5_contacts)) } }
            if (bio.isNotBlank()) Text(bio, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SoftButton(stringResource(R.string.g5_edit_profile), Icons.Rounded.EditNote, onClick = onEditProfile)
                SoftButton(stringResource(R.string.g5_share), Icons.Rounded.IosShare) { shareText(ctx, shareProfile) } }
        }
        // Profile is who I am and what I post. Orders and activity, settings, help and log out live in the ☰ menu, with the Bucks ID and everything Pro.
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
        Row(Modifier.padding(horizontal = Gutter, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name), size = 40, photoUrl = me?.photoUrl)
            Box(Modifier.weight(1f).padding(start = 10.dp).height(40.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { compose = true }.padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) { Muted(stringResource(R.string.g5_share_nearby_hint)) }
            IconButton(onClick = { compose = true }, modifier = Modifier.size(48.dp)) { Icon(Icons.Rounded.Add, stringResource(R.string.g5_cd_create_post), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        var ptab by rememberSaveable { mutableIntStateOf(0) }
        PrimaryTabRow(selectedTabIndex = ptab, containerColor = MaterialTheme.colorScheme.surface, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
            listOf(stringResource(R.string.g5_ptab_feed), stringResource(R.string.g5_ptab_media), stringResource(R.string.g5_ptab_files), stringResource(R.string.g5_ptab_recommended)).forEachIndexed { i, l -> Tab(selected = ptab == i, onClick = { ptab = i }, text = { Text(l, style = MaterialTheme.typography.labelLarge, maxLines = 1) }) }
        }
        when (ptab) {
            0 -> {
                if (me != null && mine.isEmpty()) Muted(stringResource(R.string.g5_posts_empty), Modifier.padding(Gutter))
                mine.forEach { p -> CloudPostCard(vm, p, onVote = { social.vote(p.id, it) }, onComments = { comments = p.id }, onShare = { shareText(ctx, sharePostFmt.format(p.authorName, p.body)) }, onDelete = { social.deletePost(p.id) }) }
            }
            1 -> MyMediaTab(vm)
            2 -> MyFilesTab(vm)
            else -> MyRecommendationsTab(vm, onOpen)
        }
        Spacer(Modifier.height(24.dp))
    }
    }
    if (compose) NewPostSheet(vm) { compose = false }
    comments?.let { id -> CloudCommentsSheet(vm, id) { comments = null } }
}

@Composable
private fun VerificationCard(vm: BucksViewModel, id: String, levels: Set<VerificationLevel>) {
    val ctx = LocalContext.current
    val docPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) vm.grantVerification(VerificationLevel.DOCUMENT) }
    BucksCard {
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Fingerprint, null, tint = MaterialTheme.colorScheme.primary); Column(Modifier.padding(start = 14.dp)) { Text(stringResource(R.string.g5_your_bucks_id), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g5_id_key_line, "${id.take(8)}…${id.takeLast(4)}")) } }
        Muted(stringResource(R.string.g5_id_key_explain), Modifier.padding(top = 10.dp))
        Divider()
        VerificationLevel.entries.forEach { lvl -> val ok = lvl in levels
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = if (ok) MaterialTheme.status.good else MaterialTheme.colorScheme.outline)
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(lvl.label, style = MaterialTheme.typography.titleSmall); Muted(lvl.detail) }
                if (!ok) when (lvl) {
                    VerificationLevel.DOCUMENT -> SmallButton(stringResource(R.string.g5_upload), tonal = true) { docPicker.launch(arrayOf("image/*", "application/pdf")) }
                    VerificationLevel.DEVICE -> SmallButton(stringResource(R.string.g5_check), tonal = true) { vm.grantVerification(VerificationLevel.DEVICE) }
                    else -> {}
                }
            }
        }
        Muted(stringResource(R.string.g5_doc_check_note), Modifier.padding(top = 10.dp))
    }
}

@Composable private fun StatCard(value: String, label: String, modifier: Modifier) = BucksCard(modifier, padding = 14) { Text(value, style = MaterialTheme.typography.titleLarge); Muted(label) }
@Composable private fun ProfileRow(icon: ImageVector, title: String, sub: String) = BucksCard(Modifier.padding(bottom = 10.dp), padding = 14) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Column(Modifier.padding(start = 14.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(sub) } } }
@Composable private fun ListRowCompact(icon: ImageVector, title: String, sub: String, onClick: (() -> Unit)? = null) { Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(icon = icon, size = 36, tinted = false); Column(Modifier.padding(start = 12.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(sub) } }; Divider() }

