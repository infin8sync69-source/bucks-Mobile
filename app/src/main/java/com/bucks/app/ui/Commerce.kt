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
 * Cloud commerce state: a single-shop cart over cloud items, checkout through `place_order`, the buyer's orders,
 * and the vendor's live order inbox. Same shape as [Social]: plain Compose state, actions wrapped in [go] so a
 * failure becomes a toast. Reached as `vm.commerce`.
 */
class Commerce(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    /** One cart line: a cloud item and how many of it. */
    data class Line(val item: ItemRow, val qty: Int) { val amount: Int get() = item.price * qty }
    /** An add() for a different shop than the cart holds; the UI asks before replacing the cart. */
    data class PendingSwitch(val listing: ListingRow, val item: ItemRow, val delta: Int)

    // ---------- cart ----------
    /** The shop the cart belongs to; null while the cart is empty. */
    var shop by mutableStateOf<ListingRow?>(null); private set
    var lines by mutableStateOf<List<Line>>(emptyList()); private set
    var pendingSwitch by mutableStateOf<PendingSwitch?>(null); private set
    /** Total number of pieces in the cart, for the cart badge. */
    val count: Int get() = lines.sumOf { it.qty }
    val subtotal: Int get() = lines.sumOf { it.amount }
    /** True while an order is being placed. */
    var placing by mutableStateOf(false); private set

    fun qty(itemId: String): Int = lines.firstOrNull { it.item.id == itemId }?.qty ?: 0

    /** Adds [delta] pieces (negative removes). One shop at a time: adding from another shop sets [pendingSwitch] instead of changing anything. */
    fun add(listing: ListingRow, item: ItemRow, delta: Int) {
        val id = item.id ?: return
        val cur = shop
        if (cur != null && cur.id != listing.id && lines.isNotEmpty()) { if (delta > 0) pendingSwitch = PendingSwitch(listing, item, delta); return }
        val next = (qty(id) + delta).coerceAtLeast(0)
        lines = when {
            next == 0 -> lines.filterNot { it.item.id == id }
            lines.any { it.item.id == id } -> lines.map { if (it.item.id == id) it.copy(qty = next) else it }
            else -> lines + Line(item, next)
        }
        shop = if (lines.isEmpty()) null else listing
    }
    fun remove(itemId: String) { lines = lines.filterNot { it.item.id == itemId }; if (lines.isEmpty()) shop = null }
    /** The user agreed to drop the old shop's cart and start with the item they just tapped. */
    fun confirmSwitch() { val p = pendingSwitch ?: return; pendingSwitch = null; clear(); add(p.listing, p.item, p.delta) }
    fun dismissSwitch() { pendingSwitch = null }
    fun clear() { lines = emptyList(); shop = null; pendingSwitch = null }

    /** True when the shop has its own delivery riders (listing_members with role STORE_RIDER is readable by everyone). */
    suspend fun hasStoreRiders(listingId: String): Boolean = Backend.members(listingId).any { it.role == "STORE_RIDER" }

    /** Places the order with the drop at [Social.here]; the server prices the lines and adds the delivery fee. */
    fun checkout(mode: String, payment: String, dropLabel: String, onPlaced: (String) -> Unit) = go {
        val s = shop ?: run { toast("Your cart is empty."); return@go }
        val ls = lines.mapNotNull { l -> l.item.id?.let { it to l.qty } }.filter { it.second > 0 }
        if (ls.isEmpty()) { toast("Your cart is empty."); return@go }
        if (placing) return@go
        placing = true
        try {
            val id = Backend.placeOrder(s.id, ls, social.here, dropLabel.trim(), payment, mode)
            clear(); toast("Order placed. ${s.title} has 5 minutes to accept.")
            refreshMyOrders(); onPlaced(id)
        } finally { placing = false }
    }

    // ---------- my orders (buyer) ----------
    var myOrders by mutableStateOf<List<OrderRow>>(emptyList()); private set
    /** False until the first load finishes, so the empty state is not shown while loading. */
    var myOrdersLoaded by mutableStateOf(false); private set
    /** Listing id -> title, for order lists. */
    val listingTitles: SnapshotStateMap<String, String> = mutableStateMapOf()
    /** Order id -> the latest full row seen, shared by the order page and the lists. */
    val orders: SnapshotStateMap<String, CloudOrderRow> = mutableStateMapOf()

    fun refreshMyOrders() = go { val me = social.me ?: return@go; val rows = Backend.myOrders(me.id); myOrders = rows; myOrdersLoaded = true; titlesFor(rows.map { it.listingId }) }
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
    fun cancelOrder(id: String, then: () -> Unit = {}) = go { Backend.cancelOrder(id); toast("Order cancelled. Nothing to pay."); order(id); refreshMyOrders(); then() }

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
    fun stopOrders() {
        liveJob?.cancel(); liveJob = null
        liveChannel?.let { ch -> scope.launch { Backend.closeChannel(ch) } }; liveChannel = null
        liveListing = null
    }
    /** Owner or admin accepts (which creates the delivery task) or rejects a PLACED order. */
    fun respondOrder(id: String, accept: Boolean) = go {
        Backend.respondOrder(id, accept)
        toast(if (accept) "Accepted. The customer can see it is on the way." else "Rejected. The customer has been told.")
        refreshVendorOrder(id)
    }
    /** READY for any accepted order; DELIVERED only for pick-up orders once collected. */
    fun updateOrderStatus(id: String, status: String) = go {
        Backend.updateOrderStatus(id, status)
        toast(if (status == "READY") "Marked ready." else "Marked as collected. Thanks!")
        refreshVendorOrder(id)
    }
    private suspend fun refreshVendorOrder(id: String) {
        val o = Backend.orderDetail(id) ?: return
        orders[id] = o; vendorOrders = vendorOrders.map { if (it.id == id) o else it }
    }

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }
}
