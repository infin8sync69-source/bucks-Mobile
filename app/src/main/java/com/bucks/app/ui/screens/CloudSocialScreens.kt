package com.bucks.app.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Social
import com.bucks.app.ui.components.*
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/* ---------- shared bits ---------- */

/** "2m", "3h", "Yesterday", "12 Mar" from an ISO timestamp. */
fun ago(iso: String): String = runCatching {
    val t = Instant.parse(iso.replace(" ", "T").let { if (it.endsWith("Z") || it.contains("+")) it else it + "Z" }); val s = (Instant.now().epochSecond - t.epochSecond).coerceAtLeast(0)
    when { s < 60 -> "now"; s < 3600 -> "${s / 60}m"; s < 86400 -> "${s / 3600}h"; s < 172800 -> "Yesterday"; else -> DateTimeFormatter.ofPattern("d MMM").format(t.atZone(ZoneId.systemDefault())) }
}.getOrDefault("")

/** Loads a private file's short-lived URL and shows it. */
@Composable
fun SignedImage(vm: BucksViewModel, bucket: String, path: String, modifier: Modifier, contentScale: ContentScale = ContentScale.Crop) {
    val url by produceState<String?>(null, path) { value = runCatching { vm.social.fileUrl(bucket, path) }.getOrNull() }
    Box(modifier.background(MaterialTheme.colorScheme.surfaceContainer), contentAlignment = Alignment.Center) {
        if (url == null) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = contentScale)
    }
}
private fun JsonObject.s(k: String) = this[k]?.jsonPrimitive?.content ?: ""

/**
 * Plays one video (a signed URL or a content:// URI picked on the phone) with Media3 ExoPlayer.
 * [onProgress] gets 0..1 from the player's own position; [onEnded] fires once at the end (unless [loop]).
 * The player is created per [url] and released when this leaves the screen.
 */
@androidx.annotation.OptIn(UnstableApi::class)
@Composable
fun MomentVideo(url: String, paused: Boolean, modifier: Modifier = Modifier, loop: Boolean = false, muted: Boolean = false, onProgress: (Float) -> Unit = {}, onEnded: () -> Unit = {}) {
    val ctx = LocalContext.current
    var buffering by remember { mutableStateOf(true) }
    val ended by rememberUpdatedState(onEnded); val progress by rememberUpdatedState(onProgress)
    val player = remember(url) {
        ExoPlayer.Builder(ctx).build().apply {
            setMediaItem(MediaItem.fromUri(url)); repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            volume = if (muted) 0f else 1f; prepare(); playWhenReady = !paused
        }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) { buffering = playbackState == Player.STATE_BUFFERING; if (playbackState == Player.STATE_ENDED) ended() }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.release() }
    }
    LaunchedEffect(player, paused) { player.playWhenReady = !paused }
    LaunchedEffect(player) { while (true) { val d = player.duration; if (d > 0) progress((player.currentPosition.toFloat() / d).coerceIn(0f, 1f)); delay(50) } }
    Box(modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        AndroidView(factory = { c -> PlayerView(c).apply { useController = false; resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT; setShutterBackgroundColor(android.graphics.Color.BLACK) } }, update = { it.player = player }, modifier = Modifier.fillMaxSize())
        if (buffering) CircularProgressIndicator(color = Color.White)
    }
}

/* ---------- FEED with the Moments tray ---------- */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudFeedScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onOpenMoments: (String) -> Unit, onNewMoment: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current
    var compose by remember { mutableStateOf(false) }; var comments by remember { mutableStateOf<String?>(null) }
    var muteFor by remember { mutableStateOf<TrayRow?>(null) }; var showMuted by remember { mutableStateOf(false) }
    LaunchedEffect(social.me?.id) { if (social.me != null) social.refreshFeed() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Feed", onMenu = onMenu, unread = social.unread, onChat = onMessages)
        LazyColumn {
            item { MomentsTray(social.tray, myName = social.me?.name ?: "You", onOpen = onOpenMoments, onNew = onNewMoment, onMute = { muteFor = it }, onMore = { showMuted = true }) }
            item { Box(Modifier.padding(horizontal = Gutter, vertical = 8.dp)) { Surface(Modifier.fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).clickable { compose = true }, shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
                Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Edit, null, Modifier.size(24.dp)); Spacer(Modifier.width(16.dp)); Text("Share with your neighbours", style = MaterialTheme.typography.bodyLarge) } } } }
            if (social.feed.isEmpty()) item { Muted("Nothing here yet. Sync with people nearby, or be the first to post.", Modifier.padding(Gutter)) }
            items(social.feed, key = { it.id }) { p -> CloudPostCard(vm, p, onVote = { social.vote(p.id, it) }, onComments = { comments = p.id }, onShare = { shareText(ctx, "${p.authorName} on Bucks: ${p.body}") }, onDelete = { social.deletePost(p.id) }) }
            if (social.feed.isNotEmpty() && !social.feedEnd) item { TextButton({ social.loadMoreFeed() }, Modifier.fillMaxWidth().padding(8.dp)) { Text("Load more") } }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    if (compose) NewPostSheet(vm) { compose = false }
    comments?.let { id -> CloudCommentsSheet(vm, id) { comments = null } }
    muteFor?.let { t -> AlertDialog(onDismissRequest = { muteFor = null }, title = { Text("Hide ${t.authorName.substringBefore(' ')}'s moments?") },
        text = { Text("Their moments leave this row. You stay synced and can still message each other. Unmute any time from the More button at the end of the row.") },
        confirmButton = { TextButton({ social.muteMoments(t.authorId, true); muteFor = null }) { Text("Mute") } }, dismissButton = { TextButton({ muteFor = null }) { Text("Cancel") } }) }
    if (showMuted) MutedMomentsSheet(vm) { showMuted = false }
}

