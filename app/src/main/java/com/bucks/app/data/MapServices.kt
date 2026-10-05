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
    data class Step(val text: String, val metres: Double, val at: LatLng, val type: String, val modifier: String)
    data class RoadRoute(val km: Double, val minutes: Int, val points: List<LatLng>, val steps: List<Step> = emptyList())

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

    private val token get() = com.bucks.app.BuildConfig.MAPBOX_TOKEN

    private fun mapboxHit(f: JsonObject): PlaceHit? {
        val c = f["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return null
        val lng = c.getOrNull(0)?.jsonPrimitive?.doubleOrNull ?: return null; val lat = c.getOrNull(1)?.jsonPrimitive?.doubleOrNull ?: return null
        val p = f["properties"]?.jsonObject ?: return null
        val name = p.s("name") ?: return null
        return PlaceHit(name, p.s("place_formatted").orEmpty(), LatLng(lat, lng))
    }

    /** Places matching [query], nearest to [near] first. Null when no search server could be reached (so "offline" isn't shown as "no places"). */
    suspend fun searchOrNull(query: String, near: LatLng): List<PlaceHit>? {
        val q = query.trim(); if (q.length < 3) return emptyList()
        if (token.isNotBlank()) {
            val m = get("https://api.mapbox.com/search/geocode/v6/forward?q=${enc(q)}&proximity=${near.lng},${near.lat}&limit=8&language=en&access_token=$token") as? JsonObject
            val hits = m?.let { o -> (o["features"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::mapboxHit) } }
            if (!hits.isNullOrEmpty()) return hits.distinctBy { it.name + it.detail }
        }
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

    /** A short name for the point: "12th Main, Indiranagar" or a landmark; null when offline. Mapbox when a token is built in (the public
     *  Photon server is only a fallback: it is not meant for an app's traffic, and this runs every time a pick-up pin settles). */
    suspend fun label(at: LatLng): String? {
        val h = (if (token.isNotBlank()) mapboxPlaceAt(at) else null) ?: photonPlaceAt(at) ?: return null
        val area = h.detail.split(", ").firstOrNull { it.isNotBlank() }
        return listOfNotNull(h.name, area?.takeIf { it != h.name }).joinToString(", ")
    }
    private suspend fun mapboxPlaceAt(at: LatLng): PlaceHit? {
        val o = get("https://api.mapbox.com/search/geocode/v6/reverse?longitude=${at.lng}&latitude=${at.lat}&types=address,street,neighborhood,locality,place&language=en&access_token=$token") as? JsonObject
        return (o?.get("features") as? JsonArray)?.firstNotNullOfOrNull { (it as? JsonObject)?.let(::mapboxHit) }
    }
    private suspend fun photonPlaceAt(at: LatLng): PlaceHit? {
        val o = get("https://photon.komoot.io/reverse?lat=${at.lat}&lon=${at.lng}&limit=1&lang=en") as? JsonObject ?: return null
        return (o["features"] as? JsonArray)?.firstOrNull()?.let { it as? JsonObject }?.let(::hitOf)
    }

    /** Road route for [profile] (driving, driving-traffic, cycling, walking) with its turn-by-turn steps; null when offline or no route (the caller draws a straight line instead). */
    suspend fun route(from: LatLng, to: LatLng, profile: String = "driving"): RoadRoute? {
        val xy = "${from.lng},${from.lat};${to.lng},${to.lat}"
        if (token.isNotBlank()) {
            val m = get("https://api.mapbox.com/directions/v5/mapbox/$profile/$xy?overview=full&geometries=geojson&steps=true&language=en&access_token=$token") as? JsonObject
            parseRoute(m, from, to)?.let { return it }
        }
        val host = when { profile.startsWith("cycling") -> "https://routing.openstreetmap.de/routed-bike"; profile.startsWith("walking") -> "https://routing.openstreetmap.de/routed-foot"; else -> "https://router.project-osrm.org" }
        return parseRoute(get("$host/route/v1/driving/$xy?overview=full&geometries=geojson&steps=true") as? JsonObject, from, to)
    }

    private fun words(type: String, mod: String, name: String): String {
        val onto = if (name.isNotBlank()) " onto $name" else ""
        return when (type) {
            "depart" -> if (name.isNotBlank()) "Head out on $name" else "Start"
            "arrive" -> "You have arrived"
            "roundabout", "rotary", "roundabout turn" -> "Take the roundabout$onto"
            "merge" -> "Merge$onto"
            "fork" -> "Keep ${mod.ifBlank { "straight" }} at the fork$onto"
            "end of road" -> "At the end of the road, turn ${mod.ifBlank { "ahead" }}$onto"
            "on ramp", "off ramp" -> "Take the ramp$onto"
            "new name", "continue" -> if (mod == "uturn") "Make a U-turn" else "Continue$onto"
            else -> if (mod == "uturn") "Make a U-turn" else if (mod.isBlank() || mod == "straight") "Continue straight$onto" else "Turn $mod$onto"
        }
    }

    /** Mapbox and OSRM answer alike: routes[0] with distance (m), duration (s), a GeoJSON line and legs[].steps[] (maneuver with type, modifier, location, and Mapbox's own instruction text). */
    private fun parseRoute(o: JsonObject?, from: LatLng, to: LatLng): RoadRoute? {
        val r = (o?.get("routes") as? JsonArray)?.firstOrNull() as? JsonObject ?: return null
        val metres = r["distance"]?.jsonPrimitive?.doubleOrNull ?: return null; val seconds = r["duration"]?.jsonPrimitive?.doubleOrNull ?: return null
        val pts = r["geometry"]?.jsonObject?.get("coordinates")?.jsonArray?.mapNotNull { p ->
            val a = p as? JsonArray ?: return@mapNotNull null
            val lng = a.getOrNull(0)?.jsonPrimitive?.doubleOrNull; val lat = a.getOrNull(1)?.jsonPrimitive?.doubleOrNull
            if (lat != null && lng != null) LatLng(lat, lng) else null
        }.orEmpty()
        val steps = (r["legs"] as? JsonArray).orEmpty().flatMap { leg -> ((leg as? JsonObject)?.get("steps") as? JsonArray).orEmpty() }.mapNotNull { st ->
            val so = st as? JsonObject ?: return@mapNotNull null; val mv = so["maneuver"] as? JsonObject ?: return@mapNotNull null
            val loc = mv["location"]?.jsonArray ?: return@mapNotNull null
            val lng = loc.getOrNull(0)?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null; val lat = loc.getOrNull(1)?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
            val type = mv.s("type").orEmpty(); val mod = mv.s("modifier").orEmpty()
            Step(mv.s("instruction") ?: words(type, mod, so.s("name").orEmpty()), so["distance"]?.jsonPrimitive?.doubleOrNull ?: 0.0, LatLng(lat, lng), type, mod)
        }
        return RoadRoute(Math.round(metres / 100.0) / 10.0, maxOf(1, Math.round(seconds / 60.0).toInt()), pts.ifEmpty { listOf(from, to) }, steps)
    }
}
