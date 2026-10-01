package com.bucks.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
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
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.payWord
import com.bucks.app.ui.dial
import com.bucks.app.ui.sms
import com.bucks.app.ui.shareText
import com.bucks.app.ui.upiPayLink
import com.bucks.app.ui.upiPayee
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status

/**
 * Shown while a booking can't start because Bucks has no position for the rider (permission off, location switched off, or no fix yet):
 * says which, and [onEnable] asks for the permission, opens the phone's location switch, or looks again. Never booked from the map's default centre.
 */
@Composable
fun LocationNotice(onEnable: () -> Unit, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current; var tick by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { tick++ }
    val perm = remember(tick) { Here.hasPermission(ctx) }; val on = remember(tick) { Here.switchedOn(ctx) }
    Column(modifier.fillMaxWidth()) {
        Notice(when { !perm -> "Bucks can't see where you are: location permission is off. Your rider needs your exact pick-up point."; !on -> "Location is switched off on this phone. Turn it on so your rider can find you."
                      else -> "Bucks hasn't found your position yet. Step outside or check your GPS signal, then try again." })
        SmallButton(if (perm && on) "Try again" else "Turn on location", Modifier.padding(top = 8.dp), onClick = onEnable)
    }
}

/** "Pick-up in 4 min" / "under a minute"; null when the rider's position isn't known yet (a negative estimate). */
fun etaText(min: Int): String? = when { min < 0 -> null; min == 0 -> "under a minute"; else -> "$min min" }