/** The row of circles at the top of the feed: me first (with a + to add), then people with unseen moments ringed. Long-press someone to mute them; the last circle lists who's muted. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MomentsTray(tray: List<TrayRow>, myName: String, onOpen: (String) -> Unit, onNew: () -> Unit, onMute: ((TrayRow) -> Unit)? = null, onMore: (() -> Unit)? = null) {
    val mine = tray.firstOrNull { it.isMe }; val others = tray.filter { !it.isMe }
    LazyRow(contentPadding = PaddingValues(horizontal = Gutter, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(68.dp)) {
            Box(Modifier.size(64.dp).clickable { if (mine != null) onOpen(mine.authorId) else onNew() }, contentAlignment = Alignment.Center) {
                MomentRing(unseen = false, has = mine != null) { Avatar(initials(myName), size = 56) }
                Box(Modifier.align(Alignment.BottomEnd).size(22.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary).border(2.dp, MaterialTheme.colorScheme.surface, CircleShape).clickable(onClick = onNew), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Add, "Add a moment", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onPrimary) }
            }
            Text(if (mine != null) "Your moment" else "Add moment", style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) } }
        items(others, key = { it.authorId }) { t -> Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(68.dp).combinedClickable(onClick = { onOpen(t.authorId) }, onLongClick = { onMute?.invoke(t) })) {
            MomentRing(unseen = t.unseen > 0, has = true) { Avatar(initials(t.authorName), size = 56) }
            Text(t.listingTitle ?: t.authorName.substringBefore(' '), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) } }
        if (onMore != null) item { Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(68.dp).clickable(onClick = onMore)) {
            MomentRing(unseen = false, has = false) { Avatar(icon = Icons.Rounded.MoreHoriz, size = 56, tinted = false) }
            Text("More", style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 4.dp)) } }
    }
}
@Composable
private fun MomentRing(unseen: Boolean, has: Boolean, content: @Composable () -> Unit) {
    val ring = when { unseen -> Brush.sweepGradient(listOf(MaterialTheme.colorScheme.primary, Color(0xFFFF4D8D), MaterialTheme.colorScheme.primary)); has -> Brush.linearGradient(listOf(MaterialTheme.colorScheme.outline, MaterialTheme.colorScheme.outline)); else -> null }
    Box(Modifier.size(64.dp).then(if (ring != null) Modifier.background(ring, CircleShape).padding(3.dp) else Modifier.padding(3.dp)).background(MaterialTheme.colorScheme.surface, CircleShape).padding(2.dp), contentAlignment = Alignment.Center) { content() }
}

/** Who I've muted from the Moments row, with a way back. Reached from the row's More circle. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MutedMomentsSheet(vm: BucksViewModel, onDismiss: () -> Unit) {
    val social = vm.social
    LaunchedEffect(Unit) { social.refreshMutedMoments() }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text("Muted moments", style = MaterialTheme.typography.titleLarge)
        Muted("People here stay synced with you; only their moments are hidden from the row.", Modifier.padding(top = 4.dp, bottom = 10.dp))
        if (social.mutedMoments.isEmpty()) Muted("Nobody is muted. Press and hold someone's circle in the Moments row to hide their moments.", Modifier.padding(vertical = 12.dp))
        else social.mutedMoments.forEach { p -> PersonRow(p, trailing = { SmallButton("Unmute", tonal = true) { social.unmuteMoments(p.id) } }) }
    } }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CloudPostCard(vm: BucksViewModel, p: FeedRow, onVote: (Int) -> Unit, onComments: () -> Unit, onShare: () -> Unit, onDelete: () -> Unit) {
    val mine = p.authorId == vm.social.me?.id; var menu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { if (mine) menu = true }).padding(horizontal = Gutter, vertical = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(p.authorName), size = 40)
            Column(Modifier.padding(start = 10.dp).weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(p.listingTitle ?: p.authorName, style = MaterialTheme.typography.titleMedium); if (mine) Muted("  ·  You") else if (p.synced) Muted("  ·  Synced") }
                Muted(listOfNotNull(ago(p.createdAt), p.area.ifBlank { null }, when (p.visibility) { "SYNCED" -> "Synced only"; "PUBLIC" -> "Public"; else -> null }).joinToString(" · ")) }
            if (mine) Box { IconButton({ menu = true }) { Icon(Icons.Rounded.MoreHoriz, "More") }; DropdownMenu(menu, { menu = false }) { DropdownMenuItem({ Text("Delete post") }, { menu = false; onDelete() }) } } }
        if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        p.media.firstOrNull()?.jsonObject?.s("path")?.takeIf { it.isNotBlank() }?.let { path -> SignedImage(vm, "posts", path, Modifier.padding(top = 10.dp).fillMaxWidth().height(260.dp).clip(MaterialTheme.shapes.medium)) }
        val my = p.myVote ?: 0
        val upColor = if (my == 1) MaterialTheme.status.good else MaterialTheme.colorScheme.onSurfaceVariant; val downColor = if (my == -1) MaterialTheme.status.bad else MaterialTheme.colorScheme.onSurfaceVariant
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable { onVote(1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowUpward, "Recommend", Modifier.size(20.dp), tint = upColor); Text(" ${p.up}", color = upColor, style = MaterialTheme.typography.labelLarge) }
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable { onVote(-1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowDownward, "Not recommended", Modifier.size(20.dp), tint = downColor); Text(" ${p.down}", color = downColor, style = MaterialTheme.typography.labelLarge) }
            Spacer(Modifier.weight(1f))
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable(onClick = onComments).padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ChatBubbleOutline, "Comments", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(" ${p.comments}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge) }
            IconButton(onClick = onShare) { Icon(Icons.Rounded.IosShare, "Share", Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
    Divider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudCommentsSheet(vm: BucksViewModel, postId: String, onDismiss: () -> Unit) {
    val social = vm.social; var rows by remember { mutableStateOf<List<CommentRow>>(emptyList()) }; var reply by remember { mutableStateOf("") }; var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(postId, tick) { rows = runCatching { social.comments(postId) }.getOrDefault(emptyList()) }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) { Text("Comments", style = MaterialTheme.typography.titleLarge)
        if (rows.isEmpty()) Muted("Be the first to reply.", Modifier.padding(vertical = 12.dp)) else rows.forEach { c -> Column(Modifier.padding(vertical = 10.dp)) { Row { Text(social.nameOf(c.authorId), style = MaterialTheme.typography.titleSmall); Muted("  ${ago(c.createdAt)}") }; Text(c.body, style = MaterialTheme.typography.bodyMedium) }; Divider() }
        Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(reply, { reply = it }, placeholder = { Text("Reply") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true); Spacer(Modifier.width(8.dp))
            FilledIconButton(onClick = { val t = reply.trim(); if (t.isNotEmpty()) social.comment(postId, t) { reply = ""; tick++ } }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send") } } } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewPostSheet(vm: BucksViewModel, onDismiss: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val s by vm.state.collectAsState()
    var text by remember { mutableStateOf("") }; var visibility by remember { mutableStateOf("LOCAL") }; var photos by remember { mutableStateOf<List<Picked>>(emptyList()) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris -> photos = uris.mapNotNull { Upload.read(ctx, it) } }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text("New post", style = MaterialTheme.typography.titleLarge)
        BucksField(text, { text = it }, placeholder = "Ask for a recommendation, share a deal, thank a provider", modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 4)
        Label("Who can see it"); Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("LOCAL" to "Nearby", "SYNCED" to "Synced only", "PUBLIC" to "Everyone").forEach { (k, l) -> Chip(l, selected = visibility == k) { visibility = k } } }
        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) { SmallButton(if (photos.isEmpty()) "Add photos" else "${photos.size} photo${if (photos.size > 1) "s" else ""}", tonal = true) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }; if (photos.isNotEmpty()) TextButton({ photos = emptyList() }) { Text("Remove") } }
        PrimaryButton(if (social.busy) "Posting…" else "Post", Modifier.padding(top = 14.dp), enabled = !social.busy && (text.isNotBlank() || photos.isNotEmpty())) { social.post(text.trim(), photos, visibility, s.user?.area?.substringBefore(',') ?: ""); onDismiss() }
    } }
}

/* ---------- MOMENTS: viewer and composer ---------- */

