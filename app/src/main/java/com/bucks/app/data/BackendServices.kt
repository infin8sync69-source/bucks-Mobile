package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Backend calls for service unlocking and listing documents (supabase/migrations/services.sql, docs/SERVICES_UNLOCK.md).
 */

/**
 * One service as seen from where the customer stands (services_near). [state]: SOON (switched off), LOCKED (not enough
 * checked providers within [radiusM]), QUIET (unlocked, too few online right now), OPEN.
 */
@Serializable data class ServiceState(
    val key: String, val label: String, val mode: String = "AUTO", val state: String = "LOCKED",
    val supply: Int = 0, @SerialName("min_supply") val minSupply: Int = 0, val online: Int = 0, @SerialName("min_online") val minOnline: Int = 0,
    @SerialName("supply_noun") val supplyNoun: String = "", @SerialName("radius_m") val radiusM: Int = 0,
    val delivery: Boolean = false, @SerialName("delivery_now") val deliveryNow: Boolean = false, val interested: Int = 0, val mine: Boolean = false,
) {
    val usable get() = state == "OPEN" || state == "QUIET"
    val radiusKm get() = if (radiusM % 1000 == 0) "${radiusM / 1000} km" else "%.1f km".format(radiusM / 1000.0)
}

/** A document the listing's service asks for and where it stands (listing_compliance). status: MISSING, PENDING, VERIFIED, REJECTED, EXPIRED. */
@Serializable data class ComplianceRow(
    @SerialName("doc_type") val docType: String, val label: String, val hint: String = "", val required: Boolean = false,
    @SerialName("public_number") val publicNumber: Boolean = false, @SerialName("asks_number") val asksNumber: Boolean = true,
    @SerialName("has_expiry") val hasExpiry: Boolean = false, val status: String = "MISSING", val number: String = "",
    @SerialName("expires_on") val expiresOn: String? = null, val note: String = "", val path: String? = null,
)

/** A verified, in-date document shown on a public profile (listing_badges); [number] is blank unless the law wants it shown. */
@Serializable data class BadgeRow(@SerialName("doc_type") val docType: String, val label: String, val number: String = "", @SerialName("expires_on") val expiresOn: String? = null)

/** A document waiting for Bucks staff (documents_to_review). */
@Serializable data class ReviewItem(
    val id: String, @SerialName("listing_id") val listingId: String, @SerialName("listing_title") val listingTitle: String = "", val service: String? = null,
    @SerialName("doc_type") val docType: String, val label: String = "", val number: String = "", @SerialName("expires_on") val expiresOn: String? = null,
    val path: String, @SerialName("uploaded_by") val uploadedBy: String, @SerialName("created_at") val createdAt: String = "",
)

private val sdb get() = Backend.client.postgrest

suspend fun Backend.servicesNear(at: LatLng): List<ServiceState> =
    sdb.rpc("services_near", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList()
/** True when I am now on the "notify me" list for [key], false when I just left it. */
suspend fun Backend.toggleServiceInterest(key: String, at: LatLng): Boolean =
    sdb.rpc("toggle_service_interest", buildJsonObject { put("p_service", key); put("lat", at.lat); put("lng", at.lng) }).data.trim() == "true"
suspend fun Backend.listingCompliance(listingId: String): List<ComplianceRow> = sdb.rpc("listing_compliance", buildJsonObject { put("p_listing", listingId) }).decodeList()
suspend fun Backend.listingBadges(listingId: String): List<BadgeRow> = sdb.rpc("listing_badges", buildJsonObject { put("p_listing", listingId) }).decodeList()
/** [expires]: yyyy-MM-dd or null. The file must already be uploaded to docs/<my id>/. */
suspend fun Backend.submitDocument(listingId: String, type: String, path: String, number: String, expires: String?) {
    sdb.rpc("submit_document", buildJsonObject { put("p_listing", listingId); put("p_type", type); put("p_path", path); put("p_number", number); put("p_expires", expires) })
}
suspend fun Backend.deleteDocument(listingId: String, type: String) { sdb.rpc("delete_document", buildJsonObject { put("p_listing", listingId); put("p_type", type) }) }
suspend fun Backend.isStaff(): Boolean = sdb.rpc("is_staff").data.trim() == "true"
suspend fun Backend.documentsToReview(): List<ReviewItem> = sdb.rpc("documents_to_review").decodeList()
/** Returns the listing's status afterwards (a verified document may take it LIVE). */
suspend fun Backend.reviewDocument(id: String, approve: Boolean, note: String) {
    sdb.rpc("review_document", buildJsonObject { put("p_doc", id); put("p_approve", approve); put("p_note", note) })
}
/** Deleting an account: every file in my private docs folder (listing and vehicle documents). */
suspend fun Backend.deleteMyDocFiles(me: String) {
    val bucket = client.storage.from("docs")
    val names = bucket.list(me).map { "$me/${it.name}" }
    if (names.isNotEmpty()) bucket.delete(names)
}