@Composable
fun DestinationScreen(vm: BucksViewModel, onBack: () -> Unit, onChosen: () -> Unit, onEnableLocation: () -> Unit = {}) {
    val s by vm.state.collectAsState(); var f by remember { mutableStateOf("") }; var picked by remember { mutableStateOf<String?>(null) }
    var savedOpen by remember { mutableStateOf(false) }; var onMap by remember { mutableStateOf(false) }; var center by remember { mutableStateOf<LatLng?>(null) }
    val me = vm.mePos
    // Without a real position the distance to anywhere would be measured from the map's default centre, so the booking waits for one.
    val noFix = vm.dispatch.enabled && s.me == null
    // Back leaves the map picker first, not the whole screen.
    BackHandler(enabled = onMap) { onMap = false }
    if (onMap) { Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MeColor, true)), zoom = 14.0, onCenter = { center = it })
        Icon(Icons.Rounded.LocationOn, "Destination", Modifier.align(Alignment.Center).padding(bottom = 36.dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
        IconButton({ onMap = false }, Modifier.padding(12.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            MapAttribution(Modifier.align(Alignment.End).padding(8.dp))
            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(20.dp)) {
                Muted("Drag the map to place the pin", Modifier.padding(bottom = 10.dp)); DarkButton("Set destination here", enabled = center != null && !noFix) { center?.let { vm.chooseDestAt(it); picked = s.rideDest?.name; onMap = false; onChosen() } } } }
    }; return }
    val places = Geo.PLACES.keys.filter { it.contains(f, ignoreCase = true) }
    // Anywhere in the map's address data, nearest first; the built-in list above stays for offline and quick picks.
    var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var pickedHit by remember { mutableStateOf<MapServices.PlaceHit?>(null) }
    LaunchedEffect(f) { if (f.trim().length < 3 || f == picked) { hits = emptyList(); return@LaunchedEffect }; kotlinx.coroutines.delay(350); searching = true; hits = MapServices.search(f, me); searching = false }
    Column(Modifier.fillMaxSize().imePadding()) {
        IconButton(onBack, Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 14.dp, vertical = 6.dp)) {
            // The pick-up is where the phone is now, named from the map when it can be, never the area in the profile.
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.good)); Text(if (noFix) "Waiting for your location" else s.hereLabel?.let { "Current location · $it" } ?: "Current location", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 12.dp), maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Rounded.MyLocation, if (noFix) "Location not found yet" else "Using current location", Modifier.size(18.dp)) }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.bad))
                BasicTextField(f, { f = it; picked = null; pickedHit = null }, Modifier.weight(1f).padding(start = 12.dp), singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    decorationBox = { inner -> Box { if (f.isEmpty()) Muted("Enter destination"); inner() } }) }
        }
        if (noFix) LocationNotice(onEnableLocation, Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
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
        DarkButton("Confirm", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), enabled = (picked != null || pickedHit != null) && !noFix) {
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
    val dest = s.rideDest ?: return; val me = vm.mePos
    // The road route: its line on the map, and its distance for the fare (straight line until it arrives or when offline).
    val road = rememberRoadRoute(me, dest.latLng())
    LaunchedEffect(road) { road?.let { vm.setDestKm(it.km) } }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MeColor, true), pinAt(dest.latLng(), dest.name, MaterialTheme.colorScheme.primary)) + drivers.filter { it.online }.map { pinAt(it.pos, "", MaterialTheme.status.good) }, route = road?.points ?: listOf(me, dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Box(Modifier.fillMaxWidth()) { IconButton(onBack, Modifier.align(Alignment.CenterStart).size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }; Text("Choose vehicle", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.Center)) }
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                VehicleKind.PASSENGER.forEach { k -> val nearest = Geo.ring(me, drivers, k).firstOrNull(); val on = s.rideKind == k; val f = vm.fare(k, dest.km)
                    val away = nearest?.let { maxOf(1, (it.distanceKm * 2.5).toInt()) }; val eta = away?.let { HHMM.format(java.util.Date(System.currentTimeMillis() + (it + dest.km * 3).toLong() * 60_000)).lowercase() }
                    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).border(if (on) 2.dp else 0.dp, if (on) MaterialTheme.colorScheme.primary else Color.Transparent, MaterialTheme.shapes.small).clickable(enabled = nearest != null) { vm.setRideKind(k) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(k.icon, null, Modifier.size(40.dp), tint = if (nearest != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(k.label, style = MaterialTheme.typography.titleSmall)
                            Muted(if (away != null) "$away ${if (away == 1) "min" else "mins"} away · ETA $eta" else "No riders online nearby"); Muted("Max ${when (k) { VehicleKind.BIKE -> 1; VehicleKind.AUTO -> 3; VehicleKind.CAB -> 4 }} · ₹${k.farePerKm}/per km") }
                        Text("₹$f–${(f * 1.15).toInt()}", style = MaterialTheme.typography.titleSmall)
                    } }
            }
            // Fares are estimates until the server prices the trip; a trip the server would refuse is stopped here with the reason.
            val problem = vm.bookingProblem(dest)
            if (problem != null) Notice(problem, Modifier.padding(top = 12.dp)) else Muted("Fares are estimates. Bucks sets the final fare from the distance when you book.", Modifier.padding(top = 10.dp))
            DarkButton("Confirm", Modifier.padding(top = 14.dp), enabled = problem == null && vm.onlineCount(s.rideKind) > 0, onClick = onConfirm)
        }
    }
}

@Composable
fun ConfirmPickupScreen(vm: BucksViewModel, onBack: () -> Unit, onEnableLocation: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val me = vm.mePos; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val cloud = vm.dispatch.enabled
    var checking by remember { mutableStateOf(false) }; var noFix by remember { mutableStateOf(false) }
    LaunchedEffect(s.me) { if (s.me != null) noFix = false }
    val waiting = cloud && s.me == null
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "Pick-up", MaterialTheme.colorScheme.primary, true)), zoom = 15.0, circle = me to 500.0); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onBack, Modifier.size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }; Text("Confirm pick-up location", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 12.dp)) }
            // The pick-up is where the phone is right now; it is looked up again when you tap, and the name is the map's, never the profile's area.
            Muted(if (waiting) "Finding where you are…" else "${s.hereLabel ?: "Your current location"} · nearby riders are rung; the first to accept comes here.", Modifier.padding(vertical = 12.dp))
            if (noFix || waiting) LocationNotice(onEnableLocation, Modifier.padding(bottom = 12.dp))
            DarkButton(if (checking) "Finding you…" else "Confirm pick-up", enabled = !checking && !vm.dispatch.busy) {
                if (!cloud) { vm.requestRide(); return@DarkButton }
                // ensureActive: leaving the screen during the lookup must not pop the booking sheet up over wherever the rider went.
                scope.launch { checking = true
                    try { val ok = vm.refreshLocation(ctx); ensureActive(); if (ok) { noFix = false; vm.requestRide() } else noFix = true } finally { checking = false } }
            }
        }
    }
}

