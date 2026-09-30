package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import kotlinx.serialization.SerialName
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

// ---------- notifications ----------
/** My latest notifications, newest first. */
suspend fun Backend.notifications(limit: Int = 60): List<NotificationRow> =
    sdb.from("notifications").select { order("created_at", io.github.jan.supabase.postgrest.query.Order.DESCENDING); limit(limit.toLong()) }.decodeList()
/** Marks the given notifications (or every one when [ids] is null) read. */
suspend fun Backend.markNotificationsRead(ids: List<String>? = null) {
    sdb.rpc("mark_notifications_read", buildJsonObject { if (ids != null) put("p_ids", buildJsonArray { ids.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }) })
}
suspend fun Backend.deleteNotification(id: String) { sdb.from("notifications").delete { filter { eq("id", id) } } }

// ---------- my profile: posts, files, recommendations ----------
/** My own posts (photos, videos, text), newest first, for the profile's Feed and Media tabs. */
suspend fun Backend.myPosts(me: String, limit: Int = 60): List<PostRow> =
    sdb.from("posts").select { filter { eq("author_id", me); filter("deleted_at", FilterOperator.IS, "null") }; order("created_at", Order.DESCENDING); limit(limit.toLong()) }.decodeList()

/** Files and photos shared in my chats, sent or received, newest first (chat bucket paths are in attachment.path). */
suspend fun Backend.chatFiles(limit: Int = 60): List<MessageRow> =
    sdb.from("messages").select { filter { filterNot("attachment", FilterOperator.IS, "null"); filter("deleted_at", FilterOperator.IS, "null") }; order("created_at", Order.DESCENDING); limit(limit.toLong()) }.decodeList()

@Serializable data class RecGiven(@SerialName("listing_id") val listingId: String, @SerialName("created_at") val createdAt: String = "")

private suspend fun listingsById(ids: Collection<String>): Map<String, ListingRow> =
    if (ids.isEmpty()) emptyMap() else sdb.from("listings").select { filter { isIn("id", ids.toList()) } }.decodeList<ListingRow>().associateBy { it.id }

/** Listings I recommended in person (a recommender sees their own rows), with the listing when it is still visible to me. */
suspend fun Backend.recommendationsIGave(me: String): List<Pair<RecGiven, ListingRow?>> {
    val rows = sdb.from("recommendations").select { filter { eq("recommender_id", me) }; order("created_at", Order.DESCENDING) }.decodeList<RecGiven>()
    val by = listingsById(rows.map { it.listingId }); return rows.map { it to by[it.listingId] }
}

/** Reviews I wrote after orders and trips, with the listing they were for. */
suspend fun Backend.reviewsIWrote(me: String): List<Pair<ReviewRow, ListingRow?>> {
    val rows = sdb.from("reviews").select { filter { eq("author_id", me) }; order("created_at", Order.DESCENDING); limit(40) }.decodeList<ReviewRow>()
    val by = listingsById(rows.map { it.listingId }); return rows.map { it to by[it.listingId] }
}

// ---------- contact details I attach to people I'm synced with (private to me; contact_links.sql) ----------
@Serializable data class ContactLinkRow(@SerialName("profile_id") val profileId: String, val phones: List<String> = emptyList(), val emails: List<String> = emptyList(),
    val org: String = "", val title: String = "", val address: String = "", val note: String = "") {
    val isEmpty get() = phones.isEmpty() && emails.isEmpty() && org.isBlank() && title.isBlank() && address.isBlank() && note.isBlank()
}
private fun strings(l: List<String>) = buildJsonArray { l.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }
suspend fun Backend.contactLinks(): List<ContactLinkRow> = sdb.from("contact_links").select().decodeList()
suspend fun Backend.insertContactLink(me: String, l: ContactLinkRow) {
    sdb.from("contact_links").insert(buildJsonObject { put("owner_id", me); put("profile_id", l.profileId); put("phones", strings(l.phones)); put("emails", strings(l.emails)); put("org", l.org); put("title", l.title); put("address", l.address); put("note", l.note) })
}
/** Edits an existing link column by column (who it is about can't change, so an upsert of every column would be refused). */
suspend fun Backend.updateContactLink(l: ContactLinkRow) {
    sdb.from("contact_links").update({ set("phones", strings(l.phones)); set("emails", strings(l.emails)); set("org", l.org); set("title", l.title); set("address", l.address); set("note", l.note) }) { filter { eq("profile_id", l.profileId) } }
}
suspend fun Backend.deleteContactLink(profileId: String) { sdb.from("contact_links").delete { filter { eq("profile_id", profileId) } } }

