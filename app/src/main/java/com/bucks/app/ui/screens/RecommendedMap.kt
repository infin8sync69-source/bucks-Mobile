package com.bucks.app.ui.screens

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Backend
import com.bucks.app.data.FeedRow
import com.bucks.app.data.Geo
import com.bucks.app.data.LatLng
import com.bucks.app.data.MapBackend
import com.bucks.app.data.MapPlace
import com.bucks.app.data.MapServices
import com.bucks.app.data.Str
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.formatDistance
import com.bucks.app.ui.social.CommentsSheet
import com.bucks.app.ui.social.SocialPostCard
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/*
 * The "Recommended here" layer on the Home map (reports/Map feed for Gen Z India.md, Phase 1). It shows places, never people: Bucks pages
 * and locality centres that posts are tagged to, ranked by recommend votes (supabase/migrations/map_recommended.sql). The map is a way into
 * the posts: a pin opens a small card, the card's "See posts" opens the posts about that place. The places load for the area on screen
 * once, then again only when the person taps "Search this area" or changes a chip, so panning on a slow network costs nothing.
 */

/** How many places get a numbered label on the map and a card in the strip; the rest are plain dots you can still tap. */
private const val TOP = 10

/** The layer's state, kept by Home for as long as Home is on screen. */
class RecommendedLayer {
    var on by mutableStateOf(true)
    /** ALL, FOOD, SHOPS or SERVICES. */
    var cat by mutableStateOf("ALL")
    /** 7 for "This week", 0 for all time. */
    var days by mutableStateOf(7)
    var places by mutableStateOf<List<MapPlace>>(emptyList())
    var loaded by mutableStateOf(false)
    var loading by mutableStateOf(false)
    var failed by mutableStateOf(false)
    /** The map has moved since the places were loaded: offer "Search this area". */
    var stale by mutableStateOf(false)
    var selected by mutableStateOf<MapPlace?>(null)
    var postsFor by mutableStateOf<MapPlace?>(null)
    /** Bumped to load again for the area on screen. */
    var reload by mutableStateOf(0)

    /** The pins this layer adds to the map: the top places numbered with their recommend count, the rest as dots. */
    fun pins(color: Color): List<MapPin> = if (!on) emptyList() else places.mapIndexed { i, p ->
        pinAt(p.at, p.name, color).copy(id = p.key, badge = if (i < TOP) "${i + 1} · ↑${p.up}" else null, selected = selected?.key == p.key)
    }
}

@Composable fun rememberRecommendedLayer() = remember { RecommendedLayer() }

/** Loads the places for what the map shows whenever the layer, a chip or [RecommendedLayer.reload] changes. */
@Composable
fun RecommendedLoader(layer: RecommendedLayer, cmds: MapCommands, signedIn: Boolean) {
    LaunchedEffect(layer.on, layer.cat, layer.days, layer.reload, signedIn) {
        if (!layer.on || !signedIn) return@LaunchedEffect
        // The map needs a moment to be laid out before it knows its edges.
        var b = cmds.bounds(); var tries = 0
        while (b == null && tries++ < 20) { delay(150); b = cmds.bounds() }
        if (b == null) return@LaunchedEffect
        layer.loading = true; layer.failed = false
        val got = runCatching { MapBackend.places(b.s, b.w, b.n, b.e, layer.days, layer.cat.takeIf { it != "ALL" }) }
        layer.loading = false; layer.loaded = true; layer.stale = false
        got.onSuccess { layer.places = it; if (layer.selected?.let { s -> it.none { p -> p.key == s.key } } == true) layer.selected = null }
            .onFailure { layer.failed = true }
    }
}

