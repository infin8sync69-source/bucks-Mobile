package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.bucks.app.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

/** The kind chips on the search screen; [kinds] is what search_listings receives (null = every kind). */
enum class KindFilter(val label: String, val kinds: List<String>?) {
    ALL("All", null), SHOPS("Shops", listOf("BUSINESS")), PROS("Pros", listOf("SKILL")), DRIVERS("Drivers", listOf("DRIVER"))
}
/** Search radius chips, in km. */
val RADIUS_CHOICES = listOf(3, 10, 25)

/** Everything the profile screen shows for one listing, loaded together by [Discover.open]. */
data class ListingProfile(
    val listing: ListingRow, val items: List<ItemRow> = emptyList(), val reviews: List<ReviewRow> = emptyList(), val posts: List<PostRow> = emptyList(),
    val recommendations: Int = 0, val synced: Boolean = false, val syncs: Int = 0, val members: Int = 0, val openJobs: Int = 0,
    /** My role on the listing (OWNER / ADMIN / STORE_RIDER), null for a listing that isn't mine. */
    val myRole: String? = null,
    /** Where the listing is, when it has a location. */
    val at: LatLng? = null,
    /** Other live listings of the same kind and category nearby, for "More <category> nearby". */
    val similar: List<SearchHit> = emptyList(),
) {
    val mine get() = myRole != null
    val products get() = items.filter { it.kind == "PRODUCT" }
    /** Services of a pro; older rows without a kind still count when nothing is marked SERVICE. */
    val services get() = items.filter { it.kind == "SERVICE" }.ifEmpty { items.filter { it.kind != "PRODUCT" } }
}

/**
 * Cloud discovery: search over live listings near me and the universal profile of a shop, pro or driver.
 * Screens read the state and call the actions; every action reports a failure as a toast.
 */
class Discover(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    var query by mutableStateOf("")
    /** The selected kind chip; change it through [selectKind], which also re-runs the search. */
    var kind by mutableStateOf(KindFilter.ALL); private set
    var radiusKm by mutableIntStateOf(10)
    var results by mutableStateOf<List<SearchHit>>(emptyList()); private set
    var searching by mutableStateOf(false); private set
    /** True once a search has returned, so the empty state never shows before the first results. */
    var searched by mutableStateOf(false); private set
    /** Listing id -> everything its profile shows. */
    val profiles: SnapshotStateMap<String, ListingProfile> = mutableStateMapOf()
    /** Ids whose profile is loading right now. */
    var loading by mutableStateOf<Set<String>>(emptySet()); private set
    /** Ids that could not be found (deleted, or pending and not mine). */
    var missing by mutableStateOf<Set<String>>(emptySet()); private set
    /** Ids whose last load failed (no network, server error); the screen offers a retry instead of spinning forever. */
    var failed by mutableStateOf<Set<String>>(emptySet()); private set
    /** Listings I am synced with. */
    var mySyncs by mutableStateOf<Set<String>>(emptySet()); private set
    /** Ids whose sync toggle is in flight. */
    var syncing by mutableStateOf<Set<String>>(emptySet()); private set
    private var searchJob: Job? = null
    private var searchSeq = 0
    private var syncsLoaded = false

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }

    // ---------- search ----------
    /** Runs the current query, kind and radius against listings near [Social.here]. An empty query browses everything nearby. */
    fun search() {
        searchJob?.cancel()
        val n = ++searchSeq
        searchJob = scope.launch {
            searching = true
            try { results = Backend.search(query.trim(), social.here, radiusKm * 1000, kind.kinds); searched = true }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { toast(friendly(e)) }
            finally { if (n == searchSeq) searching = false }
        }
    }
    // Named selectKind, not setKind: the property's own JVM setter is already setKind(KindFilter).
    fun selectKind(k: KindFilter) { if (kind != k) { kind = k; search() } }
    fun setRadius(km: Int) { if (radiusKm != km) { radiusKm = km; search() } }
    /** The next wider radius chip, or null at the widest. */
    val widerRadius: Int? get() = RADIUS_CHOICES.firstOrNull { it > radiusKm }
    fun clear() { query = ""; search() }

    // ---------- profile ----------
    /**
     * Loads (or reloads) everything the profile screen needs for [id]. A listing that isn't there goes to [missing];
     * a fetch that throws (offline, server error) goes to [failed] so the screen shows "Try again" rather than an endless spinner.
     * Only the listing row itself is required; every other part degrades to empty when its own call fails.
     */
    fun open(id: String) = go {
        if (id in loading) return@go
        loading = loading + id
        failed = failed - id
        try {
            if (!syncsLoaded) runCatching { refreshSyncsNow() }
            val l = Backend.listing(id) ?: run { missing = missing + id; profiles.remove(id); return@go }
            missing = missing - id
            val me = social.me?.id
            val items = runCatching { Backend.items(id) }.getOrDefault(emptyList())
            val reviews = runCatching { Backend.reviews(id) }.getOrDefault(emptyList())
            val posts = if (l.kind == "SKILL") runCatching { Backend.listingPosts(id) }.getOrDefault(emptyList()) else emptyList()
            val members = runCatching { Backend.members(id) }.getOrDefault(emptyList())
            val myRole = members.firstOrNull { it.profileId == me }?.role
            // One call once the discover migration is applied; the plain tables otherwise.
            val counts = runCatching { Backend.listingCounts(id) }.getOrNull() ?: ListingCounts(
                recommendations = runCatching { Backend.recommendationCount(id) }.getOrDefault(0),
                syncs = runCatching { Backend.listingSyncCount(id) }.getOrDefault(0),
                members = members.size,
                openJobs = if (l.kind == "BUSINESS") runCatching { Backend.jobs(id).count { it.open } }.getOrDefault(0) else 0)
            val at = runCatching { Backend.listingPoint(id) }.getOrNull()
            val similar = if (at != null) runCatching { Backend.search("", at, 5_000, listOf(l.kind)) }.getOrDefault(emptyList())
                .filter { it.id != id && (l.category.isBlank() || it.category.equals(l.category, true)) }.take(4) else emptyList()
            runCatching { social.namesFor((reviews.map { it.authorId } + posts.map { it.authorId } + l.ownerId).distinct()) }
            profiles[id] = ListingProfile(l, items, reviews, posts, counts.recommendations, id in mySyncs, counts.syncs, maxOf(counts.members, members.size), counts.openJobs, myRole, at, similar)
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { failed = failed + id; toast(friendly(e)) }
        finally { loading = loading - id }
    }
    fun refreshSyncs() = go { refreshSyncsNow() }
    private suspend fun refreshSyncsNow() { val me = social.me?.id ?: return; mySyncs = Backend.myListingSyncs(me).map { it.listingId }.toSet(); syncsLoaded = true }
    fun isSynced(id: String) = id in mySyncs

    /** Follow or unfollow a listing: its posts then show up in my feed. */
    fun syncListing(id: String, on: Boolean) = go {
        val me = social.me?.id ?: return@go
        if (id in syncing || on == (id in mySyncs)) return@go
        syncing = syncing + id
        try {
            if (on) Backend.syncListing(me, id) else Backend.unsyncListing(me, id)
            mySyncs = if (on) mySyncs + id else mySyncs - id
            profiles[id]?.let { profiles[id] = it.copy(synced = on, syncs = (it.syncs + if (on) 1 else -1).coerceAtLeast(0)) }
            val title = profiles[id]?.listing?.title ?: results.firstOrNull { it.id == id }?.title ?: "them"
            toast(if (on) "Synced with $title. Their posts now show in your feed." else "Unsynced from $title.")
        } finally { syncing = syncing - id }
    }

    /** Opens (or reuses) my chat with the people who run a listing; [firstLine] is sent before the chat opens, e.g. a service request. */
    fun startListingChat(id: String, onOpen: (String) -> Unit, firstLine: String? = null) = go {
        val conv = Backend.startListingChat(id)
        val me = social.me?.id
        if (me != null && !firstLine.isNullOrBlank()) Backend.send(conv, me, firstLine.trim())
        social.refreshInbox()
        onOpen(conv)
    }
}

