package com.bucks.app.ui

import androidx.compose.runtime.getValue
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
    companion object { /** Local recommendations a listing needs before it goes live (settings.min_recommendations). */ const val NEEDED = 7 }

    val me: ProfileRow? get() = social.me
    val here: LatLng get() = social.here

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
    /** listing id -> how many neighbours have recommended it. */
    val recommendations: SnapshotStateMap<String, Int> = mutableStateMapOf()
    /** Invites waiting for my answer. */
    var invites by mutableStateOf<List<InviteForMe>>(emptyList()); private set
    /** Invites I sent that are still pending. */
    var sentInvites by mutableStateOf<List<InviteRow>>(emptyList()); private set
    var stats by mutableStateOf<List<VehicleStat>>(emptyList()); private set
    /** The current recommendation token while the QR screen is open. */
    var token by mutableStateOf<String?>(null); private set
    var loading by mutableStateOf(false); private set
    /** True once the first refresh finished (empty states only show after that). */
    var loaded by mutableStateOf(false); private set
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
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }

    // ---------- loading ----------
    fun refresh() = go { val p = me ?: return@go; loading = true
        try {
            listings = Backend.myListings(p.id).sortedBy { it.title.lowercase() }
            roles = Backend.myRoles(p.id)
            vehicles = Backend.myVehicles().sortedBy { it.model.lowercase() }
            vehicleDocs = runCatching { Backend.vehicleDocs() }.getOrDefault(emptyMap())
            loadRecommendations(); loadInvites()
        } finally { loading = false; loaded = true } }
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
        "BUSINESS" -> "$title is saved. It goes live once $NEEDED neighbours recommend it."
        "SKILL" -> "$title is saved. It goes live once $NEEDED neighbours recommend you."
        else -> "Your driver profile is saved. It goes live once $NEEDED neighbours recommend you."
    }
    /** Creates a listing at my current position; the photo, if any, goes to listing-media/<listing id>/. */
    fun createListing(kind: String, title: String, category: String, description: String, area: String, details: JsonObject, photo: Picked?, onDone: (ListingRow) -> Unit) = go {
        val p = me ?: return@go; busy = true
        try {
            var row = Backend.createListing(p.id, kind, title, category, description, area, here, details)
            if (photo != null) { val url = uploadListingPhoto(row.id, photo); Backend.setListingPhoto(row.id, url); row = row.copy(photoUrl = url) }
            toast(savedMessage(kind, title)); refresh(); onDone(row)
        } finally { busy = false } }
    /** [at] null keeps the saved location. */
    fun updateListing(id: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JsonObject, photo: Picked?, onDone: () -> Unit) = go { busy = true
        try {
            Backend.updateListing(id, title, category, description, area, at, details)
            if (photo != null) Backend.setListingPhoto(id, uploadListingPhoto(id, photo))
            toast("Saved."); refresh(); onDone()
        } finally { busy = false } }
    fun deleteListing(id: String, onDone: () -> Unit) = go { val l = listing(id); Backend.deleteListing(id); listings = listings.filterNot { it.id == id }; toast("${l?.title ?: "Listing"} deleted."); onDone() }
    fun setOnline(id: String, on: Boolean) = go { val l = listing(id) ?: return@go
        listings = listings.map { if (it.id == id) it.copy(online = on) else it }
        try { Backend.setOnline(id, on) } catch (e: Exception) { listings = listings.map { if (it.id == id) it.copy(online = !on) else it }; throw e }
        toast(when (l.kind) {
            "BUSINESS" -> if (on) "${l.title} is open. Orders will reach you." else "${l.title} is closed. No orders until you open again."
            "SKILL" -> if (on) "${l.title} is online. Requests will reach you." else "${l.title} is offline."
            else -> if (on) "You're shown as available." else "You're shown as unavailable." }) }

    // ---------- products and services ----------
    fun saveItem(item: ItemRow, photo: Picked?, onDone: () -> Unit) = go { busy = true
        try {
            var row = item
            if (photo != null) { val path = "${item.listingId}/${photo.objectName()}"; Backend.upload("listing-media", path, photo.bytes); row = row.copy(photoUrl = Backend.publicUrl("listing-media", path)) }
            val saved = Backend.saveItem(row)
            items[item.listingId] = (items[item.listingId].orEmpty().filterNot { it.id == saved.id } + saved).sortedWith(compareBy({ it.sort }, { it.name.lowercase() }))
            toast(if (item.id == null) "${saved.name} added." else "Saved."); onDone()
        } finally { busy = false } }
    fun setInStock(item: ItemRow, on: Boolean) = go { val id = item.id ?: return@go
        items[item.listingId] = items[item.listingId].orEmpty().map { if (it.id == id) it.copy(inStock = on) else it }
        try { Backend.saveItem(item.copy(inStock = on)) } catch (e: Exception) { items[item.listingId] = items[item.listingId].orEmpty().map { if (it.id == id) it.copy(inStock = !on) else it }; throw e } }
    fun deleteItem(item: ItemRow, onDone: () -> Unit) = go { val id = item.id ?: return@go; Backend.deleteItem(id); items[item.listingId] = items[item.listingId].orEmpty().filterNot { it.id == id }; toast("${item.name} removed."); onDone() }

    // ---------- vehicles ----------
    private suspend fun uploadDocs(meId: String, docs: List<Pair<String, Picked>>): List<VehicleDoc> =
        docs.map { (kind, f) -> val path = "$meId/vehicle-${kind.lowercase()}-${f.objectName()}"; Backend.upload("docs", path, f.bytes); VehicleDoc(kind, path) }
    /** [docs]: document kind (RC, INSURANCE, PERMIT) to the picked file; they go to docs/<my id>/. */
    fun addVehicle(kind: String, model: String, plate: String, docs: List<Pair<String, Picked>>, onDone: () -> Unit) = go { val p = me ?: return@go; busy = true
        try {
            val v = Backend.addVehicle(p.id, kind, model, plate)
            if (docs.isNotEmpty()) { val uploaded = uploadDocs(p.id, docs); Backend.setVehicleDocs(v.id, uploaded); vehicleDocs = vehicleDocs + (v.id to uploaded) }
            toast("${v.model.ifBlank { v.kind }} (${v.plate}) added. Bucks checks the documents before it can go online.")
            refresh(); onDone()
        } finally { busy = false } }
    /** Keeps [keep], uploads [add], and removes files no longer referenced. */
    fun updateVehicle(id: String, kind: String, model: String, plate: String, keep: List<VehicleDoc>, add: List<Pair<String, Picked>>, onDone: () -> Unit) = go { val p = me ?: return@go; busy = true
        try {
            val all = keep + uploadDocs(p.id, add)
            Backend.updateVehicleDetails(id, kind, model, plate, all)
            val gone = vehicleDocs[id].orEmpty().map { it.path }.filter { path -> all.none { it.path == path } }
            runCatching { Backend.deleteFiles("docs", gone) }
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
    /** Scanned someone's code in person: the server checks distance, account age and position, and returns the new count. */
    fun recommend(token: String, onDone: (Int) -> Unit) = go {
        val n = Backend.recommend(token, here)
        toast(if (n >= NEEDED) "Thanks, that's $n of $NEEDED. They're live on Bucks now." else "Thanks, that's $n of $NEEDED."); onDone(n) }
}
