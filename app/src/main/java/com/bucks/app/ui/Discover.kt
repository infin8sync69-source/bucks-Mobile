package com.bucks.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Apartment
import androidx.compose.material.icons.rounded.Handyman
import androidx.compose.material.icons.rounded.LocalTaxi
import androidx.compose.material.icons.rounded.Storefront
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.graphics.vector.ImageVector
import com.bucks.app.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

/**
 * The chips on the search screen. [kinds] is what search_listings receives (null = every kind); a page group's chip also limits
 * BUSINESS results to that group's service rows ([services], from PageTypes.groups), so shops, local services, companies, NGOs and
 * institutions each get their own chip while pros, assets and drivers stay one chip per kind.
 */
enum class KindFilter(val label: String, val kinds: List<String>?, val group: String? = null) {
    ALL("All", null),
    SHOPS("Shops", listOf("BUSINESS"), "SHOPS"),
    LOCAL_SERVICES("Local services", listOf("BUSINESS"), "LOCAL_SERVICES"),
    COMPANIES("Companies", listOf("BUSINESS"), "COMPANIES"),
    COMMUNITY("NGOs and groups", listOf("BUSINESS"), "COMMUNITY"),
    INSTITUTIONS("Institutions", listOf("BUSINESS"), "INSTITUTIONS"),
    PROS("Pros", listOf("SKILL")), ASSETS("Buy & rent", listOf("ASSET")), DRIVERS("Drivers", listOf("DRIVER"));

    /** The service rows search_listings is limited to (a page group's), or null for every service. */
    val services: List<String>? get() = PageTypes.group(group)?.services
    /** The chip's icon: the group's, else the kind's; none for All. */
    val icon: ImageVector? get() = PageTypes.group(group)?.icon ?: kinds?.firstOrNull()?.let { kindIcon(it) }
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
    /** Services of a pro or a service page; older rows without a kind still count when nothing is marked SERVICE. */
    val services get() = items.filter { it.kind == "SERVICE" }.ifEmpty { items.filter { it.kind !in setOf("PRODUCT", "PROGRAM", "EVENT") } }
    /** Programs of an NGO or a school / college (items.kind PROGRAM). */
    val programs get() = items.filter { it.kind == "PROGRAM" }
    /** Events of a community group, association or place of worship (items.kind EVENT). */
    val events get() = items.filter { it.kind == "EVENT" }
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
    /** A service tile (FOOD, GROCERY, ...) the search is limited to, or null. Set through [useService]. */
    var service by mutableStateOf<String?>(null); private set
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
    /**
     * Runs the current query, kind and radius against listings near [Social.here]. An empty query browses everything nearby.
     * A Services tile ([service]) limits the search to that one service; otherwise a group chip limits it to the group's services.
     */
    fun search() {
        searchJob?.cancel()
        val n = ++searchSeq
        searchJob = scope.launch {
            searching = true
            try { results = Backend.search(query.trim(), social.here, radiusKm * 1000, kind.kinds, service?.let { listOf(it) } ?: kind.services); searched = true }
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
    /**
     * Opens search limited to one service (a Services tile), or clears that limit (null). Does not search by itself: the search
     * screen runs one when it opens. The service's own radius is used, so results match what unlocked the tile.
     */
    fun useService(key: String?, radiusM: Int? = null) {
        service = key
        if (key != null) { query = ""; kind = KindFilter.ALL; radiusM?.let { m -> radiusKm = RADIUS_CHOICES.firstOrNull { it * 1000 >= m } ?: RADIUS_CHOICES.last() } }
    }

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
            // A store's Products tab needs names, prices and one photo each, not every description: the slim catalogue is about a quarter of the size.
            // Pages that don't sell products (services, programs, events) show descriptions in their rows, so they take the full rows.
            val sellsProducts = PageTypes.of(l)?.sellsProducts ?: true
            val items = (if (l.kind == "BUSINESS" && sellsProducts) runCatching { Backend.catalogItems(id) }.getOrNull() else null) ?: runCatching { Backend.items(id) }.getOrDefault(emptyList())
            val reviews = runCatching { Backend.reviews(id) }.getOrDefault(emptyList())
            val posts = if (l.kind == "SKILL" || l.kind == "BUSINESS") runCatching { Backend.listingPosts(id) }.getOrDefault(emptyList()) else emptyList()
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
    private suspend fun refreshSyncsNow() { val me = social.me?.id ?: return; val rows = Backend.myListingSyncs(me); if (social.me?.id != me) return; mySyncs = rows.map { it.listingId }.toSet(); syncsLoaded = true }
    /** Sign-out and account deletion: results, profiles (which carry "mine" and "synced") and my listing syncs belong to this person only. */
    fun signedOut() {
        searchJob?.cancel(); searchJob = null; searchSeq++
        query = ""; service = null; results = emptyList(); searching = false; searched = false
        profiles.clear(); loading = emptySet(); missing = emptySet(); failed = emptySet()
        mySyncs = emptySet(); syncing = emptySet(); syncsLoaded = false
    }
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
/** The icon of a listing kind (a business page's own type icon comes from PageTypes.badgeIcon). */
fun kindIcon(kind: String): ImageVector = when (kind) { "BUSINESS" -> Icons.Rounded.Storefront; "SKILL" -> Icons.Rounded.Handyman; "ASSET" -> Icons.Rounded.Apartment; else -> Icons.Rounded.LocalTaxi }
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
