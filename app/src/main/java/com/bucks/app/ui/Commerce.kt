package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.bucks.app.data.*
import io.github.jan.supabase.realtime.RealtimeChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Cloud commerce state: a cart over cloud items with one part per store, checkout through `place_order`, the buyer's orders,
 * and the vendor's live order inbox. Same shape as [Social]: plain Compose state, actions wrapped in [go] so a
 * failure becomes a toast. Reached as `vm.commerce`.
 */
class Commerce(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    /** One cart line: a cloud item and how many of it. */
    data class Line(val item: ItemRow, val qty: Int) { val amount: Int get() = item.price * qty }
    /** One store's part of the cart. Each store becomes its own order with its own delivery, fee and payment. */
    data class StoreCart(val listing: ListingRow, val lines: List<Line>) { val amount: Int get() = lines.sumOf { it.amount }; val count: Int get() = lines.sumOf { it.qty } }
    /** How one store's order is delivered and paid; chosen per store in the cart. */
    data class Choice(val mode: String, val payment: String, val dropLabel: String, val address: AddressRow? = null)

    // ---------- cart ----------
    /** The cart, by store, in the order the first item from each was added. Empty while nothing is in it. */
    var stores by mutableStateOf<List<StoreCart>>(emptyList()); private set
    /** Total number of pieces in the cart across every store, for the cart badge. */
    val count: Int get() = stores.sumOf { it.count }
    val subtotal: Int get() = stores.sumOf { it.amount }
    /** True while orders are being placed. */
    var placing by mutableStateOf(false); private set

    fun qty(itemId: String): Int = stores.firstNotNullOfOrNull { st -> st.lines.firstOrNull { it.item.id == itemId }?.qty } ?: 0

    /** Adds [delta] pieces of [item] from [listing] (negative removes). Stores mix freely: each keeps its own part of the cart. */
    fun add(listing: ListingRow, item: ItemRow, delta: Int) {
        val id = item.id ?: return
        val cur = stores.firstOrNull { it.listing.id == listing.id }
        val was = cur?.lines?.firstOrNull { it.item.id == id }?.qty ?: 0
        val next = (was + delta).coerceIn(0, item.stock?.coerceAtLeast(0) ?: 99)
        if (next == was) { if (delta > 0 && item.stock != null && was >= item.stock) toast("Only ${item.stock} of ${item.name} in stock."); return }
        val old = cur?.lines ?: emptyList()
        val lines = when {
            next == 0 -> old.filterNot { it.item.id == id }
            old.any { it.item.id == id } -> old.map { if (it.item.id == id) it.copy(qty = next) else it }
            else -> old + Line(item, next)
        }
        stores = when {
            lines.isEmpty() -> stores.filterNot { it.listing.id == listing.id }
            cur == null -> stores + StoreCart(listing, lines)
            else -> stores.map { if (it.listing.id == listing.id) it.copy(lines = lines) else it }
        }
    }
    fun remove(itemId: String) { stores = stores.mapNotNull { st -> val ls = st.lines.filterNot { it.item.id == itemId }; if (ls.isEmpty()) null else st.copy(lines = ls) } }
    fun clearStore(listingId: String) { stores = stores.filterNot { it.listing.id == listingId } }
    fun clear() { stores = emptyList() }
    /** Kept so older call sites compile; the cart no longer asks to switch stores. */
    fun confirmSwitch() {}
    fun dismissSwitch() {}

    /** True when the shop has its own delivery riders (listing_members with role STORE_RIDER is readable by everyone). */
    suspend fun hasStoreRiders(listingId: String): Boolean = Backend.members(listingId).any { it.role == "STORE_RIDER" }

    /**
     * Places one order per store in the cart, each with its own delivery mode and payment, one after another. The drop is the phone's
     * real location (null until a fix arrives; only pick-up can be placed without it). A store whose order fails stays in the cart with
     * its reason in a toast; the ones that went through are removed. [onDone] gets the ids of the orders placed, in order.
     */
    fun checkoutAll(choices: Map<String, Choice>, drop: LatLng?, onDone: (List<String>) -> Unit) = go {
        if (placing) return@go
        val todo = stores.toList()
        if (todo.isEmpty()) { toast("Your cart is empty."); return@go }
        placing = true
        val placed = mutableListOf<String>(); var failed = 0; var shipped = 0
        try {
            for (st in todo) {
                val c = choices[st.listing.id] ?: continue
                val ls = st.lines.mapNotNull { l -> l.item.id?.let { it to l.qty } }.filter { it.second > 0 }
                if (ls.isEmpty()) continue
                try {
                    val id = if (c.mode == "SHIP") {
                        val a = c.address
                        if (a == null) { failed++; toast("Add a delivery address for ${st.listing.title}'s order."); continue }
                        Backend.placeShipOrder(st.listing.id, ls, a.json(), c.payment).also { shipped++ }
                    } else {
                        val at = drop ?: if (c.mode == "PICKUP") social.here else null
                        if (at == null) { failed++; toast("Turn on location to get ${st.listing.title}'s order delivered, or choose pick-up."); continue }
                        Backend.placeOrder(st.listing.id, ls, at, c.dropLabel.trim(), c.payment, c.mode)
                    }
                    placed += id; clearStore(st.listing.id)
                } catch (e: Exception) { failed++; toast("${st.listing.title}: ${friendly(e)}") }
            }
        } finally { placing = false }
        if (placed.isNotEmpty()) {
            toast(when {
                placed.size == 1 && shipped == 1 -> "Order placed. The shop has 24 hours to accept and ship it."
                placed.size == 1 -> "Order placed. The shop has 5 minutes to accept."
                else -> "${placed.size} orders placed, each delivered separately. Shops that ship have 24 hours to accept; local shops 5 minutes."
            })
            refreshMyOrders(); onDone(placed)
        } else if (failed == 0) toast("Nothing to place.")
    }

    // ---------- address book (delivery addresses for shipped orders) ----------
    var addresses by mutableStateOf<List<AddressRow>>(emptyList()); private set
    var addressesLoaded by mutableStateOf(false); private set
    fun loadAddresses() = go { addresses = Backend.addresses(); addressesLoaded = true }
    /** Saves a new address or edits one (id set); [onSaved] gets the saved row so checkout can pick it. */
    fun saveAddress(a: AddressRow, onSaved: (AddressRow) -> Unit = {}) = go {
        val me = social.me?.id ?: return@go
        val saved = Backend.saveAddress(me, a); addresses = Backend.addresses(); addressesLoaded = true; toast("Address saved."); onSaved(saved)
    }
    fun deleteAddress(id: String) = go { Backend.deleteAddress(id); addresses = addresses.filterNot { it.id == id }; toast("Address deleted.") }

    // ---------- shipping (shop side and buyer side) ----------
    /** The shop hands an accepted shipped order to a carrier; the customer is told and sees the tracking. */
    fun shipOrder(id: String, carrier: String, tracking: String, url: String, then: () -> Unit = {}) = go {
        Backend.shipOrder(id, carrier, tracking, url); toast("Marked shipped. The customer has been told."); refreshVendorOrder(id); then()
    }
    /** The buyer received it, or the shop delivered it itself: closes the shipped order. */
    fun markDelivered(id: String) = go { Backend.markDelivered(id); toast("Marked delivered."); order(id); refreshMyOrders(); runCatching { refreshVendorOrder(id) } }

    // ---------- my orders (buyer) ----------
    var myOrders by mutableStateOf<List<OrderRow>>(emptyList()); private set
    /** False until the first load finishes, so the empty state is not shown while loading. */
    var myOrdersLoaded by mutableStateOf(false); private set
    /** Listing id -> title, for order lists. */
    val listingTitles: SnapshotStateMap<String, String> = mutableStateMapOf()
    /** Order id -> the latest full row seen, shared by the order page and the lists. */
    val orders: SnapshotStateMap<String, CloudOrderRow> = mutableStateMapOf()

    /** [quiet] is for background polling: a failed refresh keeps what's on screen instead of toasting every few seconds. */
    fun refreshMyOrders(quiet: Boolean = false) = scope.launch { try { val me = social.me ?: return@launch; val rows = Backend.myOrders(me.id); if (social.me?.id != me.id) return@launch
        myOrders = rows; myOrdersLoaded = true; titlesFor(rows.map { it.listingId }) } catch (e: Exception) { if (!quiet) toast(friendly(e)) } }
    suspend fun titlesFor(ids: Collection<String>) { val missing = ids.distinct().filter { it !in listingTitles }; if (missing.isNotEmpty()) Backend.listingsByIds(missing).forEach { listingTitles[it.id] = it.title } }
    fun titleOf(listingId: String) = listingTitles[listingId] ?: "Shop"

    /** Loads one order with its lines, caches it in [orders] and returns it (null when it is not mine or does not exist). */
    suspend fun order(id: String): CloudOrderRow? {
        val o = Backend.orderDetail(id) ?: return null
        orders[id] = o; titlesFor(listOf(o.listingId)); social.namesFor(listOf(o.buyerId)); return o
    }
    fun loadOrder(id: String) = go { order(id) }
    suspend fun taskForOrder(orderId: String): TaskRow? = Backend.taskForOrder(orderId)
    suspend fun contactFor(orderId: String): OrderContactRow? = Backend.contactForOrder(orderId)
    /** [reason] is a CancelReasons.buyer code. [done] gets true once the server cancelled it, false when it refused (the reason sheet stays open). */
    fun cancelOrder(id: String, reason: String? = null, done: (Boolean) -> Unit = {}) = goDone(done) { Backend.cancelOrder(id, reason); toast("Order cancelled. Nothing to pay."); runCatching { order(id) }; refreshMyOrders(quiet = true) }

    // ---------- vendor inbox ----------
    var vendorOrders by mutableStateOf<List<CloudOrderRow>>(emptyList()); private set
    var vendorLoaded by mutableStateOf(false); private set
    /** Goes up each time a new PLACED order arrives live while the inbox is open; the screen plays a sound on change. */
    var newOrderTick by mutableIntStateOf(0); private set
    private var liveChannel: RealtimeChannel? = null
    private var liveJob: Job? = null
    private var liveListing: String? = null

    /** Loads a shop's orders (newest first) and follows them live until [stopOrders]. */
    fun ordersFor(listingId: String) {
        if (liveListing != listingId) { stopOrders(); vendorOrders = emptyList(); vendorLoaded = false }
        go { val rows = Backend.vendorOrders(listingId); vendorOrders = rows; vendorLoaded = true; social.namesFor(rows.map { it.buyerId }); rows.forEach { orders[it.id] = it } }
        if (liveListing == listingId && liveJob?.isActive == true) return
        stopOrders()   // a channel whose collector died is closed before a new one opens
        liveListing = listingId
        val (channel, flow) = Backend.liveOrders(listingId)
        liveChannel = channel
        liveJob = scope.launch { runCatching { flow.collect { merge(it) } } }
    }
    private suspend fun merge(o: CloudOrderRow) {
        val known = vendorOrders.any { it.id == o.id }
        vendorOrders = (listOf(o) + vendorOrders.filterNot { it.id == o.id }).sortedByDescending { it.createdAt }
        orders[o.id] = o
        social.namesFor(listOf(o.buyerId))
        if (!known && o.status == "PLACED") newOrderTick++
    }
    /** Sign-out and account deletion: nothing of this person's cart, orders or shop inbox stays for the next account on the phone. */
    fun signedOut() {
        stopOrders(); clear(); placing = false
        myOrders = emptyList(); myOrdersLoaded = false; listingTitles.clear(); orders.clear(); addresses = emptyList(); addressesLoaded = false
        vendorOrders = emptyList(); vendorLoaded = false
    }
    fun stopOrders() {
        liveJob?.cancel(); liveJob = null
        liveChannel?.let { ch -> scope.launch { Backend.closeChannel(ch) } }; liveChannel = null
        liveListing = null
    }
    /** Owner or admin accepts (which creates the delivery task) or rejects a PLACED order. */
    fun respondOrder(id: String, accept: Boolean, reason: String? = null, done: (Boolean) -> Unit = {}) = goDone(done) {
        Backend.respondOrder(id, accept, reason)
        toast(if (accept) "Accepted. The customer can see it is on the way." else "Rejected. The customer has been told.")
        runCatching { refreshVendorOrder(id) }
    }
    /** READY for any accepted order; DELIVERED only for pick-up orders once collected; CANCELLED when no rider has it (or the buyer never came). */
    fun updateOrderStatus(id: String, status: String, reason: String? = null, done: (Boolean) -> Unit = {}) = goDone(done) {
        Backend.updateOrderStatus(id, status, reason)
        toast(when (status) { "READY" -> "Marked ready."; "CANCELLED" -> "Order cancelled. The customer has been told."; else -> "Marked as collected. Thanks!" })
        runCatching { refreshVendorOrder(id) }
    }
    private suspend fun refreshVendorOrder(id: String) {
        val o = Backend.orderDetail(id) ?: return
        orders[id] = o; vendorOrders = vendorOrders.map { if (it.id == id) o else it }
    }

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Like [go], and tells the caller whether it worked, so a reason sheet can stay open on a refusal. */
    private fun goDone(done: (Boolean) -> Unit, block: suspend () -> Unit) = scope.launch { try { block(); done(true) } catch (e: Exception) { toast(friendly(e)); done(false) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }
}