@Composable
fun MomentViewerScreen(vm: BucksViewModel, author: String, onClose: () -> Unit, onOpenChat: (String) -> Unit) {
    val social = vm.social; val scope = rememberCoroutineScope()
    var slides by remember { mutableStateOf<List<Pair<MomentRow, String>>>(emptyList()) }; var index by remember { mutableIntStateOf(0) }
    var progress by remember { mutableFloatStateOf(0f) }; var reply by remember { mutableStateOf("") }; var replyFocused by remember { mutableStateOf(false) }
    var viewers by remember { mutableStateOf<List<ViewerRow>?>(null) }
    val mine = author == social.me?.id
    // Photos and videos both wait while the reply field is in use or the viewers list is open.
    val paused = replyFocused || reply.isNotBlank() || viewers != null
    LaunchedEffect(author) { slides = runCatching { social.momentsOf(author) }.getOrDefault(emptyList()); if (slides.isEmpty()) onClose() }
    val cur = slides.getOrNull(index)
    val isVideo = cur?.first?.mediaType == "VIDEO"
    fun next() { if (index < slides.lastIndex) index++ else onClose() }
    LaunchedEffect(cur?.first?.id) { progress = 0f; cur?.let { if (!mine) social.viewMoment(it.first.id) } }
    // Photos: 6 seconds each. Videos: the player drives the bar and moves on when the clip ends.
    LaunchedEffect(cur?.first?.id, paused, isVideo) { if (cur == null || paused || isVideo) return@LaunchedEffect
        while (progress < 1f) { delay(50); progress += 50f / 6000f }
        next() }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        cur?.let { (m, url) ->
            if (isVideo) key(m.id) { MomentVideo(url, paused = paused, modifier = Modifier.fillMaxSize(), onProgress = { progress = it }, onEnded = { next() }) }
            else AsyncImage(url, m.caption, Modifier.fillMaxSize().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) {}, contentScale = ContentScale.Fit)
            // Tap zones: left third goes back, the rest goes forward.
            Row(Modifier.fillMaxSize()) { Box(Modifier.weight(1f).fillMaxHeight().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { if (index > 0) index-- else progress = 0f })
                Box(Modifier.weight(2f).fillMaxHeight().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { next() }) }
            Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 8.dp, vertical = 8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { slides.forEachIndexed { i, _ -> LinearProgressIndicator(progress = { when { i < index -> 1f; i == index -> progress; else -> 0f } }, modifier = Modifier.weight(1f).height(3.dp).clip(CircleShape), color = Color.White, trackColor = Color.White.copy(alpha = .35f)) } }
                Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(social.nameOf(m.authorId).ifBlank { "?" }), size = 32)
                    Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(social.nameOf(m.authorId), color = Color.White, style = MaterialTheme.typography.titleSmall); Text(listOfNotNull(ago(m.createdAt), if (isVideo) "Video" else null).joinToString(" · "), color = Color.White.copy(alpha = .7f), style = MaterialTheme.typography.labelSmall) }
                    if (mine) IconButton({ social.deleteMoment(m.id); if (slides.size == 1) onClose() else { slides = slides.filterNot { it.first.id == m.id }; index = index.coerceAtMost(slides.lastIndex) } }) { Icon(Icons.Rounded.DeleteOutline, "Delete", tint = Color.White) }
                    IconButton(onClose) { Icon(Icons.Rounded.Close, "Close", tint = Color.White) } }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .7f)))).navigationBarsPadding().imePadding().padding(16.dp)) {
                if (m.caption.isNotBlank()) Text(m.caption, color = Color.White, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(bottom = 10.dp))
                if (mine) TextButton({ scope.launch { viewers = runCatching { social.momentViewers(m.id) }.getOrDefault(emptyList()) } }) { Icon(Icons.Rounded.Visibility, null, tint = Color.White); Text("  Seen by", color = Color.White) }
                else {
                    Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { listOf("❤️", "🔥", "👏", "😂", "😮").forEach { e -> Text(e, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.clip(CircleShape).clickable { social.viewMoment(m.id, e) }.padding(6.dp)) } }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(reply, { reply = it }, placeholder = { Text("Reply to ${social.nameOf(m.authorId).substringBefore(' ')}…", color = Color.White.copy(alpha = .7f)) }, modifier = Modifier.weight(1f).onFocusChanged { replyFocused = it.isFocused }, shape = CircleShape, singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = Color.White, unfocusedBorderColor = Color.White.copy(alpha = .5f), cursorColor = Color.White))
                        Spacer(Modifier.width(8.dp)); FilledIconButton({ val t = reply.trim(); if (t.isNotEmpty()) social.replyToMoment(m.id, t, onOpenChat) }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send") }
                    }
                }
            }
        } ?: Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White) }
    }
    viewers?.let { list -> AlertDialog(onDismissRequest = { viewers = null }, title = { Text("Seen by ${list.size}") }, text = { Column { if (list.isEmpty()) Muted("No views yet."); list.take(30).forEach { v -> Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(v.name), size = 32); Text(v.name, Modifier.weight(1f).padding(start = 10.dp)); Text(v.reaction ?: "") } } } }, confirmButton = { TextButton({ viewers = null }) { Text("Close") } }) }
}

