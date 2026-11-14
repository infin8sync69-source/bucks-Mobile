package com.bucks.app.data

import io.github.jan.supabase.exceptions.RestException
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerializationException
import com.bucks.app.R

/** Statuses that say nothing about the request itself: an expired or withheld token (401), a timeout (408), rate limiting (429). Retry them like a lost connection. */
private val TRANSIENT_STATUS = setOf(401, 408, 429)

/** True when the server answered and said no (its message is ours to show); false for a lost connection, a timeout, a gateway or server error (5xx), an expired token or a bad reply. */
fun isServerRefusal(e: Throwable) = e is RestException && e.statusCode in 400..499 && e.statusCode !in TRANSIENT_STATUS

/** True when no usable answer came back: no signal, a timeout, a 5xx/401/429 or a dropped connection. The action may or may not have reached the server. */
fun isTransportError(e: Throwable) = !isServerRefusal(e) && e !is SerializationException && e !is CancellationException

/**
 * The stable code a server function attached to its refusal (`raise exception ... using detail = 'BK_...'`), or null. Decide on this,
 * never on the sentence: the sentence is for people and may be reworded or translated.
 */
fun errorCode(e: Throwable): String? = Regex("\\bBK_[A-Z_]+\\b").find(listOfNotNull((e as? RestException)?.description, e.message).joinToString("\n"))?.value

/** Our own database errors come back wrapped; show just the sentence we wrote. Connection problems get one plain sentence instead of an exception name. */
fun friendlyError(e: Throwable): String {
    if (isTransportError(e)) return Str.get(R.string.g6_err_offline)
    val m = e.message ?: return Str.get(R.string.g6_err_generic)
    val text = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(m)?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\\\", "\\") ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    return text.trim().replaceFirstChar { it.uppercase() }.ifBlank { Str.get(R.string.g6_err_generic) }
}
