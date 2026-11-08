package com.bucks.app.ui.social

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.BackendSafety
import com.bucks.app.data.FeedRow
import com.bucks.app.data.ProfileRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.MyFilesTab
import com.bucks.app.ui.screens.MyMediaTab
import com.bucks.app.ui.screens.ProfileMediaHeader
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.Purple
import com.bucks.app.ui.theme.PurpleDeep
import kotlinx.coroutines.launch

/** A person's posts with local voting (the feed's vote only knows posts that are in the feed). */
private class PostsOf(private val vm: BucksViewModel, private val author: String) {
    var rows by mutableStateOf<List<FeedRow>?>(null)
    suspend fun load() { rows = runCatching { BackendSafety.postsBy(author) }.getOrDefault(emptyList()) }
    suspend fun vote(p: FeedRow, v: Int) {
        val me = vm.social.me?.id ?: return
        val prev = p.myVote ?: 0; val next = if (prev == v) 0 else v
        runCatching { Backend.vote(p.id, me, next) }.onSuccess {
            rows = rows?.map { if (it.id != p.id) it else it.copy(myVote = next.takeIf { n -> n != 0 }, up = it.up - (if (prev == 1) 1 else 0) + (if (next == 1) 1 else 0), down = it.down - (if (prev == -1) 1 else 0) + (if (next == -1) 1 else 0)) }
        }.onFailure { vm.toast("Couldn't save that. Try again.") }
    }
}

