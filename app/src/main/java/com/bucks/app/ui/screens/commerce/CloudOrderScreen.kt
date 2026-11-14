package com.bucks.app.ui.screens.commerce

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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.myOrderReview
import com.bucks.app.ui.theme.status
import com.bucks.app.data.CloudOrderRow
import com.bucks.app.data.OrderContactRow
import com.bucks.app.data.TaskRow
import com.bucks.app.data.liveOrder
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.secondsSince
import com.bucks.app.data.CancelReasons
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.bucks.app.R
import androidx.compose.ui.res.stringResource

/**
 * The order page. For the buyer: lines and totals, a status timeline, pay the shop by UPI, call the shop, track the delivery,
 * cancel while the shop hasn't answered. For the shop owner or an admin opening it from the inbox (the viewer is not the buyer):
 * the same order in the shop's words, with accept / reject / packed / collected, "Call <customer>" and cancel for an accepted
 * order no rider has taken. Follows the row live and also polls every 10 seconds; a failed load keeps retrying.
 */
@Composable
fun CloudOrderScreen(vm: BucksViewModel, orderId: String, onBack: () -> Unit, onTrack: (String) -> Unit, onOpenListing: (String) -> Unit) {
    val commerce = vm.commerce; val social = vm.social; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val o = commerce.orders[orderId]
    var missing by remember { mutableStateOf(false) }
    // The last load threw (no signal, timeout, token refresh) and nothing is cached yet: not the same as "no such order".
    var loadFailed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var task by remember { mutableStateOf<TaskRow?>(null) }
    var contact by remember { mutableStateOf<OrderContactRow?>(null) }
    var confirmCancel by remember { mutableStateOf(false) }
    var confirmReject by remember { mutableStateOf(false) }
    var showShip by remember { mutableStateOf(false) }
    // First load, then a 10-second poll: status, the delivery task once accepted, and contact details while live.
    LaunchedEffect(orderId, attempt) {
        while (true) {
            val res = runCatching { commerce.order(orderId) }
            res.exceptionOrNull()?.let { if (it is CancellationException) throw it }   // "Try again" restarted the loop
            val row = res.getOrNull()
            // Only a query that worked and found no row means the order is not ours; a failure is retried on the next round.
            if (res.isSuccess && row == null && commerce.orders[orderId] == null) { missing = true; break }
            loadFailed = res.isFailure && commerce.orders[orderId] == null
            val cur = row ?: commerce.orders[orderId]
            if (cur != null) {
                val mine = cur.buyerId == social.me?.id
                if (mine && cur.deliveryMode !in setOf("PICKUP", "SHIP") && cur.status in setOf("ACCEPTED", "READY", "PICKED_UP", "DELIVERED") && task?.status != "COMPLETED") task = runCatching { commerce.taskForOrder(orderId) }.getOrNull() ?: task
                if (hasContact(cur)) contact = runCatching { commerce.contactFor(orderId) }.getOrNull() ?: contact
                if (orderDone(cur.status) && (!hasContact(cur) || contact != null)) break
            }
            delay(10_000)
        }
    }
    DisposableEffect(orderId) {
        val (channel, flow) = Backend.liveOrder(orderId)
        val job = scope.launch { runCatching { flow.collect { commerce.orders[it.id] = it } } }
        onDispose { job.cancel(); Backend.releaseChannel(channel) }
    }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g6_order_title), onBack = onBack)
        when {
            missing -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(R.string.g6_order_missing), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g6_order_missing_detail), Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton(stringResource(R.string.g6_go_back), Modifier.padding(top = 18.dp), onClick = onBack) }
            o == null && loadFailed -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(R.string.g6_order_load_failed), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g6_order_load_failed_detail), Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton(stringResource(R.string.g6_try_again), Modifier.padding(top = 18.dp)) { loadFailed = false; attempt++ } }
            o == null -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { BucksLoader() }
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                val title = commerce.titleOf(o.listingId); val acting = commerce.isActing(o.id)
                // Anyone but the buyer who can read the order runs the shop (owner, admin); they get the shop's view.
                val vendor = o.buyerId != social.me?.id
                val customer = social.nameOf(o.buyerId).takeIf { it != "…" && it.isNotBlank() }
                Row(Modifier.fillMaxWidth().clickable { onOpenListing(o.listingId) }, verticalAlignment = Alignment.CenterVertically) {
                    Avatar(icon = Icons.Rounded.Storefront, tinted = false)
                    Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(title, style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g6_order_header_line, shortOrderId(o.id), ago(o.createdAt), deliveryModeLabel(o.deliveryMode))) }
                    Icon(Icons.Rounded.ChevronRight, stringResource(R.string.g6_cd_open_shop), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (vendor) Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Person, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(" " + (if (customer != null) stringResource(R.string.g6_order_for_name, customer) else stringResource(R.string.g6_order_for_customer)), style = MaterialTheme.typography.titleSmall)
                }
                Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) { OrderStatusPill(o.status, o.deliveryMode); Spacer(Modifier.width(8.dp)); PillGrey(paymentLabel(o.payment)) }

                BucksCard(Modifier.padding(top = 14.dp)) {
                    o.lines.forEach { OrderLineRow(it) }
                    OrderTotals(o, forShop = vendor)
                    if (o.deliveryMode !in setOf("PICKUP", "SHIP") && o.dropLabel.isNotBlank()) Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Place, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${o.dropLabel}") }
                }

                ShipToCard(o, Modifier.padding(top = 12.dp))
                ShipmentCard(o, Modifier.padding(top = 12.dp))
                SectionTitle(stringResource(R.string.g6_order_progress), Modifier.padding(top = 22.dp, bottom = 10.dp))
                if (o.status == "PLACED" && !vendor) AcceptCountdown(o.acceptBy)
                OrderTimeline(o.status, o.deliveryMode, task, forShop = vendor, cancelledBy = o.cancelledBy, carrier = o.carrier, ringWindowS = vm.dispatch.ringWindowS)
                if (!vendor && o.status == "DELIVERED") OrderReviewCard(vm, o.id, o.listingId, commerce.titleOf(o.listingId))

                if (!vendor) {
                    // The shop is paid for what it sells (and its own rider's fee); a Bucks rider's fee goes to the rider at the door.
                    val payable = o.payment == "UPI" && o.status in setOf("ACCEPTED", "READY", "PICKED_UP", "SHIPPED", "DELIVERED")
                    val riderNote = if (o.feeAtDoor > 0) stringResource(R.string.g6_order_rider_note, rupees(o.feeAtDoor)) else ""
                    fun withNote(text: String) = if (riderNote.isEmpty()) text else "$text $riderNote"
                    val msgNoUpiApp = stringResource(R.string.g6_order_no_upi_app)
                    if (payable) {
                        val upi = contact?.upiUri
                        PrimaryButton(stringResource(R.string.g6_order_pay_upi_btn, rupees(o.toShop)), Modifier.padding(top = 18.dp), enabled = upi != null) {
                            if (upi == null) return@PrimaryButton
                            if (!openUpi(ctx, upiPayUri(upi, o.toShop, "Bucks order ${shortOrderId(o.id)}"))) vm.toast(msgNoUpiApp)
                        }
                        Muted(when { upi != null -> withNote(stringResource(R.string.g6_order_upi_opens, title)); contact == null -> stringResource(R.string.g6_order_upi_loading); else -> withNote(stringResource(R.string.g6_order_upi_none, title)) }, Modifier.padding(top = 6.dp).fillMaxWidth(), TextAlign.Center)
                    } else if (o.payment == "UPI" && o.status == "PLACED") Muted(withNote(stringResource(R.string.g6_order_upi_after_accept, title)), Modifier.padding(top = 18.dp).fillMaxWidth(), TextAlign.Center)
                    else if (o.payment == "COD" && orderLive(o.status)) Notice(stringResource(R.string.g6_order_cod_ready, rupees(o.total)), Modifier.padding(top = 18.dp))

                    if (o.shipped && o.status == "SHIPPED") PrimaryButton(stringResource(R.string.g6_order_received), Modifier.padding(top = 10.dp)) { commerce.markDelivered(o.id) }
                    val t = task
                    if (t != null && t.status != "COMPLETED" && t.status != "PAID" && t.status != "CANCELLED") TintButton(stringResource(R.string.g6_order_track), Modifier.padding(top = 10.dp)) { onTrack(t.id) }
                } else when (o.status) {
                    "PLACED" -> Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallButton(if (acting) stringResource(R.string.g6_order_working) else stringResource(R.string.g6_accept), Modifier.weight(1f), enabled = !acting) { commerce.respondOrder(o.id, true) }
                        SmallButton(stringResource(R.string.g6_order_reject), Modifier.weight(1f), tonal = true, enabled = !acting) { confirmReject = true }
                    }
                    "ACCEPTED" -> if (o.shipped) PrimaryButton(if (acting) stringResource(R.string.g6_order_working) else stringResource(R.string.g6_order_mark_shipped), Modifier.padding(top = 18.dp), enabled = !acting) { showShip = true }
                                  else PrimaryButton(if (acting) stringResource(R.string.g6_order_working) else if (o.deliveryMode == "PICKUP") stringResource(R.string.g6_order_btn_ready) else stringResource(R.string.g6_order_btn_packed), Modifier.padding(top = 18.dp), enabled = !acting) { commerce.updateOrderStatus(o.id, "READY") }
                    "SHIPPED" -> if (o.shipped) PrimaryButton(if (acting) stringResource(R.string.g6_order_working) else stringResource(R.string.g6_order_mark_delivered), Modifier.padding(top = 18.dp), enabled = !acting) { commerce.markDelivered(o.id) }
                    "READY" -> if (o.deliveryMode == "PICKUP") PrimaryButton(if (acting) stringResource(R.string.g6_order_working) else stringResource(R.string.g6_order_btn_collected), Modifier.padding(top = 18.dp), enabled = !acting) { commerce.updateOrderStatus(o.id, "DELIVERED") }
                    else -> {}
                }
                if (hasContact(o)) {
                    val phone = contact?.phone
                    val who = if (vendor) (if (phone != null && customer != null) customer else null) else (if (phone != null) title else null)
                    GhostButton(if (who != null) stringResource(R.string.g6_order_call_name, who) else stringResource(if (vendor) R.string.g6_order_call_customer else R.string.g6_order_call_shop), Modifier.padding(top = 10.dp), enabled = phone != null) { phone?.let { dial(ctx, it) } }
                }
                // Buyer: only before the shop answers. Shop: an accepted order no rider has taken (the server refuses once one has).
                if ((!vendor && o.status == "PLACED") || (vendor && o.status in setOf("ACCEPTED", "READY"))) BadButton(if (acting) stringResource(R.string.g6_order_working) else stringResource(R.string.g6_order_cancel), Modifier.padding(top = 10.dp), enabled = !acting) { confirmCancel = true }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    // The order as the shop sees it (null for the buyer): decides which cancel the dialog runs.
    val shopOrder = commerce.orders[orderId]?.takeIf { it.buyerId != social.me?.id }
    val shopSide = shopOrder != null
    var busy by remember { mutableStateOf(false) }
    if (confirmCancel) CancelSheet(
        title = stringResource(R.string.g6_order_cancel_title),
        message = when {
            shopOrder == null -> stringResource(R.string.g6_order_cancel_msg_buyer)
            shopOrder.shipped -> stringResource(if (shopOrder.payment == "UPI") R.string.g6_order_cancel_msg_ship_upi else R.string.g6_order_cancel_msg_ship)
            shopOrder.deliveryMode == "PICKUP" -> stringResource(if (shopOrder.payment == "UPI") R.string.g6_order_cancel_msg_pickup_upi else R.string.g6_order_cancel_msg_pickup)
            else -> stringResource(if (shopOrder.payment == "UPI") R.string.g6_order_cancel_msg_rider_upi else R.string.g6_order_cancel_msg_rider)
        },
        reasons = if (shopSide) CancelReasons.shop else CancelReasons.buyer, requireReason = shopSide, confirmLabel = stringResource(R.string.g6_order_cancel), busy = busy,
        onConfirm = { code, _ -> busy = true
            val done = { ok: Boolean -> busy = false; if (ok) confirmCancel = false }
            if (shopSide) commerce.updateOrderStatus(orderId, "CANCELLED", code, done) else commerce.cancelOrder(orderId, code, done) },
        onDismiss = { confirmCancel = false })
    if (showShip) ShipSheet({ showShip = false }) { c, t, u -> showShip = false; commerce.shipOrder(orderId, c, t, u) }
    if (confirmReject) CancelSheet(
        title = stringResource(R.string.g6_order_reject_title), message = stringResource(R.string.g6_order_reject_msg),
        reasons = CancelReasons.shopReject, requireReason = true, confirmLabel = stringResource(R.string.g6_order_reject_btn), reasonTitle = stringResource(R.string.g6_order_reject_reason), busy = busy,
        onConfirm = { code, _ -> busy = true; commerce.respondOrder(orderId, false, code) { ok -> busy = false; if (ok) confirmReject = false } },
        onDismiss = { confirmReject = false })
}

