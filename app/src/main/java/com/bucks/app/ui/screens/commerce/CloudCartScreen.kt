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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Trust
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Commerce
import com.bucks.app.ui.components.*

/**
 * The cart, one card per store. Each store becomes its own order with its own delivery (its own rider, fee and payment), so the
 * delivery mode and payment are chosen per store; the "Deliver to" label is shared. One tap places every order, one after another.
 * The delivery fee is worked out by the server from each shop to the drop point and shown on each order page.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CloudCartScreen(vm: BucksViewModel, onBack: () -> Unit, onPlaced: (List<String>) -> Unit) {
    val commerce = vm.commerce; val social = vm.social; val s by vm.state.collectAsState()
    val stores = commerce.stores
    val modes = remember { mutableStateMapOf<String, String>() }; val payments = remember { mutableStateMapOf<String, String>() }
    val hasRiders = remember { mutableStateMapOf<String, Boolean>() }
    var dropLabel by rememberSaveable { mutableStateOf(social.me?.area ?: "") }
    var confirmClear by remember { mutableStateOf(false) }
    val ids = stores.map { it.listing.id }
    LaunchedEffect(ids) { ids.filter { it !in hasRiders }.forEach { id -> hasRiders[id] = runCatching { commerce.hasStoreRiders(id) }.getOrDefault(false) } }
    fun modeOf(st: Commerce.StoreCart): String = (modes[st.listing.id] ?: "MARKETPLACE").let { if (it == "STORE_RIDER" && hasRiders[st.listing.id] != true) "MARKETPLACE" else it }
    fun paymentOf(st: Commerce.StoreCart): String = (payments[st.listing.id] ?: "UPI").let { if (it == "COD" && !(modeOf(st) == "STORE_RIDER" && st.listing.details.flag("cod"))) "UPI" else it }
    val here = s.me
    val needsDrop = stores.any { modeOf(it) != "PICKUP" }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Cart", onBack = onBack, actions = { if (stores.isNotEmpty()) IconButton({ confirmClear = true }) { Icon(Icons.Rounded.DeleteOutline, "Empty the cart") } })
        if (stores.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.ShoppingBag, size = 72)
                Text("Your cart is empty", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted("Open a shop and tap Add on what you need. You can mix shops: each shop's items become their own order, delivered separately.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Find shops", Modifier.padding(top = 18.dp), onClick = onBack)
            }
            return@ContentColumn
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (stores.size > 1) Notice("${stores.size} shops, so ${stores.size} separate orders and deliveries. Each has its own delivery fee, payment and time.", Modifier.padding(bottom = 12.dp))
            stores.forEachIndexed { index, st ->
                val shop = st.listing; val mode = modeOf(st); val payment = paymentOf(st)
                val codAllowed = mode == "STORE_RIDER" && shop.details.flag("cod"); val freeDelivery = shop.details.flag("free_delivery")
                Column(Modifier.padding(bottom = 20.dp)) {
                    Text(if (stores.size > 1) "Order ${index + 1} of ${stores.size}" else "Your order", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.semantics { heading() })
                    ListRow(shop.title, listOfNotNull(shop.category.ifBlank { null }, shop.area.ifBlank { null }).joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.Storefront, tinted = false) }, trailing = { TrustBadge(Trust(shop.trustUp, shop.trustDown), compact = true) })
                    BucksCard(Modifier.padding(top = 6.dp)) {
                        st.lines.forEach { l ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(l.item.name, style = MaterialTheme.typography.bodyLarge)
                                    Muted(listOfNotNull(rupees(l.item.price), l.item.unit.ifBlank { null }).joinToString(" · "))
                                }
                                AddStepper(l.qty) { d -> commerce.add(shop, l.item, d) }
                                IconButton({ l.item.id?.let { commerce.remove(it) } }, Modifier.size(48.dp)) { Icon(Icons.Rounded.Close, "Remove ${l.item.name}", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                                Text(rupees(l.amount), style = MaterialTheme.typography.titleSmall, modifier = Modifier.widthIn(min = 56.dp), textAlign = TextAlign.End)
                            }
                        }
                        Divider()
                        Row(Modifier.padding(top = 8.dp)) { Text("Items from ${shop.title}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Text(rupees(st.amount), style = MaterialTheme.typography.titleLarge) }
                    }
                    Label("How do you want it?")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip("Delivery by a Bucks rider", selected = mode == "MARKETPLACE", icon = Icons.Rounded.TwoWheeler) { modes[shop.id] = "MARKETPLACE" }
                        if (hasRiders[shop.id] == true) Chip("Store's own rider", selected = mode == "STORE_RIDER", icon = Icons.Rounded.Storefront) { modes[shop.id] = "STORE_RIDER" }
                        Chip("I'll pick up", selected = mode == "PICKUP", icon = Icons.Rounded.DirectionsWalk) { modes[shop.id] = "PICKUP" }
                    }
                    Notice(when {
                        mode == "PICKUP" -> "No delivery fee. Collect it from ${shop.title}" + (if (shop.area.isBlank()) "" else " in ${shop.area}") + " once they mark it ready."
                        freeDelivery -> "Free delivery: ${shop.title} pays the rider's fee on this order. You pay for the items only."
                        mode == "STORE_RIDER" -> "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. It goes to ${shop.title} with the items, since it's their rider."
                        else -> "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. You pay it to the Bucks rider at the door (UPI or cash); the order page shows the amount."
                    }, Modifier.padding(top = 12.dp, bottom = 12.dp))
                    Label("Pay ${shop.title} with")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip("Pay by UPI", selected = payment == "UPI", icon = Icons.Rounded.QrCode2) { payments[shop.id] = "UPI" }
                        if (codAllowed) Chip("Cash on delivery", selected = payment == "COD", icon = Icons.Rounded.Payments) { payments[shop.id] = "COD" }
                    }
                    Muted(when {
                        payment == "COD" -> "Pay the store's rider in cash when it arrives."
                        mode == "MARKETPLACE" && !freeDelivery -> "You pay the shop for the items through your UPI app from the order page; the shop's QR is filled in for you. The rider's fee is paid to the rider."
                        else -> "You pay the shop through your UPI app from the order page; the shop's QR is filled in for you."
                    }, Modifier.padding(top = 8.dp))
                    if (index < stores.lastIndex) HorizontalDivider(Modifier.padding(top = 20.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            // Delivery needs the phone's real position: it is the rider's drop pin and what each fee is worked out from.
            if (needsDrop) {
                BucksField(dropLabel, { dropLabel = it.take(120) }, "Deliver to", "e.g. 4th block, near the park, 2nd floor")
                if (here == null) Notice("Turn on location to get it delivered. The rider needs your exact drop point, and the fee is worked out from it. You can still choose \"I'll pick up\".", Modifier.padding(top = 8.dp, bottom = 14.dp))
                else Muted("Your current location is used as the drop point for every delivery. The label helps the rider find the door.", Modifier.padding(top = 6.dp, bottom = 14.dp))
            }
            Spacer(Modifier.height(12.dp))
        }
        Surface(shadowElevation = 8.dp, color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp)) {
                PrimaryButton(if (commerce.placing) "Placing…" else if (stores.size == 1) "Place order · ${rupees(commerce.subtotal)}" else "Place ${stores.size} orders · ${rupees(commerce.subtotal)}",
                    enabled = !commerce.placing && (!needsDrop || (dropLabel.isNotBlank() && here != null))) {
                    val choices = stores.associate { st -> st.listing.id to Commerce.Choice(modeOf(st), paymentOf(st), if (modeOf(st) == "PICKUP") st.listing.area else dropLabel) }
                    commerce.checkoutAll(choices, here, onPlaced)
                }
                Muted(if (stores.size > 1) "Each shop has 5 minutes to accept its order. If one doesn't, only that order is cancelled; nothing is charged." else "${stores.first().listing.title} has 5 minutes to accept. If they don't, nothing is charged and you can try another shop.",
                    Modifier.padding(top = 8.dp).fillMaxWidth(), TextAlign.Center)
            }
        }
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("Empty the cart?") }, text = { Text(if (stores.size > 1) "Everything from all ${stores.size} shops will be removed." else "Everything from ${stores.firstOrNull()?.listing?.title ?: "this shop"} will be removed.") },
        confirmButton = { TextButton({ confirmClear = false; commerce.clear() }) { Text("Empty it", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmClear = false }) { Text("Keep") } })
}

/** The cart used to ask before mixing shops; it no longer does (each shop is its own order), so this shows nothing. Kept so older screens compile. */
@Composable
fun CartSwitchDialog(@Suppress("UNUSED_PARAMETER") vm: BucksViewModel) {}
