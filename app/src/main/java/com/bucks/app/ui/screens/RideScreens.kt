package com.bucks.app.ui.screens

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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
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
    Column(Modifier.fillMaxSize()) {
        IconButton(onBack, Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        Column(Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 14.dp, vertical = 6.dp)) {
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.good)); Text(s.user?.area?.let { "Current location · $it" } ?: "Current location", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 12.dp), maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Rounded.MyLocation, "Using current location", Modifier.size(18.dp)) }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.status.bad))
                BasicTextField(f, { f = it; picked = null }, Modifier.weight(1f).padding(start = 12.dp), singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    decorationBox = { inner -> Box { if (f.isEmpty()) Muted("Enter destination"); inner() } }) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            Text(if (f.isBlank()) "Frequently visited" else "Matches", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
            places.forEach { name -> PlaceRow(name, Geo.distanceKm(me, Geo.PLACES.getValue(name)), saved = name in s.savedPlaces, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; f = name } }
            if (places.isEmpty()) Muted("No place with that name. Try another spelling, or pick it on the map.", Modifier.padding(vertical = 12.dp))
            Row(Modifier.fillMaxWidth().clickable { savedOpen = !savedOpen }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Star, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary); Text("Saved places", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(start = 10.dp)); Icon(if (savedOpen) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, null) }
            if (savedOpen) { if (s.savedPlaces.isEmpty()) Muted("Star a place to save it.", Modifier.padding(bottom = 8.dp)); s.savedPlaces.forEach { name -> Geo.PLACES[name]?.let { ll -> PlaceRow(name, Geo.distanceKm(me, ll), saved = true, selected = picked == name, onStar = { vm.toggleSavedPlace(name) }) { picked = name; f = name } } } }
        }
        Row(Modifier.align(Alignment.CenterHorizontally).padding(vertical = 10.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { onMap = true }.padding(horizontal = 18.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" Select on map") }
        DarkButton("Confirm", Modifier.padding(start = 20.dp, end = 20.dp, bottom = 20.dp), enabled = picked != null) { picked?.let { vm.chooseDest(it); onChosen() } }
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

private fun Place.latLng() = Geo.fromPercent(x, y)
private val HHMM = java.text.SimpleDateFormat("h:mma", java.util.Locale.ENGLISH)

@Composable
fun ChooseRideScreen(vm: BucksViewModel, onBack: () -> Unit, onConfirm: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState()
    val dest = s.rideDest ?: return; val me = vm.mePos
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MeColor, true), pinAt(dest.latLng(), dest.name, MaterialTheme.colorScheme.primary)) + drivers.filter { it.online }.map { MapPin(it.x, it.y, "", MaterialTheme.status.good) }, route = listOf(me, dest.latLng()))
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Box(Modifier.fillMaxWidth()) { IconButton(onBack, Modifier.align(Alignment.CenterStart).size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }; Text("Choose vehicle", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.Center)) }
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                VehicleKind.entries.forEach { k -> val nearest = Geo.ring(me, drivers, k).firstOrNull(); val on = s.rideKind == k; val f = vm.fare(k, dest.km)
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

@Composable
fun ConfirmPickupScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val s by vm.state.collectAsState(); val me = vm.mePos
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "Pick-up", MaterialTheme.colorScheme.primary, true)), zoom = 15.0, circle = me to 500.0); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet {
            Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onBack, Modifier.size(32.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }; Text("Confirm pick-up location", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 12.dp)) }
            Muted("${s.user?.area ?: "Your location"} · riders within 5 km are rung; the first to accept comes here.", Modifier.padding(vertical = 12.dp))
            DarkButton("Confirm pick-up") { vm.requestRide() }
        }
    }
}

@Composable
fun SearchingScreen(vm: BucksViewModel, onChangeType: () -> Unit) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val r = s.ride ?: return
    val n = vm.onlineCount(r.kind)
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        SimMap(Modifier.weight(1f).fillMaxWidth(), listOf(MapPin(s.meX, s.meY, "You", MeColor, true), MapPin(r.dest.x, r.dest.y, r.dest.name, MaterialTheme.status.bad)) + drivers.filter { it.online && it.vehicle == r.kind }.map { MapPin(it.x, it.y, "", MaterialTheme.colorScheme.primary) }, radiusAt = Offset(s.meX, s.meY))
        Sheet {
            if (r.status == RideStatus.SEARCHING) {
                Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(40.dp), strokeWidth = 3.dp); Column(Modifier.padding(start = 16.dp)) { Text("Ringing $n rider${if (n > 1) "s" else ""}", style = MaterialTheme.typography.titleLarge); Muted("${r.kind.label} · within 5 km · first to accept gets the ride") } }
                BadButton("Cancel request", Modifier.padding(top = 14.dp)) { vm.cancelRide("Changed my mind") }
            } else {
                Text("No rider accepted", style = MaterialTheme.typography.titleLarge); Muted(if (n > 0) "All nearby riders were busy. Try again or switch vehicle type." else "Nobody is online nearby.")
                PrimaryButton("Ring again", Modifier.padding(top = 14.dp)) { vm.requestRide() }; GhostButton("Change ride type", Modifier.padding(top = 10.dp), onClick = onChangeType)
            }
        }
    }
}