/** Byte size of a picked file, before reading it, so a huge video is refused without loading it. */
private fun contentSize(ctx: Context, uri: Uri): Long? = runCatching { ctx.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null } }.getOrNull()

@Composable
fun NewMomentScreen(vm: BucksViewModel, onClose: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }; var caption by remember { mutableStateOf("") }
    var audience by remember { mutableStateOf(social.settings?.momentsAudience ?: "SYNCED") }; var reading by remember { mutableStateOf(false) }; var wantVideo by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri ?: return@rememberLauncherForActivityResult
        // Some galleries don't report a type; the chooser the user tapped is the next best guess.
        val mime = ctx.contentResolver.getType(uri) ?: if (wantVideo) "video/mp4" else ""
        if (mime.startsWith("video/")) {
            if (mime != "video/mp4") { vm.toast("Only MP4 videos can be shared. Phone camera videos are MP4."); return@rememberLauncherForActivityResult }
            val size = contentSize(ctx, uri); if (size != null && size > Social.MAX_VIDEO_BYTES) { vm.toast("That video is ${humanSize(size)}. Videos up to 30 MB, about 30 seconds."); return@rememberLauncherForActivityResult }
        }
        reading = true
        scope.launch {
            val p = withContext(Dispatchers.IO) { runCatching { Upload.read(ctx, uri, maxPx = 1920) }.getOrNull() }
                ?.let { r -> if (wantVideo && !r.isVideo && !r.isImage) Picked(r.bytes, if (r.name.endsWith(".mp4", true)) r.name else "${r.name}.mp4", "video/mp4") else r }
            reading = false
            when { p == null -> vm.toast("Couldn't open that file. Try another one.")
                   p.isVideo && p.bytes.size > Social.MAX_VIDEO_BYTES -> vm.toast("Videos up to 30 MB. Pick a shorter one.")
                   else -> { preview = uri; picked = p } }
        }
    }
    fun choose(video: Boolean) { wantVideo = video; pick.launch(PickVisualMediaRequest(if (video) ActivityResultContracts.PickVisualMedia.VideoOnly else ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    Column(Modifier.fillMaxSize().background(Color.Black).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClose) { Icon(Icons.Rounded.Close, "Close", tint = Color.White) }; Text("New moment", color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (picked != null) TextButton({ picked = null; preview = null }) { Text("Change", color = Color.White) } }
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val p = picked; val u = preview
            when {
                reading -> Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(color = Color.White); Text("Preparing…", color = Color.White.copy(alpha = .7f), modifier = Modifier.padding(top = 12.dp)) }
                p != null && u != null && p.isVideo -> MomentVideo(u.toString(), paused = false, modifier = Modifier.fillMaxSize(), loop = true)
                p != null && u != null -> AsyncImage(u, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                else -> Column(Modifier.padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("What do you want to share?", color = Color.White, style = MaterialTheme.typography.titleLarge)
                    Text("It stays up for 24 hours, then disappears.", color = Color.White.copy(alpha = .7f), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        MediaChoice(Icons.Rounded.Image, "Photo", "JPG or PNG", Modifier.weight(1f)) { choose(false) }
                        MediaChoice(Icons.Rounded.Videocam, "Video", "MP4, up to 30 MB", Modifier.weight(1f)) { choose(true) }
                    }
                }
            }
        }
        if (picked != null) Column(Modifier.padding(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("SYNCED" to "Synced", "LOCAL" to "Nearby", "CLOSE" to "Close friends").forEach { (k, l) -> Chip(l, selected = audience == k) { audience = k } } }
            OutlinedTextField(caption, { caption = it.take(200) }, placeholder = { Text("Add a caption", color = Color.White.copy(alpha = .6f)) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp), shape = MaterialTheme.shapes.medium, singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = Color.White, unfocusedBorderColor = Color.White.copy(alpha = .5f), cursorColor = Color.White))
            PrimaryButton(if (social.busy) "Uploading…" else "Share for 24 hours", Modifier.padding(top = 12.dp), enabled = picked != null && !social.busy) { picked?.let { social.postMoment(it, caption.trim(), audience); onClose() } }
        }
    }
}
@Composable
private fun MediaChoice(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, hint: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier.clip(MaterialTheme.shapes.large).background(Color.White.copy(alpha = .12f)).clickable(onClick = onClick).padding(vertical = 22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, null, Modifier.size(36.dp), tint = Color.White); Text(title, color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)); Text(hint, color = Color.White.copy(alpha = .7f), style = MaterialTheme.typography.labelSmall)
    }
}

