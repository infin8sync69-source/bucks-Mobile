package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Backend calls for the Studio (the professional space): galleries, the recommendation threshold and the Bucks ID card.
 * Schema in supabase/migrations/studio.sql.
 */

@Serializable private data class SettingValue(val key: String, val value: Double)

private val sdb get() = Backend.client.postgrest

fun mediaJson(photos: List<MediaPhoto>): JsonArray = buildJsonArray { photos.forEach { p -> add(buildJsonObject { put("url", p.url); if (p.caption.isNotBlank()) put("caption", p.caption) }) } }

/** Replaces a listing's gallery (the server keeps only photos from the listing's own listing-media folder, at most 20). */
suspend fun Backend.setGallery(listingId: String, photos: List<MediaPhoto>) {
    sdb.from("listings").update({ set("gallery", mediaJson(photos)) }) { filter { eq("id", listingId) } }
}

/** Uploads a photo to listing-media/<listing id>/ and returns its public URL. */
suspend fun Backend.uploadListingMedia(listingId: String, photo: Picked): String {
    val path = "$listingId/${photo.objectName()}"; upload("listing-media", path, photo.bytes); return publicUrl("listing-media", path)
}

/** Removes files of listing-media by their public URLs (photos taken out of a gallery or a product). Failures are ignored by callers. */
suspend fun Backend.deleteListingMedia(urls: List<String>) {
    val paths = urls.mapNotNull { it.substringAfter("/object/public/listing-media/", "").ifBlank { null } }
    deleteFiles("listing-media", paths)
}

/** How many in-person recommendations take a listing live (settings.min_recommendations); null when it can't be read. */
suspend fun Backend.minRecommendations(): Int? =
    sdb.from("settings").select { filter { eq("key", "min_recommendations") } }.decodeList<SettingValue>().firstOrNull()?.value?.toInt()

/** Starts a new year on my Bucks ID card; the server allows it in the card's last 30 days or after it lapsed. Returns the new issue time. */
suspend fun Backend.renewBucksId(): String = sdb.rpc("renew_bucks_id").decodeAs()
