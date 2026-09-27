package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.CloudOrderRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The shop's order inbox: live list of orders for one listing. New orders show a 5-minute countdown with Accept / Reject;
 * accepted ones show their status, "Call customer" and, for pick-up orders, Ready / Collected. Rings when a new order lands.
 */
@Composable
fun VendorOrdersScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onOpen: (String) -> Unit) {
    val commerce = vm.commerce; val social = vm.social; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var filter by rememberSaveable { mutableStateOf("New") }
    var rejectFor by remember { mutableStateOf<CloudOrderRow?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val title = commerce.titleOf(listingId)
    DisposableEffect(listingId) { commerce.ordersFor(listingId); onDispose { commerce.stopOrders() } }
    LaunchedEffect(listingId) { runCatching { commerce.titlesFor(listOf(listingId)) } }
    // Buyers pay by UPI to the owner's payment QR; tell the owner when there isn't one (admins can't fix it, so they aren't asked).
    val d = vm.dispatch
    LaunchedEffect(listingId) { if (d.enabled && !d.paymentLinkLoaded) d.refreshPaymentLink() }
    val owner = vm.myListings.listing(listingId)?.ownerId?.let { it == social.me?.id } == true
    // The clock for the countdowns, plus a 30-second reload in case the live feed drops.
    LaunchedEffect(listingId) { var n = 0; while (true) { now = System.currentTimeMillis(); if (++n % 30 == 0) commerce.ordersFor(listingId); delay(1000) } }
    // Sound and buzz when a new PLACED order arrives while this screen is open (not for the first load).
    var seenTick by remember { mutableIntStateOf(commerce.newOrderTick) }
    LaunchedEffect(commerce.newOrderTick) { if (commerce.newOrderTick != seenTick) { seenTick = commerce.newOrderTick; alertNewOrder(ctx); if (filter != "New") vm.toast("New order for $title.") } }

    val all = commerce.vendorOrders
    val newOnes = all.filter { it.status == "PLACED" }; val active = all.filter { it.status in setOf("ACCEPTED", "READY", "PICKED_UP") }; val done = all.filter { orderDone(it.status) }
    val shown = when (filter) { "New" -> newOnes; "Active" -> active; else -> done }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Orders · $title", onBack = onBack, actions = { IconButton({ commerce.ordersFor(listingId) }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        Row(Modifier.padding(horizontal = Gutter, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip(if (newOnes.isEmpty()) "New" else "New · ${newOnes.size}", selected = filter == "New", icon = Icons.Rounded.NotificationsActive) { filter = "New" }
            Chip(if (active.isEmpty()) "Active" else "Active · ${active.size}", selected = filter == "Active", icon = Icons.Rounded.LocalShipping) { filter = "Active" }
            Chip("Done", selected = filter == "Done", icon = Icons.Rounded.Done) { filter = "Done" }
        }
        if (owner && d.enabled && d.paymentLinkLoaded && d.paymentLink == null) Column(Modifier.padding(horizontal = Gutter, vertical = 4.dp)) {
            Notice("Customers can't pay these orders by UPI: you haven't added your UPI QR yet. Add it and their Pay button fills in your account and the amount.")
            SmallButton("Add payment QR", Modifier.padding(top = 8.dp)) { vm.open(Routes.PAYMENT_QR) }
        }
        when {
            !commerce.vendorLoaded -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            shown.isEmpty() -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = if (filter == "New") Icons.Rounded.NotificationsNone else Icons.Rounded.Inventory2, size = 72)
                Text(when (filter) { "New" -> "No new orders"; "Active" -> "Nothing in progress"; else -> "No finished orders yet" }, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted(when (filter) { "New" -> "Keep this screen open while the shop is online: new orders ring here and you have 5 minutes to accept each one."; "Active" -> "Accepted orders stay here until they're delivered or collected."; else -> "Delivered, rejected and cancelled orders are kept here." }, Modifier.padding(top = 6.dp), TextAlign.Center)
            }
            else -> LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(shown, key = { it.id }) { o ->
                    VendorOrderCard(o, buyer = social.nameOf(o.buyerId), now = now, onOpen = { onOpen(o.id) },
                        onAccept = { commerce.respondOrder(o.id, true) }, onReject = { rejectFor = o },
                        onReady = { commerce.updateOrderStatus(o.id, "READY") }, onCollected = { commerce.updateOrderStatus(o.id, "DELIVERED") },
                        onCall = { scope.launch { val c = runCatching { commerce.contactFor(o.id) }.getOrNull(); val p = c?.phone; if (p.isNullOrBlank()) vm.toast("This customer hasn't shared a phone number.") else dial(ctx, p) } })
                }
                item { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
    rejectFor?.let { o -> AlertDialog(onDismissRequest = { rejectFor = null }, title = { Text("Reject this order?") }, text = { Text("${social.nameOf(o.buyerId)} will be told the shop couldn't take it. Rejecting often lowers how high ${title} shows in search.") },
        confirmButton = { TextButton({ commerce.respondOrder(o.id, false); rejectFor = null }) { Text("Reject", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ rejectFor = null }) { Text("Keep it") } }) }
}

@Composable
private fun VendorOrderCard(o: CloudOrderRow, buyer: String, now: Long, onOpen: () -> Unit, onAccept: () -> Unit, onReject: () -> Unit, onReady: () -> Unit, onCollected: () -> Unit, onCall: () -> Unit) {
    val st = MaterialTheme.status
    BucksCard(onClick = onOpen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(buyer.ifBlank { "?" }), size = 40)
            Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(buyer, style = MaterialTheme.typography.titleMedium); Muted("${ago(o.createdAt)} · ${shortOrderId(o.id)}") }
            if (o.status == "PLACED") {
                val left = epochMillis(o.acceptBy) - now
                if (left <= 0) PillBad("Time's up") else Pill("Accept in ${mmss(left)}", if (left < 60_000) st.badTint else st.warnTint, if (left < 60_000) st.bad else st.warn)
            } else OrderStatusPill(o.status, o.deliveryMode)
        }
        Text(orderLinesSummary(o.lines), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            // What the customer pays the shop: a Bucks rider's fee goes to the rider, a store rider's fee comes to the shop.
            Text(rupees(o.toShop), style = MaterialTheme.typography.titleMedium)
            if (o.deliveryMode != "PICKUP" && o.feePaidBy == "VENDOR") Muted("  + ${rupees(o.deliveryFee)} rider fee paid by you")
            else if (o.deliveryMode == "STORE_RIDER" && o.deliveryFee > 0) Muted("  incl. ${rupees(o.deliveryFee)} delivery")
            Spacer(Modifier.weight(1f))
            PillGrey(paymentLabel(o.payment))
        }
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(when (o.deliveryMode) { "PICKUP" -> Icons.Rounded.DirectionsWalk; "STORE_RIDER" -> Icons.Rounded.Storefront; else -> Icons.Rounded.TwoWheeler }, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Muted(" ${deliveryModeLabel(o.deliveryMode)}" + (if (o.deliveryMode != "PICKUP" && o.dropLabel.isNotBlank()) " · ${o.dropLabel}" else ""), maxLines = 1)
        }
        when (o.status) {
            "PLACED" -> Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallButton("Accept", Modifier.weight(1f), onClick = onAccept)
                SmallButton("Reject", Modifier.weight(1f), tonal = true, onClick = onReject)
            }
            "ACCEPTED", "READY", "PICKED_UP" -> Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallButton("Call customer", Modifier.weight(1f), tonal = true, onClick = onCall)
                if (o.status == "ACCEPTED") SmallButton(if (o.deliveryMode == "PICKUP") "Ready to collect" else "Packed", Modifier.weight(1f), onClick = onReady)
                else if (o.status == "READY" && o.deliveryMode == "PICKUP") SmallButton("Collected", Modifier.weight(1f), onClick = onCollected)
            }
            else -> {}
        }
        val payRider = if (o.deliveryMode == "MARKETPLACE" && o.feePaidBy == "VENDOR") " Free delivery: pay the rider ${rupees(o.deliveryFee)} when they collect it." else ""
        if (o.status == "ACCEPTED" && o.deliveryMode != "PICKUP") Muted("A rider is being rung. Mark it packed when it's ready to hand over.$payRider", Modifier.padding(top = 8.dp))
        if (o.status == "READY" && o.deliveryMode != "PICKUP") Muted("Hand it to the rider. They enter the customer's PIN when collecting.$payRider", Modifier.padding(top = 8.dp))
    }
}