@Composable
fun SearchingScreen(vm: BucksViewModel, onChangeType: () -> Unit, onBack: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val r = s.ride ?: return
    val n = vm.onlineCount(r.kind); val cancelling = vm.dispatch.cancelling
    var ask by remember { mutableStateOf(false) }
    // Back while searching asks first (leaving would leave the request ringing); once nobody took it, Back just leaves.
    BackHandler(enabled = r.status == RideStatus.SEARCHING) { ask = true }
    BackHandler(enabled = r.status == RideStatus.NO_DRIVER) { vm.dismissEndedRide(); onBack() }
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        // The 5 km circle the request rings within, with the riders of this kind that are in it.
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.mePos, "You", MeColor, true), pinAt(r.dest.latLng(), r.dest.name, MaterialTheme.status.bad)) + drivers.filter { it.online && it.vehicle == r.kind }.map { pinAt(it.pos, "", MaterialTheme.colorScheme.primary) },
                zoom = 13.0, circle = vm.mePos to 5000.0)
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            if (r.status == RideStatus.SEARCHING) {
                Row(verticalAlignment = Alignment.CenterVertically) { PulseRings(Modifier.size(56.dp)) { Icon(r.kind.icon, null, Modifier.size(26.dp).breathe(amount = 0.08f), tint = MaterialTheme.colorScheme.primary) }; Column(Modifier.padding(start = 12.dp)) { Text("Looking for nearby ${r.kind.label.lowercase()} riders", style = MaterialTheme.typography.titleLarge); Muted("${r.kind.label} · riders nearby are rung · first to accept gets the ride") } }
                BadButton(if (cancelling) "Cancelling…" else "Cancel request", Modifier.padding(top = 14.dp), enabled = !cancelling) { vm.cancelRide("Changed my mind") }
            } else {
                Text("No rider accepted", style = MaterialTheme.typography.titleLarge); Muted(if (n > 0) "All nearby riders were busy. Try again or switch vehicle type." else "Nobody is online nearby.")
                PrimaryButton("Ring again", Modifier.padding(top = 14.dp)) { vm.requestRide() }; GhostButton("Change ride type", Modifier.padding(top = 10.dp), onClick = onChangeType)
            }
        }
    }
    if (ask) AlertDialog(onDismissRequest = { ask = false }, title = { Text("Cancel this ride request?") }, text = { Text("Riders nearby will stop being rung. You can book again any time.") },
        confirmButton = { TextButton({ ask = false; vm.cancelRide("Changed my mind") }, enabled = !cancelling) { Text("Cancel ride", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ ask = false }) { Text("Keep searching") } })
}

