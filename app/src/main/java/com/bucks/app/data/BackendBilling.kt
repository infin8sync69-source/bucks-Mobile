package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Provider licences (Skills, Taxi, Business): one per listing or vehicle, with a code and a VALID TILL date. Read-only status for
 * the owner; schema in supabase/migrations/billing.sql (my_licences).
 *
 * The app never sells a licence, shows its price or links to the payment page (Google Play payments policy): the renewal details
 * reach the provider by SMS, and the server decides from Razorpay's webhooks when a licence is renewed.
 */
@Serializable
data class LicenceRow(
    @SerialName("licence_id") val id: String,
    /** What the provider types on the payment page, e.g. TX7KQ2MP. */
    val code: String,
    @SerialName("listing_id") val listingId: String? = null,
    @SerialName("vehicle_id") val vehicleId: String? = null,
    val subject: String = "",
    @SerialName("plan_code") val planCode: String,
    @SerialName("plan_label") val planLabel: String,
    /** FOUNDING or TRIAL (free period), ACTIVE, GRACE (lapsed, still live) or EXPIRED (paused). */
    val state: String,
    val founding: Boolean = false,
    @SerialName("valid_from") val validFrom: String? = null,
    @SerialName("valid_till") val validTill: String? = null,
    @SerialName("grace_until") val graceUntil: String? = null,
    @SerialName("founding_bonus_until") val foundingBonusUntil: String? = null,
    val paid: Boolean = false,
    /** Chats and orders (pages) or accepted trips (vehicles) in the last 30 days. */
    @SerialName("enquiries_month") val enquiries30d: Int = 0,
)

/** My licences, one per listing or vehicle that has one (none while billing is switched off on the server). */
suspend fun Backend.myLicences(): List<LicenceRow> = client.postgrest.rpc("my_licences").decodeList()
