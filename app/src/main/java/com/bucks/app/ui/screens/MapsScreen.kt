package com.bucks.app.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.speech.tts.TextToSpeech
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextOverflow
import androidx.core.content.ContextCompat
import com.bucks.app.data.RoutePath
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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

/** A place or search picked elsewhere (the app's search bars, a shop's Directions button, an address in Contacts) for the Maps screen to open on; taken once. */
object MapsPick { var place: MapServices.PlaceHit? = null; var query: String? = null }

/** Opens the same trip in another maps app; kept as a small fallback next to the in-app navigation. */
fun openDirections(ctx: android.content.Context, to: LatLng, label: String = "", mode: Char = 'd') {
    val nav = Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=${to.lat},${to.lng}&mode=$mode")).setPackage("com.google.android.apps.maps")
    val any = Intent(Intent.ACTION_VIEW, Uri.parse("geo:${to.lat},${to.lng}?q=${to.lat},${to.lng}" + if (label.isNotBlank()) "(${Uri.encode(label)})" else ""))
    runCatching { ctx.startActivity(nav) }.recoverCatching { ctx.startActivity(any) }
        .onFailure { android.widget.Toast.makeText(ctx, "No other maps app found.", android.widget.Toast.LENGTH_SHORT).show() }
}

private enum class TravelMode(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector?, val profile: String) {
    DRIVE("Drive", Icons.Rounded.DirectionsCar, "driving-traffic"), TWO("Two-wheeler", Icons.Rounded.TwoWheeler, "driving"), CYCLE("Cycle", null, "cycling"), WALK("Walk", Icons.Rounded.DirectionsWalk, "walking")
}

/** A position fix: where, and which way and how fast when the phone knows. */
private data class Fix(val at: LatLng, val accuracy: Float)

/** Live position from the phone while the screen is open: every [intervalMs], best accuracy. Null until the first fix or without permission. */
@Composable
private fun rememberLiveFix(intervalMs: Long): State<Fix?> {
    val ctx = LocalContext.current; val fix = remember { mutableStateOf<Fix?>(null) }
    DisposableEffect(intervalMs) {
        val ok = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val client = LocationServices.getFusedLocationProviderClient(ctx)
        val cb = object : LocationCallback() { override fun onLocationResult(r: LocationResult) { r.lastLocation?.let { fix.value = Fix(LatLng(it.latitude, it.longitude), it.accuracy) } } }
        if (ok) runCatching { client.requestLocationUpdates(LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMs).setMinUpdateDistanceMeters(3f).build(), cb, android.os.Looper.getMainLooper()) }
        onDispose { runCatching { client.removeLocationUpdates(cb) } }
    }
    return fix
}

/** Rotation of the arrow icon for a maneuver: straight 0, right +90, left -90, U-turn 180. */
private fun turnAngle(type: String, mod: String): Float = when {
    type == "arrive" -> 0f
    mod == "uturn" -> 180f; mod == "sharp right" -> 135f; mod == "right" -> 90f; mod == "slight right" -> 45f
    mod == "sharp left" -> -135f; mod == "left" -> -90f; mod == "slight left" -> -45f; else -> 0f
}

private fun spoken(m: Double) = if (m >= 1000) "%.1f kilometres".format(m / 1000) else "${(Math.round(m / 10.0) * 10).toInt()} metres"

/**
 * Maps, inside the app: search anywhere or long-press the map to drop a pin, see the road route with distance and time (drive, two-wheeler, cycle, walk),
 * read its steps, then Start for live turn-by-turn: the next turn and how far, distance and time left, voice, re-routing when you leave the route.
 * Search, routes and tiles come from Mapbox when a token is built in (MapServices, BucksMap), else from OpenStreetMap's public servers.
 */
