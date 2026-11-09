package com.bucks.app.ui.screens

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.AudioAttributes
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
    when { s < 60 -> Str.get(R.string.g2_ago_now); s < 3600 -> Str.get(R.string.g2_ago_min, (s / 60).toInt()); s < 86400 -> Str.get(R.string.g2_ago_hours, (s / 3600).toInt()); s < 172800 -> Str.get(R.string.g2_ago_yesterday); else -> DateTimeFormatter.ofPattern("d MMM").format(t.atZone(ZoneId.systemDefault())) }
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
    val ended by rememberUpdatedState(onEnded); val progress by rememberUpdatedState(onProgress); val isPaused by rememberUpdatedState(paused)
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val player = remember(url) {
        // handleAudioFocus: a call or another app's audio pauses the clip instead of playing over it.
        ExoPlayer.Builder(ctx).setAudioAttributes(AudioAttributes.DEFAULT, true).build().apply {
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
    // In the background (Home, a call, another app on top) the clip stops: no sound, and it can't reach its end and move the viewer on.
    DisposableEffect(player, lifecycle) {
        val observer = LifecycleEventObserver { _, e -> when (e) { Lifecycle.Event.ON_STOP -> player.pause(); Lifecycle.Event.ON_START -> player.setPlayWhenReady(!isPaused); else -> {} } }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(player, paused) { player.playWhenReady = !paused && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) }
    LaunchedEffect(player) { while (true) { val d = player.duration; if (d > 0) progress((player.currentPosition.toFloat() / d).coerceIn(0f, 1f)); delay(50) } }
    Box(modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        AndroidView(factory = { c -> PlayerView(c).apply { useController = false; resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT; setShutterBackgroundColor(android.graphics.Color.BLACK) } }, update = { it.player = player }, modifier = Modifier.fillMaxSize())
        if (buffering) BucksLoader(color = Color.White, label = stringResource(R.string.g2_cd_buffering))
    }
}

/* ---------- FEED with the Moments tray ---------- */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudFeedScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onOpenMoments: (String) -> Unit, onNewMoment: () -> Unit, onFindPeople: () -> Unit = {}) {
    val social = vm.social; val ctx = LocalContext.current
    var compose by remember { mutableStateOf(false) }; var comments by remember { mutableStateOf<String?>(null) }
    var muteFor by remember { mutableStateOf<TrayRow?>(null) }; var showMuted by remember { mutableStateOf(false) }
    LaunchedEffect(social.me?.id) { if (social.me != null) social.refreshFeed() }
    var hintSeen by remember { mutableStateOf(com.bucks.app.data.Prefs.voteHintSeen) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_feed_title), onMenu = onMenu, unread = social.unread, onChat = onMessages)
        LazyColumn {
            item { MomentsTray(social.tray, myName = social.me?.name ?: stringResource(R.string.g2_you), onOpen = onOpenMoments, onNew = onNewMoment, onMute = { muteFor = it }, onMore = { showMuted = true }) }
            item { Box(Modifier.padding(horizontal = Gutter, vertical = 8.dp)) { Surface(Modifier.fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).clickable { compose = true }, shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
                Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Edit, null, Modifier.size(24.dp)); Spacer(Modifier.width(16.dp)); Text(stringResource(R.string.g2_feed_compose_prompt), style = MaterialTheme.typography.bodyLarge) } } } }
            // Once: why only one number shows on a post before voting.
            if (!hintSeen && social.feed.any { it.myVote == null && it.authorId != social.me?.id }) item {
                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 6.dp)) {
                    Row(Modifier.padding(start = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.g2_feed_vote_hint), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.weight(1f).padding(vertical = 10.dp))
                        TextButton({ hintSeen = true; com.bucks.app.data.Prefs.voteHintSeen = true }) { Text(stringResource(R.string.g2_got_it)) }
                    }
                }
            }
            // The Feed is the people you've synced with (and pages you sync with); strangers' posts never land here.
            if (social.feed.isEmpty()) item { Column(Modifier.padding(Gutter)) {
                Muted(stringResource(R.string.g2_feed_empty))
                SmallButton(stringResource(R.string.g2_feed_find_people), Modifier.padding(top = 10.dp), tonal = true, onClick = onFindPeople) } }
            items(social.feed, key = { it.id }) { p -> CloudPostCard(vm, p, onVote = { social.vote(p.id, it); if (!hintSeen) { hintSeen = true; com.bucks.app.data.Prefs.voteHintSeen = true } }, onComments = { comments = p.id }, onShare = { shareText(ctx, Str.get(R.string.g2_share_post, p.authorName, p.body)) }, onDelete = { social.deletePost(p.id) }) }
            if (social.feed.isNotEmpty() && !social.feedEnd) item { TextButton({ social.loadMoreFeed() }, Modifier.fillMaxWidth().padding(8.dp)) { Text(stringResource(R.string.g2_load_more)) } }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    if (compose) NewPostSheet(vm) { compose = false }
    comments?.let { id -> CloudCommentsSheet(vm, id) { comments = null } }
    muteFor?.let { t -> AlertDialog(onDismissRequest = { muteFor = null }, title = { Text(stringResource(R.string.g2_mute_moments_title, t.authorName.substringBefore(' '))) },
        text = { Text(stringResource(R.string.g2_mute_moments_body)) },
        confirmButton = { TextButton({ social.muteMoments(t.authorId, true); muteFor = null }) { Text(stringResource(R.string.g2_mute)) } }, dismissButton = { TextButton({ muteFor = null }) { Text(stringResource(R.string.g2_cancel)) } }) }
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
                Box(Modifier.align(Alignment.BottomEnd).size(22.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary).border(2.dp, MaterialTheme.colorScheme.surface, CircleShape).clickable(onClick = onNew), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Add, stringResource(R.string.g2_cd_add_moment), Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onPrimary) }
            }
            Text(stringResource(if (mine != null) R.string.g2_your_moment else R.string.g2_add_moment), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) } }
        items(others, key = { it.authorId }) { t -> Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(68.dp).combinedClickable(onClick = { onOpen(t.authorId) }, onLongClick = { onMute?.invoke(t) })) {
            MomentRing(unseen = t.unseen > 0, has = true) { Avatar(initials(t.authorName), size = 56) }
            Text(t.listingTitle ?: t.authorName.substringBefore(' '), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) } }
        if (onMore != null) item { Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(68.dp).clickable(onClick = onMore)) {
            MomentRing(unseen = false, has = false) { Avatar(icon = Icons.Rounded.MoreHoriz, size = 56, tinted = false) }
            Text(stringResource(R.string.g2_more), style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 4.dp)) } }
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
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text(stringResource(R.string.g2_muted_moments_title), style = MaterialTheme.typography.titleLarge)
        Muted(stringResource(R.string.g2_muted_moments_info), Modifier.padding(top = 4.dp, bottom = 10.dp))
        if (social.mutedMoments.isEmpty()) Muted(stringResource(R.string.g2_muted_moments_empty), Modifier.padding(vertical = 12.dp))
        else social.mutedMoments.forEach { p -> PersonRow(p, trailing = { SmallButton(stringResource(R.string.g2_unmute), tonal = true) { social.unmuteMoments(p.id) } }) }
    } }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CloudPostCard(vm: BucksViewModel, p: FeedRow, onVote: (Int) -> Unit, onComments: () -> Unit, onShare: () -> Unit, onDelete: () -> Unit) {
    val mine = p.authorId == vm.social.me?.id; var menu by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { if (mine) menu = true }).padding(horizontal = Gutter, vertical = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(p.authorName), size = 40, photoUrl = vm.social.photoOf(p.authorId))
            Column(Modifier.padding(start = 10.dp).weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(p.listingTitle ?: p.authorName, style = MaterialTheme.typography.titleMedium); if (mine) Muted("  ·  " + stringResource(R.string.g2_you)) else if (p.synced) Muted("  ·  " + stringResource(R.string.g2_synced)) }
                Muted(listOfNotNull(ago(p.createdAt), p.area.ifBlank { null }, when (p.visibility) { "SYNCED" -> stringResource(R.string.g2_visibility_synced); "PUBLIC" -> stringResource(R.string.g2_visibility_public); else -> null }).joinToString(" · ")) }
            if (mine) Box { IconButton({ menu = true }) { Icon(Icons.Rounded.MoreHoriz, stringResource(R.string.g2_more)) }; DropdownMenu(menu, { menu = false }) { DropdownMenuItem({ Text(stringResource(R.string.g2_delete_post)) }, { menu = false; onDelete() }) } } }
        if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        // In the viewer a vote is a direct one (no feedback box); the box stays on the arrows below the post.
        PostMedia(vm, p.media, vote = com.bucks.app.ui.ViewerVote(p.up, p.down, p.myVote ?: 0, onVote = onVote))
        val my = p.myVote ?: 0
        val upColor = if (my == 1) MaterialTheme.status.good else MaterialTheme.colorScheme.onSurfaceVariant; val downColor = if (my == -1) MaterialTheme.status.bad else MaterialTheme.colorScheme.onSurfaceVariant
        // Tapping an arrow opens the feedback box; tapping the arrow I already chose takes my vote back (my own posts too).
        var voting by remember { mutableStateOf<Int?>(null) }
        fun tap(v: Int) { if (my == v) onVote(v) else voting = v }
        voting?.let { v -> VoteFeedbackSheet(stringResource(R.string.g2_recommend_post_q), v, onSubmit = { vote, text, _ ->
            voting = null; if (vote != my) onVote(vote); if (text.isNotBlank()) vm.social.comment(p.id, text) {} }, onDismiss = { voting = null }) }
        // Only the larger side carries a number until I vote; then both do (postCountsShown).
        val (upShown, downShown) = postCountsShown(p.up, p.down, my)
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable(onClickLabel = stringResource(R.string.g2_recommend)) { tap(1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowUpward, stringResource(R.string.g2_recommend), Modifier.size(20.dp), tint = upColor); upShown?.let { Text(" $it", color = upColor, style = MaterialTheme.typography.labelLarge) } }
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable(onClickLabel = stringResource(R.string.g2_not_recommend)) { tap(-1) }.padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowDownward, stringResource(R.string.g2_cd_not_recommended), Modifier.size(20.dp), tint = downColor); downShown?.let { Text(" $it", color = downColor, style = MaterialTheme.typography.labelLarge) } }
            Spacer(Modifier.weight(1f))
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).clickable(onClick = onComments).padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ChatBubbleOutline, stringResource(R.string.g2_comments), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(" ${p.comments}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge) }
            IconButton(onClick = onShare) { Icon(Icons.Rounded.IosShare, stringResource(R.string.g2_cd_share), Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
    Divider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudCommentsSheet(vm: BucksViewModel, postId: String, onDismiss: () -> Unit) {
    val social = vm.social; var rows by remember { mutableStateOf<List<CommentRow>>(emptyList()) }; var reply by remember { mutableStateOf("") }; var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(postId, tick) { rows = runCatching { social.comments(postId) }.getOrDefault(emptyList()) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) { Text(stringResource(R.string.g2_comments), style = MaterialTheme.typography.titleLarge)
        if (rows.isEmpty()) Muted(stringResource(R.string.g2_comments_empty), Modifier.padding(vertical = 12.dp)) else rows.forEach { c -> Column(Modifier.padding(vertical = 10.dp)) { Row { Text(social.nameOf(c.authorId), style = MaterialTheme.typography.titleSmall); Muted("  ${ago(c.createdAt)}") }; Text(c.body, style = MaterialTheme.typography.bodyMedium) }; Divider() }
        Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(reply, { reply = it }, placeholder = { Text(stringResource(R.string.g2_reply)) }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, singleLine = true); Spacer(Modifier.width(8.dp))
            FilledIconButton(onClick = { val t = reply.trim(); if (t.isNotEmpty()) social.comment(postId, t) { reply = ""; tick++ } }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.g2_cd_send)) } } } }
}

