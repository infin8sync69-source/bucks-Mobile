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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import androidx.compose.foundation.shape.RoundedCornerShape
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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
        Notice(when { !perm -> stringResource(R.string.g4_ride_loc_perm_off); !on -> stringResource(R.string.g4_ride_loc_switched_off)
                      else -> stringResource(R.string.g4_ride_loc_no_fix) })
        SmallButton(if (perm && on) stringResource(R.string.g4_try_again) else stringResource(R.string.g4_ride_turn_on_location), Modifier.padding(top = 8.dp), onClick = onEnable)
    }
}

/** "Pick-up in 4 min" / "under a minute"; null when the rider's position isn't known yet (a negative estimate). */
fun etaText(min: Int): String? = when { min < 0 -> null; min == 0 -> Str.get(R.string.g4_ride_eta_under_minute); else -> Str.get(R.string.g4_ride_eta_min, min) }

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
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, stringResource(R.string.g4_ride_pin_you), MeColor, true)), zoom = 14.0, onCenter = { center = it })
        Icon(Icons.Rounded.LocationOn, stringResource(R.string.g4_ride_destination), Modifier.align(Alignment.Center).padding(bottom = 36.dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
        IconButton({ onMap = false }, Modifier.padding(12.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g4_cd_back)) }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            MapAttribution(Modifier.align(Alignment.End).padding(8.dp))
            Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(20.dp)) {
                Muted(stringResource(R.string.g4_ride_drag_pin), Modifier.padding(bottom = 10.dp)); DarkButton(stringResource(R.string.g4_ride_set_destination), enabled = center != null && !noFix) { center?.let { vm.chooseDestAt(it); picked = s.rideDest?.name; onMap = false; onChosen() } } } }
    }; return }
    val places = Geo.PLACES.keys.filter { it.contains(f, ignoreCase = true) }
    // Anywhere in the map's address data, nearest first; the built-in list above stays for offline and quick picks.
    var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var pickedHit by remember { mutableStateOf<MapServices.PlaceHit?>(null) }
    LaunchedEffect(f) { if (f.trim().length < 3 || f == picked) { hits = emptyList(); return@LaunchedEffect }; kotlinx.coroutines.delay(350); searching = true; hits = MapServices.search(f, me); searching = false }
    Column(Modifier.fillMaxSize().imePadding()) {
        IconButton(onBack, Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g4_cd_back)) }
        Column(Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 14.dp, vertical = 6.dp)) {
            // The pick-up is where the phone is now, named from the map when it can be, never the area in the profile.
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.good)); Text(if (noFix) stringResource(R.string.g4_ride_waiting_location) else s.hereLabel?.let { stringResource(R.string.g4_ride_current_location_named, it) } ?: stringResource(R.string.g4_loc_current), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 12.dp), maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Rounded.MyLocation, if (noFix) stringResource(R.string.g4_ride_location_not_found) else stringResource(R.string.g4_ride_using_current), Modifier.size(18.dp)) }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.bad))
                BasicTextField(f, { f = it; picked = null; pickedHit = null }, Modifier.weight(1f).padding(start = 12.dp), singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    decorationBox = { inner -> Box { if (f.isEmpty()) Muted(stringResource(R.string.g4_ride_enter_destination)); inner() } }) }
        }
        if (noFix) LocationNotice(onEnableLocation, Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            if (hits.isNotEmpty() || searching) {
                Text(stringResource(R.string.g4_ride_places), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
                if (searching && hits.isEmpty()) Muted(stringResource(R.string.g4_ride_searching_map), Modifier.padding(vertical = 8.dp))
                hits.forEach { h -> HitRow(h, Geo.distanceKm(me, h.at), selected = pickedHit == h) { pickedHit = h; picked = null } }
            }
            if (places.isNotEmpty()) Text(if (f.isBlank()) stringResource(R.string.g4_ride_frequent) else stringResource(R.string.g4_ride_matches), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
            places.forEach { name -> PlaceRow(name, Geo.distanceKm(me, Geo.PLACES.getValue(name)), saved = name in s.savedPlaces, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; pickedHit = null; f = name } }
            if (places.isEmpty() && hits.isEmpty() && !searching && f.trim().length >= 3) Muted(stringResource(R.string.g4_ride_no_place), Modifier.padding(vertical = 12.dp))
            Row(Modifier.fillMaxWidth().clickable { savedOpen = !savedOpen }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Star, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary); Text(stringResource(R.string.g4_ride_saved_places), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 10.dp)); Icon(if (savedOpen) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, null) }
            if (savedOpen) { if (s.savedPlaces.isEmpty()) Muted(stringResource(R.string.g4_ride_star_to_save), Modifier.padding(bottom = 8.dp)); s.savedPlaces.forEach { name -> Geo.PLACES[name]?.let { ll -> PlaceRow(name, Geo.distanceKm(me, ll), saved = true, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; f = name } } } }
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(vertical = 10.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { onMap = true }.padding(horizontal = 18.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" " + stringResource(R.string.g4_ride_select_on_map)) }
        DarkButton(stringResource(R.string.g4_confirm), Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), enabled = (picked != null || pickedHit != null) && !noFix) {
            pickedHit?.let { vm.chooseDestPlace(it.name, it.at); onChosen() } ?: picked?.let { vm.chooseDest(it); onChosen() } }
    }
}

