package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
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
import com.bucks.app.data.OrderDelivery
import com.bucks.app.data.Prefs
import com.bucks.app.data.StoreRider
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.data.CancelReasons
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.delay
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import com.bucks.app.data.Str
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
    var shipFor by remember { mutableStateOf<CloudOrderRow?>(null) }
    /** Choosing a rider: to accept with ([Choosing.accept]) or to send while nobody has the delivery. */
    var choosing by remember { mutableStateOf<Choosing?>(null) }
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
    LaunchedEffect(commerce.newOrderTick) { if (commerce.newOrderTick != seenTick) { seenTick = commerce.newOrderTick; alertNewOrder(ctx); if (filter != "New") vm.toast(Str.get(R.string.g3_vo_new_order_toast, title)) } }

    val all = commerce.vendorOrders
    val newOnes = all.filter { it.status == "PLACED" }; val active = all.filter { it.status in setOf("ACCEPTED", "READY", "PICKED_UP", "SHIPPED") }; val done = all.filter { orderDone(it.status) }
    val shown = when (filter) { "New" -> newOnes; "Active" -> active; else -> done }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g3_vo_title, title), onBack = onBack, actions = { IconButton({ commerce.ordersFor(listingId) }) { Icon(Icons.Rounded.Refresh, stringResource(R.string.g3_cd_refresh)) } })
        Row(Modifier.padding(horizontal = Gutter, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip(if (newOnes.isEmpty()) stringResource(R.string.g3_vo_tab_new) else stringResource(R.string.g3_vo_tab_new_count, newOnes.size), selected = filter == "New", icon = Icons.Rounded.NotificationsActive) { filter = "New" }
            Chip(if (active.isEmpty()) stringResource(R.string.g3_vo_tab_active) else stringResource(R.string.g3_vo_tab_active_count, active.size), selected = filter == "Active", icon = Icons.Rounded.LocalShipping) { filter = "Active" }
            Chip(stringResource(R.string.g3_vo_tab_done), selected = filter == "Done", icon = Icons.Rounded.Done) { filter = "Done" }
        }
        if (owner && d.enabled && d.paymentLinkLoaded && d.paymentLink == null) Column(Modifier.padding(horizontal = Gutter, vertical = 4.dp)) {
            Notice(stringResource(R.string.g3_vo_no_upi))
            SmallButton(stringResource(R.string.g3_vo_add_qr), Modifier.padding(top = 8.dp)) { vm.open(Routes.PAYMENT_QR) }
        }
        when {
            !commerce.vendorLoaded -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { BucksLoader() }
            shown.isEmpty() -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = if (filter == "New") Icons.Rounded.NotificationsNone else Icons.Rounded.Inventory2, size = 72)
                Text(when (filter) { "New" -> stringResource(R.string.g3_vo_empty_new); "Active" -> stringResource(R.string.g3_vo_empty_active); else -> stringResource(R.string.g3_vo_empty_done) }, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted(when (filter) { "New" -> stringResource(R.string.g3_vo_empty_new_body); "Active" -> stringResource(R.string.g3_vo_empty_active_body); else -> stringResource(R.string.g3_vo_empty_done_body) }, Modifier.padding(top = 6.dp), TextAlign.Center)
            }
            else -> LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(shown, key = { it.id }) { o ->
                    val riders = commerce.riders[listingId].orEmpty()
                    VendorOrderCard(o, buyer = social.nameOf(o.buyerId), now = now, busy = commerce.isActing(o.id), onOpen = { onOpen(o.id) },
                        delivery = commerce.deliveries[o.id], hasRiders = riders.isNotEmpty(),
                        onAccept = { commerce.respondOrder(o.id, true) }, onChooseRider = { choosing = Choosing(o, accept = true) },
                        onRingAgain = { commerce.reassignDelivery(o.id, null) }, onSendRider = { choosing = Choosing(o, accept = false) },
                        onCallRider = { p -> dial(ctx, p) }, onReject = { rejectFor = o },
                        onReady = { commerce.updateOrderStatus(o.id, "READY") }, onCollected = { commerce.updateOrderStatus(o.id, "DELIVERED") }, onShip = { shipFor = o }, onDelivered = { commerce.markDelivered(o.id) },
                        onCall = { scope.launch { val c = runCatching { commerce.contactFor(o.id) }.getOrNull(); val p = c?.phone; if (p.isNullOrBlank()) vm.toast(Str.get(R.string.g3_vo_no_phone)) else dial(ctx, p) } })
                }
                item { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
    choosing?.let { c ->
        RiderSheet(commerce.riders[listingId].orEmpty(), preselect = Prefs.lastRider(listingId), accept = c.accept, busy = commerce.isActing(c.order.id),
            onDismiss = { choosing = null }) { r ->
            Prefs.rememberRider(listingId, r.profileId)
            if (c.accept) commerce.respondOrder(c.order.id, true, rider = r) { ok -> if (ok) choosing = null }
            else commerce.reassignDelivery(c.order.id, r) { ok -> if (ok) choosing = null }
        }
    }
    shipFor?.let { o -> ShipSheet({ shipFor = null }) { c, t, u -> shipFor = null; commerce.shipOrder(o.id, c, t, u) } }
    rejectFor?.let { o ->
        var busy by remember { mutableStateOf(false) }
        CancelSheet(
            title = stringResource(R.string.g3_vo_reject_title), message = stringResource(R.string.g3_vo_reject_body, social.nameOf(o.buyerId), title),
            reasons = CancelReasons.shopReject, requireReason = true, confirmLabel = stringResource(R.string.g3_vo_reject_confirm), reasonTitle = stringResource(R.string.g3_vo_reject_reason), busy = busy,
            onConfirm = { code, _ -> busy = true; commerce.respondOrder(o.id, false, code) { ok -> busy = false; if (ok) rejectFor = null } },
            onDismiss = { rejectFor = null })
    }
}

@Composable
private fun VendorOrderCard(o: CloudOrderRow, buyer: String, now: Long, busy: Boolean, onOpen: () -> Unit, delivery: OrderDelivery?, hasRiders: Boolean,
                            onAccept: () -> Unit, onChooseRider: () -> Unit, onRingAgain: () -> Unit, onSendRider: () -> Unit, onCallRider: (String) -> Unit, onReject: () -> Unit, onReady: () -> Unit, onCollected: () -> Unit, onShip: () -> Unit, onDelivered: () -> Unit, onCall: () -> Unit) {
    val st = MaterialTheme.status
    BucksCard(onClick = onOpen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(buyer.ifBlank { "?" }), size = 40)
            Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(buyer, style = MaterialTheme.typography.titleMedium); Muted("${ago(o.createdAt)} · ${shortOrderId(o.id)}") }
            if (o.status == "PLACED") {
                val left = epochMillis(o.acceptBy) - now
                if (left <= 0) PillBad(stringResource(R.string.g3_vo_times_up)) else Pill(stringResource(R.string.g3_vo_accept_in, if (left > 3_600_000) stringResource(R.string.g3_duration_hm, (left / 3_600_000).toInt(), (left / 60_000 % 60).toInt()) else mmss(left)), if (left < 60_000) st.badTint else st.warnTint, if (left < 60_000) st.bad else st.warn)
            } else OrderStatusPill(o.status, o.deliveryMode)
        }
        Text(orderLinesSummary(o.lines), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            // What the customer pays the shop: a Bucks rider's fee goes to the rider, a store rider's fee comes to the shop.
            Text(rupees(o.toShop), style = MaterialTheme.typography.titleMedium)
            if (o.deliveryMode != "PICKUP" && o.feePaidBy == "VENDOR") Muted("  " + stringResource(R.string.g3_vo_rider_fee_you, rupees(o.deliveryFee)))
            else if (o.deliveryMode == "STORE_RIDER" && o.deliveryFee > 0) Muted("  " + stringResource(R.string.g3_vo_incl_delivery, rupees(o.deliveryFee)))
            Spacer(Modifier.weight(1f))
            PillGrey(paymentLabel(o.payment))
        }
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(when (o.deliveryMode) { "SHIP" -> Icons.Rounded.LocalShipping; "PICKUP" -> Icons.Rounded.DirectionsWalk; "STORE_RIDER" -> Icons.Rounded.Storefront; else -> Icons.Rounded.TwoWheeler }, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Muted(" ${deliveryModeLabel(o.deliveryMode)}" + (if (o.deliveryMode != "PICKUP" && o.dropLabel.isNotBlank()) " · ${o.dropLabel}" else ""), maxLines = 1)
            if (o.shipped && o.carrier.isNotBlank()) Muted(" · ${o.carrier}" + (if (o.trackingNo.isNotBlank()) " ${o.trackingNo}" else ""), maxLines = 1)
        }
        when (o.status) {
            "PLACED" -> Column(Modifier.padding(top = 12.dp)) {
                val byRider = o.deliveryMode !in setOf("PICKUP", "SHIP")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // One tap does the common thing: accept, and Bucks rings the right riders.
                    SmallButton(if (busy) stringResource(R.string.g3_working) else if (byRider) stringResource(R.string.g3_vo_accept_auto) else stringResource(R.string.g3_vo_accept), Modifier.weight(1.4f), enabled = !busy, onClick = onAccept)
                    SmallButton(stringResource(R.string.g3_vo_reject), Modifier.weight(1f), tonal = true, enabled = !busy, onClick = onReject)
                }
                if (byRider && hasRiders) TextButton(onChooseRider, enabled = !busy) { Icon(Icons.Rounded.TwoWheeler, null, Modifier.size(18.dp)); Text("  " + stringResource(R.string.g3_vo_accept_choose)) }
            }
            "ACCEPTED", "READY", "PICKED_UP", "SHIPPED" -> Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallButton(stringResource(R.string.g3_vo_call_customer), Modifier.weight(1f), tonal = true, onClick = onCall)
                if (o.shipped) { if (o.status == "ACCEPTED") SmallButton(if (busy) stringResource(R.string.g3_working) else stringResource(R.string.g3_vo_mark_shipped), Modifier.weight(1f), enabled = !busy, onClick = onShip) else if (o.status == "SHIPPED") SmallButton(if (busy) stringResource(R.string.g3_working) else stringResource(R.string.g3_vo_mark_delivered), Modifier.weight(1f), enabled = !busy, onClick = onDelivered) }
                else if (o.status == "ACCEPTED") SmallButton(if (busy) stringResource(R.string.g3_working) else if (o.deliveryMode == "PICKUP") stringResource(R.string.g3_vo_ready_collect) else stringResource(R.string.g3_vo_packed), Modifier.weight(1f), enabled = !busy, onClick = onReady)
                else if (o.status == "READY" && o.deliveryMode == "PICKUP") SmallButton(if (busy) stringResource(R.string.g3_working) else stringResource(R.string.g3_vo_collected), Modifier.weight(1f), enabled = !busy, onClick = onCollected)
            }
            else -> {}
        }
        val payRider = if (o.deliveryMode == "MARKETPLACE" && o.feePaidBy == "VENDOR") " " + stringResource(R.string.g3_vo_pay_rider, rupees(o.deliveryFee)) else ""
        if (o.shipped && o.status == "ACCEPTED") Muted(stringResource(R.string.g3_vo_pack_hint), Modifier.padding(top = 8.dp))
        if (o.status in setOf("ACCEPTED", "READY", "PICKED_UP") && o.deliveryMode !in setOf("PICKUP", "SHIP"))
            DeliveryLine(delivery, busy, hasRiders, onRingAgain, onSendRider, onCallRider, Modifier.padding(top = 10.dp))
        if (o.status in setOf("ACCEPTED", "READY") && payRider.isNotBlank()) Muted(payRider.trim(), Modifier.padding(top = 6.dp))
    }
}