/** The cloud post composer (social.post): used by the feed, my profile and the create-post route in cloud builds. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewPostSheet(vm: BucksViewModel, onDismiss: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val s by vm.state.collectAsState()
    var text by remember { mutableStateOf("") }; var visibility by remember { mutableStateOf("LOCAL") }; var photos by remember { mutableStateOf<List<Picked>>(emptyList()) }
    // Photos and MP4 videos (one video at most, up to 15 MB: the posts bucket's limit).
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris ->
        var videos = 0; var skipped = 0
        photos = uris.mapNotNull { u ->
            val mime = ctx.contentResolver.getType(u).orEmpty()
            when {
                mime.startsWith("video/") -> when {
                    mime != "video/mp4" -> { vm.toast(Str.get(R.string.g2_post_mp4_only)); null }
                    ++videos > 1 -> { skipped++; null }
                    (contentSize(ctx, u) ?: 0L) > Social.MAX_POST_VIDEO_BYTES -> { vm.toast(Str.get(R.string.g2_post_video_too_big_pick)); null }
                    else -> Upload.read(ctx, u) ?: run { vm.toast(Str.get(R.string.g2_video_open_failed)); null }
                }
                else -> Upload.read(ctx, u) ?: run { vm.toast(Str.get(R.string.g2_photo_read_failed)); null }
            }
        }
        if (skipped > 0) vm.toast(Str.get(R.string.g2_post_one_video))
    }
    fun addCaptured(u: Uri, video: Boolean) {
        if (photos.size >= 4) { vm.toast(Str.get(R.string.g2_post_max_attachments)); return }
        if (video && photos.any { it.isVideo }) { vm.toast(Str.get(R.string.g2_post_one_video)); return }
        if (video && (contentSize(ctx, u) ?: 0L) > Social.MAX_POST_VIDEO_BYTES) { vm.toast(Str.get(R.string.g2_post_video_too_big_record)); return }
        Upload.read(ctx, u)?.let { photos = photos + it } ?: vm.toast(Str.get(R.string.g2_camera_open_failed))
    }
    val camera = com.bucks.app.ui.rememberCamera(maxVideoBytes = Social.MAX_POST_VIDEO_BYTES.toLong(), onError = { vm.toast(it) }, onPhoto = { addCaptured(it, false) }, onVideo = { addCaptured(it, true) })
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text(stringResource(R.string.g2_new_post), style = MaterialTheme.typography.titleLarge)
        BucksField(text, { text = it }, placeholder = stringResource(R.string.g2_new_post_hint), modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 4)
        Label(stringResource(R.string.g2_who_can_see)); Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("LOCAL" to stringResource(R.string.g2_audience_nearby), "SYNCED" to stringResource(R.string.g2_visibility_synced), "PUBLIC" to stringResource(R.string.g2_audience_everyone)).forEach { (k, l) -> Chip(l, selected = visibility == k) { visibility = k } } }
        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) { SmallButton(stringResource(R.string.g2_camera), tonal = true) { camera.takePhoto() }; Spacer(Modifier.width(6.dp)); SmallButton(stringResource(R.string.g2_record), tonal = true) { camera.recordVideo() }; Spacer(Modifier.width(6.dp)); SmallButton(if (photos.isEmpty()) stringResource(R.string.g2_gallery) else pluralStringResource(R.plurals.g2_attached, photos.size, photos.size), tonal = true) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }; if (photos.isNotEmpty()) TextButton({ photos = emptyList() }) { Text(stringResource(R.string.g2_remove)) } }
        PrimaryButton(if (social.busy) stringResource(R.string.g2_posting) else stringResource(R.string.g2_post_action), Modifier.padding(top = 14.dp), enabled = !social.busy && (text.isNotBlank() || photos.isNotEmpty())) { social.post(text.trim(), photos, visibility, s.user?.area?.substringBefore(',') ?: ""); onDismiss() }
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
                Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(social.nameOf(m.authorId).ifBlank { "?" }), size = 32, photoUrl = social.photoOf(m.authorId))
                    Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(social.nameOf(m.authorId), color = Color.White, style = MaterialTheme.typography.titleSmall); Text(listOfNotNull(ago(m.createdAt), if (isVideo) stringResource(R.string.g2_video) else null).joinToString(" · "), color = Color.White.copy(alpha = .7f), style = MaterialTheme.typography.labelSmall) }
                    if (mine) IconButton({ social.deleteMoment(m.id); if (slides.size == 1) onClose() else { slides = slides.filterNot { it.first.id == m.id }; index = index.coerceAtMost(slides.lastIndex) } }) { Icon(Icons.Rounded.DeleteOutline, stringResource(R.string.g2_cd_delete), tint = Color.White) }
                    if (!mine) com.bucks.app.ui.social.LocalReporter.current?.let { rep -> IconButton({ val t = com.bucks.app.ui.social.ReportTarget("MOMENT", m.id, m.authorId, social.nameOf(m.authorId)); onClose(); rep(t) }) { Icon(Icons.Rounded.OutlinedFlag, stringResource(R.string.g2_cd_report_moment), tint = Color.White) } }
                    IconButton(onClose) { Icon(Icons.Rounded.Close, stringResource(R.string.g2_close), tint = Color.White) } }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .7f)))).navigationBarsPadding().imePadding().padding(16.dp)) {
                if (m.caption.isNotBlank()) Text(m.caption, color = Color.White, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(bottom = 10.dp))
                if (mine) TextButton({ scope.launch { viewers = runCatching { social.momentViewers(m.id) }.getOrDefault(emptyList()) } }) { Icon(Icons.Rounded.Visibility, null, tint = Color.White); Text("  " + stringResource(R.string.g2_seen_by), color = Color.White) }
                else {
                    Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { listOf("❤️", "🔥", "👏", "😂", "😮").forEach { e -> Text(e, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.clip(CircleShape).clickable { social.viewMoment(m.id, e) }.padding(6.dp)) } }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(reply, { reply = it }, placeholder = { Text(stringResource(R.string.g2_reply_to, social.nameOf(m.authorId).substringBefore(' ')), color = Color.White.copy(alpha = .7f)) }, modifier = Modifier.weight(1f).onFocusChanged { replyFocused = it.isFocused }, shape = CircleShape, singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = Color.White, unfocusedBorderColor = Color.White.copy(alpha = .5f), cursorColor = Color.White))
                        Spacer(Modifier.width(8.dp)); FilledIconButton({ val t = reply.trim(); if (t.isNotEmpty()) social.replyToMoment(m.id, t, onOpenChat) }, enabled = reply.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.g2_cd_send)) }
                    }
                }
            }
        } ?: Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { BucksLoader(color = Color.White) }
    }
    viewers?.let { list -> AlertDialog(onDismissRequest = { viewers = null }, title = { Text(stringResource(R.string.g2_seen_by_count, list.size)) }, text = { Column { if (list.isEmpty()) Muted(stringResource(R.string.g2_no_views)); list.take(30).forEach { v -> Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(v.name), size = 32); Text(v.name, Modifier.weight(1f).padding(start = 10.dp)); Text(v.reaction ?: "") } } } }, confirmButton = { TextButton({ viewers = null }) { Text(stringResource(R.string.g2_close)) } }) }
}

/** Byte size of a picked file, before reading it, so a huge video is refused without loading it. */
private fun contentSize(ctx: Context, uri: Uri): Long? = runCatching { ctx.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null } }.getOrNull()

