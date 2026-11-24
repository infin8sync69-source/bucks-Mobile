package com.bucks.app.ai

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.OpenApiTool
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.tool
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import java.io.File

/**
 * Tier 1: the fine-tuned FunctionGemma 270M (ml/intent/, run 4) on the phone through LiteRT-LM. Offline and free; it only proposes a
 * tool call, which [IntentRouter] checks and [com.bucks.app.ui.BucksViewModel] still routes through the confirm sheet.
 *
 * [toolsJson] is ml/intent/tools.json exactly as the model was trained on it (copied to assets/intent_tools.json; scripts/hygiene.sh
 * fails if the two differ). The prompt is the training one: the developer line, the 13 declarations, the user's words, nothing else.
 * The engine starts lazily on a background thread on the first command (CPU backend) and is closed again after [IDLE_CLOSE_MS]
 * without use, so the ~300 MB it maps does not stay resident. Any failure (missing native library on 32-bit phones, a damaged file,
 * a timeout) returns null and the router carries on without the model.
 */
class FunctionGemmaIntentEngine(private val modelFile: File, private val toolsJson: String, private val cacheDir: File? = null) : IntentEngine {
    private val lock = Mutex()
    private var engine: Engine? = null
    /** The conversation with the developer line and tool declarations already prefilled; every command runs on a clone of it. */
    private var base: Conversation? = null
    private var idleJob: Job? = null
    /** Set once the engine could not start (no native library, unreadable model): no further attempts this process. */
    @Volatile var broken = false; private set

    override suspend fun parse(text: String, context: String): ParsedIntent? {
        if (broken || text.isBlank() || !modelFile.exists()) return null
        return withContext(Dispatchers.Default) {
            withTimeoutOrNull(PARSE_TIMEOUT_MS) {
                lock.withLock {
                    idleJob?.cancel()
                    val out = runCatching {
                        val b = base ?: start() ?: return@runCatching null
                        b.clone().use { c -> c.sendMessage(Message.user(text.take(MAX_INPUT_CHARS))) }
                    }.getOrNull()
                    idleJob = com.bucks.app.data.AppLife.scope.launch { delay(IDLE_CLOSE_MS); lock.withLock { close() } }
                    out?.let { m -> m.toolCalls.firstOrNull()?.let { tc -> ParsedIntent(tc.name, tc.arguments.mapValues { (_, v) -> v?.toString().orEmpty() }, MODEL_CONFIDENCE, SOURCE) } ?: parseCall(m.contents.toString()) }
                }
            }
        }
    }

    /** Starts the engine (seconds on a mid-range phone). Called with [lock] held. */
    private fun start(): Conversation? = try {
        val e = Engine(EngineConfig(modelPath = modelFile.absolutePath, backend = Backend.CPU(), maxNumTokens = 1024, cacheDir = cacheDir?.absolutePath))
        e.initialize(); engine = e
        e.createConversation(ConversationConfig(
            systemInstruction = Contents.of(DEVELOPER),
            tools = tools(toolsJson),
            // Greedy, as in training and the evaluation.
            samplerConfig = SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0),
            automaticToolCalling = false,
            prefillPrefaceOnInit = true,
            maxOutputToken = 64,
        )).also { base = it }
    } catch (t: Throwable) {   // UnsatisfiedLinkError (no arm64/x86_64 library) is an Error, not an Exception
        broken = true; close(); null
    }

    /** Frees the engine; the next command starts it again. */
    private fun close() {
        runCatching { base?.close() }; base = null
        runCatching { engine?.close() }; engine = null
    }

    companion object {
        const val SOURCE = "model"
        const val DEVELOPER = "You are a model that can do function calling with the following functions"
        /** What the model's answer is worth to the router; it accepts it only after [IntentRouter]'s checks. */
        const val MODEL_CONFIDENCE = 0.8f
        private const val PARSE_TIMEOUT_MS = 20_000L
        private const val IDLE_CLOSE_MS = 120_000L
        /** The context is 1,024 tokens and the declarations take ~750; long input is cut rather than overflowing. */
        private const val MAX_INPUT_CHARS = 300

        /** One LiteRT-LM tool per entry of tools.json ({"function": {name, description, parameters}}); never executed (no automatic calling). */
        fun tools(json: String) = JSONArray(json).let { a -> (0 until a.length()).map { i -> val f = a.getJSONObject(i).getJSONObject("function").toString()
            tool(object : OpenApiTool { override fun getToolDescriptionJsonString() = f; override fun execute(paramsJsonString: String) = "{}" }) } }

        private val CALL = Regex("""<start_function_call>\s*call:([A-Za-z_][A-Za-z0-9_]*)\s*\{(.*?)\}\s*(?:<end_function_call>|$)""", RegexOption.DOT_MATCHES_ALL)
        private val ARG = Regex("""([A-Za-z_][A-Za-z0-9_]*)\s*:\s*<escape>(.*?)<escape>""", RegexOption.DOT_MATCHES_ALL)

        /**
         * Reads FunctionGemma's own call syntax, which the generic model type returns as text:
         * `<start_function_call>call:request_ride{destination:<escape>MG Road<escape>,vehicle:<escape>AUTO<escape>}<end_function_call>`.
         * Null when there is no call (the router then falls back).
         */
        fun parseCall(text: String): ParsedIntent? {
            val m = CALL.find(text) ?: return null
            val args = ARG.findAll(m.groupValues[2]).associate { it.groupValues[1] to it.groupValues[2].trim() }
            return ParsedIntent(m.groupValues[1], args, MODEL_CONFIDENCE, SOURCE)
        }
    }
}
