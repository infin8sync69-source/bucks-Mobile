package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/*
 * Who delivers a shop's order, and what the shop sees of it (supabase/migrations/delivery_assignment.sql); and Bucks staff's
 * review of vehicles, without which no vehicle could ever go online.
 */

/** Where an order's delivery stands, for its shop. [status]: SEARCHING, MATCHED, ARRIVED, IN_PROGRESS, COMPLETED, NO_DRIVER, CANCELLED. */
@Serializable data class OrderDelivery(
    @SerialName("task_id") val taskId: String, val status: String,
    @SerialName("rider_id") val riderId: String? = null, @SerialName("rider_name") val riderName: String? = null,
    /** Only for the shop's own riders. */
    @SerialName("rider_phone") val riderPhone: String? = null, @SerialName("vehicle_plate") val plate: String? = null,
    @SerialName("preferred_rider") val preferredRider: String? = null, @SerialName("exclusive_until") val exclusiveUntil: String? = null,
    @SerialName("status_at") val statusAt: String? = null,
    /** The pickup PIN the shop hands over with the parcel; the rider enters it to mark it picked up. */
    val pin: String? = null,
    @SerialName("only_store_riders") val onlyStoreRiders: Boolean = false,
) {
    /** Nobody has it yet: the shop may ring again or send one of its riders. */
    val waiting get() = status == "SEARCHING" || status == "NO_DRIVER"
}

/** One of a shop's store riders. [online]: online right now with an approved bike. */
@Serializable data class StoreRider(@SerialName("profile_id") val profileId: String, val name: String, @SerialName("photo_url") val photoUrl: String? = null,
    val online: Boolean = false, @SerialName("has_bike") val hasBike: Boolean = false)

/** A vehicle waiting for Bucks staff. [docs] is a list of {kind, path} (or bare paths on old rows) in the private docs bucket. */
@Serializable data class VehicleToReview(val id: String, @SerialName("owner_id") val ownerId: String, @SerialName("owner_name") val ownerName: String,
    val kind: String, val model: String = "", val plate: String, val docs: JsonArray = JsonArray(emptyList()), @SerialName("created_at") val createdAt: String = "") {
    /** (kind, path) of each document; kind is "" on old rows that kept only the path. */
    val files: List<Pair<String, String>> get() = docs.mapNotNull { e ->
        (e as? JsonObject)?.let { o -> o["path"]?.jsonPrimitive?.contentOrNull?.let { (o["kind"]?.jsonPrimitive?.contentOrNull ?: "") to it } }
            ?: runCatching { "" to e.jsonPrimitive.content }.getOrNull()
    }
}

object DeliveryBackend {
    private val db get() = Backend.client.postgrest

    /** Accept (optionally with one of the shop's riders to ring first and alone) or reject with a reason. */
    suspend fun respond(orderId: String, accept: Boolean, reason: String?, rider: String?) {
        db.rpc("respond_order", buildJsonObject { put("p_order", orderId); put("p_accept", accept); put("p_reason", reason); put("p_rider", rider) })
    }
    /** Ring again (rider null: the usual riders) or send one of the shop's riders, while nobody has taken it. */
    suspend fun reassign(orderId: String, rider: String?) { db.rpc("reassign_delivery", buildJsonObject { put("p_order", orderId); put("p_rider", rider) }) }
    suspend fun orderDelivery(orderId: String): OrderDelivery? = db.rpc("order_delivery", buildJsonObject { put("p_order", orderId) }).decodeList<OrderDelivery>().firstOrNull()
    suspend fun storeRiders(listingId: String): List<StoreRider> = db.rpc("store_riders", buildJsonObject { put("p_listing", listingId) }).decodeList()

    suspend fun vehiclesToReview(): List<VehicleToReview> = db.rpc("vehicles_to_review").decodeList()
    suspend fun reviewVehicle(id: String, approve: Boolean, note: String) {
        db.rpc("review_vehicle", buildJsonObject { put("p_vehicle", id); put("p_approve", approve); put("p_note", note) })
    }
}
