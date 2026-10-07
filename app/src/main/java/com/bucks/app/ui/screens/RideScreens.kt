package com.bucks.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.window.Dialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.dial
import com.bucks.app.ui.sms
import com.bucks.app.ui.shareText
import com.bucks.app.ui.upiPayLink
import com.bucks.app.ui.upiPayee
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status

@Composable
fun DestinationScreen(vm: BucksViewModel, onBack: () -> Unit, onChosen: () -> Unit) {
    val s by vm.state.collectAsState(); var f by remember { mutableStateOf("") }; var picked by remember { mutableStateOf<String?>(null) }
    var savedOpen by remember { mutableStateOf(false) }; var onMap by remember { mutableStateOf(false) }; var center by remember { mutableStateOf<LatLng?>(null) }
    val me = vm.mePos
    if (onMap) { Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MeColor, true)), zoom = 14.0, onCenter = { center = it })
        Icon(Icons.Rounded.LocationOn, "Destination", Modifier.align(Alignment.Center).padding(bottom = 36.dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
        IconButton({ onMap = false }, Modifier.padding(12.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            MapAttribution(Modifier.align(Alignment.End).padding(8.dp))
            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(20.dp)) {
                Muted("Drag the map to place the pin", Modifier.padding(bottom = 10.dp)); DarkButton("Set destination here", enabled = center != null) { center?.let { vm.chooseDestAt(it); picked = s.rideDest?.name; onMap = false; onChosen() } } } }
    }; return }
    val places = Geo.PLACES.keys.filter { it.contains(f, ignoreCase = true) }
    // Anywhere in the map's address data, nearest first; the built-in list above stays for offline and quick picks.
    var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var pickedHit by remember { mutableStateOf<MapServices.PlaceHit?>(null) }
    LaunchedEffect(f) { if (f.trim().length < 3 || f == picked) { hits = emptyList(); return@LaunchedEffect }; kotlinx.coroutines.delay(350); searching = true; hits = MapServices.search(f, me); searching = false }
    Column(Modifier.fillMaxSize()) {
        IconButton(onBack, Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 14.dp, vertical = 6.dp)) {
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.good)); Text((s.hereLabel ?: s.user?.area)?.let { "Current location · $it" } ?: "Current location", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 12.dp), maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Rounded.MyLocation, "Using current location", Modifier.size(18.dp)) }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.bad))
                BasicTextField(f, { f = it; picked = null; pickedHit = null }, Modifier.weight(1f).padding(start = 12.dp), singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    decorationBox = { inner -> Box { if (f.isEmpty()) Muted("Enter destination"); inner() } }) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            if (hits.isNotEmpty() || searching) {
                Text("Places", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
                if (searching && hits.isEmpty()) Muted("Searching the map…", Modifier.padding(vertical = 8.dp))
                hits.forEach { h -> HitRow(h, Geo.distanceKm(me, h.at), selected = pickedHit == h) { pickedHit = h; picked = null } }
            }
            if (places.isNotEmpty()) Text(if (f.isBlank()) "Frequently visited" else "Matches", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
            places.forEach { name -> PlaceRow(name, Geo.distanceKm(me, Geo.PLACES.getValue(name)), saved = name in s.savedPlaces, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; pickedHit = null; f = name } }
            if (places.isEmpty() && hits.isEmpty() && !searching && f.trim().length >= 3) Muted("No place with that name. Try another spelling, or pick it on the map.", Modifier.padding(vertical = 12.dp))
            Row(Modifier.fillMaxWidth().clickable { savedOpen = !savedOpen }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Star, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary); Text("Saved places", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 10.dp)); Icon(if (savedOpen) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, null) }
            if (savedOpen) { if (s.savedPlaces.isEmpty()) Muted("Star a place to save it.", Modifier.padding(bottom = 8.dp)); s.savedPlaces.forEach { name -> Geo.PLACES[name]?.let { ll -> PlaceRow(name, Geo.distanceKm(me, ll), saved = true, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; f = name } } } }
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(vertical = 10.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { onMap = true }.padding(horizontal = 18.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" Select on map") }
        DarkButton("Confirm", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), enabled = picked != null || pickedHit != null) {
            pickedHit?.let { vm.chooseDestPlace(it.name, it.at); onChosen() } ?: picked?.let { vm.chooseDest(it); onChosen() } }
    }
}