/* ---------- small helpers shared by the discover screens ---------- */

/** Shop / Pro / Driver, the word people use for each listing kind. */
fun kindLabel(kind: String) = when (kind) { "BUSINESS" -> "Shop"; "SKILL" -> "Pro"; "DRIVER" -> "Driver"; else -> kind.lowercase().replaceFirstChar { it.uppercase() } }
/** "650 m" or "1.2 km". */
fun formatDistance(meters: Double): String = if (meters < 1000) "${meters.roundToInt()} m" else "%.1f km".format(meters / 1000)
/** A string field of a listing's details, or null when missing or blank. Booleans and numbers come back as text. */
fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotBlank() && it != "null" }
/** A list field of details ("languages": ["Kannada", "Hindi"]) or a comma-separated string. */
fun JsonObject.list(key: String): List<String> = when (val v = this[key]) {
    is JsonArray -> v.mapNotNull { (it as? JsonPrimitive)?.content?.trim()?.takeIf { s -> s.isNotBlank() } }
    is JsonPrimitive -> v.content.split(',').map { it.trim() }.filter { it.isNotBlank() }
    else -> emptyList()
}
/** The vehicle a driver listing drives, from details (vehicle_kind / vehicle / kind) or the category ("Auto"). */
fun driverKind(details: JsonObject, category: String = ""): VehicleKind? {
    val raw = listOf("vehicle_kind", "vehicle", "kind").firstNotNullOfOrNull { details.str(it) } ?: category.takeIf { it.isNotBlank() } ?: return null
    return VehicleKind.entries.firstOrNull { it.name.equals(raw, true) || it.label.equals(raw, true) || raw.contains(it.label, true) }
}
/** The rate line of a pro: details.rate, else the cheapest service. */
fun proRate(details: JsonObject, minPrice: Int?): String = details.str("rate") ?: minPrice?.let { "From ₹$it" } ?: "Rate on request"