/** The chips over the map: the layer switch, the categories, the time window; and "Search this area" after the map has moved. */
@Composable
fun RecommendedControls(layer: RecommendedLayer, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MapChip(stringResource(R.string.m1_recommended), layer.on, Icons.Rounded.ThumbUp) { layer.on = !layer.on; layer.selected = null }
            if (layer.on) {
                listOf("ALL" to R.string.m1_cat_all, "FOOD" to R.string.m1_cat_food, "SHOPS" to R.string.m1_cat_shops, "SERVICES" to R.string.m1_cat_services).forEach { (k, label) ->
                    MapChip(stringResource(label), layer.cat == k) { layer.cat = k; layer.selected = null }
                }
                MapChip(stringResource(if (layer.days > 0) R.string.m1_this_week else R.string.m1_all_time), false, Icons.Rounded.Schedule) { layer.days = if (layer.days > 0) 0 else 7 }
            }
        }
        if (layer.on && (layer.stale || layer.loading)) Surface(Modifier.padding(top = 8.dp), shape = CircleShape, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface) {
            Row(Modifier.clickable(enabled = !layer.loading) { layer.reload++ }.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (layer.loading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Icon(Icons.Rounded.Refresh, null, Modifier.size(18.dp))
                Text(stringResource(if (layer.loading) R.string.m1_loading else R.string.m1_search_area), Modifier.padding(start = 6.dp), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** A chip that reads on the map: a solid surface with a shadow, so it stays legible over any street. */
@Composable
private fun MapChip(text: String, selected: Boolean, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, onClick: () -> Unit) =
    Surface(shape = CircleShape, shadowElevation = 3.dp, color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        modifier = Modifier.heightIn(min = 40.dp).clickable(onClick = onClick)) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            icon?.let { Icon(it, null, Modifier.size(16.dp).padding(end = 2.dp), tint = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface) }
            Text(text, Modifier.padding(start = if (icon != null) 4.dp else 0.dp), style = MaterialTheme.typography.labelLarge,
                color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface, maxLines = 1)
        }
    }

/**
 * What the layer puts in Home's sheet, above the search pill: the chosen place's card, or a line about the area with the numbered strip,
 * or the "be the first" card when nothing here is recommended yet.
 */
@Composable
fun ColumnScope.RecommendedSheetContent(vm: BucksViewModel, layer: RecommendedLayer, me: LatLng?, onListing: (String) -> Unit, onPlace: () -> Unit, onPost: () -> Unit) {
    if (!layer.on) return
    val sel = layer.selected
    when {
        sel != null -> RecommendedPlaceCard(sel, layer.places.indexOfFirst { it.key == sel.key }, me, onClose = { layer.selected = null }, onPosts = { layer.postsFor = sel },
            onListing = onListing, onDirections = { MapsPick.place = MapServices.PlaceHit(sel.name, "", sel.at); onPlace() })
        layer.failed -> Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Muted(stringResource(R.string.m1_failed), Modifier.weight(1f)); TextButton({ layer.reload++ }) { Text(stringResource(R.string.m1_try_again)) } }
        !layer.loaded -> {}
        layer.places.isEmpty() -> Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
            if (layer.days > 0) {
                Text(stringResource(R.string.m1_empty_week), style = MaterialTheme.typography.titleSmall)
                TextButton({ layer.days = 0 }, contentPadding = PaddingValues(0.dp)) { Text(stringResource(R.string.m1_show_all_time)) }
            } else {
                Text(stringResource(R.string.m1_empty_title), style = MaterialTheme.typography.titleSmall)
                Muted(stringResource(R.string.m1_empty_body), Modifier.padding(top = 2.dp))
                SmallButton(stringResource(R.string.m1_write_post), Modifier.padding(top = 8.dp), tonal = true, onClick = onPost)
            }
        }
        else -> Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
            Text(pluralStringResource(R.plurals.m1_places_here, layer.places.size, layer.places.size), style = MaterialTheme.typography.titleSmall)
            PlaceStrip(layer) { layer.selected = it }
        }
    }
    layer.postsFor?.let { p -> PlacePostsSheet(vm, p) { layer.postsFor = null } }
}

/** The top places as a numbered row matching their pins, for anyone who finds a list easier than a map. */
@Composable
private fun PlaceStrip(layer: RecommendedLayer, onPick: (MapPlace) -> Unit) {
    LazyRow(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        itemsIndexed(layer.places.take(TOP), key = { _, p -> p.key }) { i, p ->
            val cd = stringResource(R.string.m1_cd_place, p.name, i + 1, p.up)
            OutlinedCard(onClick = { onPick(p) }, modifier = Modifier.widthIn(min = 120.dp, max = 200.dp).semantics { contentDescription = cd }) {
                Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                    Text("${i + 1}  ${p.name}", style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Muted(pluralStringResource(R.plurals.m1_recommended_by, p.up, p.up), maxLines = 1)
                }
            }
        }
    }
}

