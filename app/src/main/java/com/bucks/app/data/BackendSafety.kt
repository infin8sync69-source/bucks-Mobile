package com.bucks.app.data

import androidx.annotation.StringRes
import com.bucks.app.R
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Safety and discovery calls added for the social release (supabase/migrations/social_safety.sql): date of birth and age band,
 * guardian consent, reports and the staff queue, people search, and one person's posts.
 */
object BackendSafety {
    private val db get() = Backend.client.postgrest

    /** Sets my date of birth (once) and returns my band: CHILD, TEEN or ADULT. Refused for under-13s while the kids band is off. */
    suspend fun setBirthDate(isoDate: String): String = db.rpc("set_birth_date", buildJsonObject { put("p_date", isoDate) }).decodeAs()
    /** "I agree to the Terms" from the phone screen: records which version was accepted. */
    suspend fun recordTerms(version: String) { db.rpc("record_terms", buildJsonObject { put("p_version", version) }) }
    // ---- Trip safety (trip_safety.sql): trusted contacts, SOS, live trip links, "Are you OK?" ----
    suspend fun trustedContacts(): List<TrustedContact> = db.from("trusted_contacts").select { order("created_at", io.github.jan.supabase.postgrest.query.Order.ASCENDING) }.decodeList()
    suspend fun addTrustedContact(name: String, phone: String) { db.rpc("add_trusted_contact", buildJsonObject { put("p_name", name); put("p_phone", phone) }) }
    suspend fun removeTrustedContact(id: String) { db.rpc("remove_trusted_contact", buildJsonObject { put("p_id", id) }) }
    /** The token of my trip's live link (TripSafety.tripUrl makes the page address). */
    suspend fun tripShareLink(taskId: String): String = db.rpc("trip_share_link", buildJsonObject { put("p_task", taskId) }).decodeAs()
    /** Never refused for a signed-in person. [taskId] null: an SOS outside a trip. */
    suspend fun raiseSos(taskId: String?, lat: Double?, lng: Double?): SosResult =
        db.rpc("raise_sos", buildJsonObject { put("p_task", taskId); put("p_lat", lat); put("p_lng", lng) }).decodeAs()
    suspend fun cancelSos(id: String) { db.rpc("cancel_sos", buildJsonObject { put("p_sos", id) }) }
    suspend fun myRideAlerts(taskId: String): List<RideAlert> = db.rpc("my_ride_alerts", buildJsonObject { put("p_task", taskId) }).decodeList()
    suspend fun answerRideAlert(taskId: String, ok: Boolean) { db.rpc("answer_ride_alert", buildJsonObject { put("p_task", taskId); put("p_ok", ok) }) }
    suspend fun sosQueue(): List<SosQueueRow> = db.rpc("sos_queue").decodeList()
    suspend fun closeSos(id: String, note: String) { db.rpc("close_sos", buildJsonObject { put("p_sos", id); put("p_note", note) }) }

    /** The Terms version everyone must have accepted (server setting), the one I accepted, and whether the app must ask again. */
    suspend fun termsStatus(): TermsStatus? = runCatching { db.rpc("terms_status").decodeAs<TermsStatus>() }.getOrNull()
    /** Country (ISO code) and app language for my profile: currency, payments and the language of notifications. */
    suspend fun setMyLocale(country: String?, language: String?) { db.rpc("set_my_locale", buildJsonObject { put("p_country", country); put("p_language", language) }) }
    suspend fun mySafety(): SafetyRow? = db.rpc("my_safety").decodeList<SafetyRow>().firstOrNull()
    suspend fun recordGuardianConsent(name: String, phone: String, relation: String) {
        db.rpc("record_guardian_consent", buildJsonObject { put("p_name", name); put("p_phone", phone); put("p_relation", relation) })
    }

