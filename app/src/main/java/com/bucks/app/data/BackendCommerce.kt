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
    @SerialName("drop_label") val dropLabel: String = "", val status: String, @SerialName("accept_by") val acceptBy: String, @SerialName("created_at") val createdAt: String) {
    /** What the buyer hands over: items plus the rider's fee unless the shop offers free delivery. */
    val total: Int get() = subtotal + if (feePaidBy == "BUYER") deliveryFee else 0
}

/** Counterparty details while an order is live: the buyer gets the shop owner's phone and UPI link, the shop gets the buyer's phone. */
@Serializable data class OrderContactRow(val phone: String? = null, @SerialName("upi_uri") val upiUri: String? = null, val name: String? = null)

suspend fun Backend.orderDetail(id: String): CloudOrderRow? =
    client.postgrest.from("orders").select { filter { eq("id", id) } }.decodeSingleOrNull()

suspend fun Backend.vendorOrders(listingId: String): List<CloudOrderRow> =
    client.postgrest.from("orders").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()

suspend fun Backend.listingsByIds(ids: Collection<String>): List<ListingRow> =
    if (ids.isEmpty()) emptyList() else client.postgrest.from("listings").select { filter { isIn("id", ids.toList()) } }.decodeList()

/** The delivery task an accepted delivery order created; readable by the buyer (requester) and the rider who took it. */
suspend fun Backend.taskForOrder(orderId: String): TaskRow? =
    client.postgrest.from("tasks").select { filter { eq("order_id", orderId) }; order("created_at", Order.DESCENDING); limit(1) }.decodeList<TaskRow>().firstOrNull()

suspend fun Backend.contactForOrder(orderId: String): OrderContactRow? =
    client.postgrest.rpc("contact_for_order", buildJsonObject { put("p_order", orderId) }).decodeList<OrderContactRow>().firstOrNull()

/** Buyer cancels while the order is still PLACED. */
suspend fun Backend.cancelOrder(orderId: String) { client.postgrest.rpc("cancel_order", buildJsonObject { put("p_order", orderId) }) }

/** Vendor marks an accepted order READY, or a pick-up order DELIVERED once collected. */
suspend fun Backend.updateOrderStatus(orderId: String, status: String) {
    client.postgrest.rpc("update_order_status", buildJsonObject { put("p_order", orderId); put("p_status", status) })
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
