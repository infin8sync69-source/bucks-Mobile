package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.bucks.app.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/**
 * Everything an owner does with their own listings: businesses, skills and the driver profile,
 * their products and services, vehicles with documents, admins and store riders, and the
 * recommendation QR that takes a listing live. Same shape as [Social]: Compose state plus
 * actions wrapped in go { }, so every failure reaches the person as a toast.
 */
class MyListings(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    companion object {
        /** Local recommendations a listing needs before it goes live: settings.min_recommendations, read on every refresh (7 until then). */
        var NEEDED by mutableIntStateOf(7)
    }

    val me: ProfileRow? get() = social.me

    /** Listings I own or help run. */
    var listings by mutableStateOf<List<ListingRow>>(emptyList()); private set
    /** listing id -> my role in it: OWNER, ADMIN or STORE_RIDER. */
    var roles by mutableStateOf<Map<String, String>>(emptyMap()); private set
    /** Vehicles I own or drive. */
    var vehicles by mutableStateOf<List<VehicleRow>>(emptyList()); private set
    var vehicleDocs by mutableStateOf<Map<String, List<VehicleDoc>>>(emptyMap()); private set
    /** listing id -> its products or services, loaded per listing. */
    val items: SnapshotStateMap<String, List<ItemRow>> = mutableStateMapOf()
    val members: SnapshotStateMap<String, List<MemberRow>> = mutableStateMapOf()
    val vehicleMembers: SnapshotStateMap<String, List<VehicleMemberRow>> = mutableStateMapOf()
    /** listing id -> how many people nearby have recommended it. */
    val recommendations: SnapshotStateMap<String, Int> = mutableStateMapOf()
    /** listing id -> its own posts (the listing's feed), newest first. */
    val posts: SnapshotStateMap<String, List<PostRow>> = mutableStateMapOf()
    /** listing id -> customer reviews, newest first. */
    val reviews: SnapshotStateMap<String, List<ReviewRow>> = mutableStateMapOf()
    /** listing id -> recommendations, syncs, team size and open jobs. */
    val counts: SnapshotStateMap<String, ListingCounts> = mutableStateMapOf()
    /** Invites waiting for my answer. */
    var invites by mutableStateOf<List<InviteForMe>>(emptyList()); private set
    /** Invites I sent that are still pending. */
    var sentInvites by mutableStateOf<List<InviteRow>>(emptyList()); private set
    var stats by mutableStateOf<List<VehicleStat>>(emptyList()); private set
    /** The current recommendation token while the QR screen is open. */
    var token by mutableStateOf<String?>(null); private set
    var loading by mutableStateOf(false); private set
    /** True once a refresh succeeded (empty states only show after that). A failed refresh leaves it false and sets [error]. */
    var loaded by mutableStateOf(false); private set
    /** Why the last refresh failed (no network, expired session); the hub shows it with a Retry instead of an empty state. */
    var error by mutableStateOf<String?>(null); private set
    /** True while a photo or document is uploading or a save is in flight. */
    var busy by mutableStateOf(false); private set
    val pendingCount: Int get() = invites.size

    fun listing(id: String) = listings.firstOrNull { it.id == id }
    fun vehicle(id: String) = vehicles.firstOrNull { it.id == id }
    fun roleIn(listingId: String): String? = roles[listingId] ?: listing(listingId)?.takeIf { it.ownerId == me?.id }?.let { "OWNER" }
    fun isOwner(listingId: String) = roleIn(listingId) == "OWNER"
    fun canManage(listingId: String) = roleIn(listingId) == "OWNER" || roleIn(listingId) == "ADMIN"
    fun ownsVehicle(vehicleId: String) = vehicle(vehicleId)?.ownerId == me?.id
    fun driverProfile(): ListingRow? = listings.firstOrNull { it.kind == "DRIVER" && it.ownerId == me?.id }

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        // The JSON body escapes quotes (Postgres puts table names in quotes), so the match must step over \" and unescape it.
        val quoted = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(m)?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\\\", "\\")
        return quoted?.takeIf { it.isNotBlank() } ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }

    /** Sign-out and account deletion: the next account on this phone starts with nothing of mine. */
    fun signedOut() {
        listings = emptyList(); roles = emptyMap(); vehicles = emptyList(); vehicleDocs = emptyMap()
        items.clear(); members.clear(); vehicleMembers.clear(); recommendations.clear(); posts.clear(); reviews.clear(); counts.clear()
        invites = emptyList(); sentInvites = emptyList(); stats = emptyList(); token = null
        loading = false; loaded = false; error = null; busy = false
    }

    // ---------- loading ----------
    /** Loads everything I run. Vehicles and their documents come from one read and land together, so the edit form never sees a vehicle without its documents. */
    fun refresh() = go { val p = me ?: return@go; loading = true
        try {
            val ls = Backend.myListings(p.id).sortedBy { it.title.lowercase() }
            val rs = Backend.myRoles(p.id)
            val (vs, docs) = Backend.myVehiclesWithDocs()
            runCatching { Backend.minRecommendations() }.getOrNull()?.let { if (it > 0) NEEDED = it }
            if (me?.id != p.id) return@go   // signed out (or someone else signed in) while this was loading
            listings = ls; roles = rs
            vehicleDocs = docs; vehicles = vs.sortedBy { it.model.lowercase() }
            loadRecommendations(); loadInvites()
            error = null; loaded = true
        } catch (e: Exception) { error = friendly(e); throw e }
        finally { loading = false } }
    private suspend fun loadRecommendations() {
        val pending = listings.filter { it.status == "PENDING" }.map { it.id }
        val counts = Backend.recommendationCounts(pending)
        pending.forEach { recommendations[it] = counts[it] ?: 0 }
    }
    private suspend fun loadInvites() { val p = me ?: return
        val raw = Backend.myInvites()
        sentInvites = raw.filter { it.inviterId == p.id }
        social.namesFor(sentInvites.map { it.inviteeId })
        // my_invites() adds names the invitee could not read otherwise; without it (migration not applied yet) fall back to bare rows.
        invites = runCatching { Backend.invitesForMe() }.getOrElse {
            val mine = raw.filter { it.inviteeId == p.id }; social.namesFor(mine.map { it.inviterId })
            mine.map { i -> InviteForMe(i.id, i.listingId, i.vehicleId, i.inviterId, social.nameOf(i.inviterId), i.role, if (i.listingId != null) "A listing" else "A vehicle", if (i.listingId != null) "LISTING" else "VEHICLE") }
        }
    }
    fun refreshInvites() = go { loadInvites() }
    fun refreshStats() = go { stats = Backend.vehicleStats().sortedBy { it.plate } }
    fun loadItems(listingId: String) = go { items[listingId] = Backend.items(listingId) }
    fun loadMembers(listingId: String) = go { val rows = Backend.members(listingId); social.namesFor(rows.map { it.profileId }); members[listingId] = rows }
    fun loadVehicleMembers(vehicleId: String) = go { val rows = Backend.vehicleMembers(vehicleId); social.namesFor(rows.map { it.profileId }); vehicleMembers[vehicleId] = rows }
    fun loadAllVehicleMembers() = go { vehicles.forEach { v -> vehicleMembers[v.id] = Backend.vehicleMembers(v.id) }; social.namesFor(vehicleMembers.values.flatten().map { it.profileId }) }

    // ---------- listings ----------
    private suspend fun uploadListingPhoto(listingId: String, photo: Picked): String {
        val path = "$listingId/${photo.objectName()}"; Backend.upload("listing-media", path, photo.bytes); return Backend.publicUrl("listing-media", path)
    }
    private fun savedMessage(kind: String, title: String) = when (kind) {
        "BUSINESS" -> "$title is saved. It goes live once $NEEDED people nearby recommend it."
        "SKILL" -> "$title is saved. It goes live once $NEEDED people nearby recommend you."
        "ASSET" -> "$title is saved. It goes live once $NEEDED people nearby vouch for it and Bucks checks any documents it needs."
        else -> "Your driver profile is saved. It goes live once $NEEDED people nearby recommend you."
    }
    /**
     * Creates a listing at [at], a real location fix (the form only offers Save once it has one; the map's default centre
     * would place the shop in Jayanagar and nobody at the real shop could recommend it). The photo, if any, goes to
     * listing-media/<listing id>/ afterwards; the listing exists by then, so a failed upload is reported, not retried
     * through the form, or Save again would create a second listing.
     */
    fun createListing(kind: String, title: String, category: String, description: String, area: String, at: LatLng, details: JsonObject, photo: Picked?, service: String? = null, onDone: (ListingRow) -> Unit) = go {
        val p = me ?: return@go; busy = true
        try {
            var row = Backend.createListing(p.id, kind, title, category, description, area, at, details, service)
            var photoFailed = false
            if (photo != null) try { val url = uploadListingPhoto(row.id, photo); Backend.setListingPhoto(row.id, url); row = row.copy(photoUrl = url) } catch (e: Exception) { photoFailed = true }
            toast(if (photoFailed) "${if (kind == "DRIVER") "Your driver profile" else title} is saved, but the photo didn't upload. Add it from Edit." else savedMessage(kind, title))
            refresh(); onDone(row)
        } finally { busy = false } }
    /** [at] null keeps the saved location. */
    fun updateListing(id: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JsonObject, photo: Picked?, service: String? = null, onDone: () -> Unit) = go { busy = true
        try {
            Backend.updateListing(id, title, category, description, area, at, details, service)
            if (photo != null) Backend.setListingPhoto(id, uploadListingPhoto(id, photo))
            toast("Saved."); refresh(); onDone()
        } finally { busy = false } }
    /** delete_listing() keeps a hidden row behind past orders and refuses while an order is open; either way the listing leaves my hub. */
    fun deleteListing(id: String, onDone: () -> Unit) = go { val l = listing(id); Backend.removeListing(id); listings = listings.filterNot { it.id == id }; toast("${l?.title ?: "Listing"} deleted."); onDone() }
    fun setOnline(id: String, on: Boolean) = go { val l = listing(id) ?: return@go
        listings = listings.map { if (it.id == id) it.copy(online = on) else it }
        try { Backend.setOnline(id, on) } catch (e: Exception) { listings = listings.map { if (it.id == id) it.copy(online = !on) else it }; throw e }
        toast(when (l.kind) {
            "BUSINESS" -> if (on) "${l.title} is open. Orders will reach you." else "${l.title} is closed. No orders until you open again."
            "SKILL" -> if (on) "${l.title} is online. Requests will reach you." else "${l.title} is offline."
            "ASSET" -> if (on) "${l.title} is shown as available." else "${l.title} is marked not available. It stays on your profile."
            else -> if (on) "You're shown as available." else "You're shown as unavailable." }) }

    // ---------- products and services ----------
    /**
     * Saves a product or service with its photos: [keep] are photos it already had (in order), [add] new ones to upload.
     * The first photo becomes photo_url, which search and older app versions show. Photos taken out are deleted afterwards.
     */
    fun saveItem(item: ItemRow, keep: List<MediaPhoto>, add: List<Picked>, onDone: () -> Unit) = go { busy = true
        try {
            val uploaded = add.map { MediaPhoto(Backend.uploadListingMedia(item.listingId, it)) }
            val photos = (keep + uploaded).take(8)
            val row = item.copy(photos = photos, photoUrl = photos.firstOrNull()?.url)
            // Photos taken out are deleted, unless a copy of this item (Duplicate) still shows them.
            val usedElsewhere = items[item.listingId].orEmpty().filter { it.id != item.id }.flatMap { it.photos.map { p -> p.url } }.toSet()
            val dropped = item.photos.map { it.url }.filter { u -> photos.none { it.url == u } && u !in usedElsewhere }
            // Existing items go column by column (updateItem): a whole-row update drops default values, so "back in stock" or a cleared MRP would never reach the server.
            val saved = if (row.id == null) Backend.saveItem(row) else Backend.updateItem(row)
            items[item.listingId] = (items[item.listingId].orEmpty().filterNot { it.id == saved.id } + saved).sortedWith(compareBy({ it.sort }, { it.name.lowercase() }))
            toast(if (item.id == null) "${saved.name} added." else "Saved."); onDone()
            if (dropped.isNotEmpty()) runCatching { Backend.deleteListingMedia(dropped) }
        } finally { busy = false } }
    /** A copy of [item] named "<name> (copy)", out of stock until the owner checks it, with the same photos. */
    fun duplicateItem(item: ItemRow) = go {
        val copy = item.copy(id = null, name = "${item.name} (copy)".take(80), inStock = false, sort = items[item.listingId].orEmpty().size)
        val saved = Backend.saveItem(copy)
        items[item.listingId] = items[item.listingId].orEmpty() + saved; toast("Copied. Edit it and switch it on when it's ready.") }
    fun setInStock(item: ItemRow, on: Boolean) = go { val id = item.id ?: return@go
        items[item.listingId] = items[item.listingId].orEmpty().map { if (it.id == id) it.copy(inStock = on) else it }
        try { Backend.updateItem(item.copy(inStock = on)) } catch (e: Exception) { items[item.listingId] = items[item.listingId].orEmpty().map { if (it.id == id) it.copy(inStock = !on) else it }; throw e } }
    fun deleteItem(item: ItemRow, onDone: () -> Unit) = go { val id = item.id ?: return@go; Backend.deleteItem(id); items[item.listingId] = items[item.listingId].orEmpty().filterNot { it.id == id }; toast("${item.name} removed."); onDone()
        // Photos shared with a copy of this item stay; only files no other item uses are deleted.
        val stillUsed = items[item.listingId].orEmpty().flatMap { it.photos.map { p -> p.url } }.toSet()
        item.photos.map { it.url }.filter { it !in stillUsed }.takeIf { it.isNotEmpty() }?.let { runCatching { Backend.deleteListingMedia(it) } } }

    // ---------- gallery (photos, portfolio) ----------
    private fun galleryOf(listingId: String) = listing(listingId)?.gallery.orEmpty()
    private suspend fun saveGallery(listingId: String, g: List<MediaPhoto>) {
        Backend.setGallery(listingId, g); listings = listings.map { if (it.id == listingId) it.copy(gallery = g) else it }
    }
    /** Uploads [photos] and adds them to the end of the gallery (20 at most). The first photo of an empty listing also becomes its cover. */
    fun addGalleryPhotos(listingId: String, photos: List<Picked>) = go { busy = true
        try {
            val room = 20 - galleryOf(listingId).size
            if (room <= 0) { toast("The gallery holds 20 photos. Remove one to add another."); return@go }
            val added = photos.take(room).map { MediaPhoto(Backend.uploadListingMedia(listingId, it)) }
            saveGallery(listingId, galleryOf(listingId) + added)
            if (listing(listingId)?.photoUrl.isNullOrBlank()) added.firstOrNull()?.let { setCoverNow(listingId, it.url) }
            toast(if (photos.size > room) "Added $room. The gallery holds 20 photos." else if (added.size == 1) "Photo added." else "${added.size} photos added.")
        } finally { busy = false } }
    fun removeGalleryPhoto(listingId: String, url: String) = go {
        saveGallery(listingId, galleryOf(listingId).filterNot { it.url == url })
        if (listing(listingId)?.photoUrl != url) runCatching { Backend.deleteListingMedia(listOf(url)) }
        toast("Photo removed.") }
    fun setCaption(listingId: String, url: String, caption: String) = go {
        saveGallery(listingId, galleryOf(listingId).map { if (it.url == url) it.copy(caption = caption.trim().take(200)) else it }); toast("Caption saved.") }
    /** Moves a photo one place towards the start (-1) or the end (+1). */
    fun moveGalleryPhoto(listingId: String, url: String, by: Int) = go {
        val g = galleryOf(listingId).toMutableList(); val i = g.indexOfFirst { it.url == url }; val j = i + by
        if (i < 0 || j !in g.indices) return@go
        g.add(j, g.removeAt(i)); saveGallery(listingId, g) }
    private suspend fun setCoverNow(listingId: String, url: String) { Backend.setListingPhoto(listingId, url); listings = listings.map { if (it.id == listingId) it.copy(photoUrl = url) else it } }
    fun setCover(listingId: String, url: String) = go { setCoverNow(listingId, url); toast("Cover photo changed.") }

    // ---------- the listing's feed, reviews and numbers ----------
    fun loadPosts(listingId: String) = go { val rows = Backend.listingPosts(listingId); social.namesFor(rows.map { it.authorId }); posts[listingId] = rows }
    /** Posts as the listing: shown on its profile and, to people nearby and those synced with it, in the feed. */
    fun postAs(listingId: String, body: String, photo: Picked?, onDone: () -> Unit) = go { val p = me ?: return@go; val l = listing(listingId) ?: return@go; busy = true
        try {
            val media = photo?.let { f -> listOf("${p.id}/${f.objectName()}".also { Backend.upload("posts", it, f.bytes) }) }.orEmpty()
            val at = runCatching { Backend.listingPoint(listingId) }.getOrNull() ?: social.here
            Backend.post(p.id, body.trim(), media, "LOCAL", at, l.area, listingId)
            toast("Posted as ${l.title}."); onDone(); posts[listingId] = Backend.listingPosts(listingId)
        } finally { busy = false } }
    fun deletePost(post: PostRow) = go { Backend.deletePost(post.id); post.listingId?.let { lid -> posts[lid] = posts[lid].orEmpty().filterNot { it.id == post.id } }; toast("Post deleted.") }
    fun loadReviews(listingId: String) = go { val rows = Backend.reviews(listingId); social.namesFor(rows.map { it.authorId }); reviews[listingId] = rows }
    fun loadCounts(listingId: String) = go { Backend.listingCounts(listingId)?.let { counts[listingId] = it; recommendations[listingId] = it.recommendations } }

    // ---------- vehicles ----------
    private suspend fun uploadDocs(meId: String, docs: List<Pair<String, Picked>>): List<VehicleDoc> =
        docs.map { (kind, f) -> val path = "$meId/vehicle-${kind.lowercase()}-${f.objectName()}"; Backend.upload("docs", path, f.bytes); VehicleDoc(kind, path) }
    /**
     * [docs]: document kind (RC, INSURANCE, PERMIT) to the picked file; they go to docs/<my id>/. The vehicle row exists once
     * addVehicle returns (the plate is unique, so Save again could not create it twice), so documents that fail to upload
     * are reported and the ones that did upload are kept; the owner adds the rest from Edit.
     */
    fun addVehicle(kind: String, model: String, plate: String, docs: List<Pair<String, Picked>>, onDone: () -> Unit) = go { val p = me ?: return@go; busy = true
        try {
            val v = Backend.addVehicle(p.id, kind, model, plate)
            val uploaded = ArrayList<VehicleDoc>(); var failed = 0
            for ((docKind, f) in docs) try { uploaded += uploadDocs(p.id, listOf(docKind to f)) } catch (e: Exception) { failed++ }
            if (uploaded.isNotEmpty()) try { Backend.setVehicleDocs(v.id, uploaded); vehicleDocs = vehicleDocs + (v.id to uploaded.toList()) } catch (e: Exception) { failed += uploaded.size }
            val name = "${v.model.ifBlank { v.kind }} (${v.plate})"
            toast(if (failed > 0) "$name added, but $failed document${if (failed > 1) "s" else ""} didn't upload. Add them from Edit." else "$name added. Bucks checks the documents before it can go online.")
            refresh(); onDone()
        } finally { busy = false } }
    /**
     * Keeps [keep], uploads [add], and removes the files of [before] (the documents the form was opened with) that are no
     * longer referenced. [before] comes from the form, not from the cache, so a refresh in the meantime cannot make it delete
     * documents the owner never removed.
     */
    fun updateVehicle(id: String, kind: String, model: String, plate: String, before: List<VehicleDoc>, keep: List<VehicleDoc>, add: List<Pair<String, Picked>>, onDone: () -> Unit) = go { val p = me ?: return@go; busy = true
        try {
            val all = keep + uploadDocs(p.id, add)
            Backend.updateVehicleDetails(id, kind, model, plate, all)
            val gone = before.map { it.path }.filter { path -> all.none { it.path == path } }
            if (gone.isNotEmpty()) runCatching { Backend.deleteFiles("docs", gone) }
            toast("Saved."); refresh(); onDone()
        } finally { busy = false } }
    fun deleteVehicle(id: String, onDone: () -> Unit) = go {
        val paths = vehicleDocs[id].orEmpty().map { it.path }
        Backend.deleteVehicle(id); runCatching { Backend.deleteFiles("docs", paths) }
        vehicles = vehicles.filterNot { it.id == id }; toast("Vehicle removed."); onDone() }

    // ---------- admins, store riders and drivers ----------
    fun invite(listingId: String?, vehicleId: String?, bucksId: String, role: String) = go {
        Backend.invite(listingId, vehicleId, bucksId, role); toast("Invite sent to ${bucksId.trim().uppercase()}. They'll see it under Invites."); loadInvites() }
    fun revokeInvite(id: String) = go { Backend.revokeInvite(id); sentInvites = sentInvites.filterNot { it.id == id }; toast("Invite cancelled.") }
    fun respondInvite(inv: InviteForMe, accept: Boolean) = go {
        Backend.respondInvite(inv.id, accept); invites = invites.filterNot { it.id == inv.id }
        toast(if (accept) "Done. ${inv.title} is now under My listings." else "Declined."); if (accept) refresh() }
    fun removeMember(listingId: String, profileId: String) = go {
        Backend.removeMember(listingId, profileId); members[listingId] = members[listingId].orEmpty().filterNot { it.profileId == profileId }
        if (profileId == me?.id) { toast("You left."); refresh() } else toast("Removed.") }
    fun removeVehicleMember(vehicleId: String, profileId: String) = go {
        Backend.removeVehicleMember(vehicleId, profileId); vehicleMembers[vehicleId] = vehicleMembers[vehicleId].orEmpty().filterNot { it.profileId == profileId }
        if (profileId == me?.id) { toast("You left."); refresh() } else toast("Removed.") }

    // ---------- community cap: recommendations ----------
    /** A fresh token (valid 2 minutes) and the current count; the QR screen calls this every 90 seconds. */
    fun refreshToken(listingId: String) = go { token = Backend.recommendToken(listingId); recommendations[listingId] = Backend.recommendationCounts(listOf(listingId))[listingId] ?: 0
        if ((recommendations[listingId] ?: 0) >= NEEDED && listing(listingId)?.status == "PENDING") refresh() }
    fun clearToken() { token = null }
    /**
     * Scanned someone's code in person at [at], a real location fix: the server checks distance, account age and position,
     * and returns the new count. The scanner only opens with a fix; the map's default centre must never be sent, or a photo
     * of the code would count as "in person" for every listing within 3 km of it.
     */
    fun recommend(token: String, at: LatLng, onDone: (Int) -> Unit) = go {
        val n = Backend.recommend(token, at)
        toast(if (n >= NEEDED) "Thanks, that's $n of $NEEDED. They're live on Bucks now." else "Thanks, that's $n of $NEEDED."); onDone(n) }
}