@Composable
fun NewMomentScreen(vm: BucksViewModel, onClose: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }; var caption by remember { mutableStateOf("") }
    var audience by remember { mutableStateOf(social.settings?.momentsAudience ?: "SYNCED") }; var reading by remember { mutableStateOf(false) }; var wantVideo by remember { mutableStateOf(false) }
    // One path for a gallery pick and a camera capture: check the type and size, read it, show it.
    fun handle(uri: Uri) {
        // Some galleries don't report a type; the chooser the user tapped is the next best guess.
        val mime = ctx.contentResolver.getType(uri) ?: if (wantVideo) "video/mp4" else ""
        if (mime.startsWith("video/")) {
            if (mime != "video/mp4") { vm.toast(Str.get(R.string.g2_moment_mp4_only)); return }
            val size = contentSize(ctx, uri); if (size != null && size > Social.MAX_VIDEO_BYTES) { vm.toast(Str.get(R.string.g2_moment_video_too_big, humanSize(size))); return }
        }
        reading = true
        scope.launch {
            val p = withContext(Dispatchers.IO) { runCatching { Upload.read(ctx, uri, maxPx = 1920) }.getOrNull() }
                ?.let { r -> if (wantVideo && !r.isVideo && !r.isImage) Picked(r.bytes, if (r.name.endsWith(".mp4", true)) r.name else "${r.name}.mp4", "video/mp4") else r }
            reading = false
            when { p == null -> vm.toast(Str.get(R.string.g2_file_open_failed_other))
                   p.isVideo && p.bytes.size > Social.MAX_VIDEO_BYTES -> vm.toast(Str.get(R.string.g2_moment_video_limit))
                   else -> { preview = uri; picked = p } }
        }
    }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) handle(uri) }
    val camera = com.bucks.app.ui.rememberCamera(maxVideoBytes = Social.MAX_VIDEO_BYTES.toLong(), onError = { vm.toast(it) }, onPhoto = { wantVideo = false; handle(it) }, onVideo = { wantVideo = true; handle(it) })
    fun choose(video: Boolean) { wantVideo = video; pick.launch(PickVisualMediaRequest(if (video) ActivityResultContracts.PickVisualMedia.VideoOnly else ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    Column(Modifier.fillMaxSize().background(Color.Black).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) { IconButton(onClose) { Icon(Icons.Rounded.Close, stringResource(R.string.g2_close), tint = Color.White) }; Text(stringResource(R.string.g2_new_moment), color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (picked != null) TextButton({ picked = null; preview = null }) { Text(stringResource(R.string.g2_change), color = Color.White) } }
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val p = picked; val u = preview
            when {
                reading -> Column(horizontalAlignment = Alignment.CenterHorizontally) { BucksLoader(color = Color.White, label = stringResource(R.string.g2_cd_preparing)); Text(stringResource(R.string.g2_preparing), color = Color.White.copy(alpha = .7f), modifier = Modifier.padding(top = 12.dp)) }
                p != null && u != null && p.isVideo -> MomentVideo(u.toString(), paused = false, modifier = Modifier.fillMaxSize(), loop = true)
                p != null && u != null -> AsyncImage(u, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                else -> Column(Modifier.padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(stringResource(R.string.g2_moment_what), color = Color.White, style = MaterialTheme.typography.titleLarge)
                    Text(stringResource(R.string.g2_moment_24h), color = Color.White.copy(alpha = .7f), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        MediaChoice(Icons.Rounded.PhotoCamera, stringResource(R.string.g2_take_photo), stringResource(R.string.g2_use_camera), Modifier.weight(1f)) { camera.takePhoto() }
                        MediaChoice(Icons.Rounded.Videocam, stringResource(R.string.g2_record_video), stringResource(R.string.g2_up_to_30s), Modifier.weight(1f)) { camera.recordVideo() }
                    }
                    Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        MediaChoice(Icons.Rounded.Image, stringResource(R.string.g2_photo), stringResource(R.string.g2_from_gallery), Modifier.weight(1f)) { choose(false) }
                        MediaChoice(Icons.Rounded.Videocam, stringResource(R.string.g2_video), stringResource(R.string.g2_from_gallery_30mb), Modifier.weight(1f)) { choose(true) }
                    }
                }
            }
        }
        if (picked != null) Column(Modifier.padding(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("SYNCED" to stringResource(R.string.g2_synced), "LOCAL" to stringResource(R.string.g2_audience_nearby), "CLOSE" to stringResource(R.string.g2_close_friends)).forEach { (k, l) -> Chip(l, selected = audience == k) { audience = k } } }
            OutlinedTextField(caption, { caption = it.take(200) }, placeholder = { Text(stringResource(R.string.g2_add_caption), color = Color.White.copy(alpha = .6f)) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp), shape = MaterialTheme.shapes.medium, singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White, focusedBorderColor = Color.White, unfocusedBorderColor = Color.White.copy(alpha = .5f), cursorColor = Color.White))
            PrimaryButton(if (social.busy) stringResource(R.string.g2_uploading) else stringResource(R.string.g2_share_24h), Modifier.padding(top = 12.dp), enabled = picked != null && !social.busy) { picked?.let { social.postMoment(it, caption.trim(), audience); onClose() } }
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudMessagesScreen(vm: BucksViewModel, onBack: (() -> Unit)?, onOpen: (String) -> Unit, onSync: () -> Unit, onNewGroup: () -> Unit, onRoute: (String) -> Unit = {}, initialTab: Int = 0) {
    val social = vm.social; var menuFor by remember { mutableStateOf<InboxRow?>(null) }; var leaveFor by remember { mutableStateOf<InboxRow?>(null) }
    var tab by rememberSaveable { mutableIntStateOf(initialTab) }
    val report = com.bucks.app.ui.social.LocalReporter.current
    LaunchedEffect(Unit) { while (true) { social.refreshInbox(); delay(20_000) } }
    val chatUnread = social.inbox.sumOf { it.unread }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(if (tab == 0) R.string.g2_messages else R.string.g2_notifications), onBack = onBack, actions = {
            if (tab == 0) { IconButton(onNewGroup) { Icon(Icons.Rounded.GroupAdd, stringResource(R.string.g2_new_group)) }; IconButton(onSync) { Icon(Icons.Rounded.PersonAddAlt, stringResource(R.string.g2_cd_sync_someone)) } }
            else if (social.notesUnread > 0) IconButton({ social.markAllNotesRead() }) { Icon(Icons.Rounded.Done, stringResource(R.string.g2_cd_mark_all_read)) } })
        // Two tabs in one place: conversations, and everything else that needs me (sync requests, invites, orders, recommendations, documents).
        PrimaryTabRow(selectedTabIndex = tab, containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.g2_messages), style = MaterialTheme.typography.labelLarge); if (chatUnread > 0) { Spacer(Modifier.width(6.dp)); PillPurple("$chatUnread") } } })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.g2_notifications), style = MaterialTheme.typography.labelLarge); if (social.notesUnread > 0) { Spacer(Modifier.width(6.dp)); PillPurple("${social.notesUnread}") } } })
        }
        if (tab == 1) NotificationsList(vm, onRoute) else {
        if (social.inbox.isEmpty()) Column(Modifier.padding(Gutter)) { Muted(stringResource(R.string.g2_inbox_empty))
            SmallButton(stringResource(R.string.g2_new_group), Modifier.padding(top = 12.dp), tonal = true, onClick = onNewGroup) }
        LazyColumn { items(social.inbox.filter { !it.archived }, key = { it.conversationId }) { c ->
            // A listing chat names the customer for the people who run the listing (the server fills other_* only for them); customers see the listing.
            val customerRow = c.kind == "LISTING" && c.otherName != null
            val name = c.otherName ?: c.title ?: stringResource(if (c.kind == "GROUP") R.string.g2_group else R.string.g2_chat)
            ListRow(name, listOfNotNull(if (customerRow) c.title?.let { stringResource(R.string.g2_about, it) } else null, c.lastBody?.take(60), ago(c.lastAt)).joinToString("  ·  "),
                leading = { Box { if (c.kind == "GROUP") Avatar(icon = Icons.Rounded.Group) else Avatar(initials(name)); if (c.kind == "LISTING") Icon(Icons.Rounded.Storefront, null, Modifier.align(Alignment.BottomEnd).size(16.dp), tint = MaterialTheme.colorScheme.primary) } },
                trailing = { Row(verticalAlignment = Alignment.CenterVertically) { if (c.muted) Icon(Icons.Rounded.NotificationsOff, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); if (c.unread > 0) PillPurple("${c.unread}"); IconButton({ menuFor = c }) { Icon(Icons.Rounded.MoreVert, stringResource(R.string.g2_more)) } } },
                onClick = { onOpen(c.conversationId) })
            Divider() } }
        }
    }
    menuFor?.let { c -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text(c.otherName ?: c.title ?: stringResource(R.string.g2_chat)) }, text = { Column {
        TextButton({ social.mute(c.conversationId, !c.muted); menuFor = null }) { Text(stringResource(if (c.muted) R.string.g2_unmute else R.string.g2_mute_notifications)) }
        if (c.kind == "GROUP") TextButton({ leaveFor = c; menuFor = null }) { Text(stringResource(R.string.g2_leave_group), color = MaterialTheme.colorScheme.error) }
        c.otherId?.let { o -> TextButton({ social.block(o); menuFor = null }) { Text(stringResource(R.string.g2_block_name, c.otherName ?: ""), color = MaterialTheme.colorScheme.error) } }
        if (report != null) c.otherId?.let { o -> TextButton({ report(com.bucks.app.ui.social.ReportTarget("PROFILE", o, o, c.otherName ?: "")); menuFor = null }) { Text(stringResource(R.string.g2_report_name, c.otherName ?: ""), color = MaterialTheme.colorScheme.error) } }
    } }, confirmButton = { TextButton({ menuFor = null }) { Text(stringResource(R.string.g2_close)) } }) }
    leaveFor?.let { c -> LeaveGroupDialog(c.title, onConfirm = { social.leaveConversation(c.conversationId); leaveFor = null }, onDismiss = { leaveFor = null }) }
}

