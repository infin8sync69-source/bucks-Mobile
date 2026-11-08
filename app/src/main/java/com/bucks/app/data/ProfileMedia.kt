package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest

/**
 * Profile pictures and cover photos (profile_media.sql). A person's two pictures live in avatars/<profile id>/, a page's in
 * listing-media/<listing id>/; the database only accepts links into the owner's own folder. Replacing a picture removes the old file.
 */
object ProfileMedia {
    enum class Slot(val column: String, val prefix: String) { PHOTO("photo_url", "photo"), COVER("cover_url", "cover") }

    /** Uploads [picked] as my [slot] picture, saves the link on my profile and returns it. The previous file is removed afterwards. */
    suspend fun setMine(profileId: String, slot: Slot, picked: Picked, previous: String?): String {
        val path = "$profileId/${slot.prefix}-${picked.objectName()}"
        Backend.upload("avatars", path, picked.bytes)
        val url = Backend.publicUrl("avatars", path)
        try { Backend.client.postgrest.from("profiles").update({ set(slot.column, url) }) { filter { eq("id", profileId) } } }
        catch (e: Exception) { runCatching { Backend.deleteFiles("avatars", listOf(path)) }; throw e }
        removeOld("avatars", previous)
        return url
    }

    suspend fun clearMine(profileId: String, slot: Slot, previous: String?) {
        Backend.client.postgrest.from("profiles").update({ set<String?>(slot.column, null) }) { filter { eq("id", profileId) } }
        removeOld("avatars", previous)
    }

    /** A page's picture or cover: uploaded to listing-media/<listing id>/ (its owner and admins may write there). */
    suspend fun setListing(listingId: String, slot: Slot, picked: Picked, previous: String?): String {
        val path = "$listingId/${slot.prefix}-${picked.objectName()}"
        Backend.upload("listing-media", path, picked.bytes)
        val url = Backend.publicUrl("listing-media", path)
        try { if (slot == Slot.PHOTO) Backend.setListingPhoto(listingId, url) else Backend.setListingCover(listingId, url) }
        catch (e: Exception) { runCatching { Backend.deleteFiles("listing-media", listOf(path)) }; throw e }
        removeOld("listing-media", previous)
        return url
    }

    suspend fun clearListing(listingId: String, slot: Slot, previous: String?) {
        if (slot == Slot.PHOTO) Backend.setListingPhoto(listingId, null) else Backend.setListingCover(listingId, null)
        removeOld("listing-media", previous)
    }

    /** The object path inside [bucket] of one of our public URLs, or null for anything else (never deletes outside the bucket). */
    fun pathOf(bucket: String, url: String?): String? = url?.substringAfter("/storage/v1/object/public/$bucket/", "")?.takeIf { it.isNotBlank() && !it.contains("..") }

    private suspend fun removeOld(bucket: String, url: String?) { pathOf(bucket, url)?.let { runCatching { Backend.deleteFiles(bucket, listOf(it)) } } }
}
