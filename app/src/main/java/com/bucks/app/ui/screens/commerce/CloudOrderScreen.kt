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
import com.bucks.app.data.OrderContactRow
import com.bucks.app.data.TaskRow
import com.bucks.app.data.liveOrder
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The buyer's order page: lines and totals, a status timeline, pay by UPI, call the shop, track the delivery,
 * cancel while the shop hasn't answered. Follows the row live and also polls every 10 seconds.
 */
@Composable
fun CloudOrderScreen(vm: BucksViewModel, orderId: String, onBack: () -> Unit, onTrack: (String) -> Unit, onOpenListing: (String) -> Unit) {
    val commerce = vm.commerce; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    val o = commerce.orders[orderId]
    var missing by remember { mutableStateOf(false) }
    var task by remember { mutableStateOf<TaskRow?>(null) }
    var contact by remember { mutableStateOf<OrderContactRow?>(null) }
    var confirmCancel by remember { mutableStateOf(false) }
    // First load, then a 10-second poll: status, the delivery task once accepted, and contact details while live.
    LaunchedEffect(orderId) {
        while (true) {
            val row = runCatching { commerce.order(orderId) }.getOrNull()
            if (row == null && commerce.orders[orderId] == null) { missing = true; break }
            val cur = row ?: commerce.orders[orderId]
            if (cur != null) {
                if (cur.deliveryMode != "PICKUP" && cur.status in setOf("ACCEPTED", "READY", "PICKED_UP", "DELIVERED") && task?.status != "COMPLETED") task = runCatching { commerce.taskForOrder(orderId) }.getOrNull() ?: task
                if (orderLive(cur.status) || cur.status == "DELIVERED") contact = runCatching { commerce.contactFor(orderId) }.getOrNull() ?: contact
                if (orderDone(cur.status) && (cur.status != "DELIVERED" || contact != null)) break
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
            o == null -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                val title = commerce.titleOf(o.listingId)
                Row(Modifier.fillMaxWidth().clickable { onOpenListing(o.listingId) }, verticalAlignment = Alignment.CenterVertically) {
                    Avatar(icon = Icons.Rounded.Storefront, tinted = false)
                    Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(title, style = MaterialTheme.typography.titleLarge); Muted("Order ${shortOrderId(o.id)} · ${ago(o.createdAt)} · ${deliveryModeLabel(o.deliveryMode)}") }
                    Icon(Icons.Rounded.ChevronRight, "Open shop", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) { OrderStatusPill(o.status, o.deliveryMode); Spacer(Modifier.width(8.dp)); PillGrey(paymentLabel(o.payment)) }

                BucksCard(Modifier.padding(top = 14.dp)) {
                    o.lines.forEach { OrderLineRow(it) }
                    OrderTotals(o)
                    if (o.deliveryMode != "PICKUP" && o.dropLabel.isNotBlank()) Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Place, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${o.dropLabel}") }
                }

                SectionTitle("Progress", Modifier.padding(top = 22.dp, bottom = 10.dp))
                OrderTimeline(o.status, o.deliveryMode, task)

                val payable = o.payment == "UPI" && o.status in setOf("ACCEPTED", "READY", "PICKED_UP", "DELIVERED")
                if (payable) {
                    val upi = contact?.upiUri
                    PrimaryButton("Pay ${rupees(o.total)} by UPI", Modifier.padding(top = 18.dp), enabled = upi != null) {
                        if (upi == null) return@PrimaryButton
                        if (!openUpi(ctx, upiPayUri(upi, o.total, "Bucks order ${shortOrderId(o.id)}"))) vm.toast("No UPI app found on this phone. Pay the shop directly.")
                    }
                    Muted(when { upi != null -> "Opens your UPI app with ${title}'s QR and the amount filled in."; contact == null -> "Getting the shop's payment details…"; else -> "${title} hasn't added a UPI QR yet. Pay them directly when you receive the order." }, Modifier.padding(top = 6.dp).fillMaxWidth(), TextAlign.Center)
                } else if (o.payment == "UPI" && o.status == "PLACED") Muted("You can pay by UPI once ${title} accepts.", Modifier.padding(top = 18.dp).fillMaxWidth(), TextAlign.Center)
                else if (o.payment == "COD" && orderLive(o.status)) Notice("Keep ${rupees(o.total)} in cash ready for the store's rider.", Modifier.padding(top = 18.dp))

                val t = task
                if (t != null && t.status != "COMPLETED" && t.status != "PAID" && t.status != "CANCELLED") TintButton("Track delivery", Modifier.padding(top = 10.dp)) { onTrack(t.id) }
                if (orderLive(o.status) || o.status == "DELIVERED") {
                    val phone = contact?.phone
                    GhostButton(if (phone != null) "Call $title" else "Call shop", Modifier.padding(top = 10.dp), enabled = phone != null) { phone?.let { dial(ctx, it) } }
                }
                if (o.status == "PLACED") BadButton("Cancel order", Modifier.padding(top = 10.dp)) { confirmCancel = true }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    if (confirmCancel) AlertDialog(onDismissRequest = { confirmCancel = false }, title = { Text("Cancel this order?") }, text = { Text("The shop hasn't accepted it yet, so nothing is charged. Once they accept, it can't be cancelled.") },
        confirmButton = { TextButton({ confirmCancel = false; commerce.cancelOrder(orderId) }) { Text("Cancel order", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmCancel = false }) { Text("Keep it") } })
}

/** PLACED -> ACCEPTED -> (READY) -> PICKED_UP -> DELIVERED, or a terminal REJECTED / CANCELLED with a plain explanation. */
@Composable
fun OrderTimeline(status: String, mode: String, task: TaskRow?) {
    if (status == "REJECTED" || status == "CANCELLED") {
        BucksCard {
            Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Info, null, tint = MaterialTheme.colorScheme.error); Text(if (status == "REJECTED") "The shop didn't take this order" else "You cancelled this order", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 10.dp)) }
            Muted(if (status == "REJECTED") "Either they were too busy or they didn't respond within 5 minutes. Nothing has been charged. Try another shop nearby." else "Nothing has been charged.", Modifier.padding(top = 8.dp))
        }
        return
    }
    val pickup = mode == "PICKUP"
    val steps = if (pickup) listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "READY" to "Ready to collect", "DELIVERED" to "Collected")
                else listOf("PLACED" to "Order placed", "ACCEPTED" to "Shop accepted", "PICKED_UP" to "Rider picked it up", "DELIVERED" to "Delivered")
    val order = listOf("PLACED", "ACCEPTED", "READY", "PICKED_UP", "DELIVERED")
    val at = order.indexOf(status).coerceAtLeast(0)
    val cur = if (!pickup && status == "READY") "ACCEPTED" else status
    Column {
        steps.forEachIndexed { i, (key, label) ->
            val idx = order.indexOf(key)
            val detail = when (key) {
                "PLACED" -> "The shop has 5 minutes to accept."
                "ACCEPTED" -> when { pickup -> "They're getting it ready."; status == "READY" -> "Packed. Waiting for a rider to collect it."; task == null -> "Finding a rider near the shop."; task.status == "SEARCHING" -> "Ringing riders near the shop."; task.status == "NO_DRIVER" -> "No rider free right now. The shop keeps trying."; else -> "A rider is on the way to the shop." }
                "READY" -> "Go to the shop and collect it."
                "PICKED_UP" -> "On the way to you." + (task?.pin?.takeIf { it.isNotBlank() }?.let { " Tell the rider PIN $it when it arrives." } ?: "")
                else -> "Tell others how it went with a review on the shop's page."
            }
            StatusLine(label, detail, done = idx < at && key != cur, now = key == cur, last = i == steps.lastIndex)
        }
    }
}