/* ---------- MESSAGES and CHAT ---------- */

@Composable
fun CloudMessagesScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit, onSync: () -> Unit, onNewGroup: () -> Unit) {
    val social = vm.social; var menuFor by remember { mutableStateOf<InboxRow?>(null) }; var leaveFor by remember { mutableStateOf<InboxRow?>(null) }
    LaunchedEffect(Unit) { while (true) { social.refreshInbox(); delay(20_000) } }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Messages", onBack = onBack, actions = { IconButton(onNewGroup) { Icon(Icons.Rounded.GroupAdd, "New group") }; IconButton(onSync) { Icon(Icons.Rounded.PersonAddAlt, "Sync with someone") } })
        if (social.inbox.isEmpty()) Column(Modifier.padding(Gutter)) { Muted("No conversations yet. Sync with someone, then message them from their profile, or start a group with people you've synced with.")
            SmallButton("New group", Modifier.padding(top = 12.dp), tonal = true, onClick = onNewGroup) }
        LazyColumn { items(social.inbox.filter { !it.archived }, key = { it.conversationId }) { c ->
            ListRow(c.title ?: if (c.kind == "GROUP") "Group" else "Chat", listOfNotNull(c.lastBody?.take(60), ago(c.lastAt)).joinToString("  ·  "),
                leading = { Box { if (c.kind == "GROUP") Avatar(icon = Icons.Rounded.Group) else Avatar(initials(c.title ?: "?")); if (c.kind == "LISTING") Icon(Icons.Rounded.Storefront, null, Modifier.align(Alignment.BottomEnd).size(16.dp), tint = MaterialTheme.colorScheme.primary) } },
                trailing = { Row(verticalAlignment = Alignment.CenterVertically) { if (c.muted) Icon(Icons.Rounded.NotificationsOff, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); if (c.unread > 0) PillPurple("${c.unread}"); IconButton({ menuFor = c }) { Icon(Icons.Rounded.MoreVert, "More") } } },
                onClick = { onOpen(c.conversationId) })
            Divider() } }
    }
    menuFor?.let { c -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text(c.title ?: "Chat") }, text = { Column {
        TextButton({ social.mute(c.conversationId, !c.muted); menuFor = null }) { Text(if (c.muted) "Unmute" else "Mute notifications") }
        if (c.kind == "GROUP") TextButton({ leaveFor = c; menuFor = null }) { Text("Leave group", color = MaterialTheme.colorScheme.error) }
        c.otherId?.let { o -> TextButton({ social.block(o); menuFor = null }) { Text("Block ${c.otherName ?: ""}", color = MaterialTheme.colorScheme.error) } }
    } }, confirmButton = { TextButton({ menuFor = null }) { Text("Close") } }) }
    leaveFor?.let { c -> LeaveGroupDialog(c.title ?: "this group", onConfirm = { social.leaveConversation(c.conversationId); leaveFor = null }, onDismiss = { leaveFor = null }) }
}