@Composable
fun DriverFoundScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    val arrived = r.status == RideStatus.ARRIVED; var cancel by remember { mutableStateOf(false) }
    val me = vm.mePos; val car = Geo.fromPercent(r.driverX, r.driverY)
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), listOf(pinAt(me, "You", MaterialTheme.colorScheme.primary, true), pinAt(car, d.name.substringBefore(' '), MaterialTheme.status.good)), zoom = 15.0, route = listOf(car, me)); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet { Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
            Text(if (arrived) "Your rider is here" else "Pick-up in ${r.etaMin} min", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.CenterHorizontally))
            HorizontalDivider(Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.outline)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 44); Spacer(Modifier.height(4.dp)); TrustBadge(d.trust, compact = true) }
                Icon(d.vehicle.icon, null, Modifier.padding(start = 12.dp).size(44.dp))
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { r.pin.forEach { c -> Box(Modifier.size(26.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Text("$c", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleSmall) } } }
                    Text(d.plate, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 6.dp)); Muted(d.model); Muted(d.name)
                }
            }
            Muted("Share this PIN with your rider when they arrive.", Modifier.padding(top = 6.dp))
            Box(Modifier.padding(vertical = 14.dp)) { MessageBar("Message your driver", onCall = { onCall(d.name, "+91 98450 12345") }) { onChatWith(d.name, "Rider") } }
            RoutePoints(s.user?.area ?: "Current location", r.dest.name) { Icon(Icons.Rounded.Share, "Share trip", Modifier.size(18.dp).clickable { showToast("Live trip link copied") }) }
            Row(Modifier.padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text("Total fare", style = MaterialTheme.typography.titleMedium); Text("  ₹${r.fare}", style = MaterialTheme.typography.titleLarge) }
            if (arrived) DarkButton("Rider has my PIN · Start trip", Modifier.padding(bottom = 10.dp)) { vm.startTrip() }
            GhostButton("Cancel ride") { cancel = true }
        } }
    }
    if (cancel) Dialog(onDismissRequest = { cancel = false }) { Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surface) { Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Text("!", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleLarge) }
        Text("Cancel ride", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp)); Muted("${d.name.substringBefore(' ')} is already on the way. Cancel anyway?", Modifier.padding(top = 4.dp), TextAlign.Center)
        Button({ cancel = false; vm.cancelRide("Cancelled by rider") }, Modifier.fillMaxWidth().padding(top = 16.dp), shape = MaterialTheme.shapes.small) { Text("Cancel ride") }
        TextButton({ cancel = false }) { Text("Keep ride") }
    } } }
}

@Composable
fun InRideScreen(vm: BucksViewModel, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    Column(Modifier.fillMaxSize()) {
        BucksTopBar()
        SimMap(Modifier.weight(1f).fillMaxWidth(), listOf(MapPin(r.dest.x, r.dest.y, r.dest.name, MaterialTheme.status.bad), MapPin(r.driverX, r.driverY, "You", MaterialTheme.status.good, true)), route = Offset(r.driverX, r.driverY) to Offset(r.dest.x, r.dest.y))
        Sheet {
            Text("On the way to ${r.dest.name}", style = MaterialTheme.typography.titleLarge)
            Muted("${"%.1f".format((1 - r.progress) * r.dest.km)} km left · ${d.name} · ${d.plate}")
            LinearProgressIndicator(progress = { r.progress }, modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp).height(6.dp).clip(CircleShape), trackColor = MaterialTheme.colorScheme.surfaceContainerHigh)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) { IconAction(Icons.Rounded.Sos, "SOS") { showToast("Emergency contacts notified with live location") }; IconAction(Icons.Rounded.Share, "Share trip") { showToast("Live trip link copied") } }
        }
    }
}

@Composable
fun PayScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(icon = Icons.Rounded.Flag, size = 64)
            Headline("Arrived at ${r.dest.name}", Modifier.padding(top = 16.dp)); Muted("${r.dest.km} km with ${d.name}", align = TextAlign.Center)
            BucksCard(Modifier.padding(vertical = 22.dp), tint = true) { Muted("Total payable", Modifier.align(Alignment.CenterHorizontally)); Text("₹${r.fare}", style = MaterialTheme.typography.displaySmall, modifier = Modifier.align(Alignment.CenterHorizontally)) }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { DarkButton("Pay cash") { vm.payRide("Cash") }; GhostButton("Google Pay") { vm.payRide("Google Pay") }; GhostButton("Amazon Pay") { vm.payRide("Amazon Pay") }; GhostButton("Scan rider's QR") { vm.payRide("Rider QR") } }
        }
    }
}

@Composable
fun RateRideScreen(vm: BucksViewModel) {
    val s by vm.state.collectAsState(); val r = s.ride ?: return; val d = r.driver ?: return
    var vote by remember { mutableStateOf<Int?>(null) }; var comment by remember { mutableStateOf("") }
    ContentColumn { BucksTopBar()
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).padding(top = 24.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(d.name), size = 76); Headline("How was ${d.name.substringBefore(' ')}?", Modifier.padding(top = 12.dp)); Muted("Paid ₹${r.fare} by ${r.paidWith}. Your review decides who gets the next ride.", align = TextAlign.Center) }
            Row(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalArrangement = Arrangement.Center) { VoteButton("Recommend", vote == 1, true) { vote = 1 }; Spacer(Modifier.width(10.dp)); VoteButton("Not recommended", vote == -1, false) { vote = -1 } }
            BucksField(comment, { comment = it }, "One line on why", "Safe riding, on time", singleLine = false, minLines = 2)
            PrimaryButton("Post review") { vm.finishRide(vote, comment, false) }
            TextButton(onClick = { vm.finishRide(null, "", true) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text("Skip for now") }
        }
    }
}