@Composable
fun MapsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val ctx = LocalContext.current; val s by vm.state.collectAsState(); val cmds = remember { MapCommands() }
    var navigating by remember { mutableStateOf(false) }; var arrived by remember { mutableStateOf(false) }
    val fix by rememberLiveFix(if (navigating) 2_000L else 10_000L)
    val here = fix?.at ?: s.me; val start = here ?: vm.mePos
    var q by remember { mutableStateOf("") }; var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var dest by remember { mutableStateOf<MapServices.PlaceHit?>(null) }; var mode by remember { mutableStateOf(TravelMode.DRIVE) }
    var offline by remember { mutableStateOf(false) }; var retry by remember { mutableStateOf(0) }
    // The location button: asks for permission if it's missing, takes a fresh high-accuracy fix, updates the app's position and centres the map on it.
    var locating by remember { mutableStateOf(false) }
    fun locate(quiet: Boolean = false) {
        val ok = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!ok) { if (!quiet) vm.toast("Allow location in the prompt to see where you are."); return }
        locating = true
        runCatching {
            LocationServices.getFusedLocationProviderClient(ctx).getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
                .addOnSuccessListener { l -> locating = false; if (l != null) { val p = LatLng(l.latitude, l.longitude); vm.onLocation(p, false); cmds.moveTo(p, 16.0) } else { vm.toast("Couldn't get a fix. Check that location is on."); } }
                .addOnFailureListener { locating = false; vm.toast("Couldn't get your location. Check that location is on.") }
        }.onFailure { locating = false }
    }
    val askLocation = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { g -> if (g.values.any { it }) locate() else vm.toast("Location is off for Bucks. Turn it on in Settings.") }
    var satellite by remember { mutableStateOf(false) }; var showSteps by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (s.me == null) locate(quiet = true) }
    LaunchedEffect(Unit) { MapsPick.place?.let { dest = it; q = it.name; MapsPick.place = null }; MapsPick.query?.let { q = it; MapsPick.query = null } }
    LaunchedEffect(q, retry) {
        if (q.trim().length < 3 || dest != null) { hits = emptyList(); searching = false; offline = false; return@LaunchedEffect }
        searching = true; offline = false; delay(450)
        val r = MapServices.searchOrNull(q, start); hits = r.orEmpty(); offline = r == null; searching = false
    }

    // The road route from where I am (or the last known position) to the destination; fetched again when the destination or mode changes, or after a wrong turn.
    var route by remember { mutableStateOf<MapServices.RoadRoute?>(null) }; var routing by remember { mutableStateOf(false) }; var routeFailed by remember { mutableStateOf(false) }
    var reroute by remember { mutableStateOf(0) }
    LaunchedEffect(dest, mode, reroute, here != null) {
        val d = dest; val from = here
        if (d == null || from == null) { route = null; routeFailed = false; return@LaunchedEffect }
        routing = true; routeFailed = false
        val r = MapServices.route(from, d.at, mode.profile); if (r != null || reroute == 0) route = r; routeFailed = r == null; routing = false
    }
    val path = remember(route) { route?.takeIf { it.points.size >= 2 }?.let { RoutePath(it.points) } }
    val stepAt = remember(route, path) { path?.let { p -> route?.steps.orEmpty().map { st -> p.snap(st.at).along } }.orEmpty() }

    // Progress along the route while navigating.
    var seg by remember { mutableStateOf(0) }; LaunchedEffect(route) { seg = 0 }
    val snap = if (navigating && path != null && here != null) path.snap(here, seg) else null
    LaunchedEffect(snap?.seg) { snap?.let { seg = it.seg } }
    val remainingM = snap?.let { path!!.total - it.along } ?: path?.total ?: 0.0
    val totalMin = route?.minutes ?: 0
    val remainingMin = if (path != null && path.total > 0) maxOf(1, Math.round(totalMin * (remainingM / path.total)).toInt()) else totalMin
    val nextIdx = snap?.let { sn -> stepAt.indices.firstOrNull { it >= 1 && stepAt[it] > sn.along - 10 } ?: (stepAt.size - 1).takeIf { it >= 1 } }
    val next = nextIdx?.let { route?.steps?.getOrNull(it) }
    val toNext = if (snap != null && nextIdx != null) maxOf(0.0, stepAt[nextIdx] - snap.along) else 0.0

    // Voice: the turn is announced at about 200 m and again as you reach it; a fake-quiet phone or the mute button silences it.
    var muted by remember { mutableStateOf(false) }; var tts by remember { mutableStateOf<TextToSpeech?>(null) }
    DisposableEffect(Unit) {
        var t: TextToSpeech? = null
        t = TextToSpeech(ctx) { st -> if (st == TextToSpeech.SUCCESS) { t?.language = Locale.getDefault(); tts = t } }
        onDispose { t?.stop(); t?.shutdown() }
    }
    fun say(text: String) { if (!muted) tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "nav") }
    val bucket = when { toNext <= 40 -> 0; toNext <= 220 -> 1; else -> 2 }
    LaunchedEffect(nextIdx, bucket, navigating) {
        if (!navigating || next == null || bucket == 2) return@LaunchedEffect
        say(if (bucket == 1) "In ${spoken(toNext)}, ${next.text}" else next.text)
    }
    // Off the route for three fixes in a row: find a new way from here (at most every 8 seconds).
    var offCount by remember { mutableStateOf(0) }; var lastReroute by remember { mutableStateOf(0L) }
    LaunchedEffect(fix) {
        if (!navigating || snap == null) return@LaunchedEffect
        offCount = if (snap.off > 60) offCount + 1 else 0
        if (offCount >= 3 && System.currentTimeMillis() - lastReroute > 8_000) { offCount = 0; lastReroute = System.currentTimeMillis(); say("Rerouting"); reroute++ }
    }
    LaunchedEffect(navigating, remainingM) {
        if (navigating && snap != null && remainingM < 25 && path != null && path.total > 50) { say("You have arrived"); navigating = false; arrived = true }
    }
    // Follow me while navigating; a drag on the map lets go until Recentre.
    var follow by remember { mutableStateOf(true) }
    LaunchedEffect(fix) { if (navigating && follow) here?.let { cmds.moveTo(it) } }
    LaunchedEffect(navigating) { if (navigating) { follow = true; here?.let { cmds.moveTo(it, 17.0) } } }
    val view = LocalView.current
    DisposableEffect(navigating) { view.keepScreenOn = navigating; onDispose { view.keepScreenOn = false } }
    BackHandler(enabled = navigating || dest != null) { if (navigating) navigating = false else { dest = null; q = "" } }

    val line = route?.points ?: dest?.let { d -> here?.let { listOf(it, d.at) } }.orEmpty()
    val pins = buildList {
        add(pinAt(start, "You", MeColor, big = true))
        dest?.let { add(pinAt(it.at, it.name, MaterialTheme.colorScheme.primary)) }
    }
    Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), pins, route = line, commands = cmds, satellite = satellite,
            onLongPress = if (navigating) null else { p -> dest = MapServices.PlaceHit("Dropped pin", "", p); q = "Dropped pin"; hits = emptyList() },
            onUserMove = { follow = false })
        // Long-pressed pins get a street name when the search server answers.
        LaunchedEffect(dest?.at) { val d = dest; if (d != null && d.name == "Dropped pin") MapServices.label(d.at)?.let { l -> if (dest?.at == d.at) { dest = d.copy(name = l); q = l } } }

        if (!navigating) {
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
                            Column(Modifier.padding(start = 12.dp).weight(1f)) { Text(h.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis); if (h.detail.isNotBlank()) Muted(h.detail, maxLines = 1) }
                            Muted(com.bucks.app.ui.formatDistance(Geo.distanceKm(start, h.at) * 1000))
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
            // Map buttons: where am I, zoom, satellite.
            Column(Modifier.align(Alignment.TopEnd).padding(top = 150.dp, end = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.End) {
                MapButton(Icons.Rounded.MyLocation, "My location", busy = locating) {
                    val ok = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    if (ok) locate() else askLocation.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                }
                MapButton(Icons.Rounded.Add, "Zoom in") { cmds.zoomIn() }
                MapButton(Icons.Rounded.Remove, "Zoom out") { cmds.zoomOut() }
                if (com.bucks.app.BuildConfig.MAPBOX_TOKEN.isNotBlank()) Surface(shape = RoundedCornerShape(20.dp), shadowElevation = 4.dp, color = if (satellite) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface, modifier = Modifier.clickable { satellite = !satellite }) {
                    Text("Satellite", Modifier.padding(horizontal = 12.dp, vertical = 8.dp), style = MaterialTheme.typography.labelMedium, color = if (satellite) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
                }
            }
        }

        // Turn-by-turn: the next turn on top, time and distance left with mute and End at the bottom.
        if (navigating) {
            Surface(Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().padding(12.dp), shape = RoundedCornerShape(20.dp), shadowElevation = 8.dp, color = MaterialTheme.colorScheme.primary) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(44.dp).rotate(if (next != null) turnAngle(next.type, next.modifier) else 0f), tint = MaterialTheme.colorScheme.onPrimary)
                    Column(Modifier.padding(start = 14.dp)) {
                        Text(if (next != null) com.bucks.app.ui.formatDistance(toNext) else "Follow the route", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onPrimary)
                        Text(next?.text ?: "Continue to ${dest?.name.orEmpty()}", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (!follow) Box(Modifier.align(Alignment.CenterEnd).padding(end = 12.dp)) { MapButton(Icons.Rounded.MyLocation, "Recentre") { follow = true; here?.let { cmds.moveTo(it, 17.0) }; locate() } }
            Surface(Modifier.align(Alignment.BottomCenter).fillMaxWidth(), shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp), shadowElevation = 12.dp, color = MaterialTheme.colorScheme.surface) {
                Row(Modifier.navigationBarsPadding().padding(horizontal = 20.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(System.currentTimeMillis() + remainingMin * 60_000L)), style = MaterialTheme.typography.titleLarge)
                        Muted("$remainingMin min · ${com.bucks.app.ui.formatDistance(remainingM)} · ${dest?.name.orEmpty()}", maxLines = 1)
                    }
                    IconButton({ muted = !muted; if (muted) tts?.stop() }) { Icon(if (muted) Icons.Rounded.Close else Icons.Rounded.VolumeUp, if (muted) "Voice is off" else "Turn voice off") }
                    Button({ navigating = false }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("End") }
                }
            }
        } else Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { MapAttribution() }
            val d = dest
            if (d != null) Sheet {
                Row(verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) { Text(d.name, style = MaterialTheme.typography.titleLarge, maxLines = 2); if (d.detail.isNotBlank()) Muted(d.detail, maxLines = 2) }
                    IconButton({ dest = null; q = ""; showSteps = false }) { Icon(Icons.Rounded.Close, "Clear destination") }
                }
                Row(Modifier.padding(top = 10.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) { TravelMode.entries.forEach { m -> Chip(m.label, selected = mode == m, icon = m.icon) { mode = m } } }
                Text(when {
                    here == null -> "Turn on location to see the route from where you are."
                    routing && route == null -> "Finding the best route…"
                    routeFailed && route == null -> "Couldn't get a road route. ${com.bucks.app.ui.formatDistance(Geo.distanceKm(here, d.at) * 1000)} away in a straight line."
                    route != null -> "${route!!.km} km · about ${route!!.minutes} min by ${mode.label.lowercase()}"
                    else -> ""
                }, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 10.dp))
                if (routeFailed && route == null && here != null) SmallButton("Try again", Modifier.padding(top = 6.dp)) { reroute++ }
                val steps = route?.steps.orEmpty()
                if (steps.size > 1) {
                    TextButton({ showSteps = !showSteps }, contentPadding = PaddingValues(0.dp)) { Text(if (showSteps) "Hide steps" else "Show ${steps.size} steps") }
                    if (showSteps) Column(Modifier.heightIn(max = 200.dp).verticalScroll(rememberScrollState())) {
                        steps.forEach { st -> Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(20.dp).rotate(turnAngle(st.type, st.modifier)), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(st.text, Modifier.weight(1f).padding(horizontal = 10.dp), style = MaterialTheme.typography.bodyMedium)
                            if (st.metres > 0) Muted(com.bucks.app.ui.formatDistance(st.metres))
                        } }
                    }
                }
                PrimaryButton("Start", Modifier.padding(top = 8.dp), enabled = route != null && here != null) { arrived = false; showSteps = false; navigating = true; say("Starting navigation. ${route?.steps?.getOrNull(1)?.text.orEmpty()}") }
                TextButton({ openDirections(ctx, d.at, d.name, when (mode) { TravelMode.WALK -> 'w'; TravelMode.TWO -> 'l'; TravelMode.CYCLE -> 'b'; else -> 'd' }) }, Modifier.align(Alignment.CenterHorizontally)) { Text("Open in another maps app") }
            } else Muted("Search for a shop, address, landmark or town anywhere, or press and hold the map to drop a pin. You'll see the road route and can start turn-by-turn navigation here.", Modifier.padding(horizontal = 20.dp, vertical = 12.dp).background(MaterialTheme.colorScheme.surface))
        }
    }
    if (arrived) AlertDialog(onDismissRequest = { arrived = false }, title = { Text("You have arrived") }, text = { Text(dest?.name.orEmpty()) }, confirmButton = { TextButton({ arrived = false; dest = null; q = "" }) { Text("Done") } })
}

@Composable
private fun MapButton(icon: androidx.compose.ui.graphics.vector.ImageVector, desc: String, busy: Boolean = false, onClick: () -> Unit) =
    Surface(shape = CircleShape, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface, modifier = Modifier.size(44.dp).clickable(enabled = !busy, onClick = onClick)) {
        Box(contentAlignment = Alignment.Center) { if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else Icon(icon, desc) }
    }
