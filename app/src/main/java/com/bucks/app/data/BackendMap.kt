package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
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
