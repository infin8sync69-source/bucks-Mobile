package com.bucks.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Good
import com.bucks.app.ui.theme.Bad

/* ---------------- FEED ---------------- */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, showToast: (String) -> Unit) {
    val ctx = LocalContext.current
    val s by vm.state.collectAsState(); val posts by vm.repo.posts.collectAsState(); val chats by vm.repo.chats.collectAsState()
    var compose by remember { mutableStateOf(false) }; var text by remember { mutableStateOf("") }; var comments by remember { mutableStateOf<String?>(null) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Feed", onMenu = onMenu, unread = chats.sumOf { it.unread }, onChat = onMessages)
        LazyColumn {
            item { Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) { SearchBar("Share something with your neighbourhood") { compose = true } } }
            items(posts, key = { it.id }) { p -> PostCard(p, s.postVotes[p.id] ?: 0, onVote = { vm.votePost(p.id, it) }, onComments = { comments = p.id }, onShare = { sharePost(ctx, p) }) }
        }
    }
    if (compose) ModalBottomSheet(onDismissRequest = { compose = false }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) { Text("New post", style = MaterialTheme.typography.titleLarge); BucksField(text, { text = it }, placeholder = "Ask for a recommendation, share a deal, thank a provider", modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 4); PrimaryButton("Post") { vm.addPost(text.trim()); if (text.isNotBlank()) { text = ""; compose = false } } } }
    comments?.let { id -> PostCommentsSheet(vm, id) { comments = null } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostCommentsSheet(vm: BucksViewModel, id: String, onDismiss: () -> Unit) {
    val posts by vm.repo.posts.collectAsState(); val p = posts.firstOrNull { it.id == id } ?: return; var reply by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) { Text("Comments", style = MaterialTheme.typography.titleLarge)
        if (p.comments.isEmpty()) Muted("Be the first to reply.", Modifier.padding(vertical = 12.dp)) else p.comments.forEach { cm -> Column(Modifier.padding(vertical = 10.dp)) { Text(cm.first, style = MaterialTheme.typography.titleSmall); Text(cm.second, style = MaterialTheme.typography.bodyMedium) }; Divider() }
        Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(reply, { reply = it }, placeholder = { Text("Reply") }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp), singleLine = true); Spacer(Modifier.width(8.dp)); FilledIconButton(onClick = { vm.addComment(p.id, reply.trim()); reply = "" }) { Icon(Icons.AutoMirrored.Rounded.Send, "Send") } } } }
}