@Composable
private fun PlaceRow(name: String, km: Double, saved: Boolean, selected: Boolean, onStar: () -> Unit, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.LocationOn, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) { Text(name.substringBefore(","), style = MaterialTheme.typography.bodyMedium); Muted("$name · ${"%.1f".format(km)} km away", maxLines = 1) }
        IconButton(onStar, Modifier.size(32.dp)) { Icon(if (saved) Icons.Filled.Star else Icons.Rounded.StarOutline, if (saved) "Unsave" else "Save place", tint = if (saved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun HitRow(h: MapServices.PlaceHit, km: Double, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.LocationOn, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) { Text(h.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(listOf(h.detail, "${"%.1f".format(km)} km away").filter { it.isNotBlank() }.joinToString(" · "), maxLines = 1) }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

/** The real point when known (searched, pinned or cloud); the demo's grid position otherwise. */
private fun Place.latLng() = at ?: Geo.fromPercent(x, y)
private val HHMM = java.text.SimpleDateFormat("h:mma", java.util.Locale.ENGLISH)

@Composable
fun ChooseRideScreen(vm: BucksViewModel, onBack: () -> Unit, onConfirm: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState()
    val dest = s.rideDest ?: return; val me = vm.pickupAt
    // The road route: its line on the map, and its distance for the fare (straight line until it arrives or when offline).
    val road = rememberRoadRoute(me, dest.latLng())
    LaunchedEffect(road) { road?.let { vm.setDestKm(it.km) } }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, if (s.ridePickup != null) "Pick-up" else "You", MeColor, true), pinAt(dest.latLng(), dest.name, MaterialTheme.colorScheme.primary)) + drivers.filter { it.online }.map { pinAt(it.pos, "", MaterialTheme.status.good) }, route = road?.points ?: listOf(me, dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Box(Modifier.fillMaxWidth()) { IconButton(onBack, Modifier.align(Alignment.CenterStart).size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }; Text("Choose vehicle", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.Center)) }
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                VehicleKind.PASSENGER.forEach { k -> val nearest = Geo.ring(me, drivers, k).firstOrNull(); val on = s.rideKind == k; val f = vm.fare(k, dest.km)
                    val away = nearest?.let { maxOf(1, (it.distanceKm * 2.5).toInt()) }; val eta = away?.let { HHMM.format(java.util.Date(System.currentTimeMillis() + (it + dest.km * 3).toLong() * 60_000)).lowercase() }
                    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).border(if (on) 2.dp else 0.dp, if (on) MaterialTheme.colorScheme.primary else Color.Transparent, MaterialTheme.shapes.small).clickable(enabled = nearest != null) { vm.setRideKind(k) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(k.icon, null, Modifier.size(40.dp), tint = if (nearest != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(k.label, style = MaterialTheme.typography.titleSmall)
                            Muted(if (away != null) "$away mins away · ETA $eta" else "No riders online nearby"); Muted("Max ${when (k) { VehicleKind.BIKE -> 1; VehicleKind.AUTO -> 3; VehicleKind.CAB -> 4 }} · ₹${k.farePerKm}/per km") }
                        Text("₹$f–${(f * 1.15).toInt()}", style = MaterialTheme.typography.titleSmall)
                    } }
            }
            DarkButton("Confirm", Modifier.padding(top = 14.dp), enabled = vm.onlineCount(s.rideKind) > 0, onClick = onConfirm)
        }
    }
}

/**
 * Confirm (and move) the pick-up: drag the map so the pin sits where the rider should come, or search a place; the address under the pin updates.
 * "Use my location" snaps back to where I am. The fare is worked out again from the pin when it moved.
 */
