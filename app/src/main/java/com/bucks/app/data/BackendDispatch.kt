package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Dispatch calls on top of [Backend] (schema: supabase/migrations/dispatch.sql): task rows with plain coordinates,
 * online drivers for the map, the driver of a task, "my open task" for resuming, and realtime nudges on `tasks`.
 */

/**
 * A task with its points as lat/lng (view `tasks_geo`); PostgREST would otherwise return geography as EWKB hex.
 * [pin] is only filled for the requester (blank for the driver); [statusAt] is when the status last changed.
 */
@Serializable data class TaskGeoRow(val id: String, val type: String, @SerialName("requester_id") val requesterId: String, @SerialName("order_id") val orderId: String? = null,
    @SerialName("vehicle_kind") val vehicleKind: String, @SerialName("pickup_label") val pickupLabel: String = "", @SerialName("drop_label") val dropLabel: String = "", val km: Double = 0.0,
    val fare: Int = 0, val pin: String = "", val status: String, @SerialName("driver_id") val driverId: String? = null, @SerialName("vehicle_id") val vehicleId: String? = null,
    @SerialName("paid_with") val paidWith: String? = null, @SerialName("created_at") val createdAt: String = "", @SerialName("status_at") val statusAt: String = "",
    @SerialName("pickup_lat") val pickupLat: Double, @SerialName("pickup_lng") val pickupLng: Double, @SerialName("drop_lat") val dropLat: Double, @SerialName("drop_lng") val dropLng: Double,
    @SerialName("driver_lat") val driverLat: Double? = null, @SerialName("driver_lng") val driverLng: Double? = null, @SerialName("order_items") val orderItems: Int? = null,
    /** Delivery only: what the rider takes from the buyer at the door (0 = nothing); null when not readable yet. */
    val collect: Int? = null,
    /** Wrong PINs the driver has tried so far (5 lock the trip); 0 until the server counts them. */
    @SerialName("pin_attempts") val pinAttempts: Int = 0) {
    val pickup get() = LatLng(pickupLat, pickupLng)
    val drop get() = LatLng(dropLat, dropLng)
    val driverAt: LatLng? get() = driverLat?.let { la -> driverLng?.let { LatLng(la, it) } }
    val isDelivery get() = type == "DELIVERY"
}
/** An online driver near a point (`online_drivers_near`). Trust comes from their DRIVER listing, 0/0 without one. */
@Serializable data class NearDriverRow(@SerialName("profile_id") val profileId: String, val kind: String, val lat: Double, val lng: Double, val name: String = "", val model: String = "", val plate: String = "",
    val up: Int = 0, val down: Int = 0)
/** The driver of a task as the requester may see them (`task_driver`); [listingId] is what a review goes to. */
@Serializable data class TaskDriverRow(@SerialName("profile_id") val profileId: String, val name: String = "", val kind: String = "AUTO", val model: String = "", val plate: String = "",
    val up: Int = 0, val down: Int = 0, @SerialName("listing_id") val listingId: String? = null)
@Serializable data class PrivateRow(@SerialName("profile_id") val profileId: String, val phone: String? = null, @SerialName("upi_uri") val upiUri: String? = null)

suspend fun Backend.taskGeo(id: String): TaskGeoRow? = client.postgrest.from("tasks_geo").select { filter { eq("id", id) } }.decodeSingleOrNull()
/** The caller's active task as requester or driver, or null. */
suspend fun Backend.myOpenTask(): TaskGeoRow? = client.postgrest.rpc("my_open_task").decodeList<TaskGeoRow>().firstOrNull()
suspend fun Backend.onlineDriversNear(at: LatLng, radiusM: Int = 5000): List<NearDriverRow> =
    client.postgrest.rpc("online_drivers_near", buildJsonObject { put("p_lat", at.lat); put("p_lng", at.lng); put("radius_m", radiusM) }).decodeList()
suspend fun Backend.taskDriver(taskId: String): TaskDriverRow? = client.postgrest.rpc("task_driver", buildJsonObject { put("p_task", taskId) }).decodeList<TaskDriverRow>().firstOrNull()
suspend fun Backend.myPaymentLink(me: String): String? = client.postgrest.from("profile_private").select { filter { eq("profile_id", me) } }.decodeSingleOrNull<PrivateRow>()?.upiUri?.takeIf { it.isNotBlank() }
suspend fun Backend.clearPaymentLink(me: String) { client.postgrest.from("profile_private").update({ set("upi_uri", null as String?) }) { filter { eq("profile_id", me) } } }
/** Presence off by profile, without needing the vehicle (the presence row is the driver's own). */
suspend fun Backend.setOffline(me: String) { client.postgrest.from("driver_presence").update({ set("online", false) }) { filter { eq("profile_id", me) } } }
@Serializable private data class RingSetting(val key: String, val value: Double)
/** A number from the server's settings table (readable by every signed-in user); null when missing or unreadable. */
suspend fun Backend.settingValue(key: String): Double? = client.postgrest.from("settings").select { filter { eq("key", key) } }.decodeList<RingSetting>().firstOrNull()?.value

/**
 * Who is online from this phone, for the paths that outlive the UI: the location service after Bucks was swiped away
 * from recents, and a ViewModel that is already gone. Set when going online, cleared when going offline.
 */
object Presence {
    @Volatile var meId: String? = null
    /** Presence off, best effort: never throws, gives up after 4 s, and is safe to call twice. */
    suspend fun offline() { val me = meId ?: return; meId = null; withTimeoutOrNull(4_000) { runCatching { Backend.setOffline(me) } } }
}

/** Account deletion on the server: presence off, open tasks cancelled or handed back, phone and UPI link deleted, profile anonymised. */
suspend fun Backend.deleteMyAccount() { client.postgrest.rpc("delete_my_account") }

/** Every change to one task as it happens (row-level security still applies). Close the channel with [Backend.closeChannel]. */
fun Backend.liveTask(id: String): Pair<RealtimeChannel, Flow<Unit>> {
    val channel = client.channel("task-$id-${System.nanoTime()}")
    val flow = channel.postgresChangeFlow<PostgresAction>(schema = "public") { table = "tasks"; filter("id", FilterOperator.EQ, id) }
        .map { }
        .onStart { channel.subscribe() }
    return channel to flow
}
/** A nudge whenever a task is (or becomes) SEARCHING; the driver then polls `open_tasks_near` right away instead of waiting 5 s. */
fun Backend.liveOpenTasks(): Pair<RealtimeChannel, Flow<Unit>> {
    val channel = client.channel("open-tasks-${System.nanoTime()}")
    val flow = channel.postgresChangeFlow<PostgresAction>(schema = "public") { table = "tasks"; filter("status", FilterOperator.EQ, "SEARCHING") }
        .map { }
        .onStart { channel.subscribe() }
    return channel to flow
}
