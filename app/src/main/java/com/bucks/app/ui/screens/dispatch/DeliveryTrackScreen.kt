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
import com.bucks.app.ui.screens.MessageBar
import com.bucks.app.ui.screens.RoutePoints
import com.bucks.app.ui.sms
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.delay
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
        onDispose { job.cancel(); scope.launch { Backend.closeChannel(channel) } }
    }
    val t = task
    Column(Modifier.fillMaxSize()) {
        BucksTopBar("Track delivery", onBack = onBack)
        when {
            t == null && failed -> ContentColumn(Modifier.weight(1f)) { Column(Modifier.padding(Gutter)) { Text("Couldn't load this delivery", style = MaterialTheme.typography.titleMedium); Muted("Check your connection and pull down, or go back to the order.", Modifier.padding(top = 6.dp))
                PrimaryButton("Try again", Modifier.padding(top = 16.dp)) { scope.launch { refresh() } } } }
            t == null -> Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { BucksLoader() }
            else -> DeliveryBody(vm, t, rider, phone, Modifier.weight(1f), onCall = { phone?.let { dial(ctx, it) } ?: vm.toast("The rider's number will show once they've picked up the job.") },
                onMessage = { phone?.let { sms(ctx, it) } ?: vm.toast("The rider's number will show once they've picked up the job.") }, onDone = onBack)
        }
    }
}

@Composable
private fun DeliveryBody(vm: BucksViewModel, t: TaskGeoRow, rider: TaskDriverRow?, phone: String?, modifier: Modifier, onCall: () -> Unit, onMessage: () -> Unit, onDone: () -> Unit) {
    val shop = t.pickup; val door = t.drop; val at = t.driverAt
    val moving = t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS")
    // open_tasks_near stops ringing a task 3 minutes after it started searching (created, or handed back by a rider);
    // past that, "finding a rider" would be a lie.
    val stale = t.status == "SEARCHING" && olderThanMinutes(t.statusAt.ifBlank { t.createdAt }, 3)
    val route = when (t.status) { "MATCHED" -> listOfNotNull(at, shop); "IN_PROGRESS" -> listOfNotNull(at ?: shop, door); else -> listOf(shop, door) }
    val pins = listOfNotNull(pinAt(door, "You", MaterialTheme.colorScheme.primary, true), pinAt(shop, t.pickupLabel.ifBlank { "Shop" }, MaterialTheme.status.bad),
        at?.takeIf { moving }?.let { pinAt(it, rider?.name?.substringBefore(' ') ?: "Rider", MaterialTheme.status.good) })
    val (headline, detail) = when (t.status) {
        "SEARCHING" -> if (stale) "No rider yet" to "Nobody nearby took it within 3 minutes. Message the shop: they can send their own rider or refund you."
                       else "Finding a rider" to "Bikes near ${t.pickupLabel.ifBlank { "the shop" }} are being rung. The first to accept collects your order."
        "MATCHED" -> "Rider on the way to the shop" to (at?.let { "${"%.1f".format(Geo.distanceKm(it, shop))} km from ${t.pickupLabel.ifBlank { "the shop" }}" } ?: "Heading to ${t.pickupLabel.ifBlank { "the shop" }}")
        "ARRIVED" -> "Rider is at the shop" to "They'll call you for the pickup PIN below, then bring your order."
        "IN_PROGRESS" -> "On the way to you" to (at?.let { "${"%.1f".format(Geo.distanceKm(it, door))} km away" } ?: "Your order has left the shop")
        "COMPLETED", "PAID" -> "Delivered" to "Your order was handed over. Enjoy."
        "NO_DRIVER" -> "No rider was free" to "Nobody nearby could take it. The shop can send its own rider or you can reorder."
        "CANCELLED" -> "Delivery cancelled" to "This delivery was cancelled."
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
                Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(rider.name.ifBlank { "R" }), size = 44)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(rider.name.ifBlank { "Your rider" }, style = MaterialTheme.typography.titleSmall); Muted(listOf(rider.model, rider.plate).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "Bike" }) }
                    TrustBadge(Trust(rider.up, rider.down), compact = true) }
                if (moving) Box(Modifier.padding(top = 12.dp)) { MessageBar("Message your rider", onCall = onCall, onMessage = onMessage) }
            } else if (t.status == "SEARCHING" && !stale) Muted("Your rider's name and bike will show here once someone accepts.")
            if (t.status in setOf("SEARCHING", "MATCHED", "ARRIVED") && !stale) BucksCard(Modifier.padding(top = 14.dp), tint = true) {
                Text("Pickup PIN", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { t.pin.forEach { c -> Box(Modifier.size(34.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Text("$c", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleMedium) } } }
                Text("Your rider will call you for this PIN when collecting your order at the shop. Only share it with them.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.padding(top = 8.dp))
            }
            RoutePoints(t.pickupLabel.ifBlank { "Shop" }, t.dropLabel.ifBlank { "Your location" }, Modifier.padding(top = 14.dp))
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { Muted("${t.km} km"); Muted("Delivery fee ₹${t.fare}"); t.orderItems?.let { Muted("$it item${if (it == 1) "" else "s"}") } }
            if (t.status in setOf("COMPLETED", "PAID", "CANCELLED", "NO_DRIVER") || stale) PrimaryButton("Back to order", Modifier.padding(top = 16.dp), onClick = onDone)
            else Muted("Keep this screen open or come back any time; it follows the rider live.", Modifier.padding(top = 12.dp), TextAlign.Center)
        } }
    }
}

/** True when an ISO timestamp from PostgREST (with offset) is at least [minutes] old; false if it can't be read. */
private fun olderThanMinutes(iso: String, minutes: Long): Boolean =
    runCatching { java.time.Duration.between(java.time.OffsetDateTime.parse(iso.replace(" ", "T")).toInstant(), java.time.Instant.now()).toMinutes() >= minutes }.getOrDefault(false)