@Composable
private fun PlaceRow(name: String, km: Double, saved: Boolean, selected: Boolean, onStar: () -> Unit, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.LocationOn, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) { Text(name.substringBefore(","), style = MaterialTheme.typography.bodyMedium); Muted(stringResource(R.string.g4_ride_place_km_away, name, "%.1f".format(km)), maxLines = 1) }
        IconButton(onStar, Modifier.size(32.dp)) { Icon(if (saved) Icons.Filled.Star else Icons.Rounded.StarOutline, if (saved) stringResource(R.string.g4_ride_unsave) else stringResource(R.string.g4_ride_save_place), tint = if (saved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun HitRow(h: MapServices.PlaceHit, km: Double, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.LocationOn, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) { Text(h.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(listOf(placeDetail(h), stringResource(R.string.g4_ride_km_away, "%.1f".format(km))).filter { it.isNotBlank() }.joinToString(" · "), maxLines = 1) }
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
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, if (s.ridePickup != null) stringResource(R.string.g4_ride_pickup) else stringResource(R.string.g4_ride_pin_you), MeColor, true), pinAt(dest.latLng(), dest.name, MaterialTheme.colorScheme.primary)) + drivers.filter { it.online }.map { pinAt(it.pos, "", MaterialTheme.status.good) }, route = road?.points ?: listOf(me, dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Box(Modifier.fillMaxWidth()) { IconButton(onBack, Modifier.align(Alignment.CenterStart).size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g4_cd_back)) }; Text(stringResource(R.string.g4_ride_choose_vehicle), style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.Center)) }
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                VehicleKind.PASSENGER.forEach { k -> val nearest = Geo.ring(me, drivers, k).firstOrNull(); val on = s.rideKind == k; val f = vm.fare(k, dest.km)
                    val away = nearest?.let { maxOf(1, (it.distanceKm * 2.5).toInt()) }; val eta = away?.let { HHMM.format(java.util.Date(System.currentTimeMillis() + (it + dest.km * 3).toLong() * 60_000)).lowercase() }
                    Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).border(if (on) 2.dp else 0.dp, if (on) MaterialTheme.colorScheme.primary else Color.Transparent, MaterialTheme.shapes.small).clickable(enabled = nearest != null) { vm.setRideKind(k) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(k.icon, null, Modifier.size(40.dp), tint = if (nearest != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(k.label, style = MaterialTheme.typography.titleSmall)
                            Muted(if (away != null) pluralStringResource(R.plurals.g4_ride_mins_away_eta, away, away, eta.orEmpty()) else stringResource(R.string.g4_ride_no_riders)); Muted(stringResource(R.string.g4_ride_max_seats_fare, when (k) { VehicleKind.BIKE -> 1; VehicleKind.AUTO -> 3; VehicleKind.CAB -> 4 }, Money.format(k.farePerKm))) }
                        Text(stringResource(R.string.g4_ride_fare_range, Money.format(f), Money.format((f * 1.15).toInt())), style = MaterialTheme.typography.titleSmall)
                    } }
            }
            // Fares are estimates until the server prices the trip; a trip the server would refuse is stopped here with the reason.
            val problem = vm.bookingProblem(dest)
            if (problem != null) Notice(problem, Modifier.padding(top = 12.dp)) else Muted(stringResource(R.string.g4_ride_fare_estimate), Modifier.padding(top = 10.dp))
            DarkButton(stringResource(R.string.g4_confirm), Modifier.padding(top = 14.dp), enabled = problem == null && vm.onlineCount(s.rideKind) > 0, onClick = onConfirm)
        }
    }
}

