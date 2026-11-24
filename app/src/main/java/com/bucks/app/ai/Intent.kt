package com.bucks.app.ai

import com.bucks.app.data.Seed
import com.bucks.app.data.VehicleKind

/**
 * The single tool catalogue every intent engine must produce. An engine only proposes an action;
 * Kotlin validates it, fills defaults and asks for confirmation before anything moves money.
 */
data class ParsedIntent(val tool: String, val args: Map<String, String> = emptyMap(), val confidence: Float = 1f, val source: String = "rules")

object Tools {
    const val RIDE = "request_ride"; const val SEARCH = "search_marketplace"; const val COMPARE = "compare"; const val SORT = "sort_results"
    const val ACTIVITY = "show_activity"; const val POST_REQUEST = "post_request"; const val GO_ONLINE = "go_online"; const val BECOME_PRO = "become_provider"
    const val CONFIRM = "confirm_pending"; const val SHOW_MAP = "show_map"; const val CANCEL = "cancel_pending"; const val HELP = "help"
    /** Posts, videos, photos, files (Explore) or a person (Discover). Only the on-device model proposes it. */
    const val FIND_CONTENT = "find_content"

    /**
     * The 13 tools of assets/intent_tools.json (= ml/intent/tools.json, what the model was trained on), each with the arguments that
     * must be present and the values an enum argument may take. [IntentRouter] drops any model answer outside this.
     */
    private val VEHICLES = setOf("BIKE", "AUTO", "CAB")
    val required: Map<String, Map<String, Set<String>?>> = mapOf(
        RIDE to mapOf("vehicle" to VEHICLES, "destination" to null), SEARCH to mapOf("query" to null), COMPARE to mapOf("query" to null),
        SORT to mapOf("by" to setOf("TRUST", "NEAR", "PRICE")), ACTIVITY to emptyMap(), FIND_CONTENT to mapOf("kind" to setOf("ALL", "VIDEO", "IMAGE", "FILE", "PEOPLE"), "query" to null),
        POST_REQUEST to mapOf("what" to null), GO_ONLINE to emptyMap(), BECOME_PRO to emptyMap(), CONFIRM to emptyMap(), CANCEL to emptyMap(),
        SHOW_MAP to emptyMap(), HELP to emptyMap())
    /** Arguments that must also be non-blank (a search for nothing is no search). */
    val nonBlank = setOf("$SEARCH.query", "$COMPARE.query", "$POST_REQUEST.what")
}

interface IntentEngine { suspend fun parse(text: String, context: String): ParsedIntent? }

/**
 * The places a ride may go to: the app's own list ([Seed.PLACES], with map points in Geo.PLACES). The model names places in English
 * but can invent one ("Hamarang", "Rajaji Mandir"), so a destination counts only if it matches one of these; otherwise the assistant
 * asks where to instead of offering a ride.
 */
object KnownPlaces {
    private fun norm(s: String) = s.lowercase().filter { it.isLetterOrDigit() }
    /** Each place by its full name, the part before the comma and its first word (when that is distinctive: 5+ letters). */
    private val keys: List<Pair<String, String>> by lazy {
        Seed.PLACES.flatMap { p -> listOfNotNull(norm(p), norm(p.substringBefore(',')), norm(p.substringBefore(' ')).takeIf { it.length >= 5 }).distinct().map { it to p } }
    }
    /** The known place [name] means, or null. Exact, prefix (5+ letters) or one or two typos (by length) on a key. */
    fun match(name: String?): String? {
        val d = norm(name ?: ""); if (d.length < 3) return null
        keys.firstOrNull { it.first == d }?.let { return it.second }
        if (d.length >= 5) keys.firstOrNull { (k, _) -> k.length >= 5 && (k.startsWith(d) || d.startsWith(k)) }?.let { return it.second }
        val allowed = when { d.length >= 9 -> 2; d.length >= 5 -> 1; else -> 0 }
        if (allowed == 0) return null
        return keys.map { (k, p) -> distance(d, k) to p }.filter { it.first <= allowed }.minByOrNull { it.first }?.second
    }
    private fun distance(a: String, b: String): Int {
        if (kotlin.math.abs(a.length - b.length) > 2) return 99
        var prev = IntArray(b.length + 1) { it }
        for (i in 1..a.length) { val cur = IntArray(b.length + 1); cur[0] = i
            for (j in 1..b.length) cur[j] = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            prev = cur }
        return prev[b.length]
    }
}

/**
 * Which typed or spoken lines go to the assistant ([IntentRouter]) rather than straight to the results list: the English command
 * words, any non-Latin script (Hindi, Kannada, Tamil, ... sentences), or 3+ words. Short product searches ("rice", "chicken biryani")
 * stay plain searches; lines the assistant can't place still end in the results list ([IntentRouter.isClassicSearch]).
 */
object AgentGate {
    private val WORDS = Regex("\\b(bike|scooter|taxi|cab|auto|ride|car|compare|cheapest|best|sort|my orders|my rides|history|post a request|go online|become|provider|pro profile|yes|confirm|cancel|show the map|book|take me|drop me)\\b")
    fun hasCommandWord(q: String) = WORDS.containsMatchIn(q.lowercase())
    fun isAgentQuery(q: String): Boolean {
        val l = q.lowercase().trim()
        if (WORDS.containsMatchIn(l)) return true
        if (l.any { it.isLetter() && Character.UnicodeScript.of(it.code) != Character.UnicodeScript.LATIN }) return true
        return l.split(Regex("\\s+")).count { w -> w.any { it.isLetter() } } >= 3
    }
}