@Composable
fun ConfirmPickupScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val s by vm.state.collectAsState(); val cmds = remember { MapCommands() }; val scope = rememberCoroutineScope()
    val start = vm.pickupAt; val dest = s.rideDest
    var center by remember { mutableStateOf(start) }
    var label by remember { mutableStateOf(s.ridePickup?.name ?: s.hereLabel ?: s.user?.area?.ifBlank { null } ?: "Your location") }
    var q by remember { mutableStateOf("") }; var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(300); cmds.moveTo(start, 16.0) }
    // The street name under the pin, a moment after the map stops moving.
    LaunchedEffect(center) { delay(700); MapServices.label(center)?.let { label = it } }
    LaunchedEffect(q) { if (q.trim().length < 3) { hits = emptyList(); return@LaunchedEffect }; delay(450); hits = MapServices.search(q, center).take(5) }
    Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.mePos, "You", MeColor, true)), zoom = 16.0, commands = cmds, onCenter = { center = it })
        // The pin stays in the middle; the map moves under it.
        Icon(Icons.Rounded.LocationOn, "Pick-up", Modifier.align(Alignment.Center).offset(y = (-20).dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
            Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                    OutlinedTextField(q, { q = it }, placeholder = { Text("Search a pick-up place") }, singleLine = true, modifier = Modifier.weight(1f),
                        colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = Color.Transparent, focusedBorderColor = Color.Transparent))
                    if (q.isNotEmpty()) IconButton({ q = ""; hits = emptyList() }) { Icon(Icons.Rounded.Close, "Clear") }
                }
            }
            if (hits.isNotEmpty()) Surface(Modifier.padding(top = 6.dp), shape = RoundedCornerShape(20.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Column { hits.forEach { h -> HitRow(h, Geo.distanceKm(vm.mePos, h.at), false) { q = ""; hits = emptyList(); label = h.name; center = h.at; cmds.moveTo(h.at, 16.0) } } }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Spacer(Modifier.weight(1f))
                Surface(shape = CircleShape, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface, modifier = Modifier.size(44.dp).clickable { cmds.moveTo(vm.mePos, 16.0) }) { Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.MyLocation, "Use my location") } }
            }
            Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { MapAttribution() }
            Sheet {
                Text("Pick-up", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(label, style = MaterialTheme.typography.titleMedium, maxLines = 2)
                val moved = Geo.distanceKm(center, vm.mePos) * 1000
                Muted(if (moved > 50) "${com.bucks.app.ui.formatDistance(moved)} from where you are. The rider comes to the pin. Riders within 5 km of it are rung." else "Drag the map to move the pin. Riders within 5 km are rung; the first to accept comes here.", Modifier.padding(vertical = 8.dp))
                DarkButton(if (busy) "Checking the route…" else "Confirm pick-up", enabled = !busy) {
                    busy = true
                    scope.launch {
                        vm.setPickup(label, center)
                        // The fare follows the road from the pin to the drop, so work the distance out again from here.
                        if (dest != null) MapServices.route(center, dest.at ?: Geo.fromPercent(dest.x, dest.y))?.let { vm.setDestKm(it.km) }
                        busy = false; vm.requestRide()
                    }
                }
            }
        }
    }
}

