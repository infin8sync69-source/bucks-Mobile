package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.R
import com.bucks.app.data.Backend
import com.bucks.app.data.ExploreBackend
import com.bucks.app.data.FeedRow
import com.bucks.app.data.ForYouItem
import com.bucks.app.data.Str
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.FileOpener
import com.bucks.app.ui.MediaViewer
import com.bucks.app.ui.ViewerMedia
import com.bucks.app.ui.ViewerVote
import com.bucks.app.ui.components.*
import com.bucks.app.ui.social.CommentsSheet
import com.bucks.app.ui.social.LocalOpenPerson
import com.bucks.app.ui.social.SocialPostCard
import com.bucks.app.ui.social.VotePill
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/*
 * Explore (the tab that was "For you"): a search bar, a row of pills, and a page per pill.
 *   All       the rich default: what the people I'm synced with recommend comes first, each with "Asha and 22 others recommended",
 *             then public posts; shops and products they recommend ride in a row at the top.
 *   Videos    only videos, laid out like a video site's home page: a wide thumbnail, then title, author and votes.
 *   Images    only photos, as a grid.
 *   Files     only documents, as a list.
 *   Places, Products   what my synced people recommend.
 * Anything opened goes full screen in one viewer that swipes (or steps, with the side arrows) to the next and previous piece of
 * content of that page. Arrows vote with one tap everywhere; the small box under a post takes a comment.
 */

