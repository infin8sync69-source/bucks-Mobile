package com.bucks.app.ui.screens

import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.manage.CenteredLoading
import kotlinx.coroutines.launch
import com.bucks.app.ui.theme.status
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/* The tabs of my own profile below the composer: Feed (posts), Media, Files and Recommendations. */

private fun JsonObject.text(k: String) = this[k]?.jsonPrimitive?.contentOrNull.orEmpty()
internal fun humanBytes(n: Long) = when { n >= 1_048_576 -> "%.1f MB".format(n / 1_048_576.0); n >= 1024 -> "${n / 1024} KB"; else -> "$n B" }

/** Photos and videos from my posts, three to a row; tap for full size or to play. */
@Composable
fun MyMediaTab(vm: BucksViewModel) {
    val me = vm.social.me ?: return
    var posts by remember { mutableStateOf<List<PostRow>?>(null) }; var failed by remember { mutableStateOf(false) }
    LaunchedEffect(me.id) { posts = runCatching { Backend.myPosts(me.id) }.onFailure { failed = true }.getOrNull() }
    val items = posts.orEmpty().flatMap { p -> p.media.mapNotNull { m -> (m as? JsonObject)?.let { o -> o.text("path").takeIf { it.isNotBlank() }?.let { path -> path to o.text("mime") } } } }
    var open by remember { mutableStateOf<Int?>(null) }
    when {
        posts == null && !failed -> CenteredLoading()
        failed -> Muted(stringResource(R.string.g5_media_load_failed), Modifier.padding(Gutter))
        items.isEmpty() -> Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g5_media_empty_title), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g5_media_empty), Modifier.padding(top = 4.dp)) }
        else -> Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { (path, mime) ->
                        val video = mime.startsWith("video/") || path.endsWith(".mp4", true)
                        Box(Modifier.weight(1f).aspectRatio(1f).clip(MaterialTheme.shapes.small).clickable { open = items.indexOf(path to mime) }, contentAlignment = Alignment.Center) {
                            if (video) { Box(Modifier.fillMaxSize().background(Color.Black)); Icon(Icons.Rounded.PlayArrow, stringResource(R.string.g5_cd_video), Modifier.size(36.dp), tint = Color.White) }
                            else SignedImage(vm, "posts", path, Modifier.fillMaxSize())
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
    // All my post photos and videos in one swipeable viewer, opened on the one tapped.
    open?.let { i -> com.bucks.app.ui.MediaViewer(vm, items.map { (path, mime) -> com.bucks.app.ui.ViewerMedia.Stored("posts", path, if (mime.startsWith("video/") || path.endsWith(".mp4", true)) "video/mp4" else mime.ifBlank { "image/jpeg" }) }, start = i) { open = null } }
}

/** Files and photos shared in my chats, sent or received; tap opens it. */
@Composable
fun MyFilesTab(vm: BucksViewModel) {
    val ctx = LocalContext.current; val social = vm.social; val scope = rememberCoroutineScope()
    var viewing by remember { mutableStateOf<Triple<String, String, String>?>(null) }
    viewing?.let { (path, mime, _) -> com.bucks.app.ui.AttachmentViewer(vm, "chat", path, mime) { viewing = null } }
    var files by remember { mutableStateOf<List<MessageRow>?>(null) }; var failed by remember { mutableStateOf(false) }
    val openingMsg = stringResource(R.string.g5_opening); val cantOpenMsg = stringResource(R.string.g5_cant_open_file)
    LaunchedEffect(social.me?.id) { val rows = runCatching { Backend.chatFiles() }.onFailure { failed = true }.getOrNull(); rows?.let { social.namesFor(it.map { m -> m.senderId }) }; files = rows }
    when {
        files == null && !failed -> CenteredLoading()
        failed -> Muted(stringResource(R.string.g5_files_load_failed), Modifier.padding(Gutter))
        files.orEmpty().isEmpty() -> Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g5_files_empty_title), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g5_files_empty), Modifier.padding(top = 4.dp)) }
        else -> Column {
            files.orEmpty().forEach { m ->
                val a = m.attachment ?: return@forEach; val path = a.text("path"); val mime = a.text("mime"); val name = a.text("name").ifBlank { stringResource(R.string.g5_file) }; val size = a["size"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
                val mine = m.senderId == social.me?.id
                ListRow(name, listOfNotNull(if (size > 0) humanBytes(size) else null, if (mine) stringResource(R.string.g5_sent_by_you) else stringResource(R.string.g5_from_name, social.nameOf(m.senderId)), ago(m.createdAt)).joinToString(" · "),
                    leading = { Avatar(icon = when { mime.startsWith("image/") -> Icons.Rounded.Image; mime.startsWith("video/") -> Icons.Rounded.Videocam; mime == "application/pdf" -> Icons.Rounded.PictureAsPdf; else -> Icons.Rounded.InsertDriveFile }, size = 40) },
                    onClick = { if (mime.startsWith("image/") || mime.startsWith("video/")) viewing = Triple(path, mime, name)
                                else scope.launch { vm.toast(openingMsg); if (!com.bucks.app.ui.FileOpener.open(ctx, social, "chat", path, name, mime)) vm.toast(cantOpenMsg) } })
                Divider()
            }
        }
    }
}

