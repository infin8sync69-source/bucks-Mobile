package com.bucks.app.ui.screens.dispatch

import androidx.compose.foundation.background
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.secondsSince
import com.bucks.app.ui.screens.MessageBar
import com.bucks.app.ui.screens.RoutePoints
import com.bucks.app.ui.sms
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.delay
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import kotlinx.coroutines.launch

/**
 * A buyer following their delivery: the shop, their door and the rider's live position on the map, the status,
 * the rider's name and bike, call/message, and the 4-digit pickup PIN the rider asks for at the shop.
 * Follows the task through realtime on `tasks` with a 5-second poll of `tasks_geo` as the fallback.
 */
@Composable
fun DeliveryTrackScreen(vm: BucksViewModel, taskId: String, onBack: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var task by remember(taskId) { mutableStateOf<TaskGeoRow?>(null) }; var rider by remember(taskId) { mutableStateOf<TaskDriverRow?>(null) }
    var phone by remember(taskId) { mutableStateOf<String?>(null) }; var failed by remember(taskId) { mutableStateOf(false) }
    suspend fun refresh() {
        val t = runCatching { vm.dispatch.task(taskId) }.onFailure { failed = true }.getOrNull() ?: return
        task = t; failed = false
        if (t.driverId != null && rider?.profileId != t.driverId) { rider = runCatching { vm.dispatch.driverOf(taskId) }.getOrNull(); phone = null }
        if (t.driverId == null) { rider = null; phone = null }
        if (t.driverId != null && phone == null && t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS", "COMPLETED")) phone = runCatching { vm.dispatch.contact(taskId)?.phone }.getOrNull()
    }
    LaunchedEffect(taskId) { while (true) { refresh(); val done = task?.status in setOf("COMPLETED", "PAID", "CANCELLED", "NO_DRIVER"); delay(if (done) 30_000 else 5_000) } }
    DisposableEffect(taskId) {
        val (channel, flow) = Backend.liveTask(taskId)
        val job = scope.launch { runCatching { flow.collect { refresh() } } }
        onDispose { job.cancel(); Backend.releaseChannel(channel) }
    }
    val t = task
    Column(Modifier.fillMaxSize()) {
        BucksTopBar(stringResource(R.string.g3_dt_title), onBack = onBack)
        when {
            t == null && failed -> ContentColumn(Modifier.weight(1f)) { Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g3_dt_load_failed), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g3_dt_load_failed_body), Modifier.padding(top = 6.dp))
                PrimaryButton(stringResource(R.string.g3_try_again), Modifier.padding(top = 16.dp)) { scope.launch { refresh() } } } }
            t == null -> Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { BucksLoader() }
            else -> DeliveryBody(vm, t, rider, phone, Modifier.weight(1f), onCall = { phone?.let { dial(ctx, it) } ?: vm.toast(Str.get(R.string.g3_dt_no_number)) },
                onMessage = { phone?.let { sms(ctx, it) } ?: vm.toast(Str.get(R.string.g3_dt_no_number)) }, onDone = onBack)
        }
    }
}