@Composable
fun DriverFoundScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    val arrived = r.status == RideStatus.ARRIVED; var cancel by remember { mutableStateOf(false) }; val ctx = LocalContext.current; val cancelling = vm.dispatch.cancelling
    val me = vm.mePos; val car = r.driverAt ?: Geo.fromPercent(r.driverX, r.driverY); val road = rememberRoadRoute(car, me)
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MaterialTheme.colorScheme.primary, true), pinAt(car, d.name.substringBefore(' '), MaterialTheme.status.good)), zoom = 15.0, route = road?.points ?: listOf(car, me)); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet { Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
            // The headline slides to the new status so "your rider is here" can't be missed.
            AnimatedContent(if (arrived) "Your rider is here" else etaText(r.etaMin)?.let { "Pick-up in $it" } ?: "Your rider is on the way", Modifier.align(Alignment.CenterHorizontally), transitionSpec = {
                (slideInVertically(tween(Motion.MEDIUM, easing = Motion.Emphasized)) { it / 2 } + fadeIn(tween(Motion.MEDIUM))) togetherWith (slideOutVertically(tween(Motion.SHORT)) { -it / 2 } + fadeOut(tween(Motion.SHORT))) }, label = "rideHeadline") { t ->
                Text(t, style = MaterialTheme.typography.titleMedium, color = if (arrived) MaterialTheme.status.good else MaterialTheme.colorScheme.onSurface) }
            HorizontalDivider(Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.outline)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 44); Spacer(Modifier.height(4.dp)); TrustBadge(d.trust, compact = true) }
                Icon(d.vehicle.icon, null, Modifier.padding(start = 12.dp).size(44.dp))
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { r.pin.forEachIndexed { i, c -> Box(Modifier.defaultMinSize(26.dp, 26.dp).popIn(i).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary).padding(horizontal = 3.dp), contentAlignment = Alignment.Center) { Text("$c", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleSmall) } } }
                    Text(d.plate, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 6.dp)); Muted(d.model); Muted(d.name)
                }
            }
            Muted("Share this PIN with your rider when they arrive.", Modifier.padding(top = 6.dp))
            Box(Modifier.padding(vertical = 14.dp)) { MessageBar("Message your driver", onCall = { if (vm.cloud) { if (d.phone.isBlank()) showToast("${d.name.substringBefore(' ')}'s number isn't available yet. Try again in a moment.") else dial(ctx, d.phone) } else onCall(d.name, "+91 98450 12345") }) { if (vm.cloud) { if (d.phone.isBlank()) showToast("${d.name.substringBefore(' ')}'s number isn't available yet. Try again in a moment.") else sms(ctx, d.phone) } else onChatWith(d.name, "Rider") } }
            RoutePoints(r.pickupLabel.ifBlank { "Pick-up point" }, r.dest.name) { IconButton({ if (vm.cloud) shareText(ctx, "I'm on a Bucks ride to ${r.dest.name} with ${d.name}, ${d.model} ${d.plate}.") else showToast("Live trip link copied") }) { Icon(Icons.Rounded.Share, "Share trip", Modifier.size(20.dp)) } }
            Row(Modifier.padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text("Total fare", style = MaterialTheme.typography.titleMedium); Text("  ₹${r.fare}", style = MaterialTheme.typography.titleLarge) }
            // With Firebase the driver starts the trip once they've entered your PIN.
            if (arrived && !vm.cloud) DarkButton("Rider has my PIN · Start trip", Modifier.padding(bottom = 10.dp)) { vm.startTrip() }
            GhostButton(if (cancelling) "Cancelling…" else "Cancel ride", enabled = !cancelling) { cancel = true }
        } }
    }
    if (cancel) Dialog(onDismissRequest = { cancel = false }) { Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surface) { Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Text("!", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleLarge) }
        Text("Cancel ride", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp)); Muted("${d.name.substringBefore(' ')} is already on the way. Cancel anyway?", Modifier.padding(top = 4.dp), TextAlign.Center)
        Button({ cancel = false; vm.cancelRide("Cancelled by rider") }, Modifier.fillMaxWidth().padding(top = 16.dp), enabled = !cancelling, shape = MaterialTheme.shapes.small) { Text("Cancel ride") }
        TextButton({ cancel = false }) { Text("Keep ride") }
    } } }
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

/**
 * Cloud ride: pay through the driver's UPI QR (their app opens with the fare filled in) or hand over cash; both tell the driver.
 * "Done · I paid" only appears once the rider has been to their UPI app and come back to Bucks, or chose cash: Bucks can't see the
 * payment itself, so the least it can do is not offer the confirmation before the rider has even tried.
 */