    /** [kind]: POST, COMMENT, MOMENT, MESSAGE or PROFILE. [reason]: one of [ReportReason]. Reporting the same thing twice is a no-op. */
    suspend fun report(kind: String, targetId: String, reason: String, detail: String) {
        db.rpc("report_content", buildJsonObject { put("p_kind", kind); put("p_target", targetId); put("p_reason", reason); put("p_detail", detail) })
    }
    suspend fun reportQueue(): List<ReportQueueRow> = db.rpc("report_queue").decodeList()
    /** [action]: REMOVE, BAN or DISMISS. Staff only. */
    suspend fun reviewReport(id: String, action: String) { db.rpc("review_report", buildJsonObject { put("p_report", id); put("p_action", action) }) }

    suspend fun searchPeople(q: String): List<PersonHit> = db.rpc("search_people", buildJsonObject { put("q", q) }).decodeList()
    suspend fun postsBy(author: String, beforeIso: String? = null): List<FeedRow> =
        db.rpc("posts_by", buildJsonObject { put("p_author", author); beforeIso?.let { put("before", it) } }).decodeList()
}

@Serializable data class TrustedContact(val id: String, val name: String, val phone: String)
@Serializable data class SosContact(val name: String, val phone: String)
@Serializable data class SosResult(@SerialName("sos_id") val sosId: String, @SerialName("share_token") val shareToken: String? = null, val message: String = "", val contacts: List<SosContact> = emptyList())
@Serializable data class RideAlert(val id: String, val kind: String)
@Serializable data class SosQueueRow(val id: String, @SerialName("created_at") val createdAt: String, val role: String, val name: String = "", val phone: String? = null,
                                     val lat: Double? = null, val lng: Double? = null, @SerialName("task_id") val taskId: String? = null, @SerialName("task_status") val taskStatus: String? = null,
                                     @SerialName("other_name") val otherName: String? = null, @SerialName("other_phone") val otherPhone: String? = null,
                                     val vehicle: String? = null, @SerialName("trip_link") val tripLink: String? = null)
@Serializable data class TermsStatus(val current: String? = null, val accepted: String? = null, val needed: Boolean = false)
@Serializable data class SafetyRow(@SerialName("age_band") val ageBand: String = "UNKNOWN", @SerialName("birth_date_set") val birthDateSet: Boolean = false,
                                   @SerialName("guardian_consent") val guardianConsent: Boolean? = null)
@Serializable data class PersonHit(val id: String, val name: String, @SerialName("short_code") val shortCode: String, val area: String = "", val mutual: Int = 0, val synced: Boolean = false)
@Serializable data class ReportQueueRow(val id: String, @SerialName("target_kind") val targetKind: String, @SerialName("target_id") val targetId: String,
                                        @SerialName("target_owner") val targetOwner: String? = null, @SerialName("owner_name") val ownerName: String? = null,
                                        val reason: String, val detail: String = "", val reporters: Int = 1, @SerialName("created_at") val createdAt: String,
                                        val preview: String? = null)

/** Report reasons, as the server's reports.reason check lists them, with the words people see. */
enum class ReportReason(@StringRes private val labelRes: Int, private val hintRes: Int?) {
    SPAM(R.string.g3_report_spam, R.string.g3_report_spam_hint),
    HARASSMENT(R.string.g3_report_harassment, R.string.g3_report_harassment_hint),
    HATE(R.string.g3_report_hate, R.string.g3_report_hate_hint),
    NUDITY(R.string.g3_report_nudity, R.string.g3_report_nudity_hint),
    VIOLENCE(R.string.g3_report_violence, R.string.g3_report_violence_hint),
    SELF_HARM(R.string.g3_report_self_harm, R.string.g3_report_self_harm_hint),
    CHILD_SAFETY(R.string.g3_report_child_safety, R.string.g3_report_child_safety_hint),
    SCAM(R.string.g3_report_scam, R.string.g3_report_scam_hint),
    IMPERSONATION(R.string.g3_report_impersonation, R.string.g3_report_impersonation_hint),
    OTHER(R.string.g3_report_other, null),
    ;
    val label: String get() = Str.get(labelRes)
    val hint: String get() = hintRes?.let { Str.get(it) }.orEmpty()
}