@Composable
fun SearchingScreen(vm: BucksViewModel, onChangeType: () -> Unit) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val r = s.ride ?: return
    var cancel by remember { mutableStateOf(false) }
    val n = vm.onlineCount(r.kind)
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        // The 5 km circle the request rings within, with the riders of this kind that are in it.
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.pickupAt, "Pick-up", MeColor, true), pinAt(r.dest.latLng(), r.dest.name, MaterialTheme.status.bad)) + drivers.filter { it.online && it.vehicle == r.kind }.map { pinAt(it.pos, "", MaterialTheme.colorScheme.primary) },
                zoom = 13.0, circle = vm.pickupAt to 5000.0)
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            if (r.status == RideStatus.SEARCHING) {
                Row(verticalAlignment = Alignment.CenterVertically) { PulseRings(Modifier.size(56.dp)) { Icon(r.kind.icon, null, Modifier.size(26.dp).breathe(amount = 0.08f), tint = MaterialTheme.colorScheme.primary) }; Column(Modifier.padding(start = 12.dp)) { Text("Ringing $n rider${if (n > 1) "s" else ""}", style = MaterialTheme.typography.titleLarge); Muted("${r.kind.label} · within 5 km · first to accept gets the ride") } }
                BadButton("Cancel request", Modifier.padding(top = 14.dp)) { cancel = true }
            } else {
                Text("No rider accepted", style = MaterialTheme.typography.titleLarge); Muted(if (n > 0) "All nearby riders were busy. Try again or switch vehicle type." else "Nobody is online nearby.")
                PrimaryButton("Ring again", Modifier.padding(top = 14.dp)) { vm.requestRide() }; GhostButton("Change ride type", Modifier.padding(top = 10.dp), onClick = onChangeType)
            }
        }
    }
    if (cancel) RideCancelSheet(vm, null, false) { cancel = false }
}

@Composable
fun DriverFoundScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    val arrived = r.status == RideStatus.ARRIVED; var cancel by remember { mutableStateOf(false) }; val ctx = LocalContext.current
    val me = vm.mePos; val car = r.driverAt ?: Geo.fromPercent(r.driverX, r.driverY); val road = rememberRoadRoute(car, me)
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MaterialTheme.colorScheme.primary, true), pinAt(car, d.name.substringBefore(' '), MaterialTheme.status.good)), zoom = 15.0, route = road?.points ?: listOf(car, me)); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet { Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
            // The headline slides to the new status so "your rider is here" can't be missed.
            AnimatedContent(if (arrived) "Your rider is here" else "Pick-up in ${r.etaMin} min", Modifier.align(Alignment.CenterHorizontally), transitionSpec = {
                (slideInVertically(tween(Motion.MEDIUM, easing = Motion.Emphasized)) { it / 2 } + fadeIn(tween(Motion.MEDIUM))) togetherWith (slideOutVertically(tween(Motion.SHORT)) { -it / 2 } + fadeOut(tween(Motion.SHORT))) }, label = "rideHeadline") { t ->
                Text(t, style = MaterialTheme.typography.titleMedium, color = if (arrived) MaterialTheme.status.good else MaterialTheme.colorScheme.onSurface) }
            HorizontalDivider(Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.outline)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 44); Spacer(Modifier.height(4.dp)); TrustBadge(d.trust, compact = true) }
                Icon(d.vehicle.icon, null, Modifier.padding(start = 12.dp).size(44.dp))
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { r.pin.forEachIndexed { i, c -> Box(Modifier.size(26.dp).popIn(i).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Text("$c", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleSmall) } } }
                    Text(d.plate, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 6.dp)); Muted(d.model); Muted(d.name)
                }
            }
            Muted("Share this PIN with your rider when they arrive.", Modifier.padding(top = 6.dp))
            Box(Modifier.padding(vertical = 14.dp)) { MessageBar("Message your driver", onCall = { if (vm.cloud) { if (d.phone.isBlank()) showToast("${d.name.substringBefore(' ')}'s number isn't available yet. Try again in a moment.") else dial(ctx, d.phone) } else onCall(d.name, "+91 98450 12345") }) { if (vm.cloud) { if (d.phone.isBlank()) showToast("${d.name.substringBefore(' ')}'s number isn't available yet. Try again in a moment.") else sms(ctx, d.phone) } else onChatWith(d.name, "Rider") } }
            RoutePoints(s.user?.area ?: "Current location", r.dest.name) { Icon(Icons.Rounded.Share, "Share trip", Modifier.size(18.dp).clickable { if (vm.cloud) shareText(ctx, "I'm on a Bucks ride to ${r.dest.name} with ${d.name}, ${d.model} ${d.plate}.") else showToast("Live trip link copied") }) }
            Row(Modifier.padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text("Total fare", style = MaterialTheme.typography.titleMedium); Text("  ₹${r.fare}", style = MaterialTheme.typography.titleLarge) }
            // With Firebase the driver starts the trip once they've entered your PIN.
            if (arrived && !vm.cloud) DarkButton("Rider has my PIN · Start trip", Modifier.padding(bottom = 10.dp)) { vm.startTrip() }
            GhostButton("Cancel ride") { cancel = true }
        } }
    }
    if (cancel) RideCancelSheet(vm, d.name.substringBefore(' '), arrived) { cancel = false }
}