@Composable
private fun DeliveryBody(vm: BucksViewModel, t: TaskGeoRow, rider: TaskDriverRow?, phone: String?, modifier: Modifier, onCall: () -> Unit, onMessage: () -> Unit, onDone: () -> Unit) {
    val shop = t.pickup; val door = t.drop; val at = t.driverAt
    val moving = t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS")
    // open_tasks_near stops ringing a task once the ring window has passed since it started searching (created, or handed back by a rider);
    // past that, "finding a rider" would be a lie.
    val stale = t.status == "SEARCHING" && (secondsSince(t.statusAt.ifBlank { t.createdAt }) ?: 0) >= vm.dispatch.ringWindowS
    val ends = when (t.status) { "MATCHED" -> listOfNotNull(at, shop); "IN_PROGRESS" -> listOfNotNull(at ?: shop, door); else -> listOf(shop, door) }
    // Road route between the two ends (straight line until it arrives or when offline).
    val road = rememberRoadRoute(ends.getOrNull(0), ends.getOrNull(1))
    val route = if (ends.size >= 2) road?.points ?: ends else ends
    val pins = listOfNotNull(pinAt(door, stringResource(R.string.g3_map_you), MaterialTheme.colorScheme.primary, true), pinAt(shop, t.pickupLabel.ifBlank { stringResource(R.string.g3_dt_shop) }, MaterialTheme.status.bad),
        at?.takeIf { moving }?.let { pinAt(it, rider?.name?.substringBefore(' ') ?: stringResource(R.string.g3_dt_rider), MaterialTheme.status.good) })
    val shopName = t.pickupLabel.ifBlank { stringResource(R.string.g3_dt_the_shop) }
    val (headline, detail) = when (t.status) {
        "SEARCHING" -> if (stale) stringResource(R.string.g3_dt_no_rider_yet) to stringResource(R.string.g3_dt_no_rider_yet_body)
                       else stringResource(R.string.g3_dt_finding) to stringResource(R.string.g3_dt_finding_body, shopName)
        "MATCHED" -> stringResource(R.string.g3_dt_matched) to (at?.let { stringResource(R.string.g3_dt_km_from, "%.1f".format(Geo.distanceKm(it, shop)), shopName) } ?: stringResource(R.string.g3_dt_heading_to, shopName))
        "ARRIVED" -> stringResource(R.string.g3_dt_arrived) to stringResource(R.string.g3_dt_arrived_body)
        "IN_PROGRESS" -> stringResource(R.string.g3_dt_in_progress) to (at?.let { stringResource(R.string.g3_dt_km_away, "%.1f".format(Geo.distanceKm(it, door))) } ?: stringResource(R.string.g3_dt_left_shop))
        "COMPLETED", "PAID" -> stringResource(R.string.g3_order_delivered) to stringResource(R.string.g3_dt_delivered_body)
        "NO_DRIVER" -> stringResource(R.string.g3_dt_no_driver) to stringResource(R.string.g3_dt_no_driver_body)
        "CANCELLED" -> stringResource(R.string.g3_dt_cancelled) to stringResource(R.string.g3_dt_cancelled_body)
        else -> t.status to ""
    }
    Column(modifier.fillMaxWidth()) {
        Box(Modifier.weight(1f).fillMaxWidth()) { BucksMap(Modifier.fillMaxSize(), pins, zoom = 14.0, route = if (route.size >= 2) route else emptyList()); MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
        Sheet { Column(Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState())) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (t.status == "SEARCHING" && !stale) PulseRings(Modifier.size(48.dp)) { Icon(Icons.Rounded.TwoWheeler, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary) }
                else Avatar(icon = when (t.status) { "COMPLETED", "PAID" -> Icons.Rounded.CheckCircle; "CANCELLED", "NO_DRIVER", "SEARCHING" -> Icons.Rounded.Block; else -> Icons.Rounded.TwoWheeler }, size = 48)
                Column(Modifier.padding(start = 12.dp).weight(1f)) { Text(headline, style = MaterialTheme.typography.titleLarge); Muted(detail) }
            }
            HorizontalDivider(Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.outline)
            if (rider != null) {
                Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(rider.name.ifBlank { stringResource(R.string.g3_dt_rider) }), size = 44)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(rider.name.ifBlank { stringResource(R.string.g3_dt_your_rider) }, style = MaterialTheme.typography.titleSmall); Muted(listOf(rider.model, rider.plate).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { stringResource(R.string.g3_vehicle_bike) }) }
                    TrustBadge(Trust(rider.up, rider.down), compact = true) }
                if (moving) Box(Modifier.padding(top = 12.dp)) { MessageBar(stringResource(R.string.g3_dt_message_rider), onCall = onCall, onMessage = onMessage) }
            } else if (t.status == "SEARCHING" && !stale) Muted(stringResource(R.string.g3_dt_rider_pending))
            if (t.status in setOf("SEARCHING", "MATCHED", "ARRIVED") && !stale) BucksCard(Modifier.padding(top = 14.dp), tint = true) {
                Text(stringResource(R.string.g3_dt_pickup_pin), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { t.pin.forEach { c -> Box(Modifier.defaultMinSize(34.dp, 34.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) { Text("$c", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleMedium) } } }
                Text(stringResource(R.string.g3_dt_pin_body), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.padding(top = 8.dp))
            }
            RoutePoints(t.pickupLabel.ifBlank { stringResource(R.string.g3_dt_shop) }, t.dropLabel.ifBlank { stringResource(R.string.g3_dt_your_location) }, Modifier.padding(top = 14.dp))
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { Muted(stringResource(R.string.g3_dt_km, t.km.toString())); Muted(stringResource(R.string.g3_dt_fee, Money.format(t.fare))); t.orderItems?.let { Muted(pluralStringResource(R.plurals.g3_dt_items, it, it)) } }
            if (t.status in setOf("COMPLETED", "PAID", "CANCELLED", "NO_DRIVER") || stale) PrimaryButton(stringResource(R.string.g3_dt_back_to_order), Modifier.padding(top = 16.dp), onClick = onDone)
            else Muted(stringResource(R.string.g3_dt_keep_open), Modifier.padding(top = 12.dp), TextAlign.Center)
        } }
    }
}
