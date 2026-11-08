package com.bucks.app.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import coil.compose.AsyncImage
import com.bucks.app.ui.components.BucksLoader
import com.bucks.app.ui.screens.MomentVideo
import kotlinx.coroutines.launch

/** One photo or video the full-screen viewer can show. */
sealed interface ViewerMedia {
    val mime: String
    val caption: String
    val isVideo: Boolean get() = mime.startsWith("video/")

    /** A public link: profile pictures, cover photos, page galleries and product photos. */
    data class Url(val url: String, override val mime: String = "image/jpeg", override val caption: String = "") : ViewerMedia

    /** A file in a private bucket (posts, chat), opened through a short-lived signed link. */
    data class Stored(val bucket: String, val path: String, override val mime: String, override val caption: String = "") : ViewerMedia

    companion object {
        /** Post media as stored on posts.media: [{path, mime}] in the private posts bucket. */
        fun ofPost(media: kotlinx.serialization.json.JsonArray): List<ViewerMedia> = media.mapNotNull { e ->
            val o = e as? kotlinx.serialization.json.JsonObject ?: return@mapNotNull null
            val path = (o["path"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val mime = (o["mime"] as? kotlinx.serialization.json.JsonPrimitive)?.content.orEmpty()
            Stored("posts", path, if (mime.startsWith("video/") || path.endsWith(".mp4", true)) "video/mp4" else mime.ifBlank { "image/jpeg" })
        }
    }
}

/**
 * A post's arrows, for the viewer of that post's photos and videos. A vote here is a vote on the post: the same one as the
 * arrows under it in the feed. [canVote] is false on my own posts (the server refuses those, can_vote_post); the counts still show.
 * [onVote] follows the feed's rule: the arrow I already chose takes my vote back.
 */
class ViewerVote(val up: Int, val down: Int, val my: Int, val canVote: Boolean, val onVote: (Int) -> Unit)

/** The link to load [item] from: the public URL as is, a private file's signed URL once it has been fetched (null until then). */
@Composable
private fun rememberMediaUrl(vm: BucksViewModel, item: ViewerMedia): String? = when (item) {
    is ViewerMedia.Url -> item.url
    is ViewerMedia.Stored -> produceState<String?>(null, item) { value = runCatching { vm.social.fileUrl(item.bucket, item.path) }.getOrNull() }.value
}

/**
 * Full-screen photos and videos: swipe between [items], pinch or double-tap to zoom, drag to look around a zoomed photo, tap to hide
 * the bars. Videos play while on screen. Save puts the file in the phone's gallery, Share opens the share sheet. Nothing leaves the app
 * for a browser.
 */
@Composable
fun MediaViewer(vm: BucksViewModel, items: List<ViewerMedia>, start: Int = 0, title: String? = null, vote: ViewerVote? = null, onClose: () -> Unit) {
    if (items.isEmpty()) { LaunchedEffect(Unit) { onClose() }; return }
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val pager = rememberPagerState(initialPage = start.coerceIn(0, items.lastIndex)) { items.size }
    var zoomed by remember { mutableStateOf(false) }
    var chrome by remember { mutableStateOf(true) }
    LaunchedEffect(pager.currentPage) { zoomed = false }
    val current = items[pager.currentPage.coerceIn(0, items.lastIndex)]

    val save: () -> Unit = {
        scope.launch {
            val ok = when (current) {
                is ViewerMedia.Stored -> MediaSaver.save(ctx, vm.social, current.bucket, current.path, current.mime)
                is ViewerMedia.Url -> MediaSaver.saveUrl(ctx, current.url, current.mime)
            }
            vm.toast(if (ok) "Saved to your gallery, in the Bucks album." else "Couldn't save. Check your connection and try again.")
        }
    }
    val askStorage = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> if (ok) save() else vm.toast("Allow storage access to save to your gallery.") }
    val share: () -> Unit = {
        scope.launch {
            val ok = when (current) {
                is ViewerMedia.Stored -> FileOpener.share(ctx, vm.social, current.bucket, current.path, current.mime)
                is ViewerMedia.Url -> FileOpener.shareUrl(ctx, current.url, current.mime)
            }
            if (!ok) vm.toast("Couldn't share that. Check your connection.")
        }
    }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(pager, Modifier.fillMaxSize(), userScrollEnabled = !zoomed, beyondViewportPageCount = 1) { page ->
                val item = items[page]; val onScreen = pager.currentPage == page
                if (item.isVideo) ViewerVideo(vm, item, playing = onScreen, onTap = { chrome = !chrome })
                else ZoomableImage(vm, item, active = onScreen, onZoomed = { if (onScreen) zoomed = it }, onTap = { chrome = !chrome })
            }
            AnimatedVisibility(chrome, Modifier.align(Alignment.TopCenter), enter = fadeIn(), exit = fadeOut()) {
                Row(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.6f), Color.Transparent))).statusBarsPadding().padding(4.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClose) { Icon(Icons.Rounded.Close, "Close", tint = Color.White) }
                    Column(Modifier.weight(1f)) {
                        title?.let { Text(it, color = Color.White, style = MaterialTheme.typography.titleSmall, maxLines = 1) }
                        if (items.size > 1) Text("${pager.currentPage + 1} of ${items.size}", color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium)
                    }
                    IconButton({ if (Build.VERSION.SDK_INT < 29 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) askStorage.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE) else save() }) {
                        Icon(Icons.Rounded.Download, "Save to gallery", tint = Color.White) }
                    IconButton(share) { Icon(Icons.Rounded.Share, "Share", tint = Color.White) }
                }
            }
            if (current.caption.isNotBlank() || vote != null) AnimatedVisibility(chrome, Modifier.align(Alignment.BottomCenter), enter = fadeIn(), exit = fadeOut()) {
                Column(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))).navigationBarsPadding().padding(16.dp)) {
                    if (current.caption.isNotBlank()) Text(current.caption, color = Color.White, style = MaterialTheme.typography.bodyMedium)
                    vote?.let { ViewerVoteBar(it, Modifier.padding(top = if (current.caption.isNotBlank()) 12.dp else 0.dp)) }
                }
            }
        }
    }
}