/** One photo, video or document of a post. [poster]: the still frame saved beside a video when it was posted (null on older posts). */
private class PostMediaItem(val path: String, val mime: String, val poster: String?) {
    val isVideo get() = mime.startsWith("video/") || path.endsWith(".mp4", true)
    val isImage get() = !isVideo && (mime.startsWith("image/") || mime.isBlank())
    val isFile get() = !isVideo && !isImage
    val viewer get() = ViewerMedia.Stored("posts", path, if (isVideo) "video/mp4" else mime.ifBlank { "image/jpeg" })
}
private fun FeedRow.mediaItems(): List<PostMediaItem> = media.mapNotNull { e ->
    val o = e as? JsonObject ?: return@mapNotNull null
    val path = o["path"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
    PostMediaItem(path, o["mime"]?.jsonPrimitive?.contentOrNull.orEmpty(), o["poster"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() })
}
/** A piece of content in the viewer's order: the post it belongs to, which of the post's media it is, and the media. */
private class Flat(val post: FeedRow, val index: Int, val item: PostMediaItem)
private fun FeedRow.matches(kind: String) = when (kind) { "VIDEO" -> mediaItems().any { it.isVideo }; "IMAGE" -> mediaItems().any { it.isImage }; "FILE" -> mediaItems().any { it.isFile }; else -> true }
private fun FeedRow.headline(fallback: String) = body.lineSequence().firstOrNull { it.isNotBlank() }?.trim()?.take(120) ?: fallback

@Composable
fun ExploreScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onListing: (String) -> Unit, onFindPeople: () -> Unit) {
    val social = vm.social; val scope = rememberCoroutineScope(); val ctx = LocalContext.current; val focus = LocalFocusManager.current; val openPerson = LocalOpenPerson.current
    var kind by rememberSaveable { mutableStateOf("ALL") }; var q by rememberSaveable { mutableStateOf("") }
    var rows by remember { mutableStateOf<List<FeedRow>?>(null) }; var loading by remember { mutableStateOf(false) }
    var places by remember { mutableStateOf<List<ForYouItem>>(emptyList()) }
    var comments by remember { mutableStateOf<String?>(null) }; var viewing by remember { mutableStateOf<Int?>(null) }
    val postKind = if (kind == "VIDEO" || kind == "IMAGE" || kind == "FILE") kind else "ALL"
    // Posts for the chosen pill and the typed words, after a short pause while typing. The old list stays up until the new one arrives.
    LaunchedEffect(social.me?.id, postKind, q) {
        if (social.me == null) return@LaunchedEffect
        if (q.isNotBlank()) delay(350)
        loading = true
        val got = runCatching { ExploreBackend.posts(postKind, q, social.here, social.me?.id) }.getOrDefault(emptyList()).filter { it.matches(postKind) }
        rows = got; loading = false; viewing = null
        runCatching { social.namesFor(got.map { it.authorId }) }
    }
    LaunchedEffect(social.me?.id) { if (social.me != null) places = runCatching { ExploreBackend.places() }.getOrDefault(emptyList()) }
    fun vote(p: FeedRow, v: Int) { val me = social.me?.id ?: return
        val cur = rows?.firstOrNull { it.id == p.id } ?: return; val prev = cur.myVote ?: 0; val next = if (prev == v) 0 else v
        // The arrow answers at once; the server call follows, and a failure puts the numbers back.
        fun shift(from: Int, to: Int) { rows = rows?.map { if (it.id != p.id) it else it.copy(myVote = to.takeIf { n -> n != 0 }, up = it.up - (if (from == 1) 1 else 0) + (if (to == 1) 1 else 0), down = it.down - (if (from == -1) 1 else 0) + (if (to == -1) 1 else 0)) } }
        shift(prev, next)
        scope.launch { runCatching { Backend.vote(p.id, me, next) }.onFailure { shift(next, prev); vm.toast(Str.get(R.string.g5_something_wrong)) } } }

    val list = rows.orEmpty()
    // Everything the viewer can step through on this page: the page's kind of media, in the order the page shows it.
    val flat = list.flatMap { p -> p.mediaItems().mapIndexed { i, m -> Flat(p, i, m) } }.filter { when (kind) { "VIDEO" -> it.item.isVideo; "IMAGE" -> it.item.isImage; else -> it.item.isVideo || it.item.isImage } }
    fun openMedia(p: FeedRow, index: Int) { flat.indexOfFirst { it.post.id == p.id && it.index == index }.takeIf { it >= 0 }?.let { viewing = it } }
    val placeKind = when (kind) { "PLACES" -> "LISTING"; "PRODUCTS" -> "PRODUCT"; else -> null }
    val shownPlaces = places.filter { (placeKind == null || it.kind == placeKind) && (q.isBlank() || it.title.contains(q.trim(), true) || it.subtitle.contains(q.trim(), true)) }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g3_foryou_title), onMenu = onMenu, unread = social.unread, onChat = onMessages)
        OutlinedTextField(q, { q = it.take(60) }, Modifier.fillMaxWidth().padding(horizontal = Gutter).padding(bottom = 4.dp), placeholder = { Text(stringResource(R.string.r1_explore_search_hint)) },
            leadingIcon = { Icon(Icons.Rounded.Search, null) }, trailingIcon = { if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, stringResource(R.string.g3_cd_clear)) } },
            singleLine = true, shape = MaterialTheme.shapes.extraLarge, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }))
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(Triple("ALL", stringResource(R.string.g3_foryou_all), Icons.Rounded.AutoAwesome), Triple("VIDEO", stringResource(R.string.r1_explore_videos), Icons.Rounded.PlayCircleOutline),
                Triple("IMAGE", stringResource(R.string.r1_explore_images), Icons.Rounded.Image), Triple("FILE", stringResource(R.string.r1_explore_files), Icons.Rounded.Description),
                Triple("PLACES", stringResource(R.string.g3_foryou_places), Icons.Rounded.Storefront), Triple("PRODUCTS", stringResource(R.string.g3_foryou_products), Icons.Rounded.ShoppingBag))
                .forEach { (k, label, icon) -> Chip(label, selected = kind == k, icon = icon) { kind = k; com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.EXPLORE_FILTER, "kind" to k) } }
        }
        if (loading && placeKind == null) LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Gutter).height(2.dp)) else Spacer(Modifier.height(2.dp))
        val empty: @Composable (String) -> Unit = { what -> ExploreEmpty(if (q.isNotBlank()) stringResource(R.string.r1_explore_no_results, q.trim()) else what, searching = q.isNotBlank(), onFindPeople = onFindPeople) }
        when {
            placeKind != null -> if (shownPlaces.isEmpty()) empty(stringResource(if (kind == "PLACES") R.string.r1_explore_no_places else R.string.r1_explore_no_products))
                else LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp)) { items(shownPlaces, key = { it.kind + it.id }) { r -> PlaceRow(r) { r.listingId?.let(onListing) } } }
            rows == null -> Spacer(Modifier.height(1.dp))
            kind == "VIDEO" -> if (flat.isEmpty()) empty(stringResource(R.string.r1_explore_no_videos))
                else LazyColumn(contentPadding = PaddingValues(top = 10.dp, bottom = 24.dp)) {
                    items(flat.size, key = { flat[it].item.path }) { i -> val f = flat[i]
                        VideoCard(vm, f.post, f.item, onOpen = { viewing = i }, onVote = { vote(f.post, it) }, onPerson = { openPerson(f.post.authorId) }, onComments = { comments = f.post.id }) } }
            kind == "IMAGE" -> if (flat.isEmpty()) empty(stringResource(R.string.r1_explore_no_images))
                else LazyVerticalGrid(GridCells.Fixed(3), contentPadding = PaddingValues(start = 2.dp, end = 2.dp, top = 8.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    itemsIndexed(flat, key = { _, f -> f.item.path }) { i, f ->
                        Box(Modifier.aspectRatio(1f).clickable(onClickLabel = stringResource(R.string.g2_cd_view_full_screen)) { viewing = i }) {
                            SignedImage(vm, "posts", f.item.path, Modifier.fillMaxSize())
                            if (f.post.recommenders > 0) Row(Modifier.align(Alignment.BottomStart).padding(4.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 6.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(11.dp), tint = Color.White); Text(" ${f.post.recommenders}", color = Color.White, style = MaterialTheme.typography.labelSmall) }
                        } } }
            kind == "FILE" -> { val files = list.flatMap { p -> p.mediaItems().filter { it.isFile }.map { p to it } }
                if (files.isEmpty()) empty(stringResource(R.string.r1_explore_no_files))
                else LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp)) { items(files, key = { it.second.path }) { (p, m) ->
                    val ext = m.path.substringAfterLast('.', "").uppercase().take(5); val name = p.headline(stringResource(R.string.r1_explore_file_by, p.listingTitle ?: p.authorName))
                    val opening = stringResource(R.string.g5_opening); val cantOpen = stringResource(R.string.g5_cant_open_file)
                    ListRow(name, listOfNotNull(ext.ifBlank { null }, p.listingTitle ?: p.authorName, ago(p.createdAt)).joinToString(" · "),
                        leading = { Avatar(icon = if (m.mime == "application/pdf") Icons.Rounded.PictureAsPdf else Icons.Rounded.InsertDriveFile, size = 44) },
                        trailing = { if (p.recommenders > 0) VoteMark(p.recommenders, 0) },
                        onClick = { scope.launch { vm.toast(opening); if (!FileOpener.open(ctx, social, "posts", m.path, name + (if (ext.isNotBlank()) ".${ext.lowercase()}" else ""), m.mime)) vm.toast(cantOpen) } })
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant) } } }
            else -> if (list.isEmpty() && shownPlaces.isEmpty()) empty(stringResource(R.string.r1_explore_empty_body))
                else LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp)) {
                    // Shops, pros and products my people recommend: a row of cards above the posts.
                    if (shownPlaces.isNotEmpty()) {
                        item(key = "places-title") { Text(stringResource(R.string.r1_explore_from_people), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = Gutter, end = Gutter, top = 6.dp, bottom = 8.dp)) }
                        item(key = "places") { LazyRow(contentPadding = PaddingValues(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            items(shownPlaces, key = { it.kind + it.id }) { r -> PlaceCard(r) { r.listingId?.let(onListing) } } } }
                        item(key = "places-gap") { Spacer(Modifier.height(10.dp)) }
                    }
                    items(list, key = { it.id }) { p ->
                        SocialPostCard(vm, p, onVote = { vote(p, it) }, onComments = { comments = p.id }, onDelete = {}, onOpenMedia = { i -> openMedia(p, i) },
                            header = if (p.recommenders > 0) ({ RecommendedBy(p.recommenderName, p.recommenders) }) else null)
                    }
                }
        }
    }
    comments?.let { id -> CommentsSheet(vm, id) { comments = null } }
    viewing?.takeIf { it in flat.indices }?.let { start ->
        LaunchedEffect(Unit) { com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.EXPLORE_OPEN, "kind" to kind) }
        MediaViewer(vm, flat.map { it.item.viewer }, start = start,
            titleAt = { i -> flat.getOrNull(i)?.post?.let { it.listingTitle ?: it.authorName } },
            voteAt = { i -> flat.getOrNull(i)?.post?.let { fp -> (rows?.firstOrNull { it.id == fp.id } ?: fp).let { now -> ViewerVote(now.up, now.down, now.myVote ?: 0) { v -> vote(now, v) } } } }) { viewing = null }
    }
}