/** My profile tab: who I am, my numbers, my posts, media and files; settings behind the gear. */
@Composable
fun MeScreen(vm: BucksViewModel, onEditProfile: () -> Unit, onSettings: () -> Unit, onSynced: () -> Unit, onNewPost: () -> Unit, onBucksId: () -> Unit) {
    val social = vm.social; val s by vm.state.collectAsState(); val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val me = social.me
    val posts = remember(me?.id) { me?.id?.let { PostsOf(vm, it) } }
    var comments by remember { mutableStateOf<String?>(null) }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(me?.id, social.feed.size) { posts?.load(); social.refreshSyncs() }
    val name = me?.name?.ifBlank { null } ?: s.user?.name.orEmpty()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            ProfileHeader(vm, name = name, code = me?.shortCode, area = me?.area ?: s.user?.area.orEmpty(), bio = me?.bio ?: s.user?.bio.orEmpty(),
                synced = social.synced.size, postCount = posts?.rows?.size, onSynced = onSynced, photoUrl = me?.photoUrl, coverUrl = me?.coverUrl, editable = me != null,
                topEnd = { IconButton(onSettings) { Icon(Icons.Rounded.Settings, "Settings", tint = androidx.compose.ui.graphics.Color.White) } })
            Row(Modifier.padding(horizontal = Gutter, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilledTonalButton(onEditProfile, Modifier.weight(1f), shape = MaterialTheme.shapes.large) { Icon(Icons.Rounded.Edit, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Edit profile") }
                FilledTonalButton(onBucksId, Modifier.weight(1f), shape = MaterialTheme.shapes.large) { Icon(Icons.Rounded.QrCode2, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("My Bucks ID") }
                FilledTonalIconButton({ shareText(ctx, "Find me on Bucks" + (me?.let { ": Bucks ID ${it.shortCode}" } ?: "")) }) { Icon(Icons.Rounded.IosShare, "Share my profile") }
            }
            if (vm.safety.isMinor) SafetyNote("Your account has teen protections on: private by default, and only syncs can message you.")
            TabRow(selectedTabIndex = tab, containerColor = MaterialTheme.colorScheme.background) {
                listOf("Posts", "Media", "Files").forEachIndexed { i, l -> Tab(selected = tab == i, onClick = { tab = i }, text = { Text(l) }) }
            }
        }
        when (tab) {
            0 -> {
                val rows = posts?.rows
                if (rows == null) item { Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                else if (rows.isEmpty()) item {
                    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Muted("You haven't posted yet.")
                        Button(onNewPost, Modifier.padding(top = 12.dp), shape = MaterialTheme.shapes.large) { Text("Create your first post") }
                    }
                }
                else items(rows, key = { it.id }) { p -> SocialPostCard(vm, p, onVote = { v -> scope.launch { posts.vote(p, v) } }, onComments = { comments = p.id }, onDelete = { social.deletePost(p.id); posts.rows = rows.filterNot { it.id == p.id } }) }
            }
            1 -> item { MyMediaTab(vm) }
            else -> item { MyFilesTab(vm) }
        }
    }
    comments?.let { id -> CommentsSheet(vm, id) { comments = null } }
}

/**
 * Someone else's profile: Sync (or Accept / Requested / Synced), Message, and ⋯ for Close friend, Unsync, Report and Block.
 * Their posts show what I'm allowed to see; a private person I'm not synced with shows only their name and Bucks ID.
 */
@Composable
fun PersonScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onOpenChat: (String) -> Unit) {
    val social = vm.social; val scope = rememberCoroutineScope(); val report = LocalReporter.current
    var person by remember { mutableStateOf<ProfileRow?>(null) }; var missing by remember { mutableStateOf(false) }
    val posts = remember(id) { PostsOf(vm, id) }
    var comments by remember { mutableStateOf<String?>(null) }; var menu by remember { mutableStateOf(false) }; var confirmBlock by remember { mutableStateOf(false) }
    var requested by remember { mutableStateOf(false) }
    LaunchedEffect(id) { person = runCatching { Backend.profiles(listOf(id)).firstOrNull() }.getOrNull(); missing = person == null; posts.load(); social.refreshSyncs() }
    val synced = social.synced.any { it.id == id }; val incoming = social.incoming.any { it.id == id }; val close = id in social.closeFriends
    val p = person
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                ProfileHeader(vm, name = p?.name ?: "", code = p?.shortCode, area = p?.area.orEmpty(), bio = p?.bio.orEmpty(), synced = null, postCount = posts.rows?.size, onSynced = {},
                    photoUrl = p?.photoUrl, coverUrl = p?.coverUrl,
                    topStart = { IconButton(onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", tint = androidx.compose.ui.graphics.Color.White) } },
                    topEnd = {
                        Box {
                            IconButton({ menu = true }) { Icon(Icons.Rounded.MoreVert, "More options", tint = androidx.compose.ui.graphics.Color.White) }
                            DropdownMenu(menu, { menu = false }) {
                                if (synced) DropdownMenuItem({ Text(if (close) "Remove from close friends" else "Add to close friends") }, { menu = false; social.setClose(id, !close) }, leadingIcon = { Icon(Icons.Rounded.Favorite, null) })
                                if (synced) DropdownMenuItem({ Text("Unsync") }, { menu = false; social.unsync(id) }, leadingIcon = { Icon(Icons.Rounded.SyncDisabled, null) })
                                if (report != null) DropdownMenuItem({ Text("Report") }, { menu = false; report(ReportTarget("PROFILE", id, id, p?.name.orEmpty())) }, leadingIcon = { Icon(Icons.Rounded.OutlinedFlag, null) })
                                DropdownMenuItem({ Text("Block", color = MaterialTheme.colorScheme.error) }, { menu = false; confirmBlock = true }, leadingIcon = { Icon(Icons.Rounded.Block, null, tint = MaterialTheme.colorScheme.error) })
                            }
                        }
                    })
                if (missing) Muted("This account isn't available.", Modifier.padding(Gutter))
                else Row(Modifier.padding(horizontal = Gutter, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    when {
                        synced -> FilledTonalButton({}, Modifier.weight(1f), shape = MaterialTheme.shapes.large) { Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Synced") }
                        incoming -> Button({ social.acceptSync(id) }, Modifier.weight(1f), shape = MaterialTheme.shapes.large) { Text("Accept sync") }
                        requested -> OutlinedButton({}, Modifier.weight(1f), enabled = false, shape = MaterialTheme.shapes.large) { Text("Requested") }
                        else -> Button({ requested = true; social.syncWith(id, p?.name.orEmpty()) }, Modifier.weight(1f), shape = MaterialTheme.shapes.large, enabled = p != null) { Icon(Icons.Rounded.PersonAddAlt, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Sync") }
                    }
                    OutlinedButton({ social.openDirect(id, onOpenChat) }, Modifier.weight(1f), shape = MaterialTheme.shapes.large, enabled = p != null) { Icon(Icons.Rounded.ChatBubbleOutline, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Message") }
                }
                if (!synced && !missing) Muted("Sync with ${p?.name?.substringBefore(' ') ?: "them"} to see posts they share with syncs and to message them.", Modifier.padding(horizontal = Gutter))
                Text("Posts", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = Gutter, top = 20.dp, bottom = 4.dp).semantics { heading() })
            }
            val rows = posts.rows
            if (rows == null) item { Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            else if (rows.isEmpty()) item { Muted("Nothing to show here yet.", Modifier.padding(Gutter)) }
            else items(rows, key = { it.id }) { r -> SocialPostCard(vm, r, onVote = { v -> scope.launch { posts.vote(r, v) } }, onComments = { comments = r.id }, onDelete = {}) }
        }
    }
    comments?.let { c -> CommentsSheet(vm, c) { comments = null } }
    if (confirmBlock) AlertDialog(onDismissRequest = { confirmBlock = false }, title = { Text("Block ${p?.name ?: "this person"}?") },
        text = { Text("They won't be able to message you, sync with you or see your posts and Moments. They aren't told. You can unblock them in Settings.") },
        confirmButton = { TextButton({ confirmBlock = false; social.block(id); onBack() }) { Text("Block", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ confirmBlock = false }) { Text("Cancel") } })
}

/** Gradient cover, avatar overlapping it, name, Bucks ID, area, bio and the counts. */
@Composable
private fun ProfileHeader(vm: BucksViewModel, name: String, code: String?, area: String, bio: String, synced: Int?, postCount: Int?, onSynced: () -> Unit,
                          photoUrl: String? = null, coverUrl: String? = null, editable: Boolean = false,
                          topStart: @Composable () -> Unit = {}, topEnd: @Composable () -> Unit = {}) {
    // My own header lets me change both pictures; anyone's opens them full screen.
    ProfileMediaHeader(vm, name, photoUrl, coverUrl, editable = editable, busy = if (editable) vm.social.mediaBusy else null,
        onPick = { slot, picked -> vm.social.setMyPicture(slot, picked) }, onRemove = { vm.social.clearMyPicture(it) },
        avatarSize = 92.dp, topStart = topStart, topEnd = topEnd)
    Column(Modifier.padding(horizontal = Gutter).padding(top = 8.dp)) {
        Text(name.ifBlank { " " }, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold), modifier = Modifier.semantics { heading() })
        val meta = listOfNotNull(code?.let { "Bucks ID $it" }, area.ifBlank { null }).joinToString(" · ")
        if (meta.isNotBlank()) Text(meta, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (bio.isNotBlank()) Text(bio, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 10.dp))
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            if (synced != null) Row(Modifier.clip(MaterialTheme.shapes.small).clickable(role = Role.Button, onClickLabel = "See synced people", onClick = onSynced).padding(vertical = 4.dp), verticalAlignment = Alignment.Bottom) {
                Text("$synced", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)); Text(" synced", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (postCount != null) Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.Bottom) {
                Text("$postCount", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)); Text(if (postCount == 1) " post" else " posts", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