/** The reason sheet for cancelling a ride. While nobody has accepted no reason is needed; once a driver did, one is required and the driver is told why. */
@Composable
private fun RideCancelSheet(vm: BucksViewModel, driverName: String?, arrived: Boolean, onClose: () -> Unit) {
    var busy by remember { mutableStateOf(false) }
    var stats by remember { mutableStateOf<CancelStats?>(null) }
    LaunchedEffect(Unit) { if (vm.cloud && driverName != null) stats = runCatching { Backend.myCancelStats() }.getOrNull() }
    val n = stats?.riderDay ?: 0
    CancelSheet(
        title = if (driverName == null) "Cancel the request?" else "Cancel this ride?",
        message = when { driverName == null -> "No driver has accepted yet, so nothing is charged."; arrived -> "$driverName is waiting at your pickup. Cancelling wastes their trip."; else -> "$driverName is already on the way to you." },
        reasons = CancelReasons.rider, requireReason = driverName != null, confirmLabel = if (driverName == null) "Cancel request" else "Cancel ride",
        keepLabel = if (driverName == null) "Keep waiting" else "Keep ride",
        nudge = if (n >= 2) "You've cancelled $n rides after a driver accepted today. Drivers lose time and fuel when that happens." else null, busy = busy,
        onConfirm = { code, note -> busy = true; vm.cancelRide(code, note) { ok -> busy = false; if (ok) onClose() } }, onDismiss = onClose)
}

@Composable
fun InRideScreen(vm: BucksViewModel, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return; val ctx = LocalContext.current
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        val car = r.driverAt ?: Geo.fromPercent(r.driverX, r.driverY); val road = rememberRoadRoute(car, r.dest.latLng())
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(r.dest.latLng(), r.dest.name, MaterialTheme.status.bad), pinAt(car, "You", MaterialTheme.status.good, true)), zoom = 15.0, route = road?.points ?: listOf(car, r.dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Text("On the way to ${r.dest.name}", style = MaterialTheme.typography.titleLarge)
            Muted("${"%.1f".format((1 - r.progress) * r.dest.km)} km left · ${d.name} · ${d.plate}")
            LinearProgressIndicator(progress = { r.progress }, modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp).height(6.dp).clip(CircleShape), trackColor = MaterialTheme.colorScheme.surfaceContainerHigh)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) { IconAction(Icons.Rounded.Sos, "SOS") { if (vm.cloud) dial(ctx, "112") else showToast("Emergency contacts notified with live location") }; IconAction(Icons.Rounded.Share, "Share trip") { if (vm.cloud) shareText(ctx, "I'm on a Bucks ride to ${r.dest.name} with ${d.name}, ${d.model} ${d.plate}.") else showToast("Live trip link copied") } }
        }
    }
}

@Composable
fun PayScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.popIn()) { Avatar(icon = Icons.Rounded.Flag, size = 64) }
            Headline("Arrived at ${r.dest.name}", Modifier.padding(top = 16.dp)); Muted("${r.dest.km} km with ${d.name}", align = TextAlign.Center)
            BucksCard(Modifier.padding(vertical = 22.dp), tint = true) { Muted("Total payable", Modifier.align(Alignment.CenterHorizontally)); Text("₹${animatedInt(r.fare)}", style = MaterialTheme.typography.displaySmall, modifier = Modifier.align(Alignment.CenterHorizontally)) }
            if (vm.dispatch.enabled) CloudPayPanel(vm, r, d)
            else Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { DarkButton("Pay cash") { vm.payRide("Cash") }; GhostButton("Google Pay") { vm.payRide("Google Pay") }; GhostButton("Amazon Pay") { vm.payRide("Amazon Pay") }; GhostButton("Scan rider's QR") { vm.payRide("Rider QR") } }
        }
    }
}

