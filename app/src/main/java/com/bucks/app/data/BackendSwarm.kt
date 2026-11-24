package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * Swarm Phase 1: recovery and the demand field (supabase/migrations/swarm_phase1.sql, docs/ai/reports/Swarm intelligence for Bucks.md).
 * Recovery only proposes: every choice here is the person's own tap, and booking again goes through today's flow and confirm sheet.
 */
private val swarmDb get() = Backend.client.postgrest

/** A shop near the drop that lists items from an order another shop turned down (order_alternatives). */
@Serializable data class SimilarShop(
    @SerialName("listing_id") val listingId: String, val title: String = "", @SerialName("photo_url") val photoUrl: String? = null,
    val area: String = "", @SerialName("distance_m") val distanceM: Double = 0.0,
    @SerialName("matched_items") val matchedItems: List<String> = emptyList(), @SerialName("min_price") val minPrice: Int? = null,
)

/** The driver's "recent requests nearby" card (recent_requests_near). [requests3h] is null when under the privacy threshold. */
@Serializable data class RecentRequests(
    @SerialName("requests_3h") val requests3h: Int? = null, @SerialName("requests_7d") val requests7d: Int = 0,
    @SerialName("unfilled_7d") val unfilled7d: Int = 0, @SerialName("drivers_online") val driversOnline: Int = 0,
)

object Recovery {
    const val TASK = "TASK"; const val ORDER = "ORDER"
    const val TRY_AGAIN = "TRY_AGAIN"; const val TRY_CAB = "TRY_CAB"; const val NOTIFY_ME = "NOTIFY_ME"; const val SIMILAR_SHOPS = "SIMILAR_SHOPS"
    /** Orders worth suggesting other shops for: turned down, or cancelled by the shop for a reason another shop could fix. */
    fun similarShopsFor(status: String, cancelledBy: String?, reason: String?) =
        status == "REJECTED" || (status == "CANCELLED" && cancelledBy == "SHOP" && reason in setOf("OUT_OF_STOCK", "CLOSED", "CANT_DELIVER", "TOO_FAR"))
}

/** Records the person's tap on a recovery card (for recovery conversion). Books nothing. */
suspend fun Backend.recoveryChoice(kind: String, subject: String, choice: String): Boolean =
    swarmDb.rpc("recovery_choice", buildJsonObject { put("p_kind", kind); put("p_subject", subject); put("p_choice", choice) }).data.trim() == "true"

/** "Notify me when a driver is online" near [at]. False when the server has it switched off. */
suspend fun Backend.notifyMeWhenDriverOnline(kind: VehicleKind, at: LatLng): Boolean =
    swarmDb.rpc("notify_me_when_driver_online", buildJsonObject { put("p_kind", kind.name); put("lat", at.lat); put("lng", at.lng) }).data.trim() == "true"

suspend fun Backend.orderAlternatives(orderId: String): List<SimilarShop> =
    swarmDb.rpc("order_alternatives", buildJsonObject { put("p_order", orderId) }).decodeList()

suspend fun Backend.recentRequestsNear(at: LatLng): RecentRequests? =
    swarmDb.rpc("recent_requests_near", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList<RecentRequests>().firstOrNull()
