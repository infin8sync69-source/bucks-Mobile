package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onStart
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Commerce extensions to [Backend]: order detail with its lines, the vendor inbox with a live feed,
 * and the functions from supabase/migrations/commerce.sql (contact_for_order, cancel_order, update_order_status).
 */

/** One priced line of an order, as place_order stored it. */
@Serializable data class OrderLine(@SerialName("item_id") val itemId: String = "", val name: String = "", val price: Int = 0, val qty: Int = 1)

/** An orders row including its lines; [OrderRow] (in Backend.kt) leaves them out. */
@Serializable data class CloudOrderRow(val id: String, @SerialName("listing_id") val listingId: String, @SerialName("buyer_id") val buyerId: String,
    val lines: List<OrderLine> = emptyList(), val subtotal: Int, @SerialName("delivery_fee") val deliveryFee: Int = 0,
    @SerialName("fee_paid_by") val feePaidBy: String = "BUYER", @SerialName("delivery_mode") val deliveryMode: String = "MARKETPLACE", val payment: String = "UPI",
    @SerialName("drop_label") val dropLabel: String = "", val status: String, @SerialName("accept_by") val acceptBy: String, @SerialName("created_at") val createdAt: String,
    /** BUYER or SHOP once the order is CANCELLED (see commerce.sql); null otherwise and on older rows. */
    @SerialName("cancelled_by") val cancelledBy: String? = null,
    /** Shipped orders (delivery_mode SHIP, ecommerce.sql): who it goes to, the carrier and tracking the shop entered, and when. */
    @SerialName("ship_to") val shipTo: JsonObject? = null, val carrier: String = "", @SerialName("tracking_no") val trackingNo: String = "", @SerialName("tracking_url") val trackingUrl: String = "",
    @SerialName("shipped_at") val shippedAt: String? = null, @SerialName("delivered_at") val deliveredAt: String? = null) {
    val shipped get() = deliveryMode == "SHIP"
    /** The address as the shop reads it on a label: name, phone, lines, city, state, pincode. */
    val shipToText: String get() = shipTo?.let { a ->
        fun f(k: String) = (a[k] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim().orEmpty()
        listOf(f("name"), f("phone"), f("line1"), f("line2"), listOf(f("city"), f("state")).filter { it.isNotBlank() }.joinToString(", ") + " " + f("pincode")).filter { it.isNotBlank() }.joinToString("\n")
    }.orEmpty()
    /** Everything the buyer pays for this order: items plus the rider's fee unless the shop offers free delivery. */
    val total: Int get() = buyerTotal(subtotal, deliveryFee, feePaidBy)
    /**
     * The part of [total] the buyer pays the Bucks rider directly at the door (UPI or cash): the fee of a marketplace delivery.
     * The rider is independent of the shop and collects their own fare, so it never goes into the shop's UPI amount.
     * With free delivery the shop settles the rider itself, so this is 0.
     */
    val feeAtDoor: Int get() = if (deliveryMode == "MARKETPLACE" && feePaidBy == "BUYER") deliveryFee else 0
    /** What the buyer pays the shop: items, plus the delivery fee only when the shop's own rider delivers (the shop pays that rider). */
    val toShop: Int get() = total - feeAtDoor
}

/** Items plus the delivery fee when the buyer pays it; the same rule for [CloudOrderRow] and [OrderRow] lists. */
fun buyerTotal(subtotal: Int, deliveryFee: Int, feePaidBy: String): Int = subtotal + if (feePaidBy == "BUYER") deliveryFee else 0

/** Counterparty details while an order is live: the buyer gets the shop owner's phone and UPI link, the shop gets the buyer's phone. */
@Serializable data class OrderContactRow(val phone: String? = null, @SerialName("upi_uri") val upiUri: String? = null, val name: String? = null)

suspend fun Backend.orderDetail(id: String): CloudOrderRow? =
    client.postgrest.from("orders").select { filter { eq("id", id) } }.decodeSingleOrNull()

suspend fun Backend.vendorOrders(listingId: String): List<CloudOrderRow> =
    client.postgrest.from("orders").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()

suspend fun Backend.listingsByIds(ids: Collection<String>): List<ListingRow> =
    if (ids.isEmpty()) emptyList() else client.postgrest.from("listings").select { filter { isIn("id", ids.toList()) } }.decodeList()

/** The delivery task an accepted delivery order created; readable by the buyer (requester) and the rider who took it.
 *  Read through `tasks_geo`: the API may not read `tasks.pin` directly (dispatch.sql), the view gives it to the buyer only. */
suspend fun Backend.taskForOrder(orderId: String): TaskRow? =
    client.postgrest.from("tasks_geo").select { filter { eq("order_id", orderId) }; order("created_at", Order.DESCENDING); limit(1) }.decodeList<TaskRow>().firstOrNull()

suspend fun Backend.contactForOrder(orderId: String): OrderContactRow? =
    client.postgrest.rpc("contact_for_order", buildJsonObject { put("p_order", orderId) }).decodeList<OrderContactRow>().firstOrNull()

/** Buyer cancels while the order is still PLACED. */
suspend fun Backend.cancelOrder(orderId: String, reason: String? = null) { client.postgrest.rpc("cancel_order", buildJsonObject { put("p_order", orderId); put("p_reason", reason) }) }

/** Vendor marks an accepted order READY, a pick-up order DELIVERED once collected, or CANCELLED when no rider has it (or the buyer never came). */
suspend fun Backend.updateOrderStatus(orderId: String, status: String, reason: String? = null) {
    client.postgrest.rpc("update_order_status", buildJsonObject { put("p_order", orderId); put("p_status", status); put("p_reason", reason) })
}

/** Inserts and updates on a shop's orders as they happen (row-level security still applies). Close the channel when the screen goes away. */
fun Backend.liveOrders(listingId: String): Pair<RealtimeChannel, Flow<CloudOrderRow>> {
    val channel = client.channel("orders-$listingId-${System.nanoTime()}")
    val flow = channel.postgresChangeFlow<PostgresAction>(schema = "public") { table = "orders"; filter("listing_id", FilterOperator.EQ, listingId) }
        .mapNotNull { a -> when (a) { is PostgresAction.Insert -> a.decodeRecord<CloudOrderRow>(); is PostgresAction.Update -> a.decodeRecord<CloudOrderRow>(); else -> null } }
        .onStart { channel.subscribe() }
    return channel to flow
}

/** Status changes on one order, for the buyer's order page. */
fun Backend.liveOrder(orderId: String): Pair<RealtimeChannel, Flow<CloudOrderRow>> {
    val channel = client.channel("order-$orderId-${System.nanoTime()}")
    val flow = channel.postgresChangeFlow<PostgresAction.Update>(schema = "public") { table = "orders"; filter("id", FilterOperator.EQ, orderId) }
        .mapNotNull { runCatching { it.decodeRecord<CloudOrderRow>() }.getOrNull() }
        .onStart { channel.subscribe() }
    return channel to flow
}

// ---------- shipping: orders to an address anywhere, the address book (migration ecommerce.sql) ----------
/** A saved delivery address; the server checks the mobile number (10 digits) and the pincode (6 digits) again at checkout. */
@Serializable data class AddressRow(val id: String? = null, val label: String = "", val name: String, val phone: String, val line1: String, val line2: String = "",
    val city: String, val state: String, val pincode: String, @SerialName("is_default") val isDefault: Boolean = false) {
    val oneLine: String get() = listOf(line1, line2, "$city, $state $pincode").filter { it.isNotBlank() }.joinToString(", ")
    fun json(): JsonObject = buildJsonObject { put("name", name); put("phone", phone); put("line1", line1); put("line2", line2); put("city", city); put("state", state); put("pincode", pincode) }
}

suspend fun Backend.addresses(): List<AddressRow> = client.postgrest.from("addresses").select { order("created_at", Order.DESCENDING) }.decodeList()
suspend fun Backend.saveAddress(me: String, a: AddressRow): AddressRow =
    if (a.id == null) client.postgrest.from("addresses").insert(buildJsonObject { put("profile_id", me); put("label", a.label); put("name", a.name); put("phone", a.phone); put("line1", a.line1); put("line2", a.line2); put("city", a.city); put("state", a.state); put("pincode", a.pincode); put("is_default", a.isDefault) }) { select() }.decodeSingle()
    else client.postgrest.from("addresses").update({ set("label", a.label); set("name", a.name); set("phone", a.phone); set("line1", a.line1); set("line2", a.line2); set("city", a.city); set("state", a.state); set("pincode", a.pincode); set("is_default", a.isDefault) }) { select(); filter { eq("id", a.id) } }.decodeSingle()
suspend fun Backend.deleteAddress(id: String) { client.postgrest.from("addresses").delete { filter { eq("id", id) } } }

/** Orders from a shop that ships: the address is checked on the server, the shipping fee comes from the shop's own rule. */
suspend fun Backend.placeShipOrder(listingId: String, lines: List<Pair<String, Int>>, address: JsonObject, payment: String): String =
    client.postgrest.rpc("place_order_ship", buildJsonObject {
        put("p_listing", listingId)
        put("p_lines", buildJsonArray { lines.forEach { (item, qty) -> add(buildJsonObject { put("item_id", item); put("qty", qty) }) } })
        put("p_address", address); put("p_payment", payment)
    }).decodeAs()
/** The shop hands an accepted shipped order to a carrier ("Self delivery" is fine) with an optional tracking number and link. */
suspend fun Backend.shipOrder(orderId: String, carrier: String, tracking: String, url: String) {
    client.postgrest.rpc("ship_order", buildJsonObject { put("p_order", orderId); put("p_carrier", carrier); put("p_tracking", tracking); put("p_url", url) })
}
/** The buyer received it, or the shop delivered it itself. */
suspend fun Backend.markDelivered(orderId: String) { client.postgrest.rpc("mark_delivered", buildJsonObject { put("p_order", orderId) }) }