/**
 * Confirm (and move) the pick-up: drag the map so the pin sits where the rider should come, or search a place; the address under the pin updates.
 * "Use my location" snaps back to where I am. The fare is worked out again from the pin when it moved.
 */
@Composable
fun ConfirmPickupScreen(vm: BucksViewModel, onBack: () -> Unit, onEnableLocation: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val cmds = remember { MapCommands() }; val scope = rememberCoroutineScope(); val ctx = LocalContext.current
    val cloud = vm.dispatch.enabled
    val start = vm.pickupAt; val dest = s.rideDest
    var center by remember { mutableStateOf(start) }
    // The name is the map's (the street under the pin), never the profile's area.
    val yourLocation = stringResource(R.string.g4_ride_your_location)
    var label by remember { mutableStateOf(s.ridePickup?.name ?: s.hereLabel ?: yourLocation) }
    var q by remember { mutableStateOf("") }; var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var busy by remember { mutableStateOf(false) }
    // chosen: the rider picked a searched place (or came back with a pick-up already set). noFix: the last lookup of where the phone is failed.
    var chosen by remember { mutableStateOf(s.ridePickup != null) }; var noFix by remember { mutableStateOf(false) }
    val waiting = cloud && s.me == null
    LaunchedEffect(Unit) { delay(300); cmds.moveTo(start, 16.0) }
    // The first fix arrived while the pin still sat on the map's default centre: put the pin where the phone is.
    LaunchedEffect(s.me != null) { if (s.me != null) { noFix = false; if (!chosen && s.ridePickup == null) cmds.moveTo(vm.mePos, 16.0) } }
    // The street name under the pin, a moment after the map stops moving.
    LaunchedEffect(center) { delay(700); MapServices.label(center)?.let { label = it } }
    LaunchedEffect(q) { if (q.trim().length < 3) { hits = emptyList(); return@LaunchedEffect }; delay(450); hits = MapServices.search(q, center).take(5) }
    val movedM = Geo.distanceKm(center, vm.mePos) * 1000
    val moved = chosen || movedM > 50
    Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.mePos, stringResource(R.string.g4_ride_pin_you), MeColor, true)), zoom = 16.0, commands = cmds, onCenter = { center = it })
        // The pin stays in the middle; the map moves under it.
        Icon(Icons.Rounded.LocationOn, stringResource(R.string.g4_ride_pickup), Modifier.align(Alignment.Center).offset(y = (-20).dp).size(44.dp), tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
            Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g4_cd_back)) }
                    OutlinedTextField(q, { q = it }, placeholder = { Text(stringResource(R.string.g4_ride_search_pickup)) }, singleLine = true, modifier = Modifier.weight(1f),
                        colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = Color.Transparent, focusedBorderColor = Color.Transparent))
                    if (q.isNotEmpty()) IconButton({ q = ""; hits = emptyList() }) { Icon(Icons.Rounded.Close, stringResource(R.string.g4_cd_clear)) }
                }
            }
            if (hits.isNotEmpty()) Surface(Modifier.padding(top = 6.dp), shape = RoundedCornerShape(20.dp), shadowElevation = 6.dp, color = MaterialTheme.colorScheme.surface) {
                Column { hits.forEach { h -> HitRow(h, Geo.distanceKm(vm.mePos, h.at), false) { q = ""; hits = emptyList(); label = h.name; center = h.at; chosen = true; cmds.moveTo(h.at, 16.0) } } }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Spacer(Modifier.weight(1f))
                Surface(shape = CircleShape, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface, modifier = Modifier.size(48.dp).clickable { chosen = false; cmds.moveTo(vm.mePos, 16.0) }) { Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.MyLocation, stringResource(R.string.g4_loc_use_current)) } }
            }
            Row(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { MapAttribution() }
            Sheet {
                Text(stringResource(R.string.g4_ride_pickup), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(if (waiting && !moved) stringResource(R.string.g4_ride_finding_you) else label, style = MaterialTheme.typography.titleMedium, maxLines = 2)
                Muted(if (movedM > 50) stringResource(R.string.g4_ride_pin_moved, com.bucks.app.ui.formatDistance(movedM)) else stringResource(R.string.g4_ride_pin_hint), Modifier.padding(vertical = 8.dp))
                if (noFix || (waiting && !moved)) LocationNotice(onEnableLocation, Modifier.padding(bottom = 12.dp))
                vm.dispatch.bookError?.let { err ->
                    Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
                        Text(stringResource(R.string.g4_ride_book_failed, err), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.padding(12.dp))
                    }
                }
                DarkButton(if (busy) stringResource(R.string.g4_ride_checking_route) else if (vm.dispatch.bookError != null) stringResource(R.string.g4_try_again) else stringResource(R.string.g4_ride_confirm_pickup), enabled = !busy && !vm.dispatch.busy) {
                    // ensureActive: leaving the screen during a lookup must not pop the booking sheet up over wherever the rider went.
                    scope.launch { busy = true
                        try {
                            var at = center; var name = label
                            // An unmoved pin means "where I am": looked up again on tap, never booked from a stale or default position.
                            if (cloud && !moved) {
                                if (!vm.refreshLocation(ctx)) { noFix = true; return@launch }
                                ensureActive(); noFix = false; at = vm.mePos; name = vm.state.value.hereLabel ?: label
                            }
                            vm.setPickup(name, at)
                            // The fare follows the road from the pin to the drop, so work the distance out again from here.
                            if (dest != null) MapServices.route(at, dest.at ?: Geo.fromPercent(dest.x, dest.y))?.let { vm.setDestKm(it.km) }
                            ensureActive(); vm.requestRide()
                        } finally { busy = false }
                    }
                }
            }
        }
    }
}