@Composable
private fun LeaveGroupDialog(title: String?, onConfirm: () -> Unit, onDismiss: () -> Unit) = AlertDialog(onDismissRequest = onDismiss, title = { Text(if (title != null) stringResource(R.string.g2_leave_named_q, title) else stringResource(R.string.g2_leave_group_q)) },
    text = { Text(stringResource(R.string.g2_leave_group_body)) },
    confirmButton = { TextButton(onConfirm) { Text(stringResource(R.string.g2_leave), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton(onDismiss) { Text(stringResource(R.string.g2_cancel)) } })

/** Pick synced people by name: a search box, then a checklist. Shared by New group and Add people. */
@Composable
private fun PeoplePicker(people: List<ProfileRow>, selected: Set<String>, onToggle: (String) -> Unit, modifier: Modifier = Modifier, emptyText: String) {
    var q by remember { mutableStateOf("") }
    val shown = people.filter { q.isBlank() || it.name.contains(q.trim(), true) || it.area.contains(q.trim(), true) || it.shortCode.contains(q.trim().replace(" ", ""), true) }.sortedBy { it.name.lowercase() }
    Column(modifier) {
        OutlinedTextField(q, { q = it }, placeholder = { Text(stringResource(R.string.g2_search_name_id)) }, leadingIcon = { Icon(Icons.Rounded.Search, null) }, modifier = Modifier.fillMaxWidth().padding(horizontal = Gutter), shape = MaterialTheme.shapes.medium, singleLine = true,
            trailingIcon = { if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, stringResource(R.string.g2_cd_clear)) } })
        if (selected.isNotEmpty()) LazyRow(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(people.filter { it.id in selected }, key = { it.id }) { p -> Chip(p.name.substringBefore(' '), selected = true, icon = Icons.Rounded.Close) { onToggle(p.id) } } }
        when {
            people.isEmpty() -> Muted(emptyText, Modifier.padding(Gutter))
            shown.isEmpty() -> Muted(stringResource(R.string.g2_picker_no_match, q.trim()), Modifier.padding(Gutter))
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
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_new_group), onBack = onBack)
        Column(Modifier.weight(1f)) {
            Column(Modifier.padding(horizontal = Gutter)) {
                BucksField(title, { title = it.take(60) }, label = stringResource(R.string.g2_group_name), placeholder = stringResource(R.string.g2_group_name_hint))
                Label(stringResource(R.string.g2_people)); Muted(stringResource(R.string.g2_group_only_synced), Modifier.padding(bottom = 8.dp))
            }
            PeoplePicker(social.synced, selected, onToggle = { id -> selected = if (id in selected) selected - id else selected + id }, modifier = Modifier.weight(1f),
                emptyText = stringResource(R.string.g2_group_none_synced))
        }
        Column(Modifier.padding(Gutter)) {
            PrimaryButton(when { creating -> stringResource(R.string.g2_creating); selected.isEmpty() -> stringResource(R.string.g2_create_group); else -> pluralStringResource(R.plurals.g2_create_group_with, selected.size, selected.size) }, enabled = title.isNotBlank() && selected.isNotEmpty() && !creating) {
                creating = true; social.createGroup(title, selected.toList(), onCreated = onCreated, onFailed = { creating = false }) }
        }
    }
}