/**
 * A photo that zooms between 1x and 5x. One finger at 1x is left to the pager (swipe to the next photo); two fingers, or any drag once
 * zoomed in, pans and zooms the photo instead, kept inside its edges. Double-tap toggles 2.5x.
 */
@Composable
private fun ZoomableImage(vm: BucksViewModel, item: ViewerMedia, active: Boolean, onZoomed: (Boolean) -> Unit, onTap: () -> Unit) {
    val url = rememberMediaUrl(vm, item)
    var scale by remember { mutableFloatStateOf(1f) }; var offset by remember { mutableStateOf(Offset.Zero) }; var size by remember { mutableStateOf(IntSize.Zero) }
    fun clamp(o: Offset, s: Float): Offset { val mx = size.width * (s - 1f) / 2f; val my = size.height * (s - 1f) / 2f; return Offset(o.x.coerceIn(-mx, mx), o.y.coerceIn(-my, my)) }
    fun set(s: Float, o: Offset) { scale = s; offset = if (s <= 1f) Offset.Zero else clamp(o, s); onZoomed(scale > 1f) }
    LaunchedEffect(active) { if (!active) { scale = 1f; offset = Offset.Zero } }
    Box(Modifier.fillMaxSize().onSizeChanged { size = it }
        .pointerInput(Unit) { detectTapGestures(onTap = { onTap() }, onDoubleTap = { if (scale > 1f) set(1f, Offset.Zero) else set(2.5f, Offset.Zero) }) }
        .pointerInput(Unit) {
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false)
                do {
                    val event = awaitPointerEvent()
                    if (event.changes.size > 1 || scale > 1f) {
                        set((scale * event.calculateZoom()).coerceIn(1f, 5f), offset + event.calculatePan())
                        event.changes.forEach { if (it.positionChanged()) it.consume() }
                    }
                } while (event.changes.any { it.pressed })
            }
        }, contentAlignment = Alignment.Center) {
        if (url == null) BucksLoader(color = Color.White, label = "Loading")
        else AsyncImage(url, item.caption.ifBlank { null }, Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y }, contentScale = ContentScale.Fit)
    }
}

/** A video that plays while its page is on screen and pauses when swiped away. Tapping shows or hides the bars. */
@Composable
private fun ViewerVideo(vm: BucksViewModel, item: ViewerMedia, playing: Boolean, onTap: () -> Unit) {
    val url = rememberMediaUrl(vm, item)
    Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures(onTap = { onTap() }) }, contentAlignment = Alignment.Center) {
        if (url == null) BucksLoader(color = Color.White, label = "Loading")
        else MomentVideo(url, paused = !playing, modifier = Modifier.fillMaxSize(), loop = true)
    }
}

/**
 * ↑ and ↓ under a post's photo or video, on the dark viewer. Same rules as the feed: arrows only, never thumbs; only the larger side
 * carries its number (ties show the ↑ count); the arrow I chose is filled with its colour.
 */
@Composable
private fun ViewerVoteBar(v: ViewerVote, modifier: Modifier = Modifier) {
    val st = com.bucks.app.ui.theme.LocalStatus.current
    val upWins = v.up >= v.down
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ViewerArrow(up = true, on = v.my == 1, count = if (upWins && v.up > 0) v.up else null, color = st.good, enabled = v.canVote) { v.onVote(1) }
        ViewerArrow(up = false, on = v.my == -1, count = if (!upWins) v.down else null, color = st.bad, enabled = v.canVote) { v.onVote(-1) }
        if (!v.canVote) Text("Your post", color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun ViewerArrow(up: Boolean, on: Boolean, count: Int?, color: Color, enabled: Boolean, onClick: () -> Unit) {
    val label = when { !enabled -> if (up) "Recommended" else "Not recommended"; on -> "Take back my vote"; up -> "Recommend"; else -> "Not recommend" }
    val tint = if (on) color else Color.White
    Row(Modifier.heightIn(min = 48.dp).clip(androidx.compose.foundation.shape.CircleShape)
        .background(if (on) color.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.12f))
        .then(if (enabled) Modifier.clickable(onClickLabel = label, role = androidx.compose.ui.semantics.Role.Button, onClick = onClick) else Modifier)
        .padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (up) androidx.compose.material.icons.Icons.Rounded.ArrowUpward else androidx.compose.material.icons.Icons.Rounded.ArrowDownward, label, Modifier.size(22.dp), tint = tint)
        count?.let { Text(" $it", color = tint, style = MaterialTheme.typography.labelLarge) }
    }
}