/** Post in the design's style: author row, text, photo / file, then up / down votes, comments and share. */
@Composable
fun PostCard(p: Post, myVote: Int, onVote: (Int) -> Unit, onComments: () -> Unit, onShare: () -> Unit, mine: Boolean = false, divider: Boolean = true) {
    val ctx = LocalContext.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(p.who), size = 40)
            Column(Modifier.padding(start = 10.dp).weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(p.who, style = MaterialTheme.typography.titleMedium); if (mine) Muted("  ·  You") }; Muted(p.ago) } }
        if (p.text.isNotBlank()) Text(p.text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        when {
            p.image != null -> AsyncImage(p.image, null, Modifier.padding(top = 10.dp).fillMaxWidth().heightIn(max = 360.dp).clip(RoundedCornerShape(16.dp)).clickable { openUri(ctx, p.image) }, contentScale = ContentScale.Crop)
            p.hasImage -> Box(Modifier.padding(top = 10.dp).fillMaxWidth().height(200.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Image, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        p.file?.let { name -> BucksCard(Modifier.padding(top = 8.dp), padding = 12, onClick = p.attachment?.let { a -> { openUri(ctx, a.uri) } }) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.primary); Text(name, Modifier.padding(start = 10.dp), style = MaterialTheme.typography.bodyMedium) } } }
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable { onVote(1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowUpward, "Recommend post", Modifier.size(20.dp), tint = if (myVote == 1) Good else Good.copy(alpha = 0.7f)); Text(" ${p.up}", color = Good, style = MaterialTheme.typography.labelLarge.copy(fontWeight = if (myVote == 1) FontWeight.Bold else FontWeight.Medium)) }
            Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable { onVote(-1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowDownward, "Not recommended", Modifier.size(20.dp), tint = if (myVote == -1) Bad else Bad.copy(alpha = 0.7f)); Text(" ${p.down}", color = Bad, style = MaterialTheme.typography.labelLarge.copy(fontWeight = if (myVote == -1) FontWeight.Bold else FontWeight.Medium)) }
            Spacer(Modifier.weight(1f))
            Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onComments).padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ChatBubbleOutline, "Comments", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${p.comments.size}") }
            IconButton(onClick = onShare) { Icon(Icons.Rounded.IosShare, "Share", Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
    if (divider) Divider()
}

/* ---------------- FOR YOU: discovery + recommendations ---------------- */
private data class Reco(val kind: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val title: String, val detail: String, val n: Int, val onClick: () -> Unit)

@Composable
fun RecommendedScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onProvider: (String) -> Unit, onRide: (VehicleKind) -> Unit, onChatWith: (String, String) -> Unit) {
    val providers by vm.repo.providers.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val posts by vm.repo.posts.collectAsState(); val chats by vm.repo.chats.collectAsState()
    val people by vm.repo.people.collectAsState(); val communities by vm.repo.communities.collectAsState()
    var filter by remember { mutableStateOf("All") }; var driverSheet by remember { mutableStateOf<Driver?>(null) }
    val items = (providers.filter { it.up >= 20 }.map { p -> Reco(p.category, p.icon, p.name, p.bio, p.up) { onProvider(p.id) } } +
        drivers.filter { it.up >= 40 }.map { d -> Reco("${d.vehicle.label} rider", d.vehicle.icon, d.name, "${d.model} · ${d.plate} · ${d.distanceKm} km", d.up) { driverSheet = d } } +
        posts.filter { it.up >= 20 }.map { p -> Reco("Post", Icons.Rounded.Article, p.who, p.text, p.up) {} }).sortedByDescending { it.n }
        .filter { when (filter) { "Food & shops" -> it.icon == Icons.Rounded.Storefront; "Skills" -> it.icon == Icons.Rounded.Handyman; "Riders" -> it.kind.contains("rider"); "Posts" -> it.kind == "Post"; else -> true } }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("For you", onMenu = onMenu, unread = chats.sumOf { it.unread }, onChat = onMessages)
        LazyColumn {
            item { SectionTitle("People near you", Modifier.padding(20.dp, 8.dp, 20.dp, 10.dp)); LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { items(people.sortedBy { it.distanceKm }) { p -> PersonCard(p, onFollow = { vm.follow(p.id, !p.following) }, onMessage = { onChatWith(p.name, "Neighbour") }) } } }
            item { SectionTitle("Communities", Modifier.padding(20.dp, 20.dp, 20.dp, 10.dp)); LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { items(communities) { c -> CommunityCard(c) { vm.join(c.id, !c.joined) } } } }
            item { Column(Modifier.padding(20.dp, 24.dp, 20.dp, 6.dp)) { SectionTitle("Recommended"); Muted("What people you sync with recommended after a real order or ride. No algorithm."); Row(Modifier.padding(top = 12.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("All", "Food & shops", "Skills", "Riders", "Posts").forEach { f -> Chip(f, selected = filter == f) { filter = f } } } } }
            items(items) { r ->
                Column(Modifier.fillMaxWidth().clickable(onClick = r.onClick).padding(20.dp, 14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Avatar(icon = r.icon, tinted = false); Column(Modifier.weight(1f).padding(start = 14.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(r.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); PillGrey(r.kind) }; Muted(r.detail, maxLines = 1) } }
                    Row(Modifier.padding(top = 10.dp, start = 58.dp), verticalAlignment = Alignment.CenterVertically) {
                        Row { (0..2).forEach { i -> Box(Modifier.offset(x = (-6 * i).dp).size(22.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Text(Seed.PEOPLE[(r.title.length + i) % Seed.PEOPLE.size].take(1), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer) } } }
                        val first = Seed.PEOPLE[r.title.length % Seed.PEOPLE.size]
                        Text(if (r.n <= 1) "$first recommended this" else "$first and ${r.n - 1} other${if (r.n > 2) "s" else ""} recommended this", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Divider()
            }
        }
    }
    driverSheet?.let { d -> AlertDialog(onDismissRequest = { driverSheet = null }, title = { Text(d.name) }, text = { Column { Muted("${d.model} · ${d.plate} · ${d.distanceKm} km"); TrustBadge(d.trust); Text(if (d.online) "Online now" else "Offline", color = if (d.online) Good else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 6.dp)); Text("\"Safe driver, knows the shortcuts.\" — Anitha", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) } },
        confirmButton = { TextButton(enabled = d.online, onClick = { driverSheet = null; onRide(d.vehicle) }) { Text("Book a ${d.vehicle.label.lowercase()} now") } }, dismissButton = { TextButton(onClick = { driverSheet = null }) { Text("Close") } }) }
}

@Composable
private fun PersonCard(p: Person, onFollow: () -> Unit, onMessage: () -> Unit) = BucksCard(Modifier.width(200.dp), padding = 14) {
    Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(p.name), size = 40); Column(Modifier.padding(start = 10.dp)) { Text(p.name, style = MaterialTheme.typography.titleSmall, maxLines = 1); Muted("${p.distanceKm} km", maxLines = 1) } }
    Muted(p.tagline, Modifier.padding(vertical = 8.dp).height(32.dp), maxLines = 2)
    TrustBadge(p.trust, compact = true)
    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { SmallButton(if (p.following) "Following" else "Follow", Modifier.weight(1f), tonal = p.following, onClick = onFollow); FilledTonalIconButton(onClick = onMessage, modifier = Modifier.size(38.dp)) { Icon(Icons.Rounded.ChatBubbleOutline, "Message", modifier = Modifier.size(18.dp)) } }
}

@Composable
private fun CommunityCard(c: Community, onJoin: () -> Unit) = BucksCard(Modifier.width(220.dp), padding = 14) {
    Row(verticalAlignment = Alignment.CenterVertically) { Avatar(icon = Icons.Rounded.Groups, size = 36, tinted = false); Column(Modifier.padding(start = 10.dp)) { Text(c.name, style = MaterialTheme.typography.titleSmall, maxLines = 1); Muted("${c.members} members", maxLines = 1) } }
    Muted(c.description, Modifier.padding(vertical = 8.dp).height(32.dp), maxLines = 2)
    SmallButton(if (c.joined) "Joined" else "Join", Modifier.fillMaxWidth(), tonal = c.joined, onClick = onJoin)
}

/* ---------------- MESSAGES ---------------- */
@Composable
fun MessagesScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit, onCall: (String, String) -> Unit) {
    val chats by vm.repo.chats.collectAsState()
    val wide = windowWidth() == Width.EXPANDED
    var selected by remember { mutableStateOf<String?>(null) }
    Row(Modifier.fillMaxSize()) {
        Column(Modifier.then(if (wide) Modifier.width(360.dp) else Modifier.fillMaxWidth())) {
            BucksTopBar("Messages", onBack = onBack)
            LazyColumn { items(chats, key = { it.id }) { c ->
                Surface(color = if (wide && selected == c.id) MaterialTheme.colorScheme.surfaceContainer else Color.Transparent) {
                    ListRow(c.who, "${c.role} · ${c.messages.last().text}", leading = { Box { Avatar(initials(c.who)); Box(Modifier.align(Alignment.BottomEnd).size(11.dp).clip(CircleShape).background(if (c.online) Good else MaterialTheme.colorScheme.outline)) } },
                        trailing = { if (c.unread > 0) PillPurple("${c.unread}") }, onClick = { vm.markRead(c.id); if (wide) selected = c.id else onOpen(c.id) }) }
                Divider() } }
        }
        if (wide) { VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant); Box(Modifier.weight(1f)) { val id = selected; if (id == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Muted("Pick a conversation") } else ChatScreen(vm, id, onBack = { selected = null }, onCall = onCall, embedded = true) } }
    }
}

