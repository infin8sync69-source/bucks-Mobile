package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Trust
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/**
 * Cart and checkout for a cloud shop: lines with steppers, delivery mode, payment, drop label, then place_order.
 * The delivery fee is worked out by the server from the shop to the drop point and shown on the order page.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CloudCartScreen(vm: BucksViewModel, onBack: () -> Unit, onPlaced: (String) -> Unit) {
    val commerce = vm.commerce; val social = vm.social; val s by vm.state.collectAsState()
    val shop = commerce.shop
    var mode by rememberSaveable { mutableStateOf("MARKETPLACE") }
    var payment by rememberSaveable { mutableStateOf("UPI") }
    var dropLabel by rememberSaveable { mutableStateOf(social.me?.area ?: "") }
    var hasStoreRiders by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    LaunchedEffect(shop?.id) { hasStoreRiders = shop?.let { runCatching { commerce.hasStoreRiders(it.id) }.getOrDefault(false) } ?: false }
    val codAllowed = mode == "STORE_RIDER" && shop?.details?.flag("cod") == true
    val freeDelivery = shop?.details?.flag("free_delivery") == true
    // Options that stop applying fall back to a valid choice, so the button never sends something the server rejects.
    LaunchedEffect(hasStoreRiders, codAllowed) { if (mode == "STORE_RIDER" && !hasStoreRiders) mode = "MARKETPLACE"; if (payment == "COD" && !codAllowed) payment = "UPI" }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Cart", onBack = onBack, actions = { if (shop != null) IconButton({ confirmClear = true }) { Icon(Icons.Rounded.DeleteOutline, "Empty the cart") } })
        if (shop == null) {
            Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.ShoppingBag, size = 72)
                Text("Your cart is empty", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted("Open a shop near you and tap Add on what you need. One shop per order.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Find shops", Modifier.padding(top = 18.dp), onClick = onBack)
            }
            return@ContentColumn
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ListRow(shop.title, listOfNotNull(shop.category.ifBlank { null }, shop.area.ifBlank { null }).joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.Storefront, tinted = false) }, trailing = { TrustBadge(Trust(shop.trustUp, shop.trustDown), compact = true) })
            BucksCard(Modifier.padding(top = 6.dp)) {
                commerce.lines.forEach { l ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l.item.name, style = MaterialTheme.typography.bodyLarge)
                            Muted(listOfNotNull(rupees(l.item.price), l.item.unit.ifBlank { null }).joinToString(" · "))
                        }
                        AddStepper(l.qty) { d -> commerce.add(shop, l.item, d) }
                        IconButton({ l.item.id?.let { commerce.remove(it) } }, Modifier.size(36.dp)) { Icon(Icons.Rounded.Close, "Remove ${l.item.name}", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(rupees(l.amount), style = MaterialTheme.typography.titleSmall, modifier = Modifier.widthIn(min = 56.dp), textAlign = TextAlign.End)
                    }
                }
                Divider()
                Row(Modifier.padding(top = 8.dp)) { Text("Items", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Text(rupees(commerce.subtotal), style = MaterialTheme.typography.titleLarge) }
            }

            Label("How do you want it?")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("Delivery by a Bucks rider", selected = mode == "MARKETPLACE", icon = Icons.Rounded.TwoWheeler) { mode = "MARKETPLACE" }
                if (hasStoreRiders) Chip("Store's own rider", selected = mode == "STORE_RIDER", icon = Icons.Rounded.Storefront) { mode = "STORE_RIDER" }
                Chip("I'll pick up", selected = mode == "PICKUP", icon = Icons.Rounded.DirectionsWalk) { mode = "PICKUP" }
            }
            Notice(when {
                mode == "PICKUP" -> "No delivery fee. Collect it from ${shop.title}" + (if (shop.area.isBlank()) "" else " in ${shop.area}") + " once they mark it ready."
                freeDelivery -> "Free delivery: ${shop.title} pays the rider's fee on this order."
                else -> "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. Bucks adds it when you place the order and shows it on the order page."
            }, Modifier.padding(top = 12.dp, bottom = 16.dp))

            Label("Pay with")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("Pay by UPI", selected = payment == "UPI", icon = Icons.Rounded.QrCode2) { payment = "UPI" }
                if (codAllowed) Chip("Cash on delivery", selected = payment == "COD", icon = Icons.Rounded.Payments) { payment = "COD" }
            }
            Muted(if (payment == "COD") "Pay the store's rider in cash when it arrives." else "You pay the shop through your UPI app from the order page; the shop's QR is filled in for you.", Modifier.padding(top = 8.dp, bottom = 16.dp))

            if (mode != "PICKUP") {
                BucksField(dropLabel, { dropLabel = it.take(120) }, "Deliver to", "e.g. 4th block, near the park, 2nd floor")
                if (s.me == null) Notice("Turn on location so the rider gets your exact drop point. Without it the fee is worked out from the centre of town.", Modifier.padding(bottom = 14.dp))
                else Muted("Your current location is used as the drop point. The label helps the rider find the door.", Modifier.padding(bottom = 14.dp))
            }
            PrimaryButton(if (commerce.placing) "Placing…" else "Place order · ${rupees(commerce.subtotal)}", enabled = !commerce.placing && commerce.lines.isNotEmpty() && (mode == "PICKUP" || dropLabel.isNotBlank())) {
                commerce.checkout(mode, payment, if (mode == "PICKUP") shop.area else dropLabel, onPlaced)
            }
            Muted("${shop.title} has 5 minutes to accept. If they don't, nothing is charged and you can try another shop.", Modifier.padding(top = 12.dp).fillMaxWidth(), TextAlign.Center)
            Spacer(Modifier.height(24.dp))
        }
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("Empty the cart?") }, text = { Text("Everything from ${shop?.title ?: "this shop"} will be removed.") },
        confirmButton = { TextButton({ confirmClear = false; commerce.clear() }) { Text("Empty it", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmClear = false }) { Text("Keep") } })
    CartSwitchDialog(vm)
}

/** Asks before replacing a cart from another shop; any screen that adds to the cart can show it. */
@Composable
fun CartSwitchDialog(vm: BucksViewModel) {
    val commerce = vm.commerce; val p = commerce.pendingSwitch ?: return
    AlertDialog(onDismissRequest = { commerce.dismissSwitch() }, title = { Text("Start a new cart?") },
        text = { Text("Your cart has ${commerce.count} item${if (commerce.count == 1) "" else "s"} from ${commerce.shop?.title ?: "another shop"}. One order goes to one shop, so adding ${p.item.name} from ${p.listing.title} empties it.") },
        confirmButton = { TextButton({ commerce.confirmSwitch() }) { Text("Replace cart") } }, dismissButton = { TextButton({ commerce.dismissSwitch() }) { Text("Keep my cart") } })
}
