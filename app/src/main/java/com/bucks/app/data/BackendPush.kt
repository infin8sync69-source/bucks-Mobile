package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Push notifications (supabase/migrations/push.sql): this phone's Firebase Cloud Messaging token, stored against
 * whoever is signed in. The Edge Function "notify" reads the table when something happens for that person.
 */

/** Stores (or takes over) this phone's token for the signed-in person; called after sign-in and whenever FCM rotates the token. */
suspend fun Backend.registerDeviceToken(token: String, platform: String = "android") {
    client.postgrest.rpc("register_device_token", buildJsonObject { put("p_token", token); put("p_platform", platform) })
}

/** Forgets this phone before sign-out, so the next person to sign in here does not get the previous person's notifications. */
suspend fun Backend.unregisterDeviceToken(token: String) {
    client.postgrest.rpc("unregister_device_token", buildJsonObject { put("p_token", token) })
}

/** The phones currently registered to me (row-level security shows only my own). */
suspend fun Backend.myDeviceTokens(): List<DeviceTokenRow> = client.postgrest.from("device_tokens").select().decodeList()

@Serializable data class DeviceTokenRow(val token: String, @SerialName("profile_id") val profileId: String, val platform: String = "android", @SerialName("updated_at") val updatedAt: String)