internal data class Choosing(val order: CloudOrderRow, val accept: Boolean)

/** Where the delivery stands, with what the shop can do about it: ring again or send its rider while nobody has it, call its rider. */
@Composable
private fun DeliveryLine(d: OrderDelivery?, busy: Boolean, hasRiders: Boolean, onRingAgain: () -> Unit, onSendRider: () -> Unit, onCallRider: (String) -> Unit, modifier: Modifier) {
    val rider = d?.riderName?.substringBefore(' ') ?: stringResource(R.string.g3_vo_the_rider)
    val (icon, text) = when (d?.status) {
        null -> Icons.Rounded.HourglassTop to stringResource(R.string.g3_vo_finding_rider)
        "SEARCHING" -> Icons.Rounded.NotificationsActive to (if (d.exclusiveUntil != null) stringResource(R.string.g3_vo_ringing_first) else if (d.onlyStoreRiders) stringResource(R.string.g3_vo_ringing_yours) else stringResource(R.string.g3_vo_ringing_nearby))
        "NO_DRIVER" -> Icons.Rounded.ErrorOutline to stringResource(R.string.g3_vo_no_rider)
        "MATCHED" -> Icons.Rounded.TwoWheeler to (d.plate?.let { stringResource(R.string.g3_vo_rider_coming_plate, rider, it) } ?: stringResource(R.string.g3_vo_rider_coming, rider))
        "ARRIVED" -> Icons.Rounded.Storefront to stringResource(R.string.g3_vo_rider_at_shop, rider)
        "IN_PROGRESS" -> Icons.Rounded.LocalShipping to stringResource(R.string.g3_vo_rider_to_customer, rider)
        "COMPLETED" -> Icons.Rounded.Done to stringResource(R.string.g3_order_delivered)
        else -> Icons.Rounded.Info to stringResource(R.string.g3_vo_delivery_status, d.status.lowercase())
    }
    Column(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(18.dp), tint = if (d?.status == "NO_DRIVER") MaterialTheme.status.bad else MaterialTheme.colorScheme.primary)
            Text(" $text", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        }
        // The pickup PIN goes with the parcel: the rider enters it when they collect.
        if (d != null && d.status in setOf("MATCHED", "ARRIVED") && !d.pin.isNullOrBlank()) Muted(stringResource(R.string.g3_vo_handover_pin, d.pin.orEmpty()), Modifier.padding(top = 4.dp))
        if (d != null && (d.waiting || d.riderPhone != null)) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (d.waiting) SmallButton(if (busy) stringResource(R.string.g3_working) else stringResource(R.string.g3_vo_ring_again), Modifier.weight(1f), tonal = true, enabled = !busy, onClick = onRingAgain)
            if (d.waiting && hasRiders) SmallButton(stringResource(R.string.g3_vo_send_my_rider), Modifier.weight(1f), enabled = !busy, onClick = onSendRider)
            d.riderPhone?.takeIf { !d.waiting }?.let { p -> SmallButton(stringResource(R.string.g3_vo_call_rider, rider), Modifier.weight(1f), tonal = true) { onCallRider(p) } }
        }
    }
}

