package com.bucks.app.data

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

@Serializable data class SafetyRow(@SerialName("age_band") val ageBand: String = "UNKNOWN", @SerialName("birth_date_set") val birthDateSet: Boolean = false,
                                   @SerialName("guardian_consent") val guardianConsent: Boolean? = null)
@Serializable data class PersonHit(val id: String, val name: String, @SerialName("short_code") val shortCode: String, val area: String = "", val mutual: Int = 0, val synced: Boolean = false)
@Serializable data class ReportQueueRow(val id: String, @SerialName("target_kind") val targetKind: String, @SerialName("target_id") val targetId: String,
                                        @SerialName("target_owner") val targetOwner: String? = null, @SerialName("owner_name") val ownerName: String? = null,
                                        val reason: String, val detail: String = "", val reporters: Int = 1, @SerialName("created_at") val createdAt: String,
                                        val preview: String? = null)

/** Report reasons, as the server's reports.reason check lists them, with the words people see. */
enum class ReportReason(val label: String, val hint: String) {
    SPAM("Spam", "Ads, scams to click, the same thing over and over"),
    HARASSMENT("Bullying or harassment", "Picking on someone, threats, unwanted contact"),
    HATE("Hate speech", "Attacks on people for who they are"),
    NUDITY("Nudity or sexual content", "Photos, videos or messages that are sexual"),
    VIOLENCE("Violence", "Threats, graphic violence, dangerous acts"),
    SELF_HARM("Self-harm or suicide", "Someone may be at risk"),
    CHILD_SAFETY("A child may be at risk", "Grooming, exploitation, a child in danger"),
    SCAM("Fraud or scam", "Asking for money, fake offers"),
    IMPERSONATION("Pretending to be someone", "A fake account of a real person"),
    OTHER("Something else", ""),
}