/** Title row for a group or listing chat: the title itself opens the members sheet or the listing. */
@Composable
private fun ChatTopBar(title: String, subtitle: String?, onBack: () -> Unit, onTitle: (() -> Unit)?, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g2_cd_back)) }
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
    var viewing by remember { mutableStateOf<Triple<String, String, String>?>(null) }   // attachment open in the viewer: path, mime, name
    var conv by remember { mutableStateOf<ConversationRow?>(null) }; var members by remember { mutableStateOf<List<ConversationMemberRow>>(emptyList()) }; var showMembers by remember { mutableStateOf(false) }
    val listState = rememberLazyListState(); val meId = social.me?.id
    val reportMsg = com.bucks.app.ui.social.LocalReporter.current
    val inboxRow = social.inbox.firstOrNull { it.conversationId == id }
    // The conversation row is the source of truth for kind and title; the inbox row fills in until it loads (and names the other person in a DM).
    val kind = conv?.kind ?: inboxRow?.kind ?: "DIRECT"
    val listingTitle = conv?.title ?: inboxRow?.title ?: stringResource(R.string.g2_listing)
    // A listing chat is named after the shop or pro; the people who run it see the customer's name instead.
    // Until the members load, the inbox row names the customer (the server fills other_name only for the people who run the listing).
    val customer = if (kind == "LISTING" && members.any { it.profileId == meId && it.role == "ADMIN" }) members.firstOrNull { it.role == "MEMBER" }?.let { social.nameOf(it.profileId) }
        else if (kind == "LISTING" && members.isEmpty()) inboxRow?.otherName else null
    val title = when (kind) { "DIRECT" -> inboxRow?.title ?: stringResource(R.string.g2_chat); "LISTING" -> customer ?: listingTitle; else -> conv?.title ?: inboxRow?.title ?: stringResource(R.string.g2_group) }
    LaunchedEffect(id) { conv = runCatching { social.conversation(id) }.getOrNull(); msgs = runCatching { social.messages(id) }.getOrDefault(emptyList()); social.markRead(id); seen = runCatching { social.seenUpTo(id) }.getOrNull() }
    LaunchedEffect(id, kind) { if (kind != "DIRECT") members = runCatching { social.members(id) }.getOrDefault(emptyList()) }
    DisposableEffect(id) {
        val (channel, flow) = Backend.liveMessages(id)
        val job = scope.launch { runCatching { flow.collect { m -> if (msgs.none { it.id == m.id }) { social.namesFor(listOf(m.senderId)); msgs = msgs + m; if (m.senderId != meId) social.markRead(id) } } } }
        onDispose { job.cancel(); Backend.releaseChannel(channel) }
    }
    LaunchedEffect(msgs.size) { if (msgs.isNotEmpty()) listState.animateScrollToItem(msgs.size - 1) }
    // Photos and videos from the gallery; a file that can't be read (or is over 25 MB) says so instead of doing nothing.
    fun sendPicked(u: Uri) { val f = Upload.read(ctx, u); when { f == null -> vm.toast(Str.get(R.string.g2_chat_file_open_failed)); f.bytes.size > 25 * 1024 * 1024 -> vm.toast(Str.get(R.string.g2_chat_file_limit)); else -> social.sendFile(id, f) } }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { sendPicked(it) } }
    val camera = com.bucks.app.ui.rememberCamera(onError = { vm.toast(it) }, onPhoto = { sendPicked(it) }, onVideo = { sendPicked(it) })
    var cameraMenu by remember { mutableStateOf(false) }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { sendPicked(it) } }
    val listingId = conv?.listingId
    Column(Modifier.fillMaxSize().imePadding()) {
        when (kind) {
            "DIRECT" -> BucksTopBar(title, onBack = onBack)
            "LISTING" -> ChatTopBar(title, when { customer != null -> stringResource(R.string.g2_chat_customer_about, listingTitle); listingId != null -> stringResource(R.string.g2_chat_shop_tap); else -> null }, onBack, onTitle = listingId?.let { l -> { onOpenListing(l) } },
                actions = { if (listingId != null) IconButton({ onOpenListing(listingId) }) { Icon(Icons.Rounded.Storefront, stringResource(R.string.g2_open_listing)) }; IconButton({ showMembers = true }) { Icon(Icons.Rounded.Group, stringResource(R.string.g2_cd_people_in_chat)) } })
            else -> ChatTopBar(title, if (members.isEmpty()) stringResource(R.string.g2_group) else pluralStringResource(R.plurals.g2_members_tap, members.size, members.size), onBack, onTitle = { showMembers = true },
                actions = { IconButton({ showMembers = true }) { Icon(Icons.Rounded.Group, stringResource(R.string.g2_cd_members)) } })
        }
        if (msgs.isEmpty()) Muted(stringResource(when (kind) { "GROUP" -> R.string.g2_chat_empty_group; "LISTING" -> R.string.g2_chat_empty_listing; else -> R.string.g2_chat_empty }), Modifier.padding(Gutter))
        LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp), state = listState, contentPadding = PaddingValues(vertical = 12.dp)) {
            items(msgs, key = { it.id }) { m -> val mine = m.senderId == meId
                Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                    Column(Modifier.widthIn(max = 320.dp).clip(MaterialTheme.shapes.large).background(if (mine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer).combinedClickable(onClick = {}, onLongClickLabel = if (mine) stringResource(R.string.g2_edit_or_delete) else if (reportMsg != null) stringResource(R.string.g2_report) else null, onLongClick = { if (m.deletedAt != null) Unit else if (mine) menuFor = m else reportMsg?.invoke(com.bucks.app.ui.social.ReportTarget("MESSAGE", m.id, m.senderId, social.nameOf(m.senderId))) }).padding(4.dp)) {
                        val fg = if (mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
                        // Groups and listing inboxes have several people on the other side, so every bubble that isn't mine carries its sender.
                        if (!mine && kind != "DIRECT") Text(social.nameOf(m.senderId), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 10.dp, top = 6.dp))
                        m.attachment?.let { a -> val path = a.s("path"); val mime = a.s("mime")
                            // Photos and videos open inside Bucks; documents open with the phone's own viewer. Nothing goes to a browser.
                            if (mime.startsWith("image/")) SignedImage(vm, "chat", path, Modifier.size(220.dp).clip(MaterialTheme.shapes.medium).clickable { viewing = Triple(path, mime, a.s("name")) })
                            else Row(Modifier.clip(MaterialTheme.shapes.medium).background(fg.copy(alpha = .12f)).clickable {
                                if (mime.startsWith("video/")) viewing = Triple(path, mime, a.s("name"))
                                else scope.launch { vm.toast(Str.get(R.string.g2_opening)); if (!com.bucks.app.ui.FileOpener.open(ctx, social, "chat", path, a.s("name"), mime)) vm.toast(Str.get(R.string.g2_file_cant_open)) } }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (mime.startsWith("video/")) Icons.Rounded.Videocam else Icons.Rounded.Description, null, tint = fg); Column(Modifier.padding(start = 10.dp)) { Text(a.s("name"), style = MaterialTheme.typography.titleSmall, color = fg, maxLines = 1); Text(humanSize(a.s("size").toLongOrNull() ?: 0), style = MaterialTheme.typography.labelSmall, color = fg.copy(alpha = .8f)) } } }
                        if (m.deletedAt != null) Text(stringResource(R.string.g2_message_deleted), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Normal), color = fg.copy(alpha = .7f), modifier = Modifier.padding(10.dp, 8.dp))
                        else if (m.body.isNotBlank()) Text(m.body, style = MaterialTheme.typography.bodyMedium, color = fg, modifier = Modifier.padding(10.dp, 8.dp))
                        Text(listOfNotNull(ago(m.createdAt), if (m.editedAt != null) stringResource(R.string.g2_edited) else null).joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = fg.copy(alpha = .7f), modifier = Modifier.padding(start = 10.dp, end = 10.dp, bottom = 6.dp).align(Alignment.End))
                    }
                }
            }
            val lastMine = msgs.lastOrNull { it.senderId == meId }
            if (lastMine != null && seen != null && seen!! >= lastMine.createdAt) item { Text(stringResource(R.string.g2_seen), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.End) }
        }
        if (social.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        editing?.let { e -> Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Muted(stringResource(R.string.g2_editing), Modifier.weight(1f)); IconButton({ editing = null; text = "" }) { Icon(Icons.Rounded.Close, stringResource(R.string.g2_cd_cancel_edit)) } } }
        Surface(tonalElevation = 1.dp) { Row(Modifier.fillMaxWidth().padding(12.dp, 10.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton({ pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }, enabled = !social.busy) { Icon(Icons.Rounded.Image, stringResource(R.string.g2_cd_photo_or_video), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            Box { IconButton({ cameraMenu = true }, enabled = !social.busy) { Icon(Icons.Rounded.PhotoCamera, stringResource(R.string.g2_camera), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                DropdownMenu(cameraMenu, { cameraMenu = false }) { DropdownMenuItem({ Text(stringResource(R.string.g2_take_photo)) }, { cameraMenu = false; camera.takePhoto() }); DropdownMenuItem({ Text(stringResource(R.string.g2_record_video)) }, { cameraMenu = false; camera.recordVideo() }) } }
            IconButton({ pickFile.launch(arrayOf("*/*")) }, enabled = !social.busy) { Icon(Icons.Rounded.AttachFile, stringResource(R.string.g2_cd_file), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            OutlinedTextField(text, { text = it }, placeholder = { Text(stringResource(R.string.g2_message)) }, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.medium, maxLines = 4)
            Spacer(Modifier.width(8.dp))
            FilledIconButton(onClick = { val t = text.trim(); if (t.isEmpty()) return@FilledIconButton
                editing?.let { e -> social.editMessage(e.id, t); msgs = msgs.map { if (it.id == e.id) it.copy(body = t, editedAt = "now") else it }; editing = null } ?: social.send(id, t); text = "" }, enabled = text.isNotBlank()) { Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.g2_cd_send)) }
        } }
    }
    viewing?.let { (path, mime, _) -> com.bucks.app.ui.AttachmentViewer(vm, "chat", path, mime) { viewing = null } }
    menuFor?.let { m -> AlertDialog(onDismissRequest = { menuFor = null }, title = { Text(stringResource(R.string.g2_your_message)) }, text = { Column {
        if (m.body.isNotBlank()) TextButton({ editing = m; text = m.body; menuFor = null }) { Text(stringResource(R.string.g2_edit)) }
        TextButton({ social.deleteMessage(m.id); msgs = msgs.map { if (it.id == m.id) it.copy(body = "", attachment = null, deletedAt = "now") else it }; menuFor = null }) { Text(stringResource(R.string.g2_delete_for_everyone), color = MaterialTheme.colorScheme.error) }
    } }, confirmButton = { TextButton({ menuFor = null }) { Text(stringResource(R.string.g2_close)) } }) }
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
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (group) IconButton({ rename = title }) { Icon(Icons.Rounded.Edit, stringResource(R.string.g2_rename_group)) } }
        Muted(if (group) pluralStringResource(R.plurals.g2_members_synced_only, members.size, members.size) else stringResource(R.string.g2_listing_chat_info), Modifier.padding(bottom = 8.dp))
        if (group) Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SmallButton(stringResource(R.string.g2_add_people), tonal = true) { adding = true }; SmallButton(stringResource(R.string.g2_rename), tonal = true) { rename = title } }
        if (!group && onOpenListing != null) SmallButton(stringResource(R.string.g2_open_listing), Modifier.padding(bottom = 6.dp), tonal = true, onClick = onOpenListing)
        if (members.isEmpty()) Muted(stringResource(R.string.g2_loading_people), Modifier.padding(vertical = 12.dp))
        LazyColumn(Modifier.heightIn(max = 320.dp)) { items(members, key = { it.profileId }) { m -> val name = social.nameOf(m.profileId)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Avatar(initials(name.ifBlank { "?" }), size = 40)
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(if (m.profileId == meId) stringResource(R.string.g2_name_you, name) else name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); if (m.role == "ADMIN") Muted(stringResource(if (group) R.string.g2_admin else R.string.g2_runs_listing)) }
                if (group && iAmAdmin && m.profileId != meId) IconButton({ removeFor = m }) { Icon(Icons.Rounded.PersonRemove, stringResource(R.string.g2_cd_remove_name, name), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }; Divider() } }
        if (group) BadButton(stringResource(R.string.g2_leave_group), Modifier.padding(top = 10.dp)) { leaving = true }
    } }
    rename?.let { r -> AlertDialog(onDismissRequest = { rename = null }, title = { Text(stringResource(R.string.g2_rename_group)) },
        text = { OutlinedTextField(r, { rename = it.take(60) }, placeholder = { Text(stringResource(R.string.g2_group_name)) }, singleLine = true, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { TextButton({ val t = r.trim(); if (t.isNotEmpty()) social.renameGroup(conv, t) { onRenamed(t) }; rename = null }, enabled = r.isNotBlank()) { Text(stringResource(R.string.g2_save)) } }, dismissButton = { TextButton({ rename = null }) { Text(stringResource(R.string.g2_cancel)) } }) }
    removeFor?.let { m -> AlertDialog(onDismissRequest = { removeFor = null }, title = { Text(stringResource(R.string.g2_remove_member_q, social.nameOf(m.profileId))) }, text = { Text(stringResource(R.string.g2_remove_member_body)) },
        confirmButton = { TextButton({ social.removeFromGroup(conv, m.profileId) { onReload() }; removeFor = null }) { Text(stringResource(R.string.g2_remove), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ removeFor = null }) { Text(stringResource(R.string.g2_cancel)) } }) }
    if (leaving) LeaveGroupDialog(title, onConfirm = { leaving = false; social.leaveConversation(conv) { onLeft() } }, onDismiss = { leaving = false })
    if (adding) AddPeopleSheet(vm, conv, already = members.map { it.profileId }.toSet(), onAdded = { adding = false; onReload() }, onDismiss = { adding = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddPeopleSheet(vm: BucksViewModel, conv: String, already: Set<String>, onAdded: () -> Unit, onDismiss: () -> Unit) {
    val social = vm.social; var selected by remember { mutableStateOf<Set<String>>(emptySet()) }; var busy by remember { mutableStateOf(false) }
    val candidates = social.synced.filter { it.id !in already }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(bottom = 24.dp)) {
        Text(stringResource(R.string.g2_add_people), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = Gutter))
        Muted(stringResource(R.string.g2_add_people_info), Modifier.padding(horizontal = Gutter, vertical = 6.dp))
        PeoplePicker(candidates, selected, onToggle = { id -> selected = if (id in selected) selected - id else selected + id }, modifier = Modifier.heightIn(max = 420.dp),
            emptyText = stringResource(if (social.synced.isEmpty()) R.string.g2_add_none_synced else R.string.g2_add_all_in))
        PrimaryButton(if (busy) stringResource(R.string.g2_adding) else if (selected.isEmpty()) stringResource(R.string.g2_add) else pluralStringResource(R.plurals.g2_add_count, selected.size, selected.size), Modifier.padding(Gutter), enabled = selected.isNotEmpty() && !busy) { busy = true; social.addToGroup(conv, selected.toList()) { onAdded() } }
    } }
}
private fun humanSize(b: Long) = when { b >= 1_048_576 -> "%.1f MB".format(b / 1_048_576.0); b >= 1024 -> "${b / 1024} KB"; b > 0 -> "$b B"; else -> "" }


/** A post's photos and video: one fills the width, several scroll sideways. A video shows a play button and streams when tapped. */
@Composable
/** [vote]: the post's arrows, shown in the full-screen viewer so people can recommend a photo or video where they see it. */
fun PostMedia(vm: BucksViewModel, media: kotlinx.serialization.json.JsonArray, modifier: Modifier = Modifier, vote: com.bucks.app.ui.ViewerVote? = null) {
    val items = media.mapNotNull { (it as? JsonObject)?.let { o -> o.s("path").takeIf { p -> p.isNotBlank() }?.let { p -> p to o.s("mime") } } }
    if (items.isEmpty()) return
    val width = if (items.size == 1) Modifier.fillMaxWidth() else Modifier.width(280.dp)
    val scroll = rememberScrollState()
    // Tapping a photo opens all of the post's photos and videos full screen, on that one.
    var open by remember { mutableStateOf<Int?>(null) }
    Row(modifier.padding(top = 10.dp).then(if (items.size > 1) Modifier.horizontalScroll(scroll) else Modifier), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEachIndexed { i, (path, mime) ->
            val shape = Modifier.then(width).height(260.dp).clip(MaterialTheme.shapes.medium)
            if (mime.startsWith("video/") || path.endsWith(".mp4", true)) Box(shape) {
                PostVideo(vm, path, Modifier.fillMaxSize())
                IconButton({ open = i }, Modifier.align(Alignment.TopEnd).padding(4.dp).size(36.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.4f))) {
                    Icon(Icons.Rounded.Fullscreen, stringResource(R.string.g2_cd_full_screen), tint = Color.White) }
            }
            else SignedImage(vm, "posts", path, shape.clickable(onClickLabel = stringResource(R.string.g2_cd_view_full_screen)) { open = i })
        }
    }
    open?.let { i -> com.bucks.app.ui.MediaViewer(vm, com.bucks.app.ui.ViewerMedia.ofPost(media), start = i, vote = vote) { open = null } }
}