@Composable
fun SearchingScreen(vm: BucksViewModel, onChangeType: () -> Unit, onBack: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val r = s.ride ?: return
    val n = vm.onlineCount(r.kind); val cancelling = vm.dispatch.cancelling
    var cancel by remember { mutableStateOf(false) }
    // Back while searching asks first (leaving would leave the request ringing); once nobody took it, Back just leaves.
    BackHandler(enabled = r.status == RideStatus.SEARCHING) { cancel = true }
    BackHandler(enabled = r.status == RideStatus.NO_DRIVER) { vm.dismissEndedRide(); onBack() }
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        // The 5 km circle the request rings within, with the riders of this kind that are in it.
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.pickupAt, stringResource(R.string.g4_ride_pickup), MeColor, true), pinAt(r.dest.latLng(), r.dest.name, MaterialTheme.status.bad)) + drivers.filter { it.online && it.vehicle == r.kind }.map { pinAt(it.pos, "", MaterialTheme.colorScheme.primary) },
                zoom = 13.0, circle = vm.pickupAt to 5000.0)
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            if (r.status == RideStatus.SEARCHING) {
                Row(verticalAlignment = Alignment.CenterVertically) { PulseRings(Modifier.size(56.dp)) { Icon(r.kind.icon, null, Modifier.size(26.dp).breathe(amount = 0.08f), tint = MaterialTheme.colorScheme.primary) }; Column(Modifier.padding(start = 12.dp)) { Text(stringResource(R.string.g4_ride_looking, r.kind.label.lowercase()), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g4_ride_looking_sub, r.kind.label)) } }
                BadButton(if (cancelling) stringResource(R.string.g4_ride_cancelling) else stringResource(R.string.g4_ride_cancel_request), Modifier.padding(top = 14.dp), enabled = !cancelling) { cancel = true }
            } else {
                Text(stringResource(R.string.g4_ride_no_rider_accepted), style = MaterialTheme.typography.titleLarge); Muted(if (n > 0) stringResource(R.string.g4_ride_all_busy) else stringResource(R.string.g4_ride_nobody_online))
                PrimaryButton(stringResource(R.string.g4_ride_ring_again), Modifier.padding(top = 14.dp)) { vm.requestRide() }; GhostButton(stringResource(R.string.g4_ride_change_type), Modifier.padding(top = 10.dp), onClick = onChangeType)
            }
        }
    }
    if (cancel) RideCancelSheet(vm, null, false) { cancel = false }
}

