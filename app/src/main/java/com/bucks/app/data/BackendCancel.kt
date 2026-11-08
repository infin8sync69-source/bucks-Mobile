package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * Cancelling a ride or an order with a reason (migration cancellation.sql). The codes are checked by the server; the labels are what people read.
 * Rider and driver reasons are required once someone has accepted; the screens ask for them.
 */
private val cancelDb get() = Backend.client.postgrest

object CancelReasons {
    /** Rider cancelling a ride. */
    val rider = listOf("TOO_LONG" to "Taking too long", "DRIVER_FAR" to "Driver is too far", "DRIVER_ASKED" to "Driver asked me to cancel", "PLANS_CHANGED" to "My plans changed", "BOOKED_BY_MISTAKE" to "Booked by mistake", "WRONG_ADDRESS" to "Wrong pickup or drop", "OTHER" to "Something else")
    /** Driver handing a ride back. */
    val driver = listOf("RIDER_NO_SHOW" to "Customer isn't at the pickup", "RIDER_UNREACHABLE" to "Can't reach the customer", "RIDER_ASKED" to "Customer asked me to cancel", "TOO_FAR" to "Pickup is too far", "VEHICLE_ISSUE" to "Vehicle problem", "UNSAFE" to "I don't feel safe", "OTHER" to "Something else")
    /** Buyer cancelling an order before the shop accepts. */
    val buyer = listOf("CHANGED_MIND" to "I changed my mind", "ORDERED_BY_MISTAKE" to "Ordered by mistake", "WRONG_ADDRESS" to "Wrong address", "TOO_SLOW" to "Shop is taking too long", "FOUND_BETTER" to "Found it elsewhere", "OTHER" to "Something else")
    /** Shop cancelling an order it had accepted. */
    val shop = listOf("OUT_OF_STOCK" to "Out of stock", "CANT_DELIVER" to "Can't deliver there", "CUSTOMER_UNREACHABLE" to "Can't reach the customer", "CUSTOMER_ASKED" to "Customer asked to cancel", "CLOSED" to "We're closed", "OTHER" to "Something else")
    /** Shop declining a new order. */
    val shopReject = listOf("OUT_OF_STOCK" to "Out of stock", "CLOSED" to "We're closed", "TOO_FAR" to "Too far to deliver", "CANT_DELIVER" to "Can't deliver there", "OTHER" to "Something else")
}

/** How often I cancelled after someone accepted: today and in the last 7 days, as a rider and as a driver. */
@Serializable data class CancelStats(
    @SerialName("rider_day") val riderDay: Int = 0, @SerialName("rider_week") val riderWeek: Int = 0,
    @SerialName("driver_day") val driverDay: Int = 0, @SerialName("driver_week") val driverWeek: Int = 0,
)

/** Rider cancels a ride. [reason] is required once a driver accepted. The server refuses once the trip has started. */
suspend fun Backend.cancelTask(taskId: String, reason: String?, note: String = "") {
    cancelDb.rpc("cancel_task", buildJsonObject { put("p_task", taskId); put("p_reason", reason); put("p_note", note) })
}
/** Driver hands an accepted ride back so it rings other drivers. [reason] is required. */
suspend fun Backend.releaseTask(taskId: String, reason: String, note: String = "") {
    cancelDb.rpc("release_task", buildJsonObject { put("p_task", taskId); put("p_reason", reason); put("p_note", note) })
}
suspend fun Backend.myCancelStats(): CancelStats = cancelDb.rpc("my_cancel_stats").decodeAs()