@Composable
private fun PostVideo(vm: BucksViewModel, path: String, modifier: Modifier) {
    var playing by remember { mutableStateOf(false) }
    val url by produceState<String?>(null, playing) { if (playing) value = runCatching { vm.social.fileUrl("posts", path) }.getOrNull() }
    Box(modifier.background(Color.Black).clickable { playing = !playing }, contentAlignment = Alignment.Center) {
        val u = url
        if (playing && u != null) MomentVideo(u, paused = false, modifier = Modifier.fillMaxSize(), loop = true)
        else if (playing) BucksLoader(color = Color.White, label = stringResource(R.string.g2_cd_loading))
        else Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, stringResource(R.string.g2_cd_play_video), Modifier.size(40.dp), tint = Color.White) }
            Text(stringResource(R.string.g2_video), color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium)
        }
    }
}


private fun noteIcon(kind: String) = when (kind) {
    "SYNC_REQUEST", "SYNC_ACCEPTED" -> Icons.Rounded.PersonAddAlt
    "INVITE" -> Icons.Rounded.MailOutline
    "ORDER_NEW", "ORDER_UPDATE" -> Icons.Rounded.ShoppingBag
    "RECOMMENDED" -> Icons.Rounded.ArrowUpward
    "LISTING_LIVE" -> Icons.Rounded.Verified
    "LISTING_PAUSED" -> Icons.Rounded.Block
    "DOCUMENT_VERIFIED", "DOCUMENT_REJECTED" -> Icons.Rounded.Description
    "REVIEW" -> Icons.Rounded.SwapVert
    else -> Icons.Rounded.Notifications
}