@Composable
private fun LeaveGroupDialog(title: String, onConfirm: () -> Unit, onDismiss: () -> Unit) = AlertDialog(onDismissRequest = onDismiss, title = { Text("Leave $title?") },
    text = { Text("You'll stop getting its messages and can't read the chat any more. Someone in the group can add you back later.") },
    confirmButton = { TextButton(onConfirm) { Text("Leave", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton(onDismiss) { Text("Cancel") } })

/** Pick synced people by name: a search box, then a checklist. Shared by New group and Add people. */
@Composable
private fun PeoplePicker(people: List<ProfileRow>, selected: Set<String>, onToggle: (String) -> Unit, modifier: Modifier = Modifier, emptyText: String) {
    var q by remember { mutableStateOf("") }
    val shown = people.filter { q.isBlank() || it.name.contains(q.trim(), true) || it.area.contains(q.trim(), true) || it.shortCode.contains(q.trim().replace(" ", ""), true) }.sortedBy { it.name.lowercase() }
    Column(modifier) {
        OutlinedTextField(q, { q = it }, placeholder = { Text("Search by name or Bucks ID") }, leadingIcon = { Icon(Icons.Rounded.Search, null) }, modifier = Modifier.fillMaxWidth().padding(horizontal = Gutter), shape = MaterialTheme.shapes.medium, singleLine = true,
            trailingIcon = { if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, "Clear") } })
        if (selected.isNotEmpty()) LazyRow(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(people.filter { it.id in selected }, key = { it.id }) { p -> Chip(p.name.substringBefore(' '), selected = true, icon = Icons.Rounded.Close) { onToggle(p.id) } } }
        when {
            people.isEmpty() -> Muted(emptyText, Modifier.padding(Gutter))
            shown.isEmpty() -> Muted("No one synced with you matches \"${q.trim()}\".", Modifier.padding(Gutter))
        }
        LazyColumn(Modifier.weight(1f, fill = false).padding(top = 4.dp)) { items(shown, key = { it.id }) { p ->
            ListRow(p.name, p.area.ifBlank { pretty(p.shortCode) }, leading = { Avatar(initials(p.name), size = 40) }, trailing = { Checkbox(checked = p.id in selected, onCheckedChange = { onToggle(p.id) }) }, onClick = { onToggle(p.id) })
            Divider() } }
    }
}

/** Start a group: name it, tick synced people, Create. Only people synced with you can be members. */
@Composable
fun NewGroupScreen(vm: BucksViewModel, onBack: () -> Unit, onCreated: (String) -> Unit) {
    val social = vm.social
    var title by remember { mutableStateOf("") }; var selected by remember { mutableStateOf<Set<String>>(emptySet()) }; var creating by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { social.refreshSyncs() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("New group", onBack = onBack)
        Column(Modifier.weight(1f)) {
            Column(Modifier.padding(horizontal = Gutter)) {
                BucksField(title, { title = it.take(60) }, label = "Group name", placeholder = "Sunday cricket, 4th Cross neighbours, shop staff")
                Label("People"); Muted("Only people synced with you can join. Ask the others to sync with you first.", Modifier.padding(bottom = 8.dp))
            }
            PeoplePicker(social.synced, selected, onToggle = { id -> selected = if (id in selected) selected - id else selected + id }, modifier = Modifier.weight(1f),
                emptyText = "Nobody is synced with you yet. Open Sync from Messages, share your Bucks ID, then come back to make a group.")
        }
        Column(Modifier.padding(Gutter)) {
            PrimaryButton(when { creating -> "Creating…"; selected.isEmpty() -> "Create group"; else -> "Create group with ${selected.size}" }, enabled = title.isNotBlank() && selected.isNotEmpty() && !creating) {
                creating = true; social.createGroup(title, selected.toList(), onCreated = onCreated, onFailed = { creating = false }) }
        }
    }
}