/** Tier 0: deterministic grammar. Free, instant, offline; handles the common phrasings. */
class RuleIntentEngine : IntentEngine {
    private fun placeIn(l: String) = Seed.PLACES.firstOrNull { l.contains(it.substringBefore(',').lowercase().substringBefore(' ')) }
    override suspend fun parse(text: String, context: String): ParsedIntent? {
        val l = text.lowercase().trim()
        if (l.isBlank()) return null
        if (Regex("^(yes|confirm|ok|okay|book it|go ahead|haan|sari|yes, ring them)\\b").containsMatchIn(l)) return ParsedIntent(Tools.CONFIRM)
        if (Regex("^(no|cancel|stop|nahi|beda|never mind)\\b").containsMatchIn(l)) return ParsedIntent(Tools.CANCEL)
        if (l.contains("show the map")) return ParsedIntent(Tools.SHOW_MAP)
        val kind = when { Regex("\\b(bike|scooter|scooty|two wheeler)\\b").containsMatchIn(l) -> VehicleKind.BIKE; Regex("\\b(auto|rickshaw)\\b").containsMatchIn(l) -> VehicleKind.AUTO; Regex("\\b(cab|taxi|car)\\b").containsMatchIn(l) -> VehicleKind.CAB; else -> null }
        if (kind != null || Regex("\\b(ride|drop me|take me|pick me)\\b").containsMatchIn(l)) return ParsedIntent(Tools.RIDE, mapOf("vehicle" to (kind ?: VehicleKind.AUTO).name, "destination" to (placeIn(l) ?: "")))
        if (Regex("\\b(compare|cheapest|best|which is better)\\b").containsMatchIn(l)) return ParsedIntent(Tools.COMPARE, mapOf("query" to l.replace(Regex("\\b(compare|cheapest|best|which is better|for|the|near me|me)\\b"), "").trim()))
        if (l.startsWith("sort")) return ParsedIntent(Tools.SORT, mapOf("by" to when { Regex("price|cheap").containsMatchIn(l) -> "PRICE"; Regex("near|close|distance").containsMatchIn(l) -> "NEAR"; else -> "TRUST" }))
        if (Regex("\\b(my orders|my rides|my requests|history|activity)\\b").containsMatchIn(l)) return ParsedIntent(Tools.ACTIVITY)
        if (l.startsWith("post a request")) return ParsedIntent(Tools.POST_REQUEST, mapOf("what" to text.replace(Regex("(?i)post a request for"), "").trim()))
        if (Regex("\\b(go online|start duty|i'm online)\\b").containsMatchIn(l)) return ParsedIntent(Tools.GO_ONLINE)
        if (Regex("\\b(become|provider|pro profile|add (my )?(vehicle|skill|business)|earn)\\b").containsMatchIn(l)) return ParsedIntent(Tools.BECOME_PRO)
        // Nothing matched: the leftover words as a search. Below the router's 0.6 bar, so it never vetoes the model.
        val q = l.replace(Regex("\\b(order|find|get|book|need|want|i|a|an|some|near|nearby|please|me|the|for)\\b"), "").trim()
        return if (q.length >= 3) ParsedIntent(Tools.SEARCH, mapOf("query" to q), confidence = FALLBACK_CONFIDENCE) else null
    }
    companion object { const val FALLBACK_CONFIDENCE = 0.5f }
}

/**
 * The intent cascade (docs/ai/reports "Swarm intelligence for Bucks": the intent cascade has three tiers):
 * Tier 0 rules, accepted at ≥ 0.9; Tier 1 the on-device model ([FunctionGemmaIntentEngine]) when it is downloaded and switched on;
 * then classic search ([isClassicSearch]: the caller shows the plain results list).
 *
 * A model answer counts only if it parses, names one of the 13 tools with its required arguments (enum values checked), is not
 * `help`, and the rules did not say something else with confidence ≥ 0.6.
 */
class IntentRouter(private val rules: IntentEngine = RuleIntentEngine(), private val model: () -> IntentEngine? = { IntentModel.engine() }) {
    suspend fun parse(text: String, context: String): ParsedIntent {
        val r = rules.parse(text, context)
        if (r != null && r.confidence >= 0.9f) return r
        model()?.parse(text, context)?.let { m -> if (accept(m, r)) return m.copy(args = m.args.mapValues { (k, v) -> if (Tools.required[m.tool]?.get(k) != null) v.trim().uppercase() else v.trim() }) }
        return r ?: ParsedIntent(Tools.HELP)
    }

    /** True for the rules' leftover-words search: nothing understood it, so the caller should run the classic search instead. */
    fun isClassicSearch(i: ParsedIntent) = i.source == "rules" && i.tool == Tools.SEARCH && i.confidence < 0.6f

    companion object {
        fun accept(m: ParsedIntent, rules: ParsedIntent?): Boolean {
            val spec = Tools.required[m.tool] ?: return false
            if (m.tool == Tools.HELP) return false
            for ((k, allowed) in spec) {
                val v = m.args[k] ?: return false
                if (allowed != null && v.trim().uppercase() !in allowed) return false
                if ("${m.tool}.$k" in Tools.nonBlank && v.isBlank()) return false
            }
            if (rules != null && rules.confidence >= 0.6f && rules.tool != m.tool) return false
            return true
        }
    }
}
