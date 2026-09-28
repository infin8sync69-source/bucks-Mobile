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
import com.bucks.app.data.CloudOrderRow
import com.bucks.app.data.OrderContactRow
import com.bucks.app.data.TaskRow
import com.bucks.app.data.liveOrder
import com.bucks.app.ui.BucksViewModel
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
                if (mine && cur.deliveryMode != "PICKUP" && cur.status in setOf("ACCEPTED", "READY", "PICKED_UP", "DELIVERED") && task?.status != "COMPLETED") task = runCatching { commerce.taskForOrder(orderId) }.getOrNull() ?: task
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
                    if (o.deliveryMode != "PICKUP" && o.dropLabel.isNotBlank()) Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Place, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${o.dropLabel}") }
                }

                SectionTitle("Progress", Modifier.padding(top = 22.dp, bottom = 10.dp))
                OrderTimeline(o.status, o.deliveryMode, task, forShop = vendor, cancelledBy = o.cancelledBy)

                if (!vendor) {
                    // The shop is paid for what it sells (and its own rider's fee); a Bucks rider's fee goes to the rider at the door.
                    val payable = o.payment == "UPI" && o.status in setOf("ACCEPTED", "READY", "PICKED_UP", "DELIVERED")
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

                    val t = task
                    if (t != null && t.status != "COMPLETED" && t.status != "PAID" && t.status != "CANCELLED") TintButton("Track delivery", Modifier.padding(top = 10.dp)) { onTrack(t.id) }
                } else when (o.status) {
                    "PLACED" -> Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SmallButton("Accept", Modifier.weight(1f)) { commerce.respondOrder(o.id, true) }
                        SmallButton("Reject", Modifier.weight(1f), tonal = true) { confirmReject = true }
                    }
                    "ACCEPTED" -> PrimaryButton(if (o.deliveryMode == "PICKUP") "Ready to collect" else "Packed", Modifier.padding(top = 18.dp)) { commerce.updateOrderStatus(o.id, "READY") }
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
    if (confirmCancel) AlertDialog(onDismissRequest = { confirmCancel = false }, title = { Text("Cancel this order?") },
        text = { Text(when {
            shopOrder == null -> "The shop hasn't accepted it yet, so nothing is charged. Once they accept, it can't be cancelled."
            shopOrder.deliveryMode == "PICKUP" -> "Use this when the customer isn't coming to collect it. They'll be told it was cancelled." + (if (shopOrder.payment == "UPI") " If they already paid you by UPI, refund them." else "")
            else -> "Use this when no rider has taken the delivery; once a rider has it, it can't be cancelled." + (if (shopOrder.payment == "UPI") " If the customer already paid you by UPI, refund them." else "")
        }) },
        confirmButton = { TextButton({ confirmCancel = false; if (shopSide) commerce.updateOrderStatus(orderId, "CANCELLED") else commerce.cancelOrder(orderId) }) { Text("Cancel order", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmCancel = false }) { Text("Keep it") } })
    if (confirmReject) AlertDialog(onDismissRequest = { confirmReject = false }, title = { Text("Reject this order?") }, text = { Text("The customer will be told the shop couldn't take it. Rejecting often lowers how high the shop shows in search.") },
        confirmButton = { TextButton({ confirmReject = false; commerce.respondOrder(orderId, false) }) { Text("Reject", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmReject = false }) { Text("Keep it") } })
}

/** Contact details are shared while the order is live or delivered, and after the shop cancelled an accepted one (for a refund). */
private fun hasContact(o: CloudOrderRow) = orderLive(o.status) || o.status == "DELIVERED" || (o.status == "CANCELLED" && o.cancelledBy == "SHOP")

/**
 * PLACED -> ACCEPTED -> (READY) -> PICKED_UP -> DELIVERED, or a terminal REJECTED / CANCELLED with a plain explanation.
 * [forShop] words it for the shop; the buyer sees the pickup PIN while the rider is on the way to or at the shop, which is when
 * the rider calls for it (advance_task checks it at pick-up, not at the door).
 */
@Composable
fun OrderTimeline(status: String, mode: String, task: TaskRow?, forShop: Boolean = false, cancelledBy: String? = null) {
    if (status == "REJECTED" || status == "CANCELLED") {
        val byShop = cancelledBy == "SHOP"
        val head = when {
            status == "REJECTED" -> if (forShop) "This order wasn't taken" else "The shop didn't take this order"
            byShop -> if (forShop) "You cancelled this order" else "The shop cancelled this order"
            else -> if (forShop) "The customer cancelled this order" else "You cancelled this order"
        }
        val detail = when {
            status == "REJECTED" -> if (forShop) "It was rejected or not accepted within 5 minutes. The customer wasn't charged." else "Either they were too busy or they didn't respond within 5 minutes. Nothing has been charged. Try another shop nearby."
            byShop -> if (forShop) "If the customer already paid you by UPI, refund them." else "If you already paid by UPI, the shop owes you a refund. Call them if it hasn't reached you."
            else -> if (forShop) "They cancelled before you accepted, so nothing was charged." else "Nothing has been charged."
        }
        BucksCard {
            Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Info, null, tint = MaterialTheme.colorScheme.error); Text(head, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 10.dp)) }
            Muted(detail, Modifier.padding(top = 8.dp))
        }
        return
    }
    val pickup = mode == "PICKUP"
    val steps = if (pickup) listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "READY" to "Ready to collect", "DELIVERED" to "Collected")
                else listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "PICKED_UP" to "Rider picked it up", "DELIVERED" to "Delivered")
    val order = listOf("PLACED", "ACCEPTED", "READY", "PICKED_UP", "DELIVERED")
    val at = order.indexOf(status).coerceAtLeast(0)
    val cur = if (!pickup && status == "READY") "ACCEPTED" else status
    // The rider asks for the PIN at the shop (ARRIVED -> IN_PROGRESS), so it is shown until then and not after.
    val pin = task?.takeIf { it.status in setOf("SEARCHING", "MATCHED", "ARRIVED") }?.pin?.takeIf { it.isNotBlank() }
    Column {
        steps.forEachIndexed { i, (key, label) ->
            val idx = order.indexOf(key)
            val detail = when (key) {
                "PLACED" -> if (forShop) "Accept or reject within 5 minutes." else "The shop has 5 minutes to accept."
                "ACCEPTED" -> when {
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
                else -> if (forShop) "Done." else "Tell others how it went with a review on the shop's page."
            }
            StatusLine(label, detail, done = idx < at && key != cur, now = key == cur, last = i == steps.lastIndex)
        }
    }
}
