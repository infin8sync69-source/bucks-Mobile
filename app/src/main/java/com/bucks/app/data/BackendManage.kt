package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Backend calls for the Manage feature: an owner's own listings, vehicles, admins and recommendations.
 * Schema additions live in supabase/migrations/manage.sql (the my_invites() function).
 */

/** An invite addressed to me, with the inviter's name and what it is for (from my_invites()). kind: BUSINESS / SKILL / DRIVER / VEHICLE. */
@Serializable data class InviteForMe(val id: String, @SerialName("listing_id") val listingId: String? = null, @SerialName("vehicle_id") val vehicleId: String? = null,
    @SerialName("inviter_id") val inviterId: String, @SerialName("inviter_name") val inviterName: String = "", val role: String, val title: String = "", val kind: String = "",
    @SerialName("created_at") val createdAt: String = "")
@Serializable data class VehicleMemberRow(@SerialName("vehicle_id") val vehicleId: String, @SerialName("profile_id") val profileId: String, val role: String)
@Serializable data class RecommendationRow(@SerialName("listing_id") val listingId: String, @SerialName("recommender_id") val recommenderId: String)
@Serializable data class VehicleDocsRow(val id: String, val docs: JsonArray = JsonArray(emptyList()))
/** One uploaded vehicle document (kind RC, INSURANCE or PERMIT) at [path] in the private "docs" bucket. */
data class VehicleDoc(val kind: String, val path: String)

private val mdb get() = Backend.client.postgrest

/** listing id -> my role (OWNER, ADMIN, STORE_RIDER) for every listing I help run. */
suspend fun Backend.myRoles(me: String): Map<String, String> =
    mdb.from("listing_members").select { filter { eq("profile_id", me) } }.decodeList<MemberRow>().associate { it.listingId to it.role }
suspend fun Backend.setListingPhoto(id: String, url: String?) { mdb.from("listings").update({ set("photo_url", url) }) { filter { eq("id", id) } } }
/** How many neighbours have recommended each listing (the community cap counts these; it goes live at 7). */
suspend fun Backend.recommendationCounts(listingIds: Collection<String>): Map<String, Int> =
    if (listingIds.isEmpty()) emptyMap()
    else mdb.from("recommendations").select { filter { isIn("listing_id", listingIds.toList()) } }.decodeList<RecommendationRow>().groupingBy { it.listingId }.eachCount()

// ---------- invites and members ----------
suspend fun Backend.invitesForMe(): List<InviteForMe> = mdb.rpc("my_invites").decodeList()
suspend fun Backend.revokeInvite(id: String) { mdb.from("invites").update({ set("status", "REVOKED") }) { filter { eq("id", id) } } }
suspend fun Backend.vehicleMembers(vehicleId: String): List<VehicleMemberRow> = mdb.from("vehicle_members").select { filter { eq("vehicle_id", vehicleId) } }.decodeList()
suspend fun Backend.removeVehicleMember(vehicleId: String, profileId: String) { mdb.from("vehicle_members").delete { filter { eq("vehicle_id", vehicleId); eq("profile_id", profileId) } } }

// ---------- vehicles ----------
/** vehicle id -> its uploaded documents, for every vehicle I own or drive. */
suspend fun Backend.vehicleDocs(): Map<String, List<VehicleDoc>> = mdb.from("vehicles").select().decodeList<VehicleDocsRow>().associate { it.id to parseVehicleDocs(it.docs) }
suspend fun Backend.setVehicleDocs(id: String, docs: List<VehicleDoc>) { mdb.from("vehicles").update({ set("docs", vehicleDocsJson(docs)) }) { filter { eq("id", id) } } }
suspend fun Backend.updateVehicleDetails(id: String, kind: String, model: String, plate: String, docs: List<VehicleDoc>) {
    mdb.from("vehicles").update({ set("kind", kind); set("model", model); set("plate", plate.uppercase().replace(" ", "")); set("docs", vehicleDocsJson(docs)) }) { filter { eq("id", id) } }
}
/** Removes files from a bucket (documents of a deleted vehicle). Row-level security still applies. */
suspend fun Backend.deleteFiles(bucket: String, paths: List<String>) { if (paths.isNotEmpty()) client.storage.from(bucket).delete(paths) }

fun parseVehicleDocs(arr: JsonArray): List<VehicleDoc> = arr.mapNotNull { e ->
    when (e) {
        is JsonObject -> e["path"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }?.let { VehicleDoc(e["kind"]?.jsonPrimitive?.content ?: "DOC", it) }
        is JsonPrimitive -> e.content.takeIf { it.isNotBlank() }?.let { VehicleDoc("DOC", it) }
        else -> null
    }
}
fun vehicleDocsJson(docs: List<VehicleDoc>): JsonArray = buildJsonArray { docs.forEach { add(buildJsonObject { put("kind", it.kind); put("path", it.path) }) } }
