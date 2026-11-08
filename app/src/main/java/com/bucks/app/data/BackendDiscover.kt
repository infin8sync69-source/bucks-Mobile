package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Discover: what Backend.kt lacks for the universal listing profile and cloud search.
 * Sync with a listing (listing_syncs), the public counts a profile shows, a listing's coordinates
 * (through the listing_points view in supabase/migrations/discover.sql) and photo URLs.
 */

/** One row of listing_syncs: [profileId] follows [listingId] (its posts show in their feed). */
@Serializable data class ListingSyncRow(@SerialName("profile_id") val profileId: String, @SerialName("listing_id") val listingId: String)
/** A listing's coordinates as plain numbers (the listing_points view; PostGIS itself comes back as EWKB hex). */
@Serializable data class ListingPoint(val id: String, val lat: Double, val lng: Double)
/** The public numbers on a listing profile, from listing_counts() in supabase/migrations/discover.sql. */
@Serializable data class ListingCounts(val recommendations: Int = 0, val syncs: Int = 0, val members: Int = 0, @SerialName("open_jobs") val openJobs: Int = 0)
@Serializable internal data class RecommenderRow(@SerialName("recommender_id") val recommenderId: String)

// ---------- sync with a listing ----------
/** Listings I follow. */
suspend fun Backend.myListingSyncs(me: String): List<ListingSyncRow> =
    client.postgrest.from("listing_syncs").select { filter { eq("profile_id", me) } }.decodeList()
suspend fun Backend.syncListing(me: String, listingId: String) {
    client.postgrest.from("listing_syncs").insert(buildJsonObject { put("profile_id", me); put("listing_id", listingId) })
}
suspend fun Backend.unsyncListing(me: String, listingId: String) {
    client.postgrest.from("listing_syncs").delete { filter { eq("profile_id", me); eq("listing_id", listingId) } }
}
/** How many people follow a listing (rows are readable by everyone). */
suspend fun Backend.listingSyncCount(listingId: String): Int =
    client.postgrest.from("listing_syncs").select { filter { eq("listing_id", listingId) } }.decodeList<ListingSyncRow>().size

// ---------- public counts ----------
/** How many neighbours recommended a listing in person (recommendations are readable by everyone). */
suspend fun Backend.recommendationCount(listingId: String): Int =
    client.postgrest.from("recommendations").select(Columns.list("recommender_id")) { filter { eq("listing_id", listingId) } }.decodeList<RecommenderRow>().size
/** All four numbers in one call; null when the listing is not visible to me (pending and not mine). */
suspend fun Backend.listingCounts(listingId: String): ListingCounts? =
    client.postgrest.rpc("listing_counts", buildJsonObject { put("p_listing", listingId) }).decodeList<ListingCounts>().firstOrNull()

// ---------- who runs a listing ----------
/** The owner, admins and riders of a listing for its public Team tab (listing_members is readable by everyone; Backend.members is the owner's copy). */
suspend fun Backend.publicMembers(listingId: String): List<MemberRow> =
    client.postgrest.from("listing_members").select { filter { eq("listing_id", listingId) } }.decodeList()

// ---------- where a listing is ----------
suspend fun Backend.listingPoint(listingId: String): LatLng? =
    client.postgrest.from("listing_points").select { filter { eq("id", listingId) } }.decodeSingleOrNull<ListingPoint>()?.let { LatLng(it.lat, it.lng) }

// ---------- photos ----------
/** A listing or product photo: photo_url is either a full URL or a path inside the public listing-media bucket. */
fun Backend.listingPhoto(photoUrl: String?): String? =
    photoUrl?.trim()?.takeIf { it.isNotBlank() }?.let { if (it.startsWith("http://") || it.startsWith("https://")) it else publicUrl("listing-media", it) }

/** The human behind a page (server function listing_owner): who they are, how long they have been on Bucks, and how far their identity has been checked. */
@Serializable data class OwnerRow(val id: String, val name: String = "Bucks member", @SerialName("short_code") val shortCode: String = "", @SerialName("photo_url") val photoUrl: String? = null,
    val area: String = "", @SerialName("member_since") val memberSince: String = "",
    /** Bucks staff have checked a photo ID of this person on one of their pages. Phone verification is implicit: every account signs in by OTP. */
    @SerialName("id_checked") val idChecked: Boolean = false, val pages: Int = 0) {
    /** The identity level shown next to the name. Face / biometric checks are a later level on this same line. */
    val identityLabel get() = if (idChecked) "ID checked by Bucks" else "Phone-verified"
}
suspend fun Backend.listingOwner(listingId: String): OwnerRow? = client.postgrest.rpc("listing_owner", buildJsonObject { put("p_listing", listingId) }).decodeList<OwnerRow>().firstOrNull()
/** The other live pages this person runs, for the owner sheet. */
suspend fun Backend.livePagesOf(ownerId: String): List<ListingRow> = client.postgrest.from("listings").select { filter { eq("owner_id", ownerId); eq("status", "LIVE") } }.decodeList()
