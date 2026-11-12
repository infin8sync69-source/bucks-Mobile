package com.bucks.app.ui.social

import com.bucks.app.data.Str
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
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
                BadgedBox(badge = { if (social.notesUnread > 0) Badge { Text(if (social.notesUnread > 99) stringResource(R.string.g1_home_badge_max) else "${social.notesUnread}") } }) {
                    Icon(Icons.Rounded.NotificationsNone, if (social.notesUnread > 0) pluralStringResource(R.plurals.g1_cd_notifs_new, social.notesUnread, social.notesUnread) else stringResource(R.string.g1_cd_notifications), Modifier.size(26.dp))
                }
            }
        }
        PullToRefreshBox(isRefreshing = refreshing, onRefresh = { scope.launch { refreshing = true; social.refreshFeed().join(); social.refreshInbox(); refreshing = false } }, modifier = Modifier.fillMaxSize()) {
            LazyColumn(state = list, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item(key = "moments") { MomentsTray(social.tray, myName = social.me?.name ?: stringResource(R.string.g1_home_you), onOpen = onOpenMoments, onNew = onNewMoment, onMute = { social.muteMoments(it.authorId, true) }, onMore = { showMuted = true }) }
                item(key = "compose") { ComposePrompt(social.me?.name ?: "", onNewPost) }
                item(key = "lens") { LensRow(lens) { lens = it } }
                if (social.me == null) items(3) { PostSkeleton() }
                else if (posts.isEmpty()) item(key = "empty") { EmptyFeed(synced = lens == 1, onDiscover = onDiscover, onNewPost = onNewPost) }
                items(posts, key = { it.id }) { p ->
                    SocialPostCard(vm, p, onVote = { social.vote(p.id, it) }, onComments = { comments = p.id }, onDelete = { social.deletePost(p.id) })
                }
                if (posts.isNotEmpty() && social.feedEnd) item(key = "end") { Muted(stringResource(R.string.g1_home_caught_up), Modifier.fillMaxWidth().padding(24.dp), align = androidx.compose.ui.text.style.TextAlign.Center) }
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
            Avatar(initials(name.ifBlank { stringResource(R.string.g1_home_you) }), size = 36)
            Text(stringResource(R.string.g1_post_hint), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 12.dp).weight(1f))
            Icon(Icons.Rounded.Image, stringResource(R.string.g1_cd_add_photo), tint = MaterialTheme.colorScheme.primary)
        }
    }

@Composable
private fun LensRow(selected: Int, onSelect: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 10.dp)) {
        listOf(stringResource(R.string.g1_home_lens_for_you), stringResource(R.string.g1_home_lens_synced)).forEachIndexed { i, l ->
            SegmentedButton(selected = selected == i, onClick = { onSelect(i) }, shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(l) }
        }
    }
}

