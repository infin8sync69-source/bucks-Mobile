package com.bucks.app.ui.screens.commerce

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
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
import com.bucks.app.data.AddressRow
import com.bucks.app.data.Backend
import com.bucks.app.data.Geo
import com.bucks.app.data.LatLng
import com.bucks.app.data.Prefs
import com.bucks.app.data.Trust
import com.bucks.app.data.listingPoint
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
    val points = remember { mutableStateMapOf<String, LatLng>() }
    LaunchedEffect(ids) {
        ids.filter { it !in hasRiders }.forEach { id -> hasRiders[id] = runCatching { commerce.hasStoreRiders(id) }.getOrDefault(false) }
        ids.filter { it !in points }.forEach { id -> runCatching { Backend.listingPoint(id) }.getOrNull()?.let { points[id] = it } }
        commerce.loadAddresses(); commerce.loadFeeRule()
    }
    // The drop point: where the phone is, or a saved address pinned for deliveries (order home from the office).
    var dropAddrId by rememberSaveable { mutableStateOf<String?>(null) }
    val pinned = commerce.addresses.filter { it.pin != null }
    val dropAddr = pinned.firstOrNull { it.id == dropAddrId } ?: if (s.me == null) pinned.firstOrNull { it.isDefault } ?: pinned.firstOrNull() else null
    val here = dropAddr?.pin ?: s.me
    // A shop is "near" when it is inside its own delivery radius (5 km when it hasn't set one); farther away only shipping works.
    // Until the position or the shop's location is known, treat it as near so the usual options show.
    fun near(st: Commerce.StoreCart): Boolean { val at = points[st.listing.id]; if (here == null || at == null) return true
        val radiusKm = (st.listing.details["delivery_radius_km"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toDoubleOrNull() ?: 5.0
        return Geo.distanceKm(here, at) <= maxOf(radiusKm, 1.0) }
    fun ships(st: Commerce.StoreCart) = st.listing.details.flag("ships_india")
    fun num(st: Commerce.StoreCart, key: String) = (st.listing.details[key] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toDoubleOrNull()?.toInt() ?: 0
    /** What the shop charges to ship this part of the cart: its flat fee, free once the items reach its free-shipping line. */
    fun shipFee(st: Commerce.StoreCart): Int { val above = num(st, "free_ship_above"); return if (above > 0 && st.amount >= above) 0 else num(st, "ship_fee") }
    fun modeOf(st: Commerce.StoreCart): String {
        // What I chose last time at this shop comes first (fewer taps); otherwise ship when it's far, else a Bucks rider.
        val m = modes[st.listing.id] ?: Prefs.checkoutMode(st.listing.id) ?: if (!near(st) && ships(st)) "SHIP" else "MARKETPLACE"
        return when {
            m == "SHIP" && !ships(st) -> "MARKETPLACE"
            m == "STORE_RIDER" && hasRiders[st.listing.id] != true -> "MARKETPLACE"
            m != "SHIP" && !near(st) && ships(st) -> "SHIP"
            else -> m
        }
    }
    fun paymentOf(st: Commerce.StoreCart): String = (payments[st.listing.id] ?: Prefs.checkoutPayment(st.listing.id) ?: "UPI").let { if (it == "COD" && !(modeOf(st) in setOf("STORE_RIDER", "SHIP") && st.listing.details.flag("cod"))) "UPI" else it }
    var addressId by rememberSaveable { mutableStateOf<String?>(null) }; var addressSheet by remember { mutableStateOf(false) }
    val addressList = commerce.addresses
    val address: AddressRow? = addressList.firstOrNull { it.id == addressId } ?: addressList.firstOrNull { it.isDefault } ?: addressList.firstOrNull()
    // A store that is too far and does not ship cannot be ordered from at all.
    fun blocked(st: Commerce.StoreCart) = !near(st) && !ships(st)
    val needsDrop = stores.any { modeOf(it) in setOf("MARKETPLACE", "STORE_RIDER") }
    val needsAddress = stores.any { modeOf(it) == "SHIP" }
    /** The local delivery fee the customer pays for [st] (the server works out the same from the drop point); 0 when the shop pays it. */
    fun localFee(st: Commerce.StoreCart): Int? {
        if (modeOf(st) !in setOf("MARKETPLACE", "STORE_RIDER") || st.listing.details.flag("free_delivery")) return 0
        val at = points[st.listing.id] ?: return null; val drop = here ?: return null
        return commerce.deliveryFee(Geo.distanceKm(drop, at))
    }
    val fees = stores.map { localFee(it) }
    val grand = commerce.subtotal + stores.filter { modeOf(it) == "SHIP" }.sumOf { shipFee(it) } + fees.sumOf { it ?: 0 }
    val feeUnknown = fees.any { it == null }

    ContentColumn(Modifier.fillMaxHeight().imePadding()) {
        BucksTopBar(stringResource(R.string.g7_cart_title), onBack = onBack, actions = { if (stores.isNotEmpty()) IconButton({ confirmClear = true }) { Icon(Icons.Rounded.DeleteOutline, stringResource(R.string.g7_cd_cart_empty)) } })
        if (stores.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.ShoppingBag, size = 72)
                Text(stringResource(R.string.g7_cart_empty), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted(stringResource(R.string.g7_cart_empty_sub), Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton(stringResource(R.string.g7_cart_find_shops), Modifier.padding(top = 18.dp), onClick = onBack)
            }
            return@ContentColumn
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (stores.size > 1) Notice(pluralStringResource(R.plurals.g7_cart_multi_notice, stores.size, stores.size), Modifier.padding(bottom = 12.dp))
            stores.forEachIndexed { index, st ->
                val shop = st.listing; val mode = modeOf(st); val payment = paymentOf(st)
                val codAllowed = mode in setOf("STORE_RIDER", "SHIP") && shop.details.flag("cod"); val freeDelivery = shop.details.flag("free_delivery")
                Column(Modifier.padding(bottom = 20.dp)) {
                    Text(if (stores.size > 1) stringResource(R.string.g7_cart_order_n_of, index + 1, stores.size) else stringResource(R.string.g7_cart_your_order), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.semantics { heading() })
                    ListRow(shop.title, listOfNotNull(shop.category.ifBlank { null }, shop.area.ifBlank { null }).joinToString(" · "), leading = { Avatar(icon = Icons.Rounded.Storefront, tinted = false) }, trailing = { TrustBadge(Trust(shop.trustUp, shop.trustDown), compact = true) })
                    BucksCard(Modifier.padding(top = 6.dp)) {
                        st.lines.forEach { l ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(l.item.name, style = MaterialTheme.typography.bodyLarge)
                                    Muted(listOfNotNull(rupees(l.item.price), l.item.unit.ifBlank { null }).joinToString(" · "))
                                }
                                AddStepper(l.qty) { d -> commerce.add(shop, l.item, d) }
                                IconButton({ l.item.id?.let { commerce.remove(it) } }, Modifier.size(48.dp)) { Icon(Icons.Rounded.Close, stringResource(R.string.g7_cd_cart_remove, l.item.name), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                                Text(rupees(l.amount), style = MaterialTheme.typography.titleSmall, modifier = Modifier.widthIn(min = 56.dp), textAlign = TextAlign.End)
                            }
                        }
                        Divider()
                        Row(Modifier.padding(top = 8.dp)) { Text(stringResource(R.string.g7_cart_items_from, shop.title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Text(rupees(st.amount), style = MaterialTheme.typography.titleLarge) }
                    }
                    Label(stringResource(R.string.g7_cart_how))
                    if (blocked(st)) Notice(stringResource(R.string.g7_cart_too_far, shop.title), Modifier.padding(bottom = 8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (ships(st)) Chip(stringResource(R.string.g7_cart_mode_ship), selected = mode == "SHIP", icon = Icons.Rounded.LocalShipping) { modes[shop.id] = "SHIP" }
                        if (near(st)) {
                            Chip(stringResource(R.string.g7_cart_mode_marketplace), selected = mode == "MARKETPLACE", icon = Icons.Rounded.TwoWheeler) { modes[shop.id] = "MARKETPLACE" }
                            if (hasRiders[shop.id] == true) Chip(stringResource(R.string.g7_cart_mode_store_rider), selected = mode == "STORE_RIDER", icon = Icons.Rounded.Storefront) { modes[shop.id] = "STORE_RIDER" }
                            Chip(stringResource(R.string.g7_cart_mode_pickup), selected = mode == "PICKUP", icon = Icons.Rounded.DirectionsWalk) { modes[shop.id] = "PICKUP" }
                        }
                    }
                    Notice(when {
                        mode == "SHIP" -> listOfNotNull(
                            if (shipFee(st) == 0) stringResource(R.string.g7_cart_ship_free) else if (num(st, "free_ship_above") > 0) stringResource(R.string.g7_cart_ship_fee_free_above, rupees(shipFee(st)), rupees(num(st, "free_ship_above"))) else stringResource(R.string.g7_cart_ship_fee, rupees(shipFee(st))),
                            (shop.details["dispatch_days"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.takeIf { it.isNotBlank() }?.let { stringResource(R.string.g7_cart_ships_in_days, it) },
                            stringResource(R.string.g7_cart_ship_accept, shop.title)).joinToString(" ")
                        mode == "PICKUP" -> if (shop.area.isBlank()) stringResource(R.string.g7_cart_pickup_note, shop.title) else stringResource(R.string.g7_cart_pickup_note_area, shop.title, shop.area)
                        freeDelivery -> stringResource(R.string.g7_cart_free_delivery, shop.title)
                        mode == "STORE_RIDER" -> localFee(st)?.let { stringResource(R.string.g7_cart_store_rider_fee, rupees(it), shop.title) } ?: stringResource(R.string.g7_cart_store_rider_nofee, shop.title)
                        else -> localFee(st)?.let { stringResource(R.string.g7_cart_rider_fee, rupees(it)) } ?: stringResource(R.string.g7_cart_rider_nofee)
                    }, Modifier.padding(top = 12.dp, bottom = 12.dp))
                    localFee(st)?.takeIf { it > 0 }?.let { f -> Row(Modifier.padding(top = 8.dp)) { Muted(stringResource(R.string.g7_cart_items_plus_delivery, rupees(st.amount), rupees(f)), Modifier.weight(1f)); Text(rupees(st.amount + f), style = MaterialTheme.typography.titleSmall) } }
                    if (mode == "SHIP") Row(Modifier.padding(top = 8.dp)) { Muted(if (shipFee(st) == 0) stringResource(R.string.g7_cart_items_free_shipping, rupees(st.amount)) else stringResource(R.string.g7_cart_items_plus_shipping, rupees(st.amount), rupees(shipFee(st))), Modifier.weight(1f)); Text(rupees(st.amount + shipFee(st)), style = MaterialTheme.typography.titleSmall) }
                    Label(stringResource(R.string.g7_cart_pay_with, shop.title))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Chip(stringResource(R.string.g7_cart_pay_upi), selected = payment == "UPI", icon = Icons.Rounded.QrCode2) { payments[shop.id] = "UPI" }
                        if (codAllowed) Chip(stringResource(R.string.g7_cart_pay_cod), selected = payment == "COD", icon = Icons.Rounded.Payments) { payments[shop.id] = "COD" }
                    }
                    Muted(when {
                        payment == "COD" -> if (mode == "SHIP") stringResource(R.string.g7_cart_cod_courier) else stringResource(R.string.g7_cart_cod_rider)
                        mode == "MARKETPLACE" && !freeDelivery -> stringResource(R.string.g7_cart_upi_note_rider)
                        else -> stringResource(R.string.g7_cart_upi_note)
                    }, Modifier.padding(top = 8.dp))
                    if (index < stores.lastIndex) HorizontalDivider(Modifier.padding(top = 20.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            if (needsAddress) {
                Text(stringResource(R.string.g7_cart_ship_to), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 6.dp).semantics { heading() })
                AddressCard(address) { addressSheet = true }
                Spacer(Modifier.height(14.dp))
            }
            // Delivery needs the phone's real position: it is the rider's drop pin and what each fee is worked out from.
            if (needsDrop) {
                if (pinned.isNotEmpty()) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (s.me != null) Chip(stringResource(R.string.g7_cart_where_i_am), selected = dropAddr == null, icon = Icons.Rounded.MyLocation) { dropAddrId = null; dropLabel = social.me?.area ?: "" }
                    pinned.forEach { a -> Chip(a.label.ifBlank { a.line1.take(18) }, selected = dropAddr?.id == a.id, icon = Icons.Rounded.Home) { dropAddrId = a.id; dropLabel = listOf(a.line1, a.line2).filter { it.isNotBlank() }.joinToString(", ").take(120) } }
                }
                BucksField(dropLabel, { dropLabel = it.take(120) }, stringResource(R.string.g7_cart_deliver_to), stringResource(R.string.g7_cart_deliver_to_hint))
                if (here == null) Notice(stringResource(R.string.g7_cart_need_location), Modifier.padding(top = 8.dp, bottom = 14.dp))
                else Muted(if (dropAddr != null) stringResource(R.string.g7_cart_drop_pinned, dropAddr.label.ifBlank { stringResource(R.string.g7_cart_this_address) }) else stringResource(R.string.g7_cart_drop_here), Modifier.padding(top = 6.dp, bottom = 14.dp))
            }
            Spacer(Modifier.height(12.dp))
        }
        Surface(shadowElevation = 8.dp, color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp)) {
                // What went wrong last time stays here, next to the button, until the next try (a toast is easy to miss).
                if (commerce.checkoutErrors.isNotEmpty()) Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(if (stores.isEmpty()) stringResource(R.string.g7_cart_some_failed) else stringResource(R.string.g7_cart_not_placed), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onErrorContainer)
                        commerce.checkoutErrors.forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.padding(top = 4.dp)) }
                        Muted(stringResource(R.string.g7_cart_fix_retry), Modifier.padding(top = 6.dp))
                    }
                }
                // Several shops are several orders, each with its own delivery: say so before the button.
                if (stores.size > 1) Muted(stores.count { modeOf(it) != "PICKUP" }.let { n -> if (n > 0) pluralStringResource(R.plurals.g7_cart_orders_deliveries, n, stores.size, n) else pluralStringResource(R.plurals.g7_cart_orders, stores.size, stores.size) }, Modifier.padding(bottom = 6.dp))
                // The total includes delivery; "about" while the drop point or the fee rule isn't known yet.
                val total = if (feeUnknown && needsDrop) stringResource(R.string.g7_cart_about, rupees(grand)) else rupees(grand)
                PrimaryButton(if (commerce.placing) stringResource(R.string.g7_cart_placing) else if (stores.size == 1) stringResource(R.string.g7_cart_place_one, total) else pluralStringResource(R.plurals.g7_cart_place_n, stores.size, stores.size, total),
                    enabled = !commerce.placing && stores.none { blocked(it) } && (!needsDrop || (dropLabel.isNotBlank() && here != null)) && (!needsAddress || address != null)) {
                    val choices = stores.associate { st -> st.listing.id to Commerce.Choice(modeOf(st), paymentOf(st), if (modeOf(st) == "PICKUP") st.listing.area else dropLabel, if (modeOf(st) == "SHIP") address else null) }
                    commerce.checkoutAll(choices, here, onPlaced)
                }
                Muted(if (stores.size > 1) stringResource(R.string.g7_cart_accept_multi) else if (modeOf(stores.first()) == "SHIP") stringResource(R.string.g7_cart_accept_24h, stores.first().listing.title) else stringResource(R.string.g7_cart_accept_5m, stores.first().listing.title),
                    Modifier.padding(top = 8.dp).fillMaxWidth(), TextAlign.Center)
            }
        }
    }
    if (addressSheet) AddressSheet(vm, address?.id, startNew = addressList.isEmpty(), onPick = { a -> addressId = a.id }, onDismiss = { addressSheet = false })
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text(stringResource(R.string.g7_cart_empty_title)) }, text = { Text(if (stores.size > 1) pluralStringResource(R.plurals.g7_cart_empty_all, stores.size, stores.size) else stringResource(R.string.g7_cart_empty_from, stores.firstOrNull()?.listing?.title ?: stringResource(R.string.g7_cart_this_shop))) },
        confirmButton = { TextButton({ confirmClear = false; commerce.clear() }) { Text(stringResource(R.string.g7_cart_empty_it), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ confirmClear = false }) { Text(stringResource(R.string.g7_cart_keep)) } })
}

/** The cart used to ask before mixing shops; it no longer does (each shop is its own order), so this shows nothing. Kept so older screens compile. */
@Composable
fun CartSwitchDialog(@Suppress("UNUSED_PARAMETER") vm: BucksViewModel) {}
