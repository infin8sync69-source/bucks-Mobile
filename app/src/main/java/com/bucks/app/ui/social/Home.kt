package com.bucks.app.ui.social

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.CommentRow
import com.bucks.app.data.FeedRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.MomentsTray
import com.bucks.app.ui.screens.MutedMomentsSheet
import com.bucks.app.ui.screens.PostMedia
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.launch

/**
 * Home: Moments on top, then the feed. Two lenses over the same posts: For you (synced people, plus public and nearby posts) and
 * Synced (only people I've synced with, and me). Pull down to refresh; more loads as you reach the end.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeFeedScreen(vm: BucksViewModel, onNotifications: () -> Unit, onOpenMoments: (String) -> Unit, onNewMoment: () -> Unit, onNewPost: () -> Unit, onDiscover: () -> Unit) {
    val social = vm.social; val scope = rememberCoroutineScope()
    var lens by rememberSaveable { mutableIntStateOf(0) }
    var comments by remember { mutableStateOf<String?>(null) }; var showMuted by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(social.me?.id) { if (social.me != null) { social.refreshFeed(); social.refreshInbox() } }
    val posts = if (lens == 0) social.feed else social.feed.filter { it.synced || it.authorId == social.me?.id }
    val list = rememberLazyListState()
    // Load more when the last few posts come into view.
    val nearEnd by remember { derivedStateOf { val last = list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0; last >= list.layoutInfo.totalItemsCount - 3 } }
    LaunchedEffect(nearEnd, social.feed.size) { if (nearEnd && social.feed.isNotEmpty() && !social.feedEnd) social.loadMoreFeed() }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = Gutter, end = 8.dp, top = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            BucksWordmark(height = 28.dp, modifier = Modifier.weight(1f, fill = false))
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onNotifications) {
                BadgedBox(badge = { if (social.notesUnread > 0) Badge { Text(if (social.notesUnread > 99) "99+" else "${social.notesUnread}") } }) {
                    Icon(Icons.Rounded.NotificationsNone, if (social.notesUnread > 0) "Notifications, ${social.notesUnread} new" else "Notifications", Modifier.size(26.dp))
                }
            }
        }
        PullToRefreshBox(isRefreshing = refreshing, onRefresh = { scope.launch { refreshing = true; social.refreshFeed().join(); social.refreshInbox(); refreshing = false } }, modifier = Modifier.fillMaxSize()) {
            LazyColumn(state = list, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item(key = "moments") { MomentsTray(social.tray, myName = social.me?.name ?: "You", onOpen = onOpenMoments, onNew = onNewMoment, onMute = { social.muteMoments(it.authorId, true) }, onMore = { showMuted = true }) }
                item(key = "compose") { ComposePrompt(social.me?.name ?: "", onNewPost) }
                item(key = "lens") { LensRow(lens) { lens = it } }
                if (social.me == null) items(3) { PostSkeleton() }
                else if (posts.isEmpty()) item(key = "empty") { EmptyFeed(synced = lens == 1, onDiscover = onDiscover, onNewPost = onNewPost) }
                items(posts, key = { it.id }) { p ->
                    SocialPostCard(vm, p, onVote = { social.vote(p.id, it) }, onComments = { comments = p.id }, onDelete = { social.deletePost(p.id) })
                }
                if (posts.isNotEmpty() && social.feedEnd) item(key = "end") { Muted("You're all caught up.", Modifier.fillMaxWidth().padding(24.dp), align = androidx.compose.ui.text.style.TextAlign.Center) }
            }
        }
    }
    comments?.let { id -> CommentsSheet(vm, id) { comments = null } }
    if (showMuted) MutedMomentsSheet(vm) { showMuted = false }
}

@Composable
private fun ComposePrompt(name: String, onClick: () -> Unit) =
    Surface(onClick = onClick, shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 6.dp)) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name.ifBlank { "You" }), size = 36)
            Text("What's on your mind?", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 12.dp).weight(1f))
            Icon(Icons.Rounded.Image, "Add a photo", tint = MaterialTheme.colorScheme.primary)
        }
    }

@Composable
private fun LensRow(selected: Int, onSelect: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 10.dp)) {
        listOf("For you", "Synced").forEachIndexed { i, l ->
            SegmentedButton(selected = selected == i, onClick = { onSelect(i) }, shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(l) }
        }
    }
}

@Composable
private fun EmptyFeed(synced: Boolean, onDiscover: () -> Unit, onNewPost: () -> Unit) = Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Box(Modifier.size(72.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Diversity3, null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(36.dp)) }
    Text(if (synced) "No posts from your syncs yet" else "Your feed is quiet", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp).semantics { heading() })
    Muted(if (synced) "Sync with friends to see what they share here." else "Sync with people you know, or share the first post nearby.", Modifier.padding(top = 6.dp), align = androidx.compose.ui.text.style.TextAlign.Center)
    Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Button(onDiscover, shape = MaterialTheme.shapes.large) { Icon(Icons.Rounded.PersonAddAlt, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Find people") }
        OutlinedButton(onNewPost, shape = MaterialTheme.shapes.large) { Text("Post") }
    }
}

@Composable
private fun PostSkeleton() = Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 14.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh))
        Column(Modifier.padding(start = 10.dp)) { Box(Modifier.size(120.dp, 12.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh)); Spacer(Modifier.height(6.dp)); Box(Modifier.size(80.dp, 10.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer)) }
    }
    Box(Modifier.padding(top = 12.dp).fillMaxWidth().height(14.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer))
    Box(Modifier.padding(top = 6.dp).fillMaxWidth(0.7f).height(14.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer))
}

/**
 * One post. The author's name and photo open their profile; ⋯ offers Delete on my posts and Report or Block on everyone else's.
 * The vote stays the existing up/down recommendation, shown as one compact control.
 */