@Composable
private fun CloudPayPanel(vm: BucksViewModel, r: Ride, d: Driver) {
    val ctx = LocalContext.current; val paying = vm.dispatch.paying
    var contact by remember(r.id) { mutableStateOf<ContactRow?>(null) }; var loaded by remember(r.id) { mutableStateOf(false) }; var upiOpened by remember(r.id) { mutableStateOf(false) }
    var away by remember(r.id) { mutableStateOf(false) }; var returned by remember(r.id) { mutableStateOf(false) }
    var confirmCash by remember { mutableStateOf(false) }
    LaunchedEffect(r.id) { contact = runCatching { vm.dispatch.contact(r.id) }.getOrNull(); loaded = true }
    // Leaving Bucks for the UPI app and coming back is what "returned" means. Pause/resume, not stop/start: some UPI apps open as a
    // see-through screen over Bucks, which pauses it without ever stopping it.
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { if (upiOpened) away = true }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (away) returned = true }
    val upi = contact?.upiUri?.takeIf { it.startsWith("upi://pay", ignoreCase = true) }
    val first = d.name.substringBefore(' ')
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when {
            !loaded -> Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp); Muted("  Checking how $first takes payments") }
            upi == null -> Notice("$first hasn't added a UPI QR yet. Pay ₹${r.fare} in cash.")
            else -> {
                upiPayee(upi)?.let { (pn, pa) -> Muted("UPI goes to $pn ($pa)", align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                DarkButton(if (upiOpened) "Open UPI app again" else "Pay ₹${r.fare} by UPI", enabled = !paying) {
                    val link = upiPayLink(upi, r.fare, "Bucks ride")
                    val ok = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }.isSuccess
                    if (ok) { upiOpened = true; away = false; returned = false } else vm.toast("No UPI app found on this phone. Pay in cash instead.")
                }
                if (upiOpened && !returned) Muted("Finish the payment in your UPI app, then come back here to confirm.", align = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                if (upiOpened && returned) PrimaryButton(if (paying) "Saving…" else "Done · I paid ₹${r.fare} by UPI", enabled = !paying) { vm.payRide("UPI") }
            }
        }
        if (loaded) GhostButton(if (paying) "Saving…" else "Paid in cash", enabled = !paying) { confirmCash = true }
        Muted("Only tap after you've paid. Your rider sees what you chose; Bucks can't check it.", align = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
    if (confirmCash) AlertDialog(onDismissRequest = { confirmCash = false }, title = { Text("Paid ₹${r.fare} in cash?") }, text = { Text("$first will be told you paid in cash.") },
        confirmButton = { TextButton({ confirmCash = false; vm.payRide("CASH") }) { Text("Yes, paid") } }, dismissButton = { TextButton({ confirmCash = false }) { Text("Not yet") } })
}

@Composable
fun RateRideScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    var vote by remember { mutableStateOf<Int?>(null) }; var comment by remember { mutableStateOf("") }
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).imePadding().padding(20.dp).padding(top = 24.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 76); Headline("How was ${d.name.substringBefore(' ')}?", Modifier.padding(top = 12.dp)); Muted("Paid ₹${r.fare} by ${payWord(r.paidWith)}.", align = TextAlign.Center) }
            Row(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalArrangement = Arrangement.Center) { VoteButton("Recommend", vote == 1, true) { vote = 1 }; Spacer(Modifier.width(10.dp)); VoteButton("Not recommended", vote == -1, false) { vote = -1 } }
            BucksField(comment, { comment = it }, "One line on why", "Safe riding, on time", singleLine = false, minLines = 2)
            PrimaryButton("Post review") { vm.finishRide(vote, comment, false) }
            TextButton(onClick = { vm.finishRide(null, "", true) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text("Skip for now") }
        }
    }
}