/** The shop's riders, online first, the last one used preselected; one tap on Send confirms. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RiderSheet(riders: List<StoreRider>, preselect: String?, accept: Boolean, busy: Boolean, onDismiss: () -> Unit, onPick: (StoreRider) -> Unit) {
    var picked by remember { mutableStateOf(riders.firstOrNull { it.profileId == preselect } ?: riders.firstOrNull { it.online } ?: riders.firstOrNull()) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Text(if (accept) stringResource(R.string.g3_vo_sheet_accept_title) else stringResource(R.string.g3_vo_sheet_send_title), style = MaterialTheme.typography.titleLarge)
            Muted(if (accept) stringResource(R.string.g3_vo_sheet_body_accept) else stringResource(R.string.g3_vo_sheet_body_send), Modifier.padding(top = 4.dp, bottom = 8.dp))
            if (riders.isEmpty()) Muted(stringResource(R.string.g3_vo_no_riders))
            riders.forEach { r ->
                Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).clickable { picked = r }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(picked?.profileId == r.profileId, { picked = r })
                    Avatar(initials(r.name), size = 36, photoUrl = r.photoUrl)
                    Column(Modifier.weight(1f).padding(start = 10.dp)) {
                        Text(r.name, style = MaterialTheme.typography.bodyLarge)
                        Muted(when { r.online -> stringResource(R.string.g3_vo_rider_online); !r.hasBike -> stringResource(R.string.g3_vo_rider_no_bike); else -> stringResource(R.string.g3_vo_rider_offline) })
                    }
                    Box(Modifier.size(10.dp).clip(CircleShape).background(if (r.online) MaterialTheme.status.good else MaterialTheme.colorScheme.outline))
                }
            }
            PrimaryButton(if (busy) stringResource(R.string.g3_working) else picked?.let { val n = it.name.substringBefore(' '); if (accept) stringResource(R.string.g3_vo_accept_send, n) else stringResource(R.string.g3_vo_send, n) } ?: stringResource(R.string.g3_vo_choose_rider),
                Modifier.padding(top = 14.dp), enabled = !busy && picked != null) { picked?.let(onPick) }
        }
    }
}
