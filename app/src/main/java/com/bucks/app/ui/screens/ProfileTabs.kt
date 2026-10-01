package com.bucks.app.ui.screens

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
    var open by remember { mutableStateOf<Pair<String, String>?>(null) }
    when {
        posts == null && !failed -> CenteredLoading()
        failed -> Muted("Couldn't load your media. Check your connection and open this tab again.", Modifier.padding(Gutter))
        items.isEmpty() -> Column(Modifier.padding(Gutter)) { Text("No photos or videos yet", style = MaterialTheme.typography.titleMedium); Muted("Photos and videos you add to posts collect here.", Modifier.padding(top = 4.dp)) }
        else -> Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { (path, mime) ->
                        val video = mime.startsWith("video/") || path.endsWith(".mp4", true)
                        Box(Modifier.weight(1f).aspectRatio(1f).clip(MaterialTheme.shapes.small).clickable { open = path to (if (video) "video/mp4" else "image/jpeg") }, contentAlignment = Alignment.Center) {
                            if (video) { Box(Modifier.fillMaxSize().background(Color.Black)); Icon(Icons.Rounded.PlayArrow, "Video", Modifier.size(36.dp), tint = Color.White) }
                            else SignedImage(vm, "posts", path, Modifier.fillMaxSize())
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
    open?.let { (path, mime) -> com.bucks.app.ui.AttachmentViewer(vm, "posts", path, mime) { open = null } }
}

/** Files and photos shared in my chats, sent or received; tap opens it. */
@Composable
fun MyFilesTab(vm: BucksViewModel) {
    val ctx = LocalContext.current; val social = vm.social; val scope = rememberCoroutineScope()
    var viewing by remember { mutableStateOf<Triple<String, String, String>?>(null) }
    viewing?.let { (path, mime, _) -> com.bucks.app.ui.AttachmentViewer(vm, "chat", path, mime) { viewing = null } }
    var files by remember { mutableStateOf<List<MessageRow>?>(null) }; var failed by remember { mutableStateOf(false) }
    LaunchedEffect(social.me?.id) { val rows = runCatching { Backend.chatFiles() }.onFailure { failed = true }.getOrNull(); rows?.let { social.namesFor(it.map { m -> m.senderId }) }; files = rows }
    when {
        files == null && !failed -> CenteredLoading()
        failed -> Muted("Couldn't load your files. Check your connection and open this tab again.", Modifier.padding(Gutter))
        files.orEmpty().isEmpty() -> Column(Modifier.padding(Gutter)) { Text("No files yet", style = MaterialTheme.typography.titleMedium); Muted("Photos, videos and documents you send or receive in chats collect here.", Modifier.padding(top = 4.dp)) }
        else -> Column {
            files.orEmpty().forEach { m ->
                val a = m.attachment ?: return@forEach; val path = a.text("path"); val mime = a.text("mime"); val name = a.text("name").ifBlank { "File" }; val size = a["size"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
                val mine = m.senderId == social.me?.id
                ListRow(name, listOfNotNull(if (size > 0) humanBytes(size) else null, if (mine) "Sent by you" else "From ${social.nameOf(m.senderId)}", ago(m.createdAt)).joinToString(" · "),
                    leading = { Avatar(icon = when { mime.startsWith("image/") -> Icons.Rounded.Image; mime.startsWith("video/") -> Icons.Rounded.Videocam; mime == "application/pdf" -> Icons.Rounded.PictureAsPdf; else -> Icons.Rounded.InsertDriveFile }, size = 40) },
                    onClick = { if (mime.startsWith("image/") || mime.startsWith("video/")) viewing = Triple(path, mime, name)
                                else scope.launch { vm.toast("Opening…"); if (!com.bucks.app.ui.FileOpener.open(ctx, social, "chat", path, name, mime)) vm.toast("No app on this phone can open that file, or the download failed.") } })
                Divider()
            }
        }
    }
}

/** Recommendations: locals I recommended, reviews I gave, and how many people recommended my own listings. */
@Composable
fun MyRecommendationsTab(vm: BucksViewModel, onOpen: (String) -> Unit) {
    val me = vm.social.me ?: return; val m = vm.myListings
    var given by remember { mutableStateOf<List<Pair<RecGiven, ListingRow?>>?>(null) }; var reviews by remember { mutableStateOf<List<Pair<ReviewRow, ListingRow?>>?>(null) }; var failed by remember { mutableStateOf(false) }
    LaunchedEffect(me.id) {
        given = runCatching { Backend.recommendationsIGave(me.id) }.onFailure { failed = true }.getOrNull()
        reviews = runCatching { Backend.reviewsIWrote(me.id) }.getOrNull()
        if (!m.loaded) m.refresh(); m.listings.forEach { m.loadCounts(it.id) }
    }
    val st = MaterialTheme.status
    Column(Modifier.padding(bottom = 12.dp)) {
        SectionTitle("For my listings", Modifier.padding(start = Gutter, end = Gutter, top = 14.dp, bottom = 4.dp))
        if (m.listings.isEmpty()) Muted("When you list a business, skill or asset, the people who recommend it show here.", Modifier.padding(horizontal = Gutter))
        m.listings.forEach { l -> val n = m.counts[l.id]?.recommendations ?: m.recommendations[l.id]
            ListRow(l.title, listOfNotNull(if (n != null) "$n ${if (n == 1) "person" else "people"} recommended" else null, if (l.status == "LIVE") "Live" else "Not live yet").joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.ThumbUp, size = 40) },
                trailing = { TrustBadge(Trust(l.trustUp, l.trustDown), compact = true) }, onClick = { onOpen(Routes.studioListing(l.id)) }); Divider() }
        SectionTitle("Locals I recommended", Modifier.padding(start = Gutter, end = Gutter, top = 18.dp, bottom = 4.dp))
        when {
            given == null && !failed -> CenteredLoading()
            failed -> Muted("Couldn't load your recommendations. Open this tab again.", Modifier.padding(horizontal = Gutter))
            given.orEmpty().isEmpty() -> Muted("Scan someone's code in person (Menu > Recommend a local) to vouch for a shop, skill or driver you know.", Modifier.padding(horizontal = Gutter))
            else -> given.orEmpty().forEach { (r, l) -> ListRow(l?.title ?: "A listing", listOfNotNull(l?.category?.ifBlank { null }, l?.area?.ifBlank { null }, ago(r.createdAt)).joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.Verified, size = 40) },
                onClick = l?.let { x -> { onOpen(Routes.listing(x.id)) } }); Divider() }
        }
        SectionTitle("Reviews I gave", Modifier.padding(start = Gutter, end = Gutter, top = 18.dp, bottom = 4.dp))
        val rv = reviews
        when {
            rv == null -> {}
            rv.isEmpty() -> Muted("After an order, visit or trip you can review it from its page.", Modifier.padding(horizontal = Gutter))
            else -> rv.forEach { (r, l) -> ListRow(l?.title ?: "A listing", listOfNotNull(r.comment.take(70), ago(r.createdAt)).joinToString(" · "),
                leading = { Icon(if (r.vote > 0) Icons.Rounded.ThumbUp else Icons.Rounded.ArrowDownward, if (r.vote > 0) "Recommended" else "Not recommended", tint = if (r.vote > 0) st.good else st.bad, modifier = Modifier.padding(8.dp)) },
                onClick = l?.let { x -> { onOpen(Routes.listing(x.id)) } }); Divider() }
        }
    }
}