/** The Notifications tab: newest first, unread in bold with a dot, tap opens the thing it is about, long-press or the x removes it. */
@Composable
private fun NotificationsList(vm: BucksViewModel, onRoute: (String) -> Unit) {
    val social = vm.social; val notes = social.notes
    if (notes.isEmpty()) { Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g2_nothing_new), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g2_notes_empty), Modifier.padding(top = 4.dp)) }; return }
    LazyColumn { items(notes, key = { it.id }) { n ->
        val unread = n.readAt == null
        Row(Modifier.fillMaxWidth().clickable { social.markNoteRead(n.id); n.route?.let(onRoute) }.padding(horizontal = Gutter, vertical = 12.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.size(40.dp).clip(CircleShape).background(if (unread) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                Icon(noteIcon(n.kind), null, Modifier.size(20.dp), tint = if (unread) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant) }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(n.title, style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (unread) FontWeight.SemiBold else FontWeight.Normal))
                if (n.body.isNotBlank()) Muted(n.body, maxLines = 2)
                Muted(ago(n.createdAt), Modifier.padding(top = 2.dp))
            }
            if (unread) Box(Modifier.padding(top = 6.dp).size(10.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
            IconButton({ social.deleteNote(n.id) }, Modifier.size(32.dp)) { Icon(Icons.Rounded.Close, stringResource(R.string.g2_remove), Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Divider()
    } }
}
