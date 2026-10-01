package com.bucks.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL

/**
 * City and state for a 6-digit Indian pincode (India Post's public directory), so a delivery address fills itself in.
 * Best effort: offline or an unknown pincode returns null and the person types the two fields.
 */
object Pincode {
    suspend fun lookup(pin: String): Pair<String, String>? {
        if (!Regex("[1-9][0-9]{5}").matches(pin)) return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val c = URL("https://api.postalpincode.in/pincode/$pin").openConnection() as HttpURLConnection
                try {
                    c.connectTimeout = 6_000; c.readTimeout = 8_000
                    if (c.responseCode != 200) null else {
                        val office = (Json.parseToJsonElement(c.inputStream.bufferedReader().use { it.readText() }) as? JsonArray)?.firstOrNull()?.jsonObject?.get("PostOffice")?.jsonArray?.firstOrNull() as? JsonObject
                        val city = office?.get("District")?.jsonPrimitive?.contentOrNull; val state = office?.get("State")?.jsonPrimitive?.contentOrNull
                        if (city.isNullOrBlank() || state.isNullOrBlank()) null else city to state
                    }
                } finally { c.disconnect() }
            }.getOrNull()
        }
    }
}
