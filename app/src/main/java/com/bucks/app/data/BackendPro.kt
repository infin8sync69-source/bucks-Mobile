package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * The Pro profile (supabase/migrations/pro_profile.sql): one professional profile per adult, its sections, and the person's CV files.
 * Row-level security decides what anyone else sees (visibility, hidden sections, blocks); CV rows and files are the owner's only.
 */

@Serializable data class ProProfileRow(
    @SerialName("profile_id") val profileId: String,
    val headline: String = "", val summary: String = "",
    /** WORK, GIGS, HIRING. */
    @SerialName("open_to") val openTo: List<String> = emptyList(),
    @SerialName("years_experience") val years: Int? = null,
    /** FULL_TIME, PART_TIME, CONTRACT, GIG, INTERNSHIP, APPRENTICESHIP. */
    @SerialName("job_types") val jobTypes: List<String> = emptyList(),
    @SerialName("work_radius_km") val radiusKm: Int? = null,
    @SerialName("expected_pay") val expectedPay: String = "", val availability: String = "",
    val languages: List<String> = emptyList(),
    /** EVERYONE (signed in), SYNCED or ONLY_ME. */
    val visibility: String = "EVERYONE",
    /** EXPERIENCE, EDUCATION, SKILLS, CERTIFICATIONS, PREFERENCES, SERVICES. */
    @SerialName("hidden_sections") val hidden: List<String> = emptyList(),
    @SerialName("updated_at") val updatedAt: String? = null,
)

/** [start] and [end] are dates (YYYY-MM-01); [end] null means "still there". */
@Serializable data class ProExperience(val id: String, @SerialName("profile_id") val profileId: String, val title: String, val org: String = "", val location: String = "",
    @SerialName("start_month") val start: String, @SerialName("end_month") val end: String? = null, val description: String = "")
@Serializable data class ProEducation(val id: String, @SerialName("profile_id") val profileId: String, val course: String, val institute: String = "",
    @SerialName("start_year") val startYear: Int? = null, @SerialName("end_year") val endYear: Int? = null, val grade: String = "")
/** [level]: BEGINNER, INTERMEDIATE or EXPERT. */
@Serializable data class ProSkill(val id: String, @SerialName("profile_id") val profileId: String, val name: String, val level: String = "INTERMEDIATE", val years: Int? = null)
@Serializable data class ProCertification(val id: String, @SerialName("profile_id") val profileId: String, val name: String, val issuer: String = "",
    @SerialName("issued_on") val issuedOn: String? = null, @SerialName("expires_on") val expiresOn: String? = null, @SerialName("credential_id") val credentialId: String = "")
/** A CV file in the private docs bucket at [path] (<profile id>/cv-...). */
@Serializable data class ProCv(val id: String, val path: String, @SerialName("file_name") val fileName: String, val mime: String, @SerialName("size_bytes") val size: Long,
    @SerialName("is_primary") val primary: Boolean = false, @SerialName("uploaded_at") val uploadedAt: String = "")

/** Everything a Pro profile screen shows. [profile] null: none yet (or not visible to me). [cvs] is empty for anyone but the owner. */
data class ProBundle(val profile: ProProfileRow?, val experience: List<ProExperience>, val education: List<ProEducation>, val skills: List<ProSkill>,
                     val certifications: List<ProCertification>, val cvs: List<ProCv>, val services: List<ListingRow>)

