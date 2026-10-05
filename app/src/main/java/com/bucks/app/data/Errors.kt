package com.bucks.app.data

import io.github.jan.supabase.exceptions.RestException
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerializationException

/** Statuses that say nothing about the request itself: an expired or withheld token (401), a timeout (408), rate limiting (429). Retry them like a lost connection. */
private val TRANSIENT_STATUS = setOf(401, 408, 429)

/** True when the server answered and said no (its message is ours to show); false for a lost connection, a timeout, a gateway or server error (5xx), an expired token or a bad reply. */
fun isServerRefusal(e: Throwable) = e is RestException && e.statusCode in 400..499 && e.statusCode !in TRANSIENT_STATUS

/** True when no usable answer came back: no signal, a timeout, a 5xx/401/429 or a dropped connection. The action may or may not have reached the server. */
fun isTransportError(e: Throwable) = !isServerRefusal(e) && e !is SerializationException && e !is CancellationException

/** Our own database errors come back wrapped; show just the sentence we wrote. Connection problems get one plain sentence instead of an exception name. */
fun friendlyError(e: Throwable): String {
    if (isTransportError(e)) return "Couldn't reach Bucks. Check your connection and try again."
    val m = e.message ?: return "Something went wrong. Try again."
    val text = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(m)?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\\\", "\\") ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    return text.trim().replaceFirstChar { it.uppercase() }.ifBlank { "Something went wrong. Try again." }
}
