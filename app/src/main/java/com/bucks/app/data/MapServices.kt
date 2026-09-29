package com.bucks.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Place search, address lookup and road routes for the live map, all on OpenStreetMap data and free of keys:
 *  - Photon (photon.komoot.io): search as you type, biased to where the person is, and "what's at this point".
 *  - OSRM (router.project-osrm.org): road distance, travel time and the route line between two points.
 * Both public servers are for light use (fine for the pilot, not for thousands of users). To move to a paid provider
 * (Ola Maps, Google Maps Platform, Mappls), replace the three functions below; nothing else in the app changes.
 * Every call fails soft (null / empty), so the app falls back to straight lines and the built-in place list.
 */
object MapServices {
    data class PlaceHit(val name: String, val detail: String, val at: LatLng)
    data class RoadRoute(val km: Double, val minutes: Int, val points: List<LatLng>)

    private val json = Json { ignoreUnknownKeys = true }
    private const val UA = "Bucks-Android/1.0 (com.bucks.app)"

    private suspend fun get(url: String): JsonElement? = withContext(Dispatchers.IO) {
        runCatching {
            val c = URL(url).openConnection() as HttpURLConnection
            try {
                c.connectTimeout = 8_000; c.readTimeout = 10_000
                c.setRequestProperty("User-Agent", UA); c.setRequestProperty("Accept", "application/json")
                if (c.responseCode != 200) null else json.parseToJsonElement(c.inputStream.bufferedReader().use { it.readText() })
            } finally { c.disconnect() }
        }.getOrNull()
    }
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    private fun JsonObject.s(k: String) = this[k]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

    private fun hitOf(f: JsonObject): PlaceHit? {
        val c = f["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return null
        val lng = c.getOrNull(0)?.jsonPrimitive?.doubleOrNull ?: return null; val lat = c.getOrNull(1)?.jsonPrimitive?.doubleOrNull ?: return null
        val p = f["properties"]?.jsonObject ?: return null
        val street = listOfNotNull(p.s("housenumber"), p.s("street")).joinToString(" ").ifBlank { null }
        val name = p.s("name") ?: street ?: p.s("district") ?: p.s("city") ?: return null
        val detail = listOfNotNull(street?.takeIf { it != name }, p.s("locality") ?: p.s("district"), p.s("city"), p.s("state")).distinct().filter { it != name }.joinToString(", ")
        return PlaceHit(name, detail, LatLng(lat, lng))
    }

    /** Nominatim (OpenStreetMap's own search) result row, used when Photon can't be reached. */
    private fun nominatimHit(o: JsonObject): PlaceHit? {
        val lat = o.s("lat")?.toDoubleOrNull() ?: return null; val lon = o.s("lon")?.toDoubleOrNull() ?: return null
        val full = o.s("display_name") ?: return null
        val name = o.s("name") ?: full.substringBefore(",").trim()
        return PlaceHit(name, full.substringAfter(",", "").trim().split(",").map { it.trim() }.filter { it.isNotBlank() }.take(3).joinToString(", "), LatLng(lat, lon))
    }

    /** Places matching [query], nearest to [near] first. Null when no search server could be reached (so "offline" isn't shown as "no places"). */
    suspend fun searchOrNull(query: String, near: LatLng): List<PlaceHit>? {
        val q = query.trim(); if (q.length < 3) return emptyList()
        val photon = get("https://photon.komoot.io/api/?q=${enc(q)}&lat=${near.lat}&lon=${near.lng}&limit=8&lang=en") as? JsonObject
        val a = photon?.let { o -> (o["features"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::hitOf) } }
        if (!a.isNullOrEmpty()) return a.distinctBy { it.name + it.detail }.sortedBy { Geo.distanceKm(near, it.at) }
        val nom = get("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=${enc(q)}") as? JsonArray
        val b = nom?.mapNotNull { (it as? JsonObject)?.let(::nominatimHit) }
        if (b != null) return b.distinctBy { it.name + it.detail }.sortedBy { Geo.distanceKm(near, it.at) }
        return if (a != null) emptyList() else null
    }

    /** Places matching [query], nearest first; empty when offline. */
    suspend fun search(query: String, near: LatLng): List<PlaceHit> = searchOrNull(query, near).orEmpty()

    /** A short name for the point: "12th Main, Indiranagar" or a landmark; null when offline. */
    suspend fun label(at: LatLng): String? {
        val o = get("https://photon.komoot.io/reverse?lat=${at.lat}&lon=${at.lng}&limit=1&lang=en") as? JsonObject ?: return null
        val h = (o["features"] as? JsonArray)?.firstOrNull()?.let { it as? JsonObject }?.let(::hitOf) ?: return null
        val area = h.detail.split(", ").firstOrNull { it.isNotBlank() }
        return listOfNotNull(h.name, area?.takeIf { it != h.name }).joinToString(", ")
    }

    /** Driving route by road; null when offline or no route (the caller draws a straight line instead). */
    suspend fun route(from: LatLng, to: LatLng): RoadRoute? {
        val o = get("https://router.project-osrm.org/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}?overview=full&geometries=geojson") as? JsonObject ?: return null
        val r = (o["routes"] as? JsonArray)?.firstOrNull() as? JsonObject ?: return null
        val metres = r["distance"]?.jsonPrimitive?.doubleOrNull ?: return null; val seconds = r["duration"]?.jsonPrimitive?.doubleOrNull ?: return null
        val pts = r["geometry"]?.jsonObject?.get("coordinates")?.jsonArray?.mapNotNull { p ->
            val a = p as? JsonArray ?: return@mapNotNull null
            val lng = a.getOrNull(0)?.jsonPrimitive?.doubleOrNull; val lat = a.getOrNull(1)?.jsonPrimitive?.doubleOrNull
            if (lat != null && lng != null) LatLng(lat, lng) else null
        }.orEmpty()
        return RoadRoute(Math.round(metres / 100.0) / 10.0, maxOf(1, Math.round(seconds / 60.0).toInt()), pts.ifEmpty { listOf(from, to) })
    }
}
