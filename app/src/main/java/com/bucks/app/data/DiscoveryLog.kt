package com.bucks.app.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * What people search for on Bucks and what they do next, sent to log_discovery (supabase/migrations/discovery_log.sql) so search can
 * be measured and keep learning (docs/DISCOVERY_ALGORITHMS.md §8 and §13).
 *
 * The same rule as [Analytics]: only adults who haven't switched usage statistics off (Settings › Appearance and data). Otherwise
 * nothing is even kept in memory, and the server drops anything from under-18s whatever it receives. Switching usage statistics off
 * also deletes what the server kept ([forgetMe]).
 *
 * Sent: the search (words, about where, radius, chips, how many results, how long it took; for people search no words at all), the
 * first 10 results shown, the result opened and its position, and what is done on that page within 30 minutes (call, message,
 * directions, cart, order, booking, sync, share). Batched every 30 s and when the search screen closes. A send that fails is dropped:
 * logging never retries forever, never shows an error and never slows search down.
 */
object DiscoveryLog {
    private const val SEND_EVERY_MS = 30_000L
    private const val ACTION_WINDOW_MS = 30 * 60_000L
    private const val MAX_PENDING = 1_000

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private val pending = ArrayList<JsonObject>()
    private var sender: Job? = null
    /** The search a result was opened from: (query id, listing id, when), so what is done on that page can point back to it. */
    @Volatile private var lastOpen: Triple<String, String, Long>? = null
    private val app: String by lazy { "android " + com.bucks.app.BuildConfig.VERSION_NAME + " (" + com.bucks.app.BuildConfig.VERSION_CODE + ")" }

    /** On for adults who haven't switched usage statistics off, in builds that talk to the cloud. */
    val on: Boolean get() = Backend.enabled && Analytics.isAllowed

    /** A new search id; the events that follow point at it. */
    fun newId(): String = java.util.UUID.randomUUID().toString()

    /** A search that ran and gave [n] results in [ms] milliseconds. People search passes [q] as null: the name typed is never sent. */
    fun search(id: String, surface: String, q: String?, at: LatLng, radiusM: Int, filters: Map<String, String?>, n: Int, ms: Long) {
        if (!on) return
        add(buildJsonObject {
            put("t", "QUERY"); put("id", id); put("surface", surface); put("q", q?.take(100))
            put("lat", at.lat); put("lng", at.lng); put("radius_m", radiusM); put("n", n); put("ms", ms)
            put("app", app); put("ranker", "v1"); put("at", now())
            put("filters", buildJsonObject { filters.forEach { (k, v) -> if (v != null) put(k, v) } })
        })
    }

    /** The first results shown for search [queryId], in the order shown. */
    fun shown(queryId: String, listingIds: List<String>) {
        if (!on || listingIds.isEmpty()) return
        add(buildJsonObject {
            put("t", "IMPRESSION"); put("query_id", queryId); put("subject_type", "LISTING"); put("at", now())
            put("ids", buildJsonArray { listingIds.take(10).forEach { add(JsonPrimitive(it)) } })
        })
    }

    /** A result of search [queryId] opened at [position] (0 = the first). */
    fun opened(queryId: String, listingId: String, position: Int) {
        if (!on) return
        lastOpen = Triple(queryId, listingId, System.currentTimeMillis())
        add(event("OPEN", queryId, listingId, position))
    }

    /**
     * Something done on a page opened from search in the last 30 minutes: CALL, MESSAGE, DIRECTIONS, ADD_TO_CART, ORDER, BOOK, SYNC
     * or SHARE. Anything done on a page that wasn't opened from search is not sent.
     */
    fun acted(kind: String, listingId: String?) {
        if (!on || listingId == null) return
        val o = lastOpen ?: return
        if (o.second != listingId || System.currentTimeMillis() - o.third > ACTION_WINDOW_MS) return
        add(event(kind, o.first, listingId, null))
    }

    /** The search [listingId] was opened from, when it was opened from search in the last 30 minutes. */
    fun queryFor(listingId: String): String? =
        lastOpen?.takeIf { it.second == listingId && System.currentTimeMillis() - it.third <= ACTION_WINDOW_MS }?.first

    /** The person rated a page ↑ ([vote] 1) or ↓ (-1): the outcome of the search it came from ([queryId], when known). */
    fun voted(listingId: String, vote: Int, queryId: String?) {
        if (!on || vote == 0) return
        add(buildJsonObject {
            put("t", "VOTE"); if (queryId != null) put("query_id", queryId); put("subject_type", "LISTING"); put("subject_id", listingId)
            put("detail", if (vote > 0) "UP" else "DOWN"); put("at", now())
        })
    }

    /** Sends what is waiting now; it is also sent every 30 s on its own. */
    fun flush() {
        val batch = synchronized(lock) { if (pending.isEmpty()) return; ArrayList(pending).also { pending.clear() } }
        if (!on) return
        scope.launch { batch.chunked(200).forEach { part -> runCatching { Backend.logDiscovery(JsonArray(part)) } } }
    }

    /** Usage statistics switched off: nothing more is sent, and what the server kept is deleted. */
    fun forgetMe() {
        synchronized(lock) { pending.clear() }
        lastOpen = null
        if (Backend.enabled) scope.launch { runCatching { Backend.discoveryForgetMe() } }
    }

    private fun event(kind: String, queryId: String, listingId: String, position: Int?) = buildJsonObject {
        put("t", kind); put("query_id", queryId); put("subject_type", "LISTING"); put("subject_id", listingId); put("at", now())
        if (position != null) put("position", position)
    }

    private fun add(e: JsonObject) {
        synchronized(lock) {
            if (pending.size < MAX_PENDING) pending += e
            if (sender?.isActive == true) return
            sender = scope.launch {
                while (true) {
                    delay(SEND_EVERY_MS)
                    flush()
                    if (synchronized(lock) { pending.isEmpty() }) break
                }
            }
        }
    }

    private fun now(): String = java.time.Instant.now().toString()
}