@Composable
fun DriverFoundScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    val arrived = r.status == RideStatus.ARRIVED; var cancel by remember { mutableStateOf(false) }; val ctx = LocalContext.current; val cancelling = vm.dispatch.cancelling
    val me = vm.mePos; val car = r.driverAt ?: Geo.fromPercent(r.driverX, r.driverY); val road = rememberRoadRoute(car, me)
    val noNumber = stringResource(R.string.g4_ride_no_number, d.name.substringBefore(' ')); val riderWord = stringResource(R.string.g4_ride_rider)
    val tripMsg = stringResource(R.string.g4_ride_share_msg, r.dest.name, d.name, d.model, d.plate); val linkCopied = stringResource(R.string.g4_ride_link_copied)
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, stringResource(R.string.g4_ride_pin_you), MaterialTheme.colorScheme.primary, true), pinAt(car, d.name.substringBefore(' '), MaterialTheme.status.good)), zoom = 15.0, route = road?.points ?: listOf(car, me)); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet { Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
            // The headline slides to the new status so "your rider is here" can't be missed.
            AnimatedContent(if (arrived) stringResource(R.string.g4_ride_rider_here) else etaText(r.etaMin)?.let { stringResource(R.string.g4_ride_pickup_in, it) } ?: stringResource(R.string.g4_ride_rider_on_way), Modifier.align(Alignment.CenterHorizontally), transitionSpec = {
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
            Muted(stringResource(R.string.g4_ride_share_pin), Modifier.padding(top = 6.dp))
            Box(Modifier.padding(vertical = 14.dp)) { MessageBar(stringResource(R.string.g4_ride_message_driver), onCall = { if (vm.cloud) { if (d.phone.isBlank()) showToast(noNumber) else dial(ctx, d.phone) } else onCall(d.name, "+91 98450 12345") }) { if (vm.cloud) { if (d.phone.isBlank()) showToast(noNumber) else sms(ctx, d.phone) } else onChatWith(d.name, riderWord) } }
            RoutePoints(r.pickupLabel.ifBlank { stringResource(R.string.g4_ride_pickup_point) }, r.dest.name) { IconButton({ if (vm.cloud) shareText(ctx, tripMsg) else showToast(linkCopied) }) { Icon(Icons.Rounded.Share, stringResource(R.string.g4_ride_share_trip), Modifier.size(20.dp)) } }
            Row(Modifier.padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.g4_ride_total_fare), style = MaterialTheme.typography.titleMedium); Text("  " + Money.format(r.fare), style = MaterialTheme.typography.titleLarge) }
            // With Firebase the driver starts the trip once they've entered your PIN.
            if (arrived && !vm.cloud) DarkButton(stringResource(R.string.g4_ride_start_trip), Modifier.padding(bottom = 10.dp)) { vm.startTrip() }
            GhostButton(if (cancelling) stringResource(R.string.g4_ride_cancelling) else stringResource(R.string.g4_ride_cancel_ride), enabled = !cancelling) { cancel = true }
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
        title = if (driverName == null) stringResource(R.string.g4_ride_cancel_request_title) else stringResource(R.string.g4_ride_cancel_ride_title),
        message = when { driverName == null -> stringResource(R.string.g4_ride_cancel_request_msg); arrived -> stringResource(R.string.g4_ride_cancel_arrived_msg, driverName); else -> stringResource(R.string.g4_ride_cancel_on_way_msg, driverName) },
        reasons = CancelReasons.rider, requireReason = driverName != null, confirmLabel = if (driverName == null) stringResource(R.string.g4_ride_cancel_request) else stringResource(R.string.g4_ride_cancel_ride),
        keepLabel = if (driverName == null) stringResource(R.string.g4_ride_keep_searching) else stringResource(R.string.g4_ride_keep_ride),
        nudge = if (n >= 2) pluralStringResource(R.plurals.g4_ride_cancel_nudge, n, n) else null, busy = busy || vm.dispatch.cancelling,
        onConfirm = { code, note -> busy = true; vm.cancelRide(code, note) { ok -> busy = false; if (ok) onClose() } }, onDismiss = onClose)
}