@Composable
private fun EmptyFeed(synced: Boolean, onDiscover: () -> Unit, onNewPost: () -> Unit) = Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Box(Modifier.size(72.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Diversity3, null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(36.dp)) }
    Text(if (synced) stringResource(R.string.g1_home_empty_synced) else stringResource(R.string.g1_home_empty), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp).semantics { heading() })
    Muted(if (synced) stringResource(R.string.g1_home_empty_synced_body) else stringResource(R.string.g1_home_empty_body), Modifier.padding(top = 6.dp), align = androidx.compose.ui.text.style.TextAlign.Center)
    Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Button(onDiscover, shape = MaterialTheme.shapes.large) { Icon(Icons.Rounded.PersonAddAlt, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.g1_home_find_people)) }
        OutlinedButton(onNewPost, shape = MaterialTheme.shapes.large) { Text(stringResource(R.string.g1_post_action)) }
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
fun SocialPostCard(vm: BucksViewModel, p: FeedRow, onVote: (Int) -> Unit, onComments: () -> Unit, onDelete: () -> Unit, onOpenMedia: ((Int) -> Unit)? = null, header: @Composable (() -> Unit)? = null) {
    val social = vm.social; val ctx = LocalContext.current; val openPerson = LocalOpenPerson.current; val report = LocalReporter.current
    val mine = p.authorId == social.me?.id
    var menu by remember { mutableStateOf(false) }; var confirmDelete by remember { mutableStateOf(false) }
    Surface(color = MaterialTheme.colorScheme.surface, shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Column(Modifier.padding(vertical = 12.dp)) {
            header?.let { Box(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 10.dp)) { it() } }
            Row(Modifier.padding(start = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).clip(MaterialTheme.shapes.small).clickable(role = Role.Button, onClickLabel = stringResource(R.string.g1_cd_open_profile_of, p.authorName)) { openPerson(p.authorId) }.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(p.authorName.ifBlank { "?" }), size = 42, photoUrl = vm.social.photoOf(p.authorId))
                    Column(Modifier.padding(start = 10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(p.listingTitle ?: p.authorName, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (p.synced && !mine) Icon(Icons.Rounded.Sync, stringResource(R.string.g1_home_lens_synced), Modifier.padding(start = 4.dp).size(14.dp), tint = MaterialTheme.colorScheme.primary)
                        }
                        Text(listOfNotNull(ago(p.createdAt), p.area.ifBlank { null }, audienceLabel(p.visibility)).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                Box {
                    IconButton({ menu = true }) { Icon(Icons.Rounded.MoreHoriz, stringResource(R.string.g1_cd_post_more)) }
                    DropdownMenu(menu, { menu = false }) {
                        if (mine) DropdownMenuItem({ Text(stringResource(R.string.g1_home_delete_post)) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Rounded.DeleteOutline, null) })
                        else {
                            DropdownMenuItem({ Text(stringResource(R.string.g1_home_view_profile)) }, { menu = false; openPerson(p.authorId) }, leadingIcon = { Icon(Icons.Rounded.Person, null) })
                            if (report != null) DropdownMenuItem({ Text(stringResource(R.string.g1_home_report_post)) }, { menu = false; report(ReportTarget("POST", p.id, p.authorId, p.authorName)) }, leadingIcon = { Icon(Icons.Rounded.OutlinedFlag, null) })
                            DropdownMenuItem({ Text(stringResource(R.string.g1_home_block, p.authorName.substringBefore(' '))) }, { menu = false; social.block(p.authorId); social.refreshFeed() }, leadingIcon = { Icon(Icons.Rounded.Block, null) })
                        }
                    }
                }
            }
            if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(horizontal = 14.dp).padding(top = 10.dp))
            Box(Modifier.padding(horizontal = 14.dp)) { PostMedia(vm, p.media, vote = com.bucks.app.ui.ViewerVote(p.up, p.down, p.myVote ?: 0, onVote = onVote), onOpen = onOpenMedia) }
            Row(Modifier.padding(start = 8.dp, end = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                VotePill(p.myVote ?: 0, p.up, p.down, onVote = onVote)
                Spacer(Modifier.width(6.dp))
                ActionChip(Icons.Rounded.ChatBubbleOutline, if (p.comments > 0) "${p.comments}" else stringResource(R.string.g1_home_comment), pluralStringResource(R.plurals.g1_cd_comments, p.comments, p.comments), onComments)
                Spacer(Modifier.weight(1f))
                val shareMsg = stringResource(R.string.g1_post_share_text, p.authorName, p.body)
                IconButton({ shareText(ctx, shareMsg) }) { Icon(Icons.Rounded.IosShare, stringResource(R.string.g1_profile_share), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            InlineCommentBox(Modifier.padding(horizontal = 14.dp).padding(top = 2.dp)) { social.comment(p.id, it) {} }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text(stringResource(R.string.g1_home_delete_title)) }, text = { Text(stringResource(R.string.g1_home_delete_body)) },
        confirmButton = { TextButton({ confirmDelete = false; onDelete() }) { Text(stringResource(R.string.g1_action_delete), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmDelete = false }) { Text(stringResource(R.string.g1_action_cancel)) } })
}

private fun audienceLabel(v: String) = when (v) { "SYNCED" -> Str.get(R.string.g1_home_aud_synced); "PUBLIC" -> Str.get(R.string.g1_priv_everyone); else -> Str.get(R.string.g1_home_aud_nearby) }

/** ↑ and ↓ in one pill: arrows, never thumbs; the larger side shows its count until I vote, then both do. */
@Composable
fun VotePill(my: Int, up: Int, down: Int, onVote: (Int) -> Unit) {
    val good = MaterialTheme.status.good; val bad = MaterialTheme.status.bad; val idle = MaterialTheme.colorScheme.onSurfaceVariant
    val (upShown, downShown) = postCountsShown(up, down, my)
    val upDesc = stringResource(R.string.g1_cd_vote_up, up); val downDesc = stringResource(R.string.g1_cd_vote_down, down)
    Row(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.clip(CircleShape).clickable(role = Role.Button, onClickLabel = if (my == 1) stringResource(R.string.g1_cd_vote_up_remove) else stringResource(R.string.g1_cd_vote_up_action)) { onVote(1) }.minimumInteractiveComponentSize().padding(horizontal = 12.dp).semantics(mergeDescendants = true) { contentDescription = upDesc }, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(18.dp), tint = if (my == 1) good else idle)
            upShown?.let { Text(" $it", style = MaterialTheme.typography.labelLarge, color = if (my == 1) good else idle) }
        }
        Box(Modifier.size(1.dp, 20.dp).background(MaterialTheme.colorScheme.outlineVariant))
        Row(Modifier.clip(CircleShape).clickable(role = Role.Button, onClickLabel = if (my == -1) stringResource(R.string.g1_cd_vote_down_remove) else stringResource(R.string.g1_cd_vote_down_action)) { onVote(-1) }.minimumInteractiveComponentSize().padding(horizontal = 12.dp).semantics(mergeDescendants = true) { contentDescription = downDesc }, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.ArrowDownward, null, Modifier.size(18.dp), tint = if (my == -1) bad else idle)
            downShown?.let { Text(" $it", style = MaterialTheme.typography.labelLarge, color = if (my == -1) bad else idle) }
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
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 16.dp).imePadding()) {
            Text(stringResource(R.string.g1_home_comments_title), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
            when {
                rows == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                rows!!.isEmpty() -> Muted(stringResource(R.string.g1_home_no_comments), Modifier.padding(vertical = 16.dp))
                else -> LazyColumn(Modifier.heightIn(max = 420.dp)) {
                    items(rows!!, key = { it.id }) { c ->
                        val mine = c.authorId == social.me?.id
                        Row(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClickLabel = if (!mine && report != null) stringResource(R.string.g1_cd_report_comment) else null,
                            onLongClick = { if (!mine) report?.invoke(ReportTarget("COMMENT", c.id, c.authorId, social.nameOf(c.authorId))) }).padding(vertical = 8.dp)) {
                            Box(Modifier.clip(CircleShape).clickable(onClickLabel = stringResource(R.string.g1_cd_open_profile)) { openPerson(c.authorId) }) { Avatar(initials(social.nameOf(c.authorId).ifBlank { "?" }), size = 34) }
                            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) { Text(social.nameOf(c.authorId), style = MaterialTheme.typography.titleSmall); Muted("  ${ago(c.createdAt)}") }
                                Text(c.body, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(reply, { reply = it.take(1000) }, placeholder = { Text(stringResource(R.string.g1_home_add_comment)) }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.extraLarge, maxLines = 4)
                Spacer(Modifier.width(8.dp))
                FilledIconButton(onClick = { val t = reply.trim(); if (t.isNotEmpty()) social.comment(postId, t) { reply = ""; tick++ } }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.g1_cd_send_comment)) }
            }
        }
    }
}