/** Cloud ride: pay through the driver's UPI QR (their app opens with the fare filled in) or hand over cash; both tell the driver. */
@Composable
private fun CloudPayPanel(vm: BucksViewModel, r: Ride, d: Driver) {
    val ctx = LocalContext.current
    var contact by remember(r.id) { mutableStateOf<ContactRow?>(null) }; var loaded by remember(r.id) { mutableStateOf(false) }; var upiOpened by remember(r.id) { mutableStateOf(false) }
    var confirmCash by remember { mutableStateOf(false) }
    LaunchedEffect(r.id) { contact = runCatching { vm.dispatch.contact(r.id) }.getOrNull(); loaded = true }
    val upi = contact?.upiUri?.takeIf { it.startsWith("upi://pay", ignoreCase = true) }
    val first = d.name.substringBefore(' ')
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when {
            !loaded -> Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp); Muted("  Checking how $first takes payments") }
            upi == null -> Notice("$first hasn't added a UPI QR yet. Pay ₹${r.fare} in cash.")
            else -> {
                upiPayee(upi)?.let { (pn, pa) -> Muted("UPI goes to $pn ($pa)", align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                DarkButton(if (upiOpened) "Open UPI app again" else "Pay ₹${r.fare} by UPI") {
                    val link = upiPayLink(upi, r.fare, "Bucks ride")
                    val ok = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }.isSuccess
                    if (ok) upiOpened = true else vm.toast("No UPI app found on this phone. Pay in cash instead.")
                }
                if (upiOpened) PrimaryButton("Done · I paid ₹${r.fare} by UPI") { vm.payRide("UPI") }
            }
        }
        if (loaded) GhostButton("Paid in cash") { confirmCash = true }
        Muted("Only tap after you've paid. Your rider sees what you chose.", align = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
    if (confirmCash) AlertDialog(onDismissRequest = { confirmCash = false }, title = { Text("Paid ₹${r.fare} in cash?") }, text = { Text("$first will be told you paid in cash.") },
        confirmButton = { TextButton({ confirmCash = false; vm.payRide("Cash") }) { Text("Yes, paid") } }, dismissButton = { TextButton({ confirmCash = false }) { Text("Not yet") } })
}

@Composable
fun RateRideScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    var vote by remember { mutableStateOf<Int?>(null) }; var comment by remember { mutableStateOf("") }; var reason by remember { mutableStateOf<String?>(null) }
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).padding(top = 24.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 76); Headline("How was ${d.name.substringBefore(' ')}?", Modifier.padding(top = 12.dp)); Muted("Paid ₹${r.fare} by ${r.paidWith}. Your review decides who gets the next ride.", align = TextAlign.Center) }
            Row(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalArrangement = Arrangement.Center) { VoteArrow(true, vote == 1, Modifier.width(96.dp)) { vote = 1 }; Spacer(Modifier.width(12.dp)); VoteArrow(false, vote == -1, Modifier.width(96.dp)) { vote = -1 } }
            if (vote == -1) { Text("What went wrong?", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(bottom = 6.dp)); ReasonChips(reason) { reason = it }; Spacer(Modifier.height(10.dp)) }
            BucksField(comment, { comment = it.take(500) }, "Tell us more (optional)", if (vote == -1) "What happened" else "Safe riding, on time", singleLine = false, minLines = 2)
            PrimaryButton("Post") { vm.finishRide(vote, comment, false, reason) }
            TextButton(onClick = { vm.finishRide(null, "", true) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text("Skip for now") }
        }
    }
}