/** Recommendations: locals I recommended, reviews I gave, and how many people recommended my own listings. */
@Composable
fun MyRecommendationsTab(vm: BucksViewModel, onOpen: (String) -> Unit) {
    val me = vm.social.me ?: return
    var given by remember { mutableStateOf<List<Pair<RecGiven, ListingRow?>>?>(null) }; var reviews by remember { mutableStateOf<List<Pair<ReviewRow, ListingRow?>>?>(null) }; var failed by remember { mutableStateOf(false) }
    LaunchedEffect(me.id) {
        given = runCatching { Backend.recommendationsIGave(me.id) }.onFailure { failed = true }.getOrNull()
        reviews = runCatching { Backend.reviewsIWrote(me.id) }.getOrNull()
    }
    val st = MaterialTheme.status
    Column(Modifier.padding(bottom = 12.dp)) {
        // Personal only: who recommends my pages is shown on each page's Pro dashboard, not here.
        SectionTitle(stringResource(R.string.g5_recs_given), Modifier.padding(start = Gutter, end = Gutter, top = 14.dp, bottom = 4.dp))
        when {
            given == null && !failed -> CenteredLoading()
            failed -> Muted(stringResource(R.string.g5_recs_load_failed), Modifier.padding(horizontal = Gutter))
            given.orEmpty().isEmpty() -> Muted(stringResource(R.string.g5_recs_empty), Modifier.padding(horizontal = Gutter))
            else -> given.orEmpty().forEach { (r, l) -> ListRow(l?.title ?: stringResource(R.string.g5_a_listing), listOfNotNull(l?.category?.ifBlank { null }, l?.area?.ifBlank { null }, ago(r.createdAt)).joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.Verified, size = 40) },
                onClick = l?.let { x -> { onOpen(Routes.listing(x.id)) } }); Divider() }
        }
        SectionTitle(stringResource(R.string.g5_reviews_given), Modifier.padding(start = Gutter, end = Gutter, top = 18.dp, bottom = 4.dp))
        val rv = reviews
        when {
            rv == null -> {}
            rv.isEmpty() -> Muted(stringResource(R.string.g5_reviews_empty), Modifier.padding(horizontal = Gutter))
            else -> rv.forEach { (r, l) -> ListRow(l?.title ?: stringResource(R.string.g5_a_listing), listOfNotNull(r.comment.take(70), ago(r.createdAt)).joinToString(" · "),
                leading = { Icon(if (r.vote > 0) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, stringResource(if (r.vote > 0) R.string.g5_cd_recommended else R.string.g5_cd_not_recommended), tint = if (r.vote > 0) st.good else st.bad, modifier = Modifier.padding(8.dp)) },
                onClick = l?.let { x -> { onOpen(Routes.listing(x.id)) } }); Divider() }
        }
    }
}