/** The chosen place: name, the counts in words (the "no" votes shown too), distance, then See posts, Directions, Open page and Share. */
@Composable
private fun RecommendedPlaceCard(p: MapPlace, index: Int, me: LatLng?, onClose: () -> Unit, onPosts: () -> Unit, onListing: (String) -> Unit, onDirections: () -> Unit) {
    val ctx = LocalContext.current
    androidx.activity.compose.BackHandler(onBack = onClose)
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text((if (index >= 0 && index < TOP) "${index + 1}  " else "") + p.name, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                val bits = listOfNotNull(
                    if (p.up > 0) pluralStringResource(R.plurals.m1_recommended_by, p.up, p.up) else pluralStringResource(R.plurals.m1_posts, p.posts, p.posts),
                    if (p.down > 0) pluralStringResource(R.plurals.m1_not_recommended, p.down, p.down) else null,
                    me?.let { formatDistance(Geo.distanceKm(it, p.at) * 1000) },
                    categoryLabel(p.category))
                Muted(bits.joinToString(" · "), maxLines = 2)
            }
            IconButton(onClose) { Icon(Icons.Rounded.Close, stringResource(R.string.m1_cd_close)) }
        }
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            PrimaryButton(stringResource(R.string.m1_see_posts), Modifier.weight(1f), onClick = onPosts)
            SmallButton(stringResource(R.string.m1_directions), tonal = true, onClick = onDirections)
            IconButton({
                val text = Str.get(R.string.m1_share_text, p.name, p.up)
                runCatching { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null)) }
            }) { Icon(Icons.Rounded.Share, stringResource(R.string.m1_share)) }
        }
        p.listingId?.let { id -> TextButton({ onListing(id) }, contentPadding = PaddingValues(0.dp)) { Text(stringResource(R.string.m1_open_page)) } }
    }
}

@Composable
private fun categoryLabel(cat: String): String? = when (cat) {
    "FOOD" -> stringResource(R.string.m1_cat_food); "SHOPS" -> stringResource(R.string.m1_cat_shops)
    "SERVICES" -> stringResource(R.string.m1_cat_services); "AREA" -> stringResource(R.string.m1_cat_area); else -> null
}

/** "See posts": the posts about one place, best first, with the feed's own post card, votes and comments. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlacePostsSheet(vm: BucksViewModel, place: MapPlace, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var rows by remember(place.key) { mutableStateOf<List<FeedRow>?>(null) }
    var comments by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(place.key) {
        rows = runCatching { MapBackend.placePosts(place.place, place.placeId) }.getOrElse { vm.toast(Str.get(R.string.m1_failed)); emptyList() }
        runCatching { vm.social.namesFor(rows.orEmpty().map { it.authorId }) }
    }
    fun vote(p: FeedRow, v: Int) { val me = vm.social.me?.id ?: return
        val prev = rows?.firstOrNull { it.id == p.id }?.myVote ?: 0; val next = if (prev == v) 0 else v
        fun shift(from: Int, to: Int) { rows = rows?.map { if (it.id != p.id) it else it.copy(myVote = to.takeIf { n -> n != 0 }, up = it.up - (if (from == 1) 1 else 0) + (if (to == 1) 1 else 0), down = it.down - (if (from == -1) 1 else 0) + (if (to == -1) 1 else 0)) } }
        shift(prev, next)
        scope.launch { runCatching { Backend.vote(p.id, me, next) }.onFailure { shift(next, prev); vm.toast(Str.get(R.string.g5_something_wrong)) } } }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, containerColor = MaterialTheme.colorScheme.surface) {
        Text(stringResource(R.string.m1_posts_title, place.name), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = Gutter).padding(bottom = 4.dp), maxLines = 2, overflow = TextOverflow.Ellipsis)
        val list = rows
        when {
            list == null -> LinearProgressIndicator(Modifier.fillMaxWidth().padding(Gutter))
            list.isEmpty() -> Muted(stringResource(R.string.m1_posts_empty), Modifier.padding(Gutter))
            else -> LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                items(list, key = { it.id }) { p -> SocialPostCard(vm, p, onVote = { vote(p, it) }, onComments = { comments = p.id }, onDelete = {}) }
            }
        }
    }
    comments?.let { id -> CommentsSheet(vm, id) { comments = null } }
}
