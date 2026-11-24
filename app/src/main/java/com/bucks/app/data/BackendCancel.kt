package com.bucks.app.data

import com.bucks.app.R
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
    val rider get() = listOf("TOO_LONG" to Str.get(R.string.g8_cancel_too_long), "DRIVER_FAR" to Str.get(R.string.g8_cancel_driver_far), "DRIVER_ASKED" to Str.get(R.string.g8_cancel_driver_asked), "PLANS_CHANGED" to Str.get(R.string.g8_cancel_plans_changed), "BOOKED_BY_MISTAKE" to Str.get(R.string.g8_cancel_booked_mistake), "WRONG_ADDRESS" to Str.get(R.string.g8_cancel_wrong_pickup), "OTHER" to Str.get(R.string.g8_cancel_other))
    /** Driver handing a ride back. */
    val driver get() = listOf("RIDER_NO_SHOW" to Str.get(R.string.g8_cancel_rider_no_show), "RIDER_UNREACHABLE" to Str.get(R.string.g8_cancel_customer_unreachable), "RIDER_ASKED" to Str.get(R.string.g8_cancel_customer_asked_me), "TOO_FAR" to Str.get(R.string.g8_cancel_pickup_far), "VEHICLE_ISSUE" to Str.get(R.string.g8_cancel_vehicle), "UNSAFE" to Str.get(R.string.g8_cancel_unsafe), "OTHER" to Str.get(R.string.g8_cancel_other))
    /** Buyer cancelling an order before the shop accepts. */
    val buyer get() = listOf("CHANGED_MIND" to Str.get(R.string.g8_cancel_changed_mind), "ORDERED_BY_MISTAKE" to Str.get(R.string.g8_cancel_ordered_mistake), "WRONG_ADDRESS" to Str.get(R.string.g8_cancel_wrong_address), "TOO_SLOW" to Str.get(R.string.g8_cancel_shop_slow), "FOUND_BETTER" to Str.get(R.string.g8_cancel_found_elsewhere), "OTHER" to Str.get(R.string.g8_cancel_other))
    /** Shop cancelling an order it had accepted. */
    val shop get() = listOf("OUT_OF_STOCK" to Str.get(R.string.g8_cancel_out_of_stock), "CANT_DELIVER" to Str.get(R.string.g8_cancel_cant_deliver), "CUSTOMER_UNREACHABLE" to Str.get(R.string.g8_cancel_customer_unreachable), "CUSTOMER_ASKED" to Str.get(R.string.g8_cancel_customer_asked), "CLOSED" to Str.get(R.string.g8_cancel_closed), "OTHER" to Str.get(R.string.g8_cancel_other))
    /** Shop declining a new order. */
    val shopReject get() = listOf("OUT_OF_STOCK" to Str.get(R.string.g8_cancel_out_of_stock), "CLOSED" to Str.get(R.string.g8_cancel_closed), "TOO_FAR" to Str.get(R.string.g8_cancel_too_far_deliver), "CANT_DELIVER" to Str.get(R.string.g8_cancel_cant_deliver), "OTHER" to Str.get(R.string.g8_cancel_other))
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