@Composable
fun InRideScreen(vm: BucksViewModel, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return; val ctx = LocalContext.current
    val tripMsg = stringResource(R.string.g4_ride_share_msg, r.dest.name, d.name, d.model, d.plate); val linkCopied = stringResource(R.string.g4_ride_link_copied); val sosMsg = stringResource(R.string.g4_ride_sos_notified)
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        val car = r.driverAt ?: Geo.fromPercent(r.driverX, r.driverY); val road = rememberRoadRoute(car, r.dest.latLng())
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(r.dest.latLng(), r.dest.name, MaterialTheme.status.bad), pinAt(car, stringResource(R.string.g4_ride_pin_you), MaterialTheme.status.good, true)), zoom = 15.0, route = road?.points ?: listOf(car, r.dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Text(stringResource(R.string.g4_ride_on_way_to, r.dest.name), style = MaterialTheme.typography.titleLarge)
            Muted(stringResource(R.string.g4_ride_km_left, "%.1f".format((1 - r.progress) * r.dest.km), d.name, d.plate))
            LinearProgressIndicator(progress = { r.progress }, modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp).height(6.dp).clip(CircleShape), trackColor = MaterialTheme.colorScheme.surfaceContainerHigh)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) { IconAction(Icons.Rounded.Sos, stringResource(R.string.g4_ride_sos)) { if (vm.cloud) dial(ctx, "112") else showToast(sosMsg) }; IconAction(Icons.Rounded.Share, stringResource(R.string.g4_ride_share_trip)) { if (vm.cloud) shareText(ctx, tripMsg) else showToast(linkCopied) } }
        }
    }
}

