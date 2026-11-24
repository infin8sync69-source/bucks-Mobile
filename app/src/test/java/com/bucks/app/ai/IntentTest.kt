package com.bucks.app.ai

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Tier 1 plumbing that does not need a phone: the call parser, the router's checks, the place matcher and the assistant gate. */
class IntentTest {
    private fun fake(answer: ParsedIntent?) = object : IntentEngine { override suspend fun parse(text: String, context: String) = answer }
    private fun router(model: ParsedIntent?) = IntentRouter(RuleIntentEngine()) { fake(model) }
    private fun m(tool: String, vararg args: Pair<String, String>) = ParsedIntent(tool, mapOf(*args), 0.8f, FunctionGemmaIntentEngine.SOURCE)

    @Test fun parsesFunctionGemmaCalls() {
        // Verbatim LiteRT-LM 0.19.1 outputs of the run-4 model (generic model type: the call comes back as text).
        val ride = FunctionGemmaIntentEngine.parseCall("<start_function_call>call:request_ride{destination:<escape>MG Road<escape>,vehicle:<escape>AUTO<escape>}<end_function_call>")!!
        assertEquals("request_ride", ride.tool); assertEquals(mapOf("destination" to "MG Road", "vehicle" to "AUTO"), ride.args); assertEquals("model", ride.source)
        val none = FunctionGemmaIntentEngine.parseCall("<start_function_call>call:request_ride{destination:<escape><escape>,vehicle:<escape>CAB<escape>}<end_function_call>")!!
        assertEquals("", none.args["destination"]); assertEquals("CAB", none.args["vehicle"])
        assertEquals("help", FunctionGemmaIntentEngine.parseCall("<start_function_call>call:help{}<end_function_call>")!!.tool)
        val content = FunctionGemmaIntentEngine.parseCall("<start_function_call>call:find_content{kind:<escape>VIDEO<escape>,query:<escape>biryani, extra<escape>}<end_function_call>")!!
        assertEquals("biryani, extra", content.args["query"])
        // Cut off at the token limit, but the call is complete.
        assertEquals("show_map", FunctionGemmaIntentEngine.parseCall("<start_function_call>call:show_map{}")!!.tool)
        assertNull(FunctionGemmaIntentEngine.parseCall("Sure! I can help with that."))
        assertNull(FunctionGemmaIntentEngine.parseCall(""))
    }

    @Test fun acceptsOnlyCompleteKnownCalls() {
        assertTrue(IntentRouter.accept(m("request_ride", "vehicle" to "AUTO", "destination" to "MG Road"), null))
        assertTrue(IntentRouter.accept(m("request_ride", "vehicle" to "cab", "destination" to ""), null))
        assertFalse(IntentRouter.accept(m("request_ride", "vehicle" to "PLANE", "destination" to "MG Road"), null))   // not in the enum
        assertFalse(IntentRouter.accept(m("request_ride", "vehicle" to "AUTO"), null))                              // destination missing
        assertFalse(IntentRouter.accept(m("transfer_money", "to" to "x"), null))                                     // not one of the 13
        assertFalse(IntentRouter.accept(m("help"), null))
        assertFalse(IntentRouter.accept(m("search_marketplace", "query" to " "), null))
        assertTrue(IntentRouter.accept(m("find_content", "kind" to "PEOPLE", "query" to ""), null))
        assertFalse(IntentRouter.accept(m("find_content", "kind" to "MUSIC", "query" to "x"), null))
        // Rules that matched with confidence ≥ 0.6 and say something else win.
        assertFalse(IntentRouter.accept(m("compare", "query" to "sugar"), ParsedIntent(Tools.SEARCH, mapOf("query" to "sugar"), 0.6f)))
        assertTrue(IntentRouter.accept(m("compare", "query" to "sugar"), ParsedIntent(Tools.SEARCH, mapOf("query" to "sugar"), RuleIntentEngine.FALLBACK_CONFIDENCE)))
    }

    @Test fun cascadeOrder() = runBlocking {
        // Rules at ≥ 0.9 never reach the model.
        assertEquals("rules", router(m("help")).parse("Auto to MG Road", "").source)
        // Hindi: the rules only find leftover words; the model's ride wins, its enum value upper-cased.
        val hi = router(m("request_ride", "vehicle" to "auto", "destination" to "Hebbal")).parse("हेब्बल के लिए ऑटो चाहिए", "")
        assertEquals(Tools.RIDE, hi.tool); assertEquals("AUTO", hi.args["vehicle"]); assertEquals("model", hi.source)
        // A model answer that fails the checks falls back to the rules' leftover-words search, which the screen shows as classic search.
        val r = router(m("help"))
        val fallback = r.parse("ಸಕ್ಕರೆ ಬೇಕು", "")
        assertEquals(Tools.SEARCH, fallback.tool); assertTrue(r.isClassicSearch(fallback))
        // No model at all: exactly the old behaviour.
        val off = IntentRouter(RuleIntentEngine()) { null }
        assertEquals(Tools.HELP, off.parse("hi", "").tool)
        assertEquals(Tools.SEARCH, off.parse("order sugar", "").tool)
    }

    @Test fun placesMustBeKnown() {
        assertEquals("MG Road", KnownPlaces.match("MG Road"))
        assertEquals("Koramangala, Bengaluru", KnownPlaces.match("Koramangala"))
        assertEquals("Jayanagar 4th block", KnownPlaces.match("Jayanagar"))
        assertEquals("Majestic bus stand", KnownPlaces.match("majestic"))
        assertEquals("Nexus Mall, Koramangala", KnownPlaces.match("Nexus Mall"))
        assertEquals("Hebbal", KnownPlaces.match("Hebbal"))
        assertEquals("HSR Layout", KnownPlaces.match("HSR layout"))
        assertEquals("Marathahalli", KnownPlaces.match("Marathalli"))        // one letter off
        assertEquals("Kempegowda airport", KnownPlaces.match("Kempegowda airport"))
        // Invented by the model on test commands (run 2 and run 4).
        assertNull(KnownPlaces.match("Hamarang")); assertNull(KnownPlaces.match("Akame no Shibori")); assertNull(KnownPlaces.match("AC repair"))
        assertNull(KnownPlaces.match("Rajaji Mandir"))
        assertNull(KnownPlaces.match("")); assertNull(KnownPlaces.match(null)); assertNull(KnownPlaces.match("MG"))
    }

    @Test fun agentGate() {
        for (s in listOf("Bike to Koramangala", "auto to MG Road", "yes", "Show my orders", "compare sugar", "go online", "take me home", "cancel",
            "हेब्बल के लिए ऑटो चाहिए", "ಸಕ್ಕರೆ", "சர்க்கரை வேண்டும்", "plumber near me", "biryani videos dikhao")) assertTrue(s, AgentGate.isAgentQuery(s))
        for (s in listOf("rice", "sugar", "biriyani", "plumber", "chicken biryani", "Find doctor", "2 kg rice")) assertFalse(s, AgentGate.isAgentQuery(s))
    }
}
