package com.bucks.app.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * "Did they help?" (docs/DISCOVERY_ALGORITHMS.md §6.4 and §13.8). When someone calls, messages, books or gets directions to a page,
 * this phone remembers it, and from 12 hours later Home asks once whether the page helped. The answer is the person's own ↑ or ↓
 * on the page's usual recommend sheet (so a ↓ still needs a reason): votes after real contact, which the trust score lacks today.
 *
 * One page at a time and at most one ask a day; never for your own page or one you already rated; each page asked about once;
 * nothing older than 7 days. Kept on this phone only (Prefs) and cleared at sign-out. Nothing is sent until the person answers.
 */
object HelpAsk {
    private const val WAIT_MS = 12 * 60 * 60_000L
    private const val KEEP_MS = 7 * 24 * 60 * 60_000L
    private const val MAX_ASKS = 10

    /** A page contacted at [at] (epoch ms); [queryId]: the search it was opened from, if it was (DiscoveryLog). */
    @Serializable data class Ask(val id: String, val title: String, val at: Long, val queryId: String? = null)
    /** The vote chosen on Home, for the page's sheet to open with. */
    data class Answer(val vote: Int, val queryId: String?)
    @Serializable private data class State(val asks: List<Ask> = emptyList(), val done: List<String> = emptyList(), val shownDay: String? = null)

    private val json = Json { ignoreUnknownKeys = true }
    private val lock = Any()
    @Volatile private var pending: Pair<String, Answer>? = null

    /** The person contacted page [id] (a call, a message, a booking or directions). */
    fun contacted(id: String, title: String, queryId: String?) {
        synchronized(lock) {
            val s = load(); val now = System.currentTimeMillis()
            if (id in s.done || s.asks.any { it.id == id }) return
            save(s.copy(asks = (s.asks.filter { now - it.at < KEEP_MS } + Ask(id, title.take(80), now, queryId)).takeLast(MAX_ASKS)))
        }
    }

    /** The page to ask about now, or null: the oldest contact between 12 hours and 7 days old, when nothing was asked today. */
    fun due(): Ask? = synchronized(lock) {
        val s = load(); val now = System.currentTimeMillis()
        if (s.shownDay == today()) null
        else s.asks.filter { (now - it.at) in WAIT_MS until KEEP_MS && it.id !in s.done }.minByOrNull { it.at }
    }

    /** The ask is on screen: no other one today. */
    fun shown() { synchronized(lock) { save(load().copy(shownDay = today())) } }

    /** Answered on Home with ↑ (1) or ↓ (-1): the page opens with that vote ready, and this page is never asked about again. */
    fun answer(id: String, vote: Int) {
        val q = synchronized(lock) { load().asks.firstOrNull { it.id == id }?.queryId }
        pending = id to Answer(vote, q)
        finish(id)
    }

    /** "Not now": this page is never asked about again. */
    fun dismiss(id: String) = finish(id)

    /** The person rated the page (now or before): nothing left to ask. */
    fun rated(id: String) = finish(id)

    /** The vote chosen on Home for page [id], handed over once. */
    fun takeVote(id: String): Answer? = pending?.takeIf { it.first == id }?.second?.also { pending = null }

    /** The search page [id] was contacted from, while its ask is still waiting. */
    fun queryFor(id: String): String? = synchronized(lock) { load().asks.firstOrNull { it.id == id }?.queryId }

    /** Signed out or account deleted: these belong to the person who left. */
    fun clear() { synchronized(lock) { Prefs.helpAsksJson = null }; pending = null }

    private fun finish(id: String) {
        synchronized(lock) {
            val s = load()
            if (s.asks.none { it.id == id } && id in s.done) return
            save(s.copy(asks = s.asks.filterNot { it.id == id }, done = (s.done + id).distinct().takeLast(200)))
        }
    }
    private fun load(): State = runCatching { Prefs.helpAsksJson?.let { json.decodeFromString(State.serializer(), it) } }.getOrNull() ?: State()
    private fun save(s: State) { Prefs.helpAsksJson = json.encodeToString(State.serializer(), s) }
    private fun today(): String = java.time.LocalDate.now().toString()
}