/** Title row for a group or listing chat: the title itself opens the members sheet or the listing. */
@Composable
private fun ChatTopBar(title: String, subtitle: String?, onBack: () -> Unit, onTitle: (() -> Unit)?, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.weight(1f).clip(MaterialTheme.shapes.small).then(if (onTitle != null) Modifier.clickable(onClick = onTitle) else Modifier).padding(horizontal = 4.dp, vertical = 2.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Muted(subtitle, maxLines = 1)
        }
        actions()
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CloudChatScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onOpenListing: (String) -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var msgs by remember { mutableStateOf<List<MessageRow>>(emptyList()) }; var text by remember { mutableStateOf("") }; var seen by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<MessageRow?>(null) }; var menuFor by remember { mutableStateOf<MessageRow?>(null) }
    var conv by remember { mutableStateOf<ConversationRow?>(null) }; var members by remember { mutableStateOf<List<ConversationMemberRow>>(emptyList()) }; var showMembers by remember { mutableStateOf(false) }
    val listState = rememberLazyListState(); val meId = social.me?.id
    val inboxRow = social.inbox.firstOrNull { it.conversationId == id }
    // The conversation row is the source of truth for kind and title; the inbox row fills in until it loads (and names the other person in a DM).
    val kind = conv?.kind ?: inboxRow?.kind ?: "DIRECT"
    val listingTitle = conv?.title ?: inboxRow?.title ?: "Listing"
    // A listing chat is named after the shop or pro; the people who run it see the customer's name instead.
    val customer = if (kind == "LISTING" && members.any { it.profileId == meId && it.role == "ADMIN" }) members.firstOrNull { it.role == "MEMBER" }?.let { social.nameOf(it.profileId) } else null
    val title = when (kind) { "DIRECT" -> inboxRow?.title ?: "Chat"; "LISTING" -> customer ?: listingTitle; else -> conv?.title ?: inboxRow?.title ?: "Group" }
    LaunchedEffect(id) { conv = runCatching { social.conversation(id) }.getOrNull(); msgs = runCatching { social.messages(id) }.getOrDefault(emptyList()); social.markRead(id); seen = runCatching { social.seenUpTo(id) }.getOrNull() }
    LaunchedEffect(id, kind) { if (kind != "DIRECT") members = runCatching { social.members(id) }.getOrDefault(emptyList()) }
    DisposableEffect(id) {
        val (channel, flow) = Backend.liveMessages(id)
        val job = scope.launch { runCatching { flow.collect { m -> if (msgs.none { it.id == m.id }) { social.namesFor(listOf(m.senderId)); msgs = msgs + m; if (m.senderId != meId) social.markRead(id) } } } }
        onDispose { job.cancel(); scope.launch { Backend.closeChannel(channel) } }
    }
    LaunchedEffect(msgs.size) { if (msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { u -> Upload.read(ctx, u)?.let { social.sendFile(id, it) } } }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { u -> Upload.read(ctx, u)?.let { f -> if (f.bytes.size > 25 * 1024 * 1024) vm.toast("Files up to 25 MB.") else social.sendFile(id, f) } } }
    val listingId = conv?.listingId
    Column(Modifier.fillMaxSize().imePadding()) {
        when (kind) {
            "DIRECT" -> BucksTopBar(title, onBack = onBack)
            "LISTING" -> ChatTopBar(title, when { customer != null -> "Customer · about $listingTitle"; listingId != null -> "Shop or pro · tap to open"; else -> null }, onBack, onTitle = listingId?.let { l -> { onOpenListing(l) } },
                actions = { if (listingId != null) IconButton({ onOpenListing(listingId) }) { Icon(Icons.Rounded.Storefront, "Open listing") }; IconButton({ showMembers = true }) { Icon(Icons.Rounded.Group, "People in this chat") } })
            else -> ChatTopBar(title, if (members.isEmpty()) "Group" else "${members.size} people · tap for details", onBack, onTitle = { showMembers = true },
                actions = { IconButton({ showMembers = true }) { Icon(Icons.Rounded.Group, "Members") } })
        }
        if (msgs.isEmpty()) Muted(when (kind) { "GROUP" -> "No messages yet. Say hello to the group."; "LISTING" -> "No messages yet. Ask about prices, timings or availability."; else -> "No messages yet. Say hello." }, Modifier.padding(Gutter))
        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp), state = listState, contentPadding = PaddingValues(vertical = 12.dp)) {
            items(msgs, key = { it.id }) { m -> val mine = m.senderId == meId
                Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                    Column(Modifier.widthIn(max = 320.dp).clip(MaterialTheme.shapes.large).background(if (mine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer).combinedClickable(onClick = {}, onLongClick = { if (mine && m.deletedAt == null) menuFor = m }).padding(4.dp)) {
                        val fg = if (mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
                        // Groups and listing inboxes have several people on the other side, so every bubble that isn't mine carries its sender.
                        if (!mine && kind != "DIRECT") Text(social.nameOf(m.senderId), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 10.dp, top = 6.dp))
                        m.attachment?.let { a -> val path = a.s("path"); val mime = a.s("mime")
                            if (mime.startsWith("image/")) SignedImage(vm, "chat", path, Modifier.size(220.dp).clip(MaterialTheme.shapes.medium).clickable { scope.launch { runCatching { social.fileUrl("chat", path) }.getOrNull()?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } } })
                            else Row(Modifier.clip(MaterialTheme.shapes.medium).background(fg.copy(alpha = .12f)).clickable { scope.launch { runCatching { social.fileUrl("chat", path) }.getOrNull()?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } } }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.Description, null, tint = fg); Column(Modifier.padding(start = 10.dp)) { Text(a.s("name"), style = MaterialTheme.typography.titleSmall, color = fg, maxLines = 1); Text(humanSize(a.s("size").toLongOrNull() ?: 0), style = MaterialTheme.typography.labelSmall, color = fg.copy(alpha = .8f)) } } }
                        if (m.deletedAt != null) Text("Message deleted", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Normal), color = fg.copy(alpha = .7f), modifier = Modifier.padding(10.dp, 8.dp))
                        else if (m.body.isNotBlank()) Text(m.body, style = MaterialTheme.typography.bodyMedium, color = fg, modifier = Modifier.padding(10.dp, 8.dp))
                        Text(listOfNotNull(ago(m.createdAt), if (m.editedAt != null) "edited" else null).joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = fg.copy(alpha = .7f), modifier = Modifier.padding(start = 10.dp, end = 10.dp, bottom = 6.dp).align(Alignment.End))
                    }
                }
            }
            val lastMine = msgs.lastOrNull { it.senderId == meId }
            if (lastMine != null && seen != null && seen!! >= lastMine.createdAt) item { Text("Seen", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.End) }
        }
        if (social.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        editing?.let { e -> Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Muted("Editing", Modifier.weight(1f)); IconButton({ editing = null; text = "" }) { Icon(Icons.Rounded.Close, "Cancel edit") } } }
        Surface(tonalElevation = 1.dp) { Row(Modifier.fillMaxWidth().padding(12.dp, 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton({ pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !social.busy) { Icon(Icons.Rounded.Image, "Photo", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            IconButton({ pickFile.launch(arrayOf("*/*")) }, enabled = !social.busy) { Icon(Icons.Rounded.AttachFile, "File", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            OutlinedTextField(text, { text = it }, placeholder = { Text("Message") }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, maxLines = 4)
            Spacer(Modifier.width(8.dp))
            FilledIconButton(onClick = { val t = text.trim(); if (t.isEmpty()) return@FilledIconButton
                editing?.let { e -> social.editMessage(e.id, t); msgs = msgs.map { if (it.id == e.id) it.copy(body = t, editedAt = "now") else it }; editing = null } ?: social.send(id, t); text = "" }, enabled = text.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, "Send") }
        } }
    }
    menuFor?.let { m -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text("Your message") }, text = { Column {
        if (m.body.isNotBlank()) TextButton({ editing = m; text = m.body; menuFor = null }) { Text("Edit") }
        TextButton({ social.deleteMessage(m.id); msgs = msgs.map { if (it.id == m.id) it.copy(body = "", attachment = null, deletedAt = "now") else it }; menuFor = null }) { Text("Delete for everyone", color = MaterialTheme.colorScheme.error) }
    } }, confirmButton = { TextButton({ menuFor = null }) { Text("Close") } }) }
    if (showMembers) MembersSheet(vm, id, kind, title, members, onReload = { scope.launch { members = runCatching { social.members(id) }.getOrDefault(emptyList()) } },
        onRenamed = { conv = conv?.copy(title = it) }, onLeft = { showMembers = false; onBack() }, onOpenListing = listingId?.let { l -> { onOpenListing(l) } }, onDismiss = { showMembers = false })
}

/** Who's in a group or listing chat. Groups: add synced people, rename, admins remove, anyone leaves. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MembersSheet(vm: BucksViewModel, conv: String, kind: String, title: String, members: List<ConversationMemberRow>, onReload: () -> Unit, onRenamed: (String) -> Unit, onLeft: () -> Unit, onOpenListing: (() -> Unit)?, onDismiss: () -> Unit) {
    val social = vm.social; val meId = social.me?.id
    val iAmAdmin = members.any { it.profileId == meId && it.role == "ADMIN" }; val group = kind == "GROUP"
    var rename by remember { mutableStateOf<String?>(null) }; var adding by remember { mutableStateOf(false) }; var removeFor by remember { mutableStateOf<ConversationMemberRow?>(null) }; var leaving by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { onReload(); if (group) social.refreshSyncs() }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (group) IconButton({ rename = title }) { Icon(Icons.Rounded.Edit, "Rename group") } }
        Muted(if (group) "${members.size} people · only people synced with you can be added" else "The shop or pro and everyone who runs it share this chat with you.", Modifier.padding(bottom = 8.dp))
        if (group) Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SmallButton("Add people", tonal = true) { adding = true }; SmallButton("Rename", tonal = true) { rename = title } }
        if (!group && onOpenListing != null) SmallButton("Open listing", Modifier.padding(bottom = 6.dp), tonal = true, onClick = onOpenListing)
        if (members.isEmpty()) Muted("Loading people…", Modifier.padding(vertical = 12.dp))
        LazyColumn(Modifier.heightIn(max = 320.dp)) { items(members, key = { it.profileId }) { m -> val name = social.nameOf(m.profileId)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Avatar(initials(name.ifBlank { "?" }), size = 40)
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(if (m.profileId == meId) "$name (you)" else name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); if (m.role == "ADMIN") Muted(if (group) "Admin" else "Runs the listing") }
                if (group && iAmAdmin && m.profileId != meId) IconButton({ removeFor = m }) { Icon(Icons.Rounded.PersonRemove, "Remove $name", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }; Divider() } }
        if (group) BadButton("Leave group", Modifier.padding(top = 10.dp)) { leaving = true }
    } }
    rename?.let { r -> AlertDialog(onDismissRequest = { rename = null }, title = { Text("Rename group") },
        text = { OutlinedTextField(r, { rename = it.take(60) }, placeholder = { Text("Group name") }, singleLine = true, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { TextButton({ val t = r.trim(); if (t.isNotEmpty()) social.renameGroup(conv, t) { onRenamed(t) }; rename = null }, enabled = r.isNotBlank()) { Text("Save") } }, dismissButton = { TextButton({ rename = null }) { Text("Cancel") } }) }
    removeFor?.let { m -> AlertDialog(onDismissRequest = { removeFor = null }, title = { Text("Remove ${social.nameOf(m.profileId)}?") }, text = { Text("They'll stop getting the group's messages. You can add them again later.") },
        confirmButton = { TextButton({ social.removeFromGroup(conv, m.profileId) { onReload() }; removeFor = null }) { Text("Remove", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ removeFor = null }) { Text("Cancel") } }) }
    if (leaving) LeaveGroupDialog(title, onConfirm = { leaving = false; social.leaveConversation(conv) { onLeft() } }, onDismiss = { leaving = false })
    if (adding) AddPeopleSheet(vm, conv, already = members.map { it.profileId }.toSet(), onAdded = { adding = false; onReload() }, onDismiss = { adding = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddPeopleSheet(vm: BucksViewModel, conv: String, already: Set<String>, onAdded: () -> Unit, onDismiss: () -> Unit) {
    val social = vm.social; var selected by remember { mutableStateOf<Set<String>>(emptySet()) }; var busy by remember { mutableStateOf(false) }
    val candidates = social.synced.filter { it.id !in already }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(bottom = 24.dp)) {
        Text("Add people", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = Gutter))
        Muted("People synced with you who aren't in the group yet.", Modifier.padding(horizontal = Gutter, vertical = 6.dp))
        PeoplePicker(candidates, selected, onToggle = { id -> selected = if (id in selected) selected - id else selected + id }, modifier = Modifier.heightIn(max = 420.dp),
            emptyText = if (social.synced.isEmpty()) "Nobody is synced with you yet. Share your Bucks ID from Sync first." else "Everyone synced with you is already in this group.")
        PrimaryButton(if (busy) "Adding…" else if (selected.isEmpty()) "Add" else "Add ${selected.size}", Modifier.padding(Gutter), enabled = selected.isNotEmpty() && !busy) { busy = true; social.addToGroup(conv, selected.toList()) { onAdded() } }
    } }
}
private fun humanSize(b: Long) = when { b >= 1_048_576 -> "%.1f MB".format(b / 1_048_576.0); b >= 1024 -> "${b / 1024} KB"; b > 0 -> "$b B"; else -> "" }
