package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.RideStatus
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.commerce.epochMillis

/** One thing the customer is waiting on: a ride or an order. [route] opens its own screen. */
data class ActivityItem(val key: String, val icon: ImageVector, val title: String, val status: String, val route: String, val needsYou: Boolean = false)

/** Order states that are still moving; once delivered, rejected or cancelled the order leaves the activity button. */
private val OPEN_ORDER = setOf("PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED")

/**
 * The customer's open ride and orders, for the Home activity button. Reads the ride from the view model and the orders the
 * Home screen keeps refreshing; recomposes whenever either changes.
 */
@Composable
fun activityItems(vm: BucksViewModel): List<ActivityItem> {
    val s by vm.state.collectAsState()
    val me = vm.social.me?.id
    val items = ArrayList<ActivityItem>()
    s.ride?.let { r ->
        val text: String?; val route: String?
        when (r.status) {
            RideStatus.SEARCHING -> { text = "Finding a driver"; route = Routes.SEARCHING }
            RideStatus.NO_DRIVER -> { text = "No driver accepted yet"; route = Routes.SEARCHING }
            RideStatus.MATCHED -> { text = "Driver on the way · ${r.etaMin} min"; route = Routes.DRIVER_FOUND }
            RideStatus.ARRIVED -> { text = "Your driver is here"; route = Routes.DRIVER_FOUND }
            RideStatus.IN_RIDE -> { text = "On your trip"; route = Routes.IN_RIDE }
            RideStatus.COMPLETED -> { text = "Pay ₹${r.fare}"; route = Routes.PAY }
            else -> { text = null; route = null }
        }
        if (text != null && route != null) items += ActivityItem("ride", r.kind.icon, "Ride to ${r.dest.name}", text, route, needsYou = r.status == RideStatus.ARRIVED || r.status == RideStatus.COMPLETED)
    }
    vm.commerce.myOrders.filter { it.status in OPEN_ORDER && (me == null || it.buyerId == me) && !(it.status == "PLACED" && epochMillis(it.acceptBy) < System.currentTimeMillis()) }.forEach { o ->
        val shop = vm.commerce.titleOf(o.listingId)
        val pickup = o.deliveryMode == "PICKUP"
        val text = when (o.status) {
            "PLACED" -> "Waiting for $shop to accept"
            "ACCEPTED" -> if (o.deliveryMode == "SHIP") "Accepted, getting ready to ship" else "Accepted, being prepared"
            "READY" -> if (pickup) "Ready to collect" else "Ready, a rider is on the way"
            "PICKED_UP" -> "On its way to you"
            "SHIPPED" -> "Shipped"
            else -> o.status.lowercase()
        }
        items += ActivityItem("order-${o.id}", Icons.Rounded.Storefront, "Order from $shop", text, Routes.cloudOrder(o.id), needsYou = o.status == "READY" && pickup)
    }
    return items
}

/** Pill on Home while a ride or order is open: shows where it stands and opens it (or the list, when there are several). */
@Composable
fun ActivityFab(items: List<ActivityItem>, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val first = items.first()
    val shape = RoundedCornerShape(28.dp)
    val one = items.size == 1
    Row(modifier.widthIn(max = 232.dp).heightIn(min = 56.dp).breathe(enabled = items.any { it.needsYou }, amount = 0.03f, periodMs = 1200)
        .shadow(10.dp, shape).clip(shape).background(MaterialTheme.colorScheme.primaryContainer)
        .clickable(onClickLabel = "See your activity", onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp)
        .semantics(mergeDescendants = true) { contentDescription = if (one) "${first.title}: ${first.status}" else "${items.size} things in progress" },
        verticalAlignment = Alignment.CenterVertically) {
        Icon(first.icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        Column(Modifier.padding(start = 10.dp)) {
            Text(if (one) first.title else "Your activity", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (one) first.status else "${items.size} in progress", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Every open ride and order with its status; tap one to open it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivitySheet(items: List<ActivityItem>, onOpen: (ActivityItem) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            Text("Your activity", style = MaterialTheme.typography.titleLarge)
            Muted("Tap one to see where it stands.", Modifier.padding(top = 2.dp, bottom = 8.dp))
            items.forEach { a ->
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clip(MaterialTheme.shapes.small).clickable { onOpen(a) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    ListingThumb(a.icon, size = 44)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text(a.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Muted(a.status, maxLines = 2)
                    }
                    Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
