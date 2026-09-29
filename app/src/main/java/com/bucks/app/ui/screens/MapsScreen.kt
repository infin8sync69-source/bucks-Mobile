package com.bucks.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Geo
import com.bucks.app.data.LatLng
import com.bucks.app.data.MapServices
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.coroutines.delay

/** How the trip is made when handed to a maps app: d = car, l = motorcycle / scooter, w = walking, b = bicycle. */
private val TRAVEL_MODES = listOf('d' to "Drive", 'l' to "Two-wheeler", 'w' to "Walk")

/**
 * Directions to any place, opened in the phone's maps app: Google Maps navigation when installed, else any app that takes a map link.
 * Used from here, from a shop's profile and from an address in Contacts.
 */
fun openDirections(ctx: android.content.Context, to: LatLng, label: String = "", mode: Char = 'd') {
    val nav = Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=${to.lat},${to.lng}&mode=$mode")).setPackage("com.google.android.apps.maps")
    val any = Intent(Intent.ACTION_VIEW, Uri.parse("geo:${to.lat},${to.lng}?q=${to.lat},${to.lng}" + if (label.isNotBlank()) "(${Uri.encode(label)})" else ""))
    runCatching { ctx.startActivity(nav) }.recoverCatching { ctx.startActivity(any) }
        .onFailure { android.widget.Toast.makeText(ctx, "No maps app found. Install Google Maps for turn-by-turn directions.", android.widget.Toast.LENGTH_SHORT).show() }
}

/** A place chosen elsewhere (the app's search bar) for the Maps screen to open on; taken once. */
object MapsPick { var place: MapServices.PlaceHit? = null }

/**
 * Maps: search anywhere, see the road route from where you are with its distance and time on the map, then Navigate to hand it to
 * turn-by-turn in a maps app. The preview route is by road (OpenStreetMap data); turn-by-turn and live traffic come from the maps app.
 */
@Composable
fun MapsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val ctx = LocalContext.current; val s by vm.state.collectAsState()
    val here = s.me; val start = here ?: vm.mePos
    var q by remember { mutableStateOf("") }; var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var dest by remember { mutableStateOf<MapServices.PlaceHit?>(null) }; var mode by remember { mutableStateOf('d') }
    var offline by remember { mutableStateOf(false) }; var retry by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { MapsPick.place?.let { dest = it; q = it.name; MapsPick.place = null } }
    LaunchedEffect(q, retry) {
        if (q.trim().length < 3 || dest != null) { hits = emptyList(); searching = false; offline = false; return@LaunchedEffect }
        searching = true; offline = false; delay(450)
        val r = MapServices.searchOrNull(q, start); hits = r.orEmpty(); offline = r == null; searching = false
    }
    val road = rememberRoadRoute(here, dest?.at)
    val line = road?.points ?: dest?.let { d -> here?.let { listOf(it, d.at) } }.orEmpty()
    val pins = buildList {
        add(pinAt(start, "You", MeColor, big = true))
        dest?.let { add(pinAt(it.at, it.name, MaterialTheme.colorScheme.primary)) }
    }
    Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), pins, route = line)
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
            Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                    OutlinedTextField(q, { q = it; dest = null }, placeholder = { Text("Search any place") }, singleLine = true, modifier = Modifier.weight(1f),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search), keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { retry++ }),
                        colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = androidx.compose.ui.graphics.Color.Transparent, focusedBorderColor = androidx.compose.ui.graphics.Color.Transparent))
                    if (q.isNotEmpty()) IconButton({ q = ""; dest = null; hits = emptyList() }) { Icon(Icons.Rounded.Close, "Clear") }
                }
            }
            if (searching) LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = 24.dp))
            if (hits.isNotEmpty() && dest == null) Surface(Modifier.padding(top = 6.dp), shape = RoundedCornerShape(20.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                LazyColumn(Modifier.heightIn(max = 340.dp)) { items(hits, key = { it.name + it.at.lat + it.at.lng }) { h ->
                    Row(Modifier.fillMaxWidth().clickable { dest = h; q = h.name; hits = emptyList() }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Place, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Column(Modifier.padding(start = 12.dp)) { Text(h.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1); if (h.detail.isNotBlank()) Muted(h.detail, maxLines = 1) }
                        Spacer(Modifier.weight(1f)); Muted(com.bucks.app.ui.formatDistance(Geo.distanceKm(start, h.at) * 1000))
                    }
                    Divider()
                } }
            } else if (q.trim().length >= 3 && !searching && hits.isEmpty() && dest == null) Surface(Modifier.padding(top = 6.dp), shape = RoundedCornerShape(20.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.padding(16.dp)) {
                    Text(if (offline) "Couldn't reach the map search" else "No places found", style = MaterialTheme.typography.titleSmall)
                    Muted(if (offline) "Check your internet connection and try again." else "Try a landmark, an area or the town's name.", Modifier.padding(top = 2.dp))
                    if (offline) SmallButton("Try again", Modifier.padding(top = 8.dp)) { retry++ }
                }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { MapAttribution() }
            val d = dest
            if (d != null) Sheet {
                Text(d.name, style = MaterialTheme.typography.titleLarge, maxLines = 2)
                if (d.detail.isNotBlank()) Muted(d.detail, maxLines = 2)
                Text(when {
                    here == null -> "Turn on location to see the route from where you are."
                    road != null -> "${road.km} km by road · about ${road.minutes} min"
                    else -> "${com.bucks.app.ui.formatDistance(Geo.distanceKm(here, d.at) * 1000)} away in a straight line"
                }, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 10.dp))
                Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { TRAVEL_MODES.forEach { (m, l) -> Chip(l, selected = mode == m) { mode = m } } }
                Muted("The route shown is by road. Turn-by-turn, live traffic and walking routes come from your maps app.", Modifier.padding(top = 6.dp))
                PrimaryButton("Navigate", Modifier.padding(top = 12.dp)) { openDirections(ctx, d.at, d.name, mode) }
            } else Muted("Search for a shop, address, landmark or town anywhere. You'll see the road route and can start turn-by-turn navigation.", Modifier.padding(horizontal = 20.dp, vertical = 12.dp).background(MaterialTheme.colorScheme.surface))
        }
    }
}
