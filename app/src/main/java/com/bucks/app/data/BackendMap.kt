package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * The map's guardrails (supabase/migrations/map_guardrails.sql): whether my posts may show on the map, which of them do, and taking
 * one off. Pins show places, never people; minors' posts never show.
 */

@Serializable private data class MapConsentRow(val allowed: Boolean = false)

/** One of my posts that has a place on the map. [onMap]: showing now; [offBy]: AUTHOR, REPORT or STAFF when taken off. */
@Serializable data class MyMapPost(val id: String, val body: String = "", val place: String? = null, @SerialName("on_map") val onMap: Boolean = false,
    @SerialName("off_by") val offBy: String? = null, @SerialName("shows_from") val showsFrom: String? = null, @SerialName("created_at") val createdAt: String = "")

object MapBackend {
    private val db get() = Backend.client.postgrest
    /** Whether I said yes to "Show my posts on the map" (no row: no). */
    suspend fun consent(): Boolean = db.from("map_consent").select().decodeList<MapConsentRow>().firstOrNull()?.allowed ?: false
    suspend fun setConsent(allowed: Boolean) { db.rpc("set_map_consent", buildJsonObject { put("p_allowed", allowed) }) }
    suspend fun myPosts(): List<MyMapPost> = db.rpc("my_map_posts").decodeList()
    suspend fun setPostOnMap(postId: String, on: Boolean) { db.rpc("set_post_on_map", buildJsonObject { put("p_post", postId); put("p_on", on) }) }
    /** "This shows my home or me": off the map at once, and a report for staff. */
    suspend fun reportLocation(postId: String, detail: String) { db.rpc("report_map_location", buildJsonObject { put("p_post", postId); put("p_detail", detail) }) }
}

/** One thing my synced people recommend (social_lenses.sql: for_you). [kind]: POST, LISTING or PRODUCT; for a PRODUCT [id] is its
 *  product key and [listingId] its shop. [photoUrl] is a public URL for pages and products, a "posts" bucket path for posts. */
@Serializable data class ForYouItem(val kind: String, val id: String, @SerialName("listing_id") val listingId: String? = null, val title: String = "",
    val subtitle: String = "", @SerialName("photo_url") val photoUrl: String? = null, val recommenders: Int = 0, val latest: String = "",
    /** One of the synced people who recommend it (explore.sql: for_you_named); null from the older for_you. */
    @SerialName("recommender_name") val recommenderName: String? = null)

object ForYouBackend {
    suspend fun items(): List<ForYouItem> = Backend.client.postgrest.rpc("for_you").decodeList()
}

/**
 * The Explore tab (supabase/migrations/explore.sql). Posts I'm allowed to see from beyond my own feed: public ones, ones from people and
 * pages I sync with, and ones the people I'm synced with voted up, those first, with one of their names. On a database that doesn't
 * have explore() yet, both calls fall back to what was there before, so the tab still fills.
 */
object ExploreBackend {
    private val db get() = Backend.client.postgrest
    /** [kind]: ALL, VIDEO, IMAGE or FILE. [q]: words to look for in the post, its author or its page; blank for everything. */
    suspend fun posts(kind: String, q: String, here: LatLng, me: String?): List<FeedRow> =
        runCatching { db.rpc("explore", buildJsonObject { put("p_kind", kind); if (q.isNotBlank()) put("q", q.trim()) }).decodeList<FeedRow>() }
            .getOrElse { Backend.feed(here).filter { r -> r.authorId != me && (q.isBlank() || r.body.contains(q.trim(), true) || r.authorName.contains(q.trim(), true) || r.listingTitle?.contains(q.trim(), true) == true) } }
    /** Shops, pros and products the people I'm synced with recommend. */
    suspend fun places(): List<ForYouItem> =
        runCatching { db.rpc("for_you_named").decodeList<ForYouItem>() }.getOrElse { ForYouBackend.items() }.filter { it.kind != "POST" }
}