@Composable
fun PayScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.popIn()) { Avatar(icon = Icons.Rounded.Flag, size = 64) }
            Headline(stringResource(R.string.g4_ride_arrived_at, r.dest.name), Modifier.padding(top = 16.dp)); Muted(stringResource(R.string.g4_ride_km_with, r.dest.km.toString(), d.name), align = TextAlign.Center)
            BucksCard(Modifier.padding(vertical = 22.dp), tint = true) { Muted(stringResource(R.string.g4_ride_total_payable), Modifier.align(Alignment.CenterHorizontally)); Text(Money.format(animatedInt(r.fare)), style = MaterialTheme.typography.displaySmall, modifier = Modifier.align(Alignment.CenterHorizontally)) }
            if (vm.dispatch.enabled) CloudPayPanel(vm, r, d)
            else Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { DarkButton(stringResource(R.string.g4_ride_pay_cash)) { vm.payRide("Cash") }; GhostButton("Google Pay") { vm.payRide("Google Pay") }; GhostButton("Amazon Pay") { vm.payRide("Amazon Pay") }; GhostButton(stringResource(R.string.g4_ride_scan_qr)) { vm.payRide("Rider QR") } }
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
    val noUpiApp = stringResource(R.string.g4_ride_no_upi_app)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when {
            !loaded -> Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp); Muted("  " + stringResource(R.string.g4_ride_checking_payments, first)) }
            upi == null -> Notice(stringResource(R.string.g4_ride_no_upi_qr, first, Money.format(r.fare)))
            else -> {
                upiPayee(upi)?.let { (pn, pa) -> Muted(stringResource(R.string.g4_ride_upi_payee, pn, pa), align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                DarkButton(if (upiOpened) stringResource(R.string.g4_ride_open_upi_again) else stringResource(R.string.g4_ride_pay_upi, r.fare), enabled = !paying) {
                    val link = upiPayLink(upi, r.fare, "Bucks ride")
                    val ok = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }.isSuccess
                    if (ok) { upiOpened = true; away = false; returned = false } else vm.toast(noUpiApp)
                }
                if (upiOpened && !returned) Muted(stringResource(R.string.g4_ride_finish_upi), align = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                if (upiOpened && returned) PrimaryButton(if (paying) stringResource(R.string.g4_saving) else stringResource(R.string.g4_ride_paid_upi, r.fare), enabled = !paying) { vm.payRide("UPI") }
            }
        }
        if (loaded) GhostButton(if (paying) stringResource(R.string.g4_saving) else stringResource(R.string.g4_ride_paid_cash), enabled = !paying) { confirmCash = true }
        Muted(stringResource(R.string.g4_ride_pay_honesty), align = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
    if (confirmCash) AlertDialog(onDismissRequest = { confirmCash = false }, title = { Text(stringResource(R.string.g4_ride_paid_cash_q, Money.format(r.fare))) }, text = { Text(stringResource(R.string.g4_ride_paid_cash_told, first)) },
        confirmButton = { TextButton({ confirmCash = false; vm.payRide("CASH") }) { Text(stringResource(R.string.g4_ride_yes_paid)) } }, dismissButton = { TextButton({ confirmCash = false }) { Text(stringResource(R.string.g4_ride_not_yet)) } })
}

@Composable
fun RateRideScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    var vote by remember { mutableStateOf<Int?>(null) }; var comment by remember { mutableStateOf("") }; var reason by remember { mutableStateOf<String?>(null) }
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).imePadding().padding(20.dp).padding(top = 24.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 76); Headline(stringResource(R.string.g4_ride_how_was, d.name.substringBefore(' ')), Modifier.padding(top = 12.dp)); Muted(stringResource(R.string.g4_ride_paid_by, Money.format(r.fare), payWord(r.paidWith)), align = TextAlign.Center) }
            Row(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalArrangement = Arrangement.Center) { VoteArrow(true, vote == 1, Modifier.width(96.dp)) { vote = 1 }; Spacer(Modifier.width(12.dp)); VoteArrow(false, vote == -1, Modifier.width(96.dp)) { vote = -1 } }
            if (vote == -1) { Text(stringResource(R.string.g4_vote_what_wrong), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(bottom = 6.dp)); ReasonChips(reason) { reason = it }; Spacer(Modifier.height(10.dp)) }
            BucksField(comment, { comment = it.take(500) }, stringResource(R.string.g4_vote_more_hint), if (vote == -1) stringResource(R.string.g4_ride_what_happened) else stringResource(R.string.g4_ride_good_hint), singleLine = false, minLines = 2)
            PrimaryButton(stringResource(R.string.g4_fb_post)) { vm.finishRide(vote, comment, false, reason) }
            TextButton(onClick = { vm.finishRide(null, "", true) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text(stringResource(R.string.g4_ride_skip)) }
        }
    }
}