/** "Asha and 22 others recommended": one of the people I'm synced with, by name, and how many more of them. Without a name, the count alone. */
@Composable
fun RecommendedBy(name: String?, count: Int, modifier: Modifier = Modifier) {
    if (count <= 0) return
    val first = name?.trim()?.substringBefore(' ')?.takeIf { it.isNotBlank() }
    val text = when { first == null -> pluralStringResource(R.plurals.g3_foryou_recommended_by, count, count); count == 1 -> stringResource(R.string.r1_rec_name, first)
        else -> pluralStringResource(R.plurals.r1_rec_name_others, count - 1, first, count - 1) }
    Row(modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f)).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
        Text(" $text", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A video the way a video site lists it: the frame edge to edge with a play mark, then who posted it, the first line, and the arrows. */
@Composable
private fun VideoCard(vm: BucksViewModel, p: FeedRow, m: PostMediaItem, onOpen: () -> Unit, onVote: (Int) -> Unit, onPerson: () -> Unit, onComments: () -> Unit) {
    val who = p.listingTitle ?: p.authorName; val title = p.headline(stringResource(R.string.r1_explore_video_by, who))
    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Brush.linearGradient(listOf(Color(0xFF2B1B4D), Color(0xFF0E0A18)))).clickable(onClickLabel = stringResource(R.string.g2_cd_play_video), onClick = onOpen), contentAlignment = Alignment.Center) {
            // The still frame, when the post has one and it can be read; otherwise the plain dark card (older posts, and before explore.sql is applied).
            val poster by produceState<String?>(null, m.poster) { value = m.poster?.let { runCatching { vm.social.fileUrl("posts", it) }.getOrNull() } }
            if (poster != null) AsyncImage(poster, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Box(Modifier.size(56.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, null, Modifier.size(34.dp), tint = Color.White) }
        }
        Row(Modifier.padding(start = Gutter, end = 8.dp, top = 10.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.clip(CircleShape).clickable(onClickLabel = stringResource(R.string.g1_cd_open_profile_of, p.authorName), onClick = onPerson)) { Avatar(initials(p.authorName.ifBlank { "?" }), size = 38, photoUrl = vm.social.photoOf(p.authorId)) }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(title, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(who, ago(p.createdAt), p.area.ifBlank { null }).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (p.recommenders > 0) RecommendedBy(p.recommenderName, p.recommenders, Modifier.padding(top = 6.dp))
            }
        }
        Row(Modifier.padding(start = Gutter, end = Gutter, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            VotePill(p.myVote ?: 0, p.up, p.down, onVote = onVote)
            Row(Modifier.padding(start = 6.dp).clip(CircleShape).clickable(onClick = onComments).minimumInteractiveComponentSize().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.ChatBubbleOutline, pluralStringResource(R.plurals.g1_cd_comments, p.comments, p.comments), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                if (p.comments > 0) Text(" ${p.comments}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        InlineCommentBox(Modifier.padding(horizontal = Gutter).padding(top = 2.dp)) { vm.social.comment(p.id, it) {} }
    }
}

/** A shop, pro or product my people recommend, as a card in the row at the top of Explore. */
@Composable
private fun PlaceCard(r: ForYouItem, onClick: () -> Unit) =
    Surface(onClick = onClick, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.width(232.dp)) {
        Column {
            Box(Modifier.fillMaxWidth().height(118.dp).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                Icon(placeIcon(r.kind), null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                if (!r.photoUrl.isNullOrBlank()) AsyncImage(r.photoUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
            Column(Modifier.padding(12.dp)) {
                Text(r.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(r.subtitle.ifBlank { " " }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                RecommendedBy(r.recommenderName, r.recommenders, Modifier.padding(top = 8.dp))
            }
        }
    }

@Composable
private fun PlaceRow(r: ForYouItem, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(64.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
            Icon(placeIcon(r.kind), null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
            if (!r.photoUrl.isNullOrBlank()) AsyncImage(r.photoUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        Column(Modifier.weight(1f).padding(start = 14.dp)) {
            Text(r.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (r.subtitle.isNotBlank()) Muted(r.subtitle, maxLines = 1)
            RecommendedBy(r.recommenderName, r.recommenders, Modifier.padding(top = 6.dp))
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
}
private fun placeIcon(kind: String): ImageVector = if (kind == "PRODUCT") Icons.Rounded.ShoppingBag else Icons.Rounded.Storefront

@Composable
private fun ExploreEmpty(text: String, searching: Boolean, onFindPeople: () -> Unit) = Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(if (searching) Icons.Rounded.SearchOff else Icons.Rounded.Explore, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(if (searching) text else stringResource(R.string.r1_explore_empty_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    if (!searching) { Muted(text, Modifier.padding(top = 4.dp), align = androidx.compose.ui.text.style.TextAlign.Center)
        SmallButton(stringResource(R.string.g3_foryou_find_people), Modifier.padding(top = 14.dp), tonal = true, onClick = onFindPeople) }
}