@Composable
fun SocialPostCard(vm: BucksViewModel, p: FeedRow, onVote: (Int) -> Unit, onComments: () -> Unit, onDelete: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val openPerson = LocalOpenPerson.current; val report = LocalReporter.current
    val mine = p.authorId == social.me?.id
    var menu by remember { mutableStateOf(false) }; var confirmDelete by remember { mutableStateOf(false) }
    Surface(color = MaterialTheme.colorScheme.surface, shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Column(Modifier.padding(vertical = 12.dp)) {
            Row(Modifier.padding(start = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).clip(MaterialTheme.shapes.small).clickable(role = Role.Button, onClickLabel = "Open ${p.authorName}'s profile") { openPerson(p.authorId) }.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(p.authorName.ifBlank { "?" }), size = 42, photoUrl = vm.social.photoOf(p.authorId))
                    Column(Modifier.padding(start = 10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(p.listingTitle ?: p.authorName, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (p.synced && !mine) Icon(Icons.Rounded.Sync, "Synced", Modifier.padding(start = 4.dp).size(14.dp), tint = MaterialTheme.colorScheme.primary)
                        }
                        Text(listOfNotNull(ago(p.createdAt), p.area.ifBlank { null }, audienceLabel(p.visibility)).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                Box {
                    IconButton({ menu = true }) { Icon(Icons.Rounded.MoreHoriz, "More options for this post") }
                    DropdownMenu(menu, { menu = false }) {
                        if (mine) DropdownMenuItem({ Text("Delete post") }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Rounded.DeleteOutline, null) })
                        else {
                            DropdownMenuItem({ Text("View profile") }, { menu = false; openPerson(p.authorId) }, leadingIcon = { Icon(Icons.Rounded.Person, null) })
                            if (report != null) DropdownMenuItem({ Text("Report post") }, { menu = false; report(ReportTarget("POST", p.id, p.authorId, p.authorName)) }, leadingIcon = { Icon(Icons.Rounded.OutlinedFlag, null) })
                            DropdownMenuItem({ Text("Block ${p.authorName.substringBefore(' ')}") }, { menu = false; social.block(p.authorId); social.refreshFeed() }, leadingIcon = { Icon(Icons.Rounded.Block, null) })
                        }
                    }
                }
            }
            if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(horizontal = 14.dp).padding(top = 10.dp))
            Box(Modifier.padding(horizontal = 14.dp)) { PostMedia(vm, p.media, vote = com.bucks.app.ui.ViewerVote(p.up, p.down, p.myVote ?: 0, canVote = !mine, onVote = onVote)) }
            Row(Modifier.padding(start = 8.dp, end = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                VotePill(p.myVote ?: 0, p.up, p.down, onVote)
                Spacer(Modifier.width(6.dp))
                ActionChip(Icons.Rounded.ChatBubbleOutline, if (p.comments > 0) "${p.comments}" else "Comment", "Comments, ${p.comments}", onComments)
                Spacer(Modifier.weight(1f))
                IconButton({ shareText(ctx, "${p.authorName} on Bucks: ${p.body}") }) { Icon(Icons.Rounded.IosShare, "Share", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Delete this post?") }, text = { Text("It disappears from everyone's feed and your profile. This can't be undone.") },
        confirmButton = { TextButton({ confirmDelete = false; onDelete() }) { Text("Delete", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel") } })
}

private fun audienceLabel(v: String) = when (v) { "SYNCED" -> "Synced only"; "PUBLIC" -> "Everyone"; else -> "Nearby" }

/** ↑ and ↓ in one pill: arrows, never thumbs; the larger side shows its count. */
@Composable
private fun VotePill(my: Int, up: Int, down: Int, onVote: (Int) -> Unit) {
    val good = MaterialTheme.status.good; val bad = MaterialTheme.status.bad; val idle = MaterialTheme.colorScheme.onSurfaceVariant
    Row(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.clip(CircleShape).clickable(role = Role.Button, onClickLabel = if (my == 1) "Remove recommendation" else "Recommend") { onVote(1) }.minimumInteractiveComponentSize().padding(horizontal = 12.dp).semantics(mergeDescendants = true) { contentDescription = "Recommend, $up" }, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(18.dp), tint = if (my == 1) good else idle)
            // Only the larger side carries its number (ties show the ups), as everywhere else in Bucks.
            if (up >= down && up > 0) Text(" $up", style = MaterialTheme.typography.labelLarge, color = if (my == 1) good else idle)
        }
        Box(Modifier.size(1.dp, 20.dp).background(MaterialTheme.colorScheme.outlineVariant))
        Row(Modifier.clip(CircleShape).clickable(role = Role.Button, onClickLabel = if (my == -1) "Take back my vote" else "Not recommend") { onVote(-1) }.minimumInteractiveComponentSize().padding(horizontal = 12.dp).semantics(mergeDescendants = true) { contentDescription = "Not for me, $down" }, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.ArrowDownward, null, Modifier.size(18.dp), tint = if (my == -1) bad else idle)
            if (down > up) Text(" $down", style = MaterialTheme.typography.labelLarge, color = if (my == -1) bad else idle)
        }
    }
}

@Composable
private fun ActionChip(icon: ImageVector, text: String, description: String, onClick: () -> Unit) =
    Row(Modifier.clip(CircleShape).clickable(role = Role.Button, onClick = onClick).minimumInteractiveComponentSize().padding(horizontal = 12.dp).semantics(mergeDescendants = true) { contentDescription = description }, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(" $text", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

/** Comments on a post: names open profiles, long-press someone else's comment to report it. */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun CommentsSheet(vm: BucksViewModel, postId: String, onDismiss: () -> Unit) {
    val social = vm.social; val report = LocalReporter.current; val openPerson = LocalOpenPerson.current
    var rows by remember { mutableStateOf<List<CommentRow>?>(null) }; var reply by remember { mutableStateOf("") }; var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(postId, tick) { rows = runCatching { social.comments(postId) }.getOrDefault(emptyList()) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 16.dp).imePadding()) {
            Text("Comments", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
            when {
                rows == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                rows!!.isEmpty() -> Muted("No comments yet. Say something nice.", Modifier.padding(vertical = 16.dp))
                else -> LazyColumn(Modifier.heightIn(max = 420.dp)) {
                    items(rows!!, key = { it.id }) { c ->
                        val mine = c.authorId == social.me?.id
                        Row(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClickLabel = if (!mine && report != null) "Report comment" else null,
                            onLongClick = { if (!mine) report?.invoke(ReportTarget("COMMENT", c.id, c.authorId, social.nameOf(c.authorId))) }).padding(vertical = 8.dp)) {
                            Box(Modifier.clip(CircleShape).clickable(onClickLabel = "Open profile") { openPerson(c.authorId) }) { Avatar(initials(social.nameOf(c.authorId).ifBlank { "?" }), size = 34) }
                            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) { Text(social.nameOf(c.authorId), style = MaterialTheme.typography.titleSmall); Muted("  ${ago(c.createdAt)}") }
                                Text(c.body, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(reply, { reply = it.take(1000) }, placeholder = { Text("Add a comment") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.extraLarge, maxLines = 4)
                Spacer(Modifier.width(8.dp))
                FilledIconButton(onClick = { val t = reply.trim(); if (t.isNotEmpty()) social.comment(postId, t) { reply = ""; tick++ } }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send comment") }
            }
        }
    }
}