/** One post by id (row-level security decides whether I may see it); null when it is gone or hidden from me. */
suspend fun Backend.postById(id: String): PostRow? = sdb.from("posts").select { filter { eq("id", id); filter("deleted_at", FilterOperator.IS, "null") } }.decodeSingleOrNull()

// ---------- store catalogue and product feedback (migration product_feedback.sql) ----------
/** A store's items without descriptions or extra photos, a fraction of the size, for the Products tab. */
suspend fun Backend.catalogItems(listingId: String): List<ItemRow> = sdb.rpc("catalog_items", buildJsonObject { put("p_listing", listingId) }).decodeList()
/** One full item (all photos, description), fetched when a product is opened. */
suspend fun Backend.itemById(id: String): ItemRow? = sdb.from("items").select { filter { eq("id", id) } }.decodeSingleOrNull()

/** How one product is rated: recommends and not-recommends, comments, and my own vote (1, -1 or null). Options of a product share one rating. */
@Serializable data class RatingSummary(@SerialName("product_key") val key: String, val up: Int = 0, val down: Int = 0, val comments: Int = 0, val mine: Int? = null) {
    val votes get() = up + down
    /** Share of people who recommend it, in percent; null while nobody has voted. */
    val percent: Int? get() = if (votes == 0) null else Math.round(up * 100.0 / votes).toInt()
}
@Serializable data class ProductComment(@SerialName("profile_id") val profileId: String, val name: String = "", val vote: Int = 1, val comment: String = "", @SerialName("updated_at") val updatedAt: String = "")

suspend fun Backend.productRatings(listingId: String): List<RatingSummary> = sdb.rpc("product_ratings_summary", buildJsonObject { put("p_listing", listingId) }).decodeList()
/** Recommend (1) or not recommend (-1) a product with an optional comment; a second call replaces the first. */
suspend fun Backend.rateProduct(listingId: String, key: String, vote: Int, comment: String) {
    sdb.rpc("rate_product", buildJsonObject { put("p_listing", listingId); put("p_key", key); put("p_vote", vote); put("p_comment", comment) })
}
suspend fun Backend.clearProductRating(listingId: String, key: String) { sdb.rpc("clear_product_rating", buildJsonObject { put("p_listing", listingId); put("p_key", key) }) }
suspend fun Backend.productComments(listingId: String, key: String, before: String? = null): List<ProductComment> =
    sdb.rpc("product_ratings_list", buildJsonObject { put("p_listing", listingId); put("p_key", key); before?.let { put("p_before", it) } }).decodeList()

// ---------- direct recommendations on any profile (migration ecommerce.sql: rate_listing) ----------
/** Recommend (1) or not recommend (-1) a shop, pro, asset or driver with an optional comment; it shows in Reviews. A second call replaces the first. */
suspend fun Backend.rateListing(listingId: String, vote: Int, comment: String) {
    sdb.rpc("rate_listing", buildJsonObject { put("p_listing", listingId); put("p_vote", vote); put("p_comment", comment) })
}
suspend fun Backend.clearListingRating(listingId: String) { sdb.rpc("clear_listing_rating", buildJsonObject { put("p_listing", listingId) }) }
/** My own direct recommendation of a listing (not an order or trip review), if I gave one. */
suspend fun Backend.myDirectReview(listingId: String, me: String): ReviewRow? =
    sdb.from("reviews").select { filter { eq("listing_id", listingId); eq("author_id", me); filter("task_id", FilterOperator.IS, "null"); filter("order_id", FilterOperator.IS, "null") } }.decodeSingleOrNull()