/** Contact details are shared while the order is live or delivered, and after the shop cancelled an accepted one (for a refund). */
private fun hasContact(o: CloudOrderRow) = orderLive(o.status) || o.status == "DELIVERED" || (o.status == "CANCELLED" && o.cancelledBy == "SHOP")

/**
 * PLACED -> ACCEPTED -> (READY) -> PICKED_UP -> DELIVERED, or a terminal REJECTED / CANCELLED with a plain explanation.
 * [forShop] words it for the shop; the buyer sees the pickup PIN while the rider is on the way to or at the shop, which is when
 * the rider calls for it (advance_task checks it at pick-up, not at the door).
 */
@Composable
fun OrderTimeline(status: String, mode: String, task: TaskRow?, forShop: Boolean = false, cancelledBy: String? = null, carrier: String = "", ringWindowS: Long = 180) {
    if (status == "REJECTED" || status == "CANCELLED") {
        val byShop = cancelledBy == "SHOP"
        val head = when {
            status == "REJECTED" -> if (forShop) stringResource(R.string.g6_tl_rejected_shop) else stringResource(R.string.g6_tl_rejected_buyer)
            byShop -> if (forShop) stringResource(R.string.g6_tl_you_cancelled) else stringResource(R.string.g6_tl_shop_cancelled)
            else -> if (forShop) stringResource(R.string.g6_tl_customer_cancelled) else stringResource(R.string.g6_tl_you_cancelled)
        }
        val detail = when {
            status == "REJECTED" -> if (forShop) stringResource(R.string.g6_tl_rejected_shop_detail) else stringResource(R.string.g6_tl_rejected_buyer_detail)
            byShop -> if (forShop) stringResource(R.string.g6_tl_shop_cancelled_shop_detail) else stringResource(R.string.g6_tl_shop_cancelled_buyer_detail)
            else -> if (forShop) stringResource(R.string.g6_tl_customer_cancelled_detail) else stringResource(R.string.g6_tl_nothing_charged)
        }
        BucksCard {
            Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Info, null, tint = MaterialTheme.colorScheme.error); Text(head, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 10.dp)) }
            Muted(detail, Modifier.padding(top = 8.dp))
        }
        return
    }
    val pickup = mode == "PICKUP"; val ship = mode == "SHIP"
    val sPlaced = stringResource(R.string.g6_tl_step_placed); val sAccepted = stringResource(R.string.g6_tl_step_accepted)
    val sDelivered = stringResource(R.string.g6_order_st_delivered)
    val steps = if (ship) listOf("PLACED" to sPlaced, "ACCEPTED" to sAccepted, "SHIPPED" to stringResource(R.string.g6_order_st_shipped), "DELIVERED" to sDelivered)
                else if (pickup) listOf("PLACED" to sPlaced, "ACCEPTED" to sAccepted, "READY" to stringResource(R.string.g6_order_st_ready_pickup), "DELIVERED" to stringResource(R.string.g6_order_st_collected))
                else listOf("PLACED" to sPlaced, "ACCEPTED" to sAccepted, "PICKED_UP" to stringResource(R.string.g6_tl_step_picked_up), "DELIVERED" to sDelivered)
    val order = listOf("PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED", "DELIVERED")
    val at = order.indexOf(status).coerceAtLeast(0)
    val cur = if (!pickup && status == "READY") "ACCEPTED" else status
    // The rider asks for the PIN at the shop (ARRIVED -> IN_PROGRESS), so it is shown until then and not after.
    val pin = task?.takeIf { it.status in setOf("SEARCHING", "MATCHED", "ARRIVED") }?.pin?.takeIf { it.isNotBlank() }
    Column {
        steps.forEachIndexed { i, (key, label) ->
            val idx = order.indexOf(key)
            val detail = when (key) {
                "PLACED" -> if (ship) (if (forShop) stringResource(R.string.g6_tl_placed_ship_shop) else stringResource(R.string.g6_tl_placed_ship_buyer)) else if (forShop) stringResource(R.string.g6_tl_placed_shop) else stringResource(R.string.g6_tl_placed_buyer)
                "SHIPPED" -> if (forShop) (if (carrier.isBlank()) stringResource(R.string.g6_tl_shipped_shop) else stringResource(R.string.g6_tl_shipped_shop_carrier, carrier)) else (if (carrier.isBlank()) stringResource(R.string.g6_tl_shipped_buyer) else stringResource(R.string.g6_tl_shipped_buyer_carrier, carrier))
                "ACCEPTED" -> when {
                    ship -> if (forShop) stringResource(R.string.g6_tl_acc_ship_shop) else stringResource(R.string.g6_tl_acc_ship_buyer)
                    pickup -> if (forShop) stringResource(R.string.g6_tl_acc_pickup_shop) else stringResource(R.string.g6_tl_acc_pickup_buyer)
                    forShop -> if (status == "READY") stringResource(R.string.g6_tl_acc_ready_shop) else stringResource(R.string.g6_tl_acc_ringing_shop)
                    else -> {
                        // A request still SEARCHING past the ring window has run out, even before the server's expiry has marked it (same rule as the delivery tracker).
                        val stale = task?.status == "SEARCHING" && (secondsSince(task.statusAt.ifBlank { task.createdAt }) ?: 0) >= ringWindowS
                        val rider = when (if (stale) "NO_DRIVER" else task?.status) {
                            null -> stringResource(R.string.g6_tl_rider_finding)
                            "SEARCHING" -> stringResource(R.string.g6_tl_rider_ringing)
                            "NO_DRIVER" -> stringResource(R.string.g6_tl_rider_none)
                            "CANCELLED" -> stringResource(R.string.g6_tl_rider_cancelled)
                            "ARRIVED" -> stringResource(R.string.g6_tl_rider_at_shop)
                            else -> stringResource(R.string.g6_tl_rider_coming)
                        }
                        listOfNotNull(if (status == "READY") stringResource(R.string.g6_tl_packed) else null, rider, pin?.let { stringResource(R.string.g6_tl_pin_note, it) }).joinToString(" ")
                    }
                }
                "READY" -> if (forShop) stringResource(R.string.g6_tl_ready_shop) else stringResource(R.string.g6_tl_ready_buyer)
                "PICKED_UP" -> if (forShop) stringResource(R.string.g6_tl_picked_shop) else stringResource(R.string.g6_tl_picked_buyer)
                else -> if (forShop) stringResource(R.string.g6_tl_done_shop) else stringResource(R.string.g6_tl_done_buyer)
            }
            StatusLine(label, detail, done = idx < at && key != cur, now = key == cur, last = i == steps.lastIndex)
        }
    }
}