@Composable
fun ChatScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onCall: (String, String) -> Unit, embedded: Boolean = false) {
    val chats by vm.repo.chats.collectAsState(); val c = chats.firstOrNull { it.id == id } ?: return
    val ctx = LocalContext.current
    var text by remember { mutableStateOf("") }; val listState = rememberLazyListState()
    LaunchedEffect(c.messages.size) { if (c.messages.isNotEmpty()) listState.animateScrollToItem(c.messages.size - 1) }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { vm.sendAttachment(c.id, Attachment(it.toString(), "Photo", true)) } }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { u ->
        runCatching { ctx.contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        val name = ctx.contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null } ?: "File"
        val isImage = ctx.contentResolver.getType(u)?.startsWith("image/") == true
        vm.sendAttachment(c.id, Attachment(u.toString(), name, isImage)) } }
    Column(Modifier.fillMaxSize()) {
        BucksTopBar(c.who, onBack = if (embedded) null else onBack, actions = { IconButton(onClick = { onCall(c.who, c.phone) }) { Icon(Icons.Rounded.Call, "Call") } })
        Muted("${c.role} · ${if (c.online) "online" else "offline"}", Modifier.padding(start = 20.dp, bottom = 4.dp))
        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp), state = listState, contentPadding = PaddingValues(vertical = 12.dp)) { items(c.messages) { m -> MessageBubble(m) { a -> runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(a.uri), if (a.isImage) "image/*" else "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) } } } }
        Surface(tonalElevation = 1.dp) { Row(Modifier.fillMaxWidth().padding(12.dp, 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Icon(Icons.Rounded.Image, "Photo", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            IconButton(onClick = { pickFile.launch(arrayOf("*/*")) }) { Icon(Icons.Rounded.AttachFile, "File", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            OutlinedTextField(text, { text = it }, placeholder = { Text("Message") }, modifier = Modifier.weight(1f), shape = RoundedCornerShape(16.dp), singleLine = true)
            Spacer(Modifier.width(8.dp)); FilledIconButton(onClick = { vm.sendChat(c.id, text.trim()); text = "" }, enabled = text.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send") }
        } }
    }
}

@Composable
private fun MessageBubble(m: ChatMessage, onOpen: (Attachment) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
        Column(Modifier.widthIn(max = 320.dp).clip(RoundedCornerShape(18.dp)).background(if (m.mine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer).padding(4.dp)) {
            m.attachment?.let { a -> if (a.isImage) AsyncImage(model = a.uri, contentDescription = "Photo", contentScale = ContentScale.Crop, modifier = Modifier.size(220.dp).clip(RoundedCornerShape(14.dp)).clickable { onOpen(a) })
                else Row(Modifier.clip(RoundedCornerShape(14.dp)).background(if (m.mine) MaterialTheme.colorScheme.onPrimary.copy(alpha = .15f) else MaterialTheme.colorScheme.surface).clickable { onOpen(a) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Description, null, tint = if (m.mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary); Text(a.name, style = MaterialTheme.typography.titleSmall, color = if (m.mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(start = 10.dp), maxLines = 1) } }
            if (m.attachment == null || !m.attachment.isImage) Text(m.text, style = MaterialTheme.typography.bodyMedium, color = if (m.mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(10.dp, 8.dp))
        }
    }
}

/* ---------------- CALL ---------------- */
@Composable
fun CallOverlay(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val call = s.call ?: return
    val ctx = LocalContext.current
    var secs by remember(call.startedAt) { mutableIntStateOf(0) }
    LaunchedEffect(call.startedAt) { while (true) { kotlinx.coroutines.delay(1000); secs = ((System.currentTimeMillis() - call.startedAt) / 1000).toInt() } }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.secondary) {
        Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Avatar(initials(call.name), size = 96)
            Text(call.name, style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onSecondary, modifier = Modifier.padding(top = 20.dp))
            Text(if (secs < 3) "Calling through Bucks…" else "%d:%02d".format(secs / 60, secs % 60), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSecondary.copy(alpha = .7f), modifier = Modifier.padding(top = 6.dp))
            Text("Your number stays private; the other person sees only your Bucks name.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondary.copy(alpha = .55f), modifier = Modifier.padding(top = 4.dp))
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                CallButton(if (call.muted) Icons.Rounded.MicOff else Icons.Rounded.Mic, if (call.muted) "Unmute" else "Mute", call.muted) { vm.toggleMute() }
                CallButton(Icons.Rounded.VolumeUp, "Speaker", call.speaker) { vm.toggleSpeaker() }
                CallButton(Icons.Rounded.Dialpad, "Use phone", false) { runCatching { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${call.phone.replace(" ", "")}"))) } }
            }
            Spacer(Modifier.height(28.dp))
            FilledIconButton(onClick = { vm.endCall() }, modifier = Modifier.size(72.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError)) { Icon(Icons.Rounded.CallEnd, "End call", modifier = Modifier.size(32.dp)) }
            Spacer(Modifier.height(24.dp))
        }
    }
}
@Composable
private fun CallButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, active: Boolean, onClick: () -> Unit) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    FilledIconButton(onClick = onClick, modifier = Modifier.size(60.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = if (active) MaterialTheme.colorScheme.onSecondary else MaterialTheme.colorScheme.onSecondary.copy(alpha = .15f), contentColor = if (active) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSecondary)) { Icon(icon, label) }
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSecondary.copy(alpha = .8f), modifier = Modifier.padding(top = 6.dp))
}
