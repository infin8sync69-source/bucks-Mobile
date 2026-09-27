package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Jobs: reads that need more than the plain tables give (supabase/migrations/jobs.sql).
 * Writes stay on [Backend]: postJob, closeJob, apply, setApplicationStatus.
 */

/** A job with its application counts (view jobs_with_counts). Counts follow row-level security: only managers see everyone's. */
@Serializable data class JobListRow(val id: String, @SerialName("listing_id") val listingId: String, val title: String, val description: String = "", val pay: String = "",
    @SerialName("job_type") val jobType: String = "FULL_TIME", val open: Boolean = true, @SerialName("created_by") val createdBy: String, @SerialName("created_at") val createdAt: String,
    val applications: Int = 0, @SerialName("new_applications") val newApplications: Int = 0)
/** One job with its business (function job_page). */
@Serializable data class JobPageRow(val id: String, @SerialName("listing_id") val listingId: String, @SerialName("listing_title") val listingTitle: String, val area: String = "",
    val title: String, val description: String = "", val pay: String = "", @SerialName("job_type") val jobType: String = "FULL_TIME", val open: Boolean = true, @SerialName("created_at") val createdAt: String)
/** An open job near a point (function jobs_near). */
@Serializable data class JobNearRow(val id: String, @SerialName("listing_id") val listingId: String, @SerialName("listing_title") val listingTitle: String, val area: String = "",
    val title: String, val pay: String = "", @SerialName("job_type") val jobType: String = "FULL_TIME", @SerialName("created_at") val createdAt: String, @SerialName("distance_m") val distanceM: Double = 0.0)
/** One of my applications with the job and business names (function my_applications). */
@Serializable data class MyApplicationRow(val id: String, @SerialName("job_id") val jobId: String, val status: String, val note: String = "", @SerialName("created_at") val createdAt: String,
    @SerialName("job_title") val jobTitle: String, @SerialName("job_open") val jobOpen: Boolean = true, val pay: String = "", @SerialName("job_type") val jobType: String = "FULL_TIME",
    @SerialName("listing_id") val listingId: String, @SerialName("listing_title") val listingTitle: String, val area: String = "")
/** An application row with its date (table applications; ApplicationRow in Backend.kt has no created_at). */
@Serializable data class JobApplicationRow(val id: String, @SerialName("job_id") val jobId: String, @SerialName("applicant_id") val applicantId: String,
    @SerialName("skill_listing_ids") val skillListingIds: List<String> = emptyList(), val note: String = "", val status: String, @SerialName("created_at") val createdAt: String)

suspend fun Backend.jobsWithCounts(listingId: String): List<JobListRow> =
    client.postgrest.from("jobs_with_counts").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()
suspend fun Backend.jobPage(jobId: String): JobPageRow? =
    client.postgrest.rpc("job_page", buildJsonObject { put("p_job", jobId) }).decodeList<JobPageRow>().firstOrNull()
suspend fun Backend.jobsNear(at: LatLng, radiusM: Int = 15_000): List<JobNearRow> =
    client.postgrest.rpc("jobs_near", buildJsonObject { put("lat", at.lat); put("lng", at.lng); put("radius_m", radiusM) }).decodeList()
suspend fun Backend.myApplications(): List<MyApplicationRow> = client.postgrest.rpc("my_applications").decodeList()
/** Applications on a job, oldest first. Row-level security returns them all to a manager and only mine otherwise. */
suspend fun Backend.jobApplications(jobId: String): List<JobApplicationRow> =
    client.postgrest.from("applications").select { filter { eq("job_id", jobId) }; order("created_at", Order.ASCENDING) }.decodeList()
suspend fun Backend.reopenJob(id: String) { client.postgrest.from("jobs").update({ set("open", true) }) { filter { eq("id", id) } } }
/** Listings by id in one call; pending ones that are not mine stay hidden by row-level security. */
suspend fun Backend.listingsByIds(ids: Collection<String>): List<ListingRow> =
    if (ids.isEmpty()) emptyList() else client.postgrest.from("listings").select { filter { isIn("id", ids.toList()) } }.decodeList()