object ProBackend {
    /** The section tables, by the name the screens use. */
    const val EXPERIENCE = "pro_experience"; const val EDUCATION = "pro_education"; const val SKILLS = "pro_skills"; const val CERTIFICATIONS = "pro_certifications"
    /** The file types a CV may be: PDF, Word .docx, or a photo (the docs bucket takes these). */
    val CV_MIMES = arrayOf("application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "image/jpeg", "image/png")
    const val CV_MAX_BYTES = 10L * 1024 * 1024

    private val db get() = Backend.client.postgrest

    suspend fun load(profileId: String, mine: Boolean): ProBundle = coroutineScope {
        fun byOwner(t: String) = async { db.from(t).select { filter { eq("profile_id", profileId) } } }
        val p = async { db.from("pro_profiles").select { filter { eq("profile_id", profileId) } }.decodeSingleOrNull<ProProfileRow>() }
        val ex = byOwner(EXPERIENCE); val ed = byOwner(EDUCATION); val sk = byOwner(SKILLS); val ce = byOwner(CERTIFICATIONS)
        val cv = async { if (mine) db.from("pro_cvs").select { filter { eq("profile_id", profileId) }; order("uploaded_at", Order.DESCENDING) }.decodeList<ProCv>() else emptyList() }
        // Services I offer: the person's skill pages (live ones for others; all of mine, so I can see what's still in review).
        val sv = async { db.from("listings").select { filter { eq("owner_id", profileId); eq("kind", "SKILL"); if (!mine) eq("status", "LIVE") else neq("status", "DELETED") } }.decodeList<ListingRow>() }
        ProBundle(p.await(),
            ex.await().decodeList<ProExperience>().sortedWith(compareByDescending<ProExperience> { it.end == null }.thenByDescending { it.start }),
            ed.await().decodeList<ProEducation>().sortedByDescending { it.endYear ?: it.startYear ?: 0 },
            sk.await().decodeList<ProSkill>().sortedWith(compareBy({ levelRank(it.level) }, { it.name.lowercase() })),
            ce.await().decodeList<ProCertification>().sortedByDescending { it.issuedOn ?: "" },
            cv.await(), sv.await())
    }
    /** True when [profileId] has a Pro profile I'm allowed to see (row-level security answers). */
    suspend fun visible(profileId: String): Boolean =
        db.from("pro_profiles").select(io.github.jan.supabase.postgrest.query.Columns.list("profile_id")) { filter { eq("profile_id", profileId) } }.decodeList<JsonObject>().isNotEmpty()
    private fun levelRank(l: String) = when (l) { "EXPERT" -> 0; "INTERMEDIATE" -> 1; else -> 2 }

    /** Creates or replaces my Pro profile's own fields ([fields] holds the columns being set). */
    suspend fun saveProfile(me: String, fields: JsonObject) {
        db.from("pro_profiles").upsert(buildJsonObject { put("profile_id", me); fields.forEach { (k, v) -> put(k, v) } })
    }

    /** Adds a row to a section table ([table] is one of the constants above); [fields] without profile_id. */
    suspend fun add(table: String, me: String, fields: JsonObject) { db.from(table).insert(buildJsonObject { put("profile_id", me); fields.forEach { (k, v) -> put(k, v) } }) }
    suspend fun edit(table: String, id: String, fields: JsonObject) { db.from(table).update(fields) { filter { eq("id", id) } } }
    suspend fun remove(table: String, id: String) { db.from(table).delete { filter { eq("id", id) } } }

    /** Uploads a CV to docs/<me>/cv-..., records it, and makes it the main CV when it's the first or [primary] is asked. */
    suspend fun uploadCv(me: String, picked: Picked, primary: Boolean, hasOthers: Boolean): ProCv {
        require(picked.mime in CV_MIMES) { "A CV can be a PDF, a Word .docx file or a photo." }
        require(picked.bytes.size <= CV_MAX_BYTES) { "That file is over 10 MB." }
        val path = "$me/cv-${picked.objectName()}"
        Backend.upload("docs", path, picked.bytes)
        val makePrimary = primary || !hasOthers
        try {
            if (makePrimary) db.from("pro_cvs").update(buildJsonObject { put("is_primary", false) }) { filter { eq("profile_id", me); eq("is_primary", true) } }
            return db.from("pro_cvs").insert(buildJsonObject {
                put("profile_id", me); put("path", path); put("file_name", picked.name.take(200)); put("mime", picked.mime); put("size_bytes", picked.bytes.size.toLong()); put("is_primary", makePrimary)
            }) { select() }.decodeSingle()
        } catch (e: Exception) { runCatching { Backend.deleteFiles("docs", listOf(path)) }; throw e }
    }
    /** One main CV at a time (a unique index keeps it so): clear the old one first. */
    suspend fun setPrimaryCv(me: String, id: String) {
        db.from("pro_cvs").update(buildJsonObject { put("is_primary", false) }) { filter { eq("profile_id", me); eq("is_primary", true) } }
        db.from("pro_cvs").update(buildJsonObject { put("is_primary", true) }) { filter { eq("id", id) } }
    }
    suspend fun deleteCv(cv: ProCv) { db.from("pro_cvs").delete { filter { eq("id", cv.id) } }; runCatching { Backend.deleteFiles("docs", listOf(cv.path)) } }
}