/**
 * "How was it?" on a delivered order: the arrows open the feedback box, and the vote is saved as a verified review (review with
 * p_order), the strongest kind there is. A down needs a reason. Once given, the card shows the arrow instead.
 */
@Composable
private fun OrderReviewCard(vm: BucksViewModel, orderId: String, listingId: String, shop: String) {
    val scope = rememberCoroutineScope()
    var mine by remember(orderId) { mutableStateOf<Int?>(null) }; var loaded by remember(orderId) { mutableStateOf(false) }
    var voting by remember { mutableStateOf<Int?>(null) }; var busy by remember { mutableStateOf(false) }
    LaunchedEffect(orderId) { mine = runCatching { Backend.myOrderReview(orderId) }.getOrNull(); loaded = true }
    if (!loaded) return
    BucksCard(Modifier.padding(top = 16.dp)) {
        val v = mine
        if (v != null) Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (v > 0) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (v > 0) stringResource(R.string.g6_cd_recommended) else stringResource(R.string.g6_cd_not_recommended), tint = if (v > 0) MaterialTheme.status.good else MaterialTheme.status.bad)
            Muted("  " + stringResource(R.string.g6_review_thanks_verified))
        } else {
            Text(stringResource(R.string.g6_review_how), style = MaterialTheme.typography.titleMedium)
            Muted(stringResource(R.string.g6_review_votes_hint), Modifier.padding(top = 2.dp))
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VoteArrow(true, false, Modifier.weight(1f)) { voting = 1 }; VoteArrow(false, false, Modifier.weight(1f)) { voting = -1 }
            }
        }
    }
    val msgPosted = stringResource(R.string.g6_review_posted); val msgSendFailed = stringResource(R.string.g6_review_send_failed)
    voting?.let { start -> VoteFeedbackSheet(stringResource(R.string.g6_review_sheet_title, shop), start, busy = busy, askReason = true, onSubmit = { vote, text, reason ->
        scope.launch { busy = true
            runCatching { Backend.review(listingId, null, orderId, vote > 0, text, reason) }
                .onSuccess { mine = vote; voting = null; vm.toast(msgPosted) }
                .onFailure { vm.toast(it.message?.substringAfter("message\":\"")?.substringBefore('"')?.takeIf { m -> m.length in 3..120 } ?: msgSendFailed) }
            busy = false } }, onDismiss = { voting = null }) }
}


/** While the shop decides: a live "Shop has 3:42 to accept" so waiting doesn't feel like nothing is happening. */
@Composable
private fun AcceptCountdown(acceptBy: String) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(acceptBy) { while (true) { now = System.currentTimeMillis(); kotlinx.coroutines.delay(1000) } }
    val left = epochMillis(acceptBy) - now
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.HourglassTop, null, tint = MaterialTheme.colorScheme.onSecondaryContainer)
            Text(if (left <= 0) stringResource(R.string.g6_order_accept_timeout) else stringResource(R.string.g6_order_accept_left, if (left > 3_600_000) stringResource(R.string.g6_order_dur_hm, (left / 3_600_000).toInt(), (left / 60_000 % 60).toInt()) else mmss(left)),
                style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.padding(start = 10.dp))
        }
    }
}
