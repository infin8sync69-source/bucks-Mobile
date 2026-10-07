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
import com.bucks.app.data.CancelReasons
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
        onDispose { job.cancel(); scope.launch { Backend.closeChannel(channel) } }
    }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Order", onBack = onBack)
        when {
            missing -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("This order isn't here", style = MaterialTheme.typography.titleLarge); Muted("It may belong to another account. Your orders are under Account > Activity.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Go back", Modifier.padding(top = 18.dp), onClick = onBack) }
            o == null && loadFailed -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Couldn't load this order", style = MaterialTheme.typography.titleLarge); Muted("Check your connection. We'll keep trying every few seconds.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Try again", Modifier.padding(top = 18.dp)) { loadFailed = false; attempt++ } }
            o == null -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { BucksLoader() }
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                val title = commerce.titleOf(o.listingId)
                // Anyone but the buyer who can read the order runs the shop (owner, admin); they get the shop's view.
                val vendor = o.buyerId != social.me?.id
                val customer = social.nameOf(o.buyerId).takeIf { it != "…" && it.isNotBlank() }
                Row(Modifier.fillMaxWidth().clickable { onOpenListing(o.listingId) }, verticalAlignment = Alignment.CenterVertically) {
                    Avatar(icon = Icons.Rounded.Storefront, tinted = false)
                    Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(title, style = MaterialTheme.typography.titleLarge); Muted("Order ${shortOrderId(o.id)} · ${ago(o.createdAt)} · ${deliveryModeLabel(o.deliveryMode)}") }
                    Icon(Icons.Rounded.ChevronRight, "Open shop", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (vendor) Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Person, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(" For ${customer ?: "a customer"}", style = MaterialTheme.typography.titleSmall)
                }
                Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) { OrderStatusPill(o.status, o.deliveryMode); Spacer(Modifier.width(8.dp)); PillGrey(paymentLabel(o.payment)) }

                BucksCard(Modifier.padding(top = 14.dp)) {
                    o.lines.forEach { OrderLineRow(it) }
                    OrderTotals(o, forShop = vendor)
                    if (o.deliveryMode !in setOf("PICKUP", "SHIP") && o.dropLabel.isNotBlank()) Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Place, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${o.dropLabel}") }
                }

                ShipToCard(o, Modifier.padding(top = 12.dp))
                ShipmentCard(o, Modifier.padding(top = 12.dp))
                SectionTitle("Progress", Modifier.padding(top = 22.dp, bottom = 10.dp))
                OrderTimeline(o.status, o.deliveryMode, task, forShop = vendor, cancelledBy = o.cancelledBy, carrier = o.carrier)
                if (!vendor && o.status == "DELIVERED") OrderReviewCard(vm, o.id, o.listingId, commerce.titleOf(o.listingId))

                if (!vendor) {
                    // The shop is paid for what it sells (and its own rider's fee); a Bucks rider's fee goes to the rider at the door.
                    val payable = o.payment == "UPI" && o.status in setOf("ACCEPTED", "READY", "PICKED_UP", "SHIPPED", "DELIVERED")
                    val riderNote = if (o.feeAtDoor > 0) " The rider's ${rupees(o.feeAtDoor)} fee is paid to the rider at the door, not here." else ""
                    if (payable) {
                        val upi = contact?.upiUri
                        PrimaryButton("Pay ${rupees(o.toShop)} by UPI", Modifier.padding(top = 18.dp), enabled = upi != null) {
                            if (upi == null) return@PrimaryButton
                            if (!openUpi(ctx, upiPayUri(upi, o.toShop, "Bucks order ${shortOrderId(o.id)}"))) vm.toast("No UPI app found on this phone. Pay the shop directly.")
                        }
                        Muted(when { upi != null -> "Opens your UPI app with ${title}'s QR and the amount filled in.$riderNote"; contact == null -> "Getting the shop's payment details…"; else -> "${title} hasn't added a UPI QR yet. Pay them directly when you receive the order.$riderNote" }, Modifier.padding(top = 6.dp).fillMaxWidth(), TextAlign.Center)
                    } else if (o.payment == "UPI" && o.status == "PLACED") Muted("You can pay by UPI once ${title} accepts.$riderNote", Modifier.padding(top = 18.dp).fillMaxWidth(), TextAlign.Center)
                    else if (o.payment == "COD" && orderLive(o.status)) Notice("Keep ${rupees(o.total)} in cash ready for the store's rider.", Modifier.padding(top = 18.dp))

                    if (o.shipped && o.status == "SHIPPED") PrimaryButton("I received it", Modifier.padding(top = 10.dp)) { commerce.markDelivered(o.id) }
                    val t = task
                    if (t != null && t.status != "COMPLETED" && t.status != "PAID" && t.status != "CANCELLED") TintButton("Track delivery", Modifier.padding(top = 10.dp)) { onTrack(t.id) }
                } else when (o.status) {
                    "PLACED" -> Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallButton("Accept", Modifier.weight(1f)) { commerce.respondOrder(o.id, true) }
                        SmallButton("Reject", Modifier.weight(1f), tonal = true) { confirmReject = true }
                    }
                    "ACCEPTED" -> if (o.shipped) PrimaryButton("Mark shipped", Modifier.padding(top = 18.dp)) { showShip = true }
                                  else PrimaryButton(if (o.deliveryMode == "PICKUP") "Ready to collect" else "Packed", Modifier.padding(top = 18.dp)) { commerce.updateOrderStatus(o.id, "READY") }
                    "SHIPPED" -> if (o.shipped) PrimaryButton("Mark delivered", Modifier.padding(top = 18.dp)) { commerce.markDelivered(o.id) }
                    "READY" -> if (o.deliveryMode == "PICKUP") PrimaryButton("Collected", Modifier.padding(top = 18.dp)) { commerce.updateOrderStatus(o.id, "DELIVERED") }
                    else -> {}
                }
                if (hasContact(o)) {
                    val phone = contact?.phone
                    val who = if (vendor) (if (phone != null && customer != null) customer else "customer") else (if (phone != null) title else "shop")
                    GhostButton("Call $who", Modifier.padding(top = 10.dp), enabled = phone != null) { phone?.let { dial(ctx, it) } }
                }
                // Buyer: only before the shop answers. Shop: an accepted order no rider has taken (the server refuses once one has).
                if ((!vendor && o.status == "PLACED") || (vendor && o.status in setOf("ACCEPTED", "READY"))) BadButton("Cancel order", Modifier.padding(top = 10.dp)) { confirmCancel = true }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    // The order as the shop sees it (null for the buyer): decides which cancel the dialog runs.
    val shopOrder = commerce.orders[orderId]?.takeIf { it.buyerId != social.me?.id }
    val shopSide = shopOrder != null
    var busy by remember { mutableStateOf(false) }
    if (confirmCancel) CancelSheet(
        title = "Cancel this order?",
        message = when {
            shopOrder == null -> "The shop hasn't accepted it yet, so nothing is charged. Once they accept, it can't be cancelled."
            shopOrder.shipped -> "Use this when you can't fulfil the order. The customer is told it was cancelled and the stock goes back." + (if (shopOrder.payment == "UPI") " If they already paid you by UPI, refund them." else "")
            shopOrder.deliveryMode == "PICKUP" -> "Use this when the customer isn't coming to collect it. They'll be told it was cancelled." + (if (shopOrder.payment == "UPI") " If they already paid you by UPI, refund them." else "")
            else -> "Use this when no rider has taken the delivery; once a rider has it, it can't be cancelled." + (if (shopOrder.payment == "UPI") " If the customer already paid you by UPI, refund them." else "")
        },
        reasons = if (shopSide) CancelReasons.shop else CancelReasons.buyer, requireReason = shopSide, confirmLabel = "Cancel order", busy = busy,
        onConfirm = { code, _ -> busy = true
            val done = { ok: Boolean -> busy = false; if (ok) confirmCancel = false }
            if (shopSide) commerce.updateOrderStatus(orderId, "CANCELLED", code, done) else commerce.cancelOrder(orderId, code, done) },
        onDismiss = { confirmCancel = false })
    if (showShip) ShipSheet({ showShip = false }) { c, t, u -> showShip = false; commerce.shipOrder(orderId, c, t, u) }
    if (confirmReject) CancelSheet(
        title = "Reject this order?", message = "The customer will be told the shop couldn't take it. Rejecting often lowers how high the shop shows in search.",
        reasons = CancelReasons.shopReject, requireReason = true, confirmLabel = "Reject order", reasonTitle = "Why can't you take it?", busy = busy,
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
fun OrderTimeline(status: String, mode: String, task: TaskRow?, forShop: Boolean = false, cancelledBy: String? = null, carrier: String = "") {
    if (status == "REJECTED" || status == "CANCELLED") {
        val byShop = cancelledBy == "SHOP"
        val head = when {
            status == "REJECTED" -> if (forShop) "This order wasn't taken" else "The shop didn't take this order"
            byShop -> if (forShop) "You cancelled this order" else "The shop cancelled this order"
            else -> if (forShop) "The customer cancelled this order" else "You cancelled this order"
        }
        val detail = when {
            status == "REJECTED" -> if (forShop) "It was rejected or not accepted in time. The customer wasn't charged." else "Either they were too busy or they didn't respond in time. Nothing has been charged. Try another shop."
            byShop -> if (forShop) "If the customer already paid you by UPI, refund them." else "If you already paid by UPI, the shop owes you a refund. Call them if it hasn't reached you."
            else -> if (forShop) "They cancelled before you accepted, so nothing was charged." else "Nothing has been charged."
        }
        BucksCard {
            Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Info, null, tint = MaterialTheme.colorScheme.error); Text(head, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 10.dp)) }
            Muted(detail, Modifier.padding(top = 8.dp))
        }
        return
    }
    val pickup = mode == "PICKUP"; val ship = mode == "SHIP"
    val steps = if (ship) listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "SHIPPED" to "Shipped", "DELIVERED" to "Delivered")
                else if (pickup) listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "READY" to "Ready to collect", "DELIVERED" to "Collected")
                else listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "PICKED_UP" to "Rider picked it up", "DELIVERED" to "Delivered")
    val order = listOf("PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED", "DELIVERED")
    val at = order.indexOf(status).coerceAtLeast(0)
    val cur = if (!pickup && status == "READY") "ACCEPTED" else status
    // The rider asks for the PIN at the shop (ARRIVED -> IN_PROGRESS), so it is shown until then and not after.
    val pin = task?.takeIf { it.status in setOf("SEARCHING", "MATCHED", "ARRIVED") }?.pin?.takeIf { it.isNotBlank() }
    Column {
        steps.forEachIndexed { i, (key, label) ->
            val idx = order.indexOf(key)
            val detail = when (key) {
                "PLACED" -> if (ship) (if (forShop) "Accept or reject within 24 hours." else "The shop has 24 hours to accept.") else if (forShop) "Accept or reject within 5 minutes." else "The shop has 5 minutes to accept."
                "SHIPPED" -> if (forShop) "With ${carrier.ifBlank { "the carrier" }}. Mark it delivered when it arrives, or the customer will confirm." else "On its way with ${carrier.ifBlank { "the carrier" }}. Tap I received it when it arrives."
                "ACCEPTED" -> when {
                    ship -> if (forShop) "Pack it and tap Mark shipped with the carrier and tracking number." else "They're packing it. You'll get the tracking number when it ships."
                    pickup -> if (forShop) "Get it ready, then mark it ready to collect." else "They're getting it ready."
                    forShop -> if (status == "READY") "Packed. Hand it to the rider; they enter the customer's PIN when collecting." else "A rider is being rung. Mark it packed when it's ready to hand over."
                    else -> {
                        val rider = when (task?.status) {
                            null -> "Finding a rider near the shop."
                            "SEARCHING" -> "Ringing riders near the shop."
                            "NO_DRIVER" -> "No rider free right now. Call the shop: they can send their own rider or cancel the order."
                            "CANCELLED" -> "The delivery was cancelled. Call the shop to sort it out."
                            "ARRIVED" -> "The rider is at the shop."
                            else -> "A rider is on the way to the shop."
                        }
                        (if (status == "READY") "Packed. " else "") + rider + (pin?.let { " The rider will call you for PIN $it at the shop." } ?: "")
                    }
                }
                "READY" -> if (forShop) "Waiting for the customer. Tap Collected when they pick it up." else "Go to the shop and collect it."
                "PICKED_UP" -> if (forShop) "On the way to the customer." else "On the way to you."
                else -> if (forShop) "Done." else "Tell others how it went: tap an arrow below."
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
            Icon(if (v > 0) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (v > 0) "You recommended it" else "You didn't recommend it", tint = if (v > 0) MaterialTheme.status.good else MaterialTheme.status.bad)
            Muted("  Thanks. Your vote counts as a verified customer's.")
        } else {
            Text("How was it?", style = MaterialTheme.typography.titleMedium)
            Muted("Votes from people who actually ordered count the most.", Modifier.padding(top = 2.dp))
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VoteArrow(true, false, Modifier.weight(1f)) { voting = 1 }; VoteArrow(false, false, Modifier.weight(1f)) { voting = -1 }
            }
        }
    }
    voting?.let { start -> VoteFeedbackSheet("Your order from $shop", start, busy = busy, askReason = true, onSubmit = { vote, text, reason ->
        scope.launch { busy = true
            runCatching { Backend.review(listingId, null, orderId, vote > 0, text, reason) }
                .onSuccess { mine = vote; voting = null; vm.toast("Thanks. Your vote is posted.") }
                .onFailure { vm.toast(it.message?.substringAfter("message\":\"")?.substringBefore('"')?.takeIf { m -> m.length in 3..120 } ?: "Couldn't send that. Try again.") }
            busy = false } }, onDismiss = { voting = null }) }
}

