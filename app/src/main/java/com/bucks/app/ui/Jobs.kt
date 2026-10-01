package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.bucks.app.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Cloud jobs state: a listing's jobs, one job with its applications, my applications, my skill profiles
 * (to apply with) and jobs near me. Screens read the state and call the actions; every action reports a
 * failure as a toast. Follows the pattern of [Social].
 */
class Jobs(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    // ---- a listing's jobs (LISTING_JOBS) ----
    var listing by mutableStateOf<ListingRow?>(null); private set
    var jobs by mutableStateOf<List<JobListRow>>(emptyList()); private set
    /** True when I own or administer the listing whose jobs are shown (or the listing of the open job). */
    var manager by mutableStateOf(false); private set
    var loadingJobs by mutableStateOf(false); private set

    // ---- one job (JOB) ----
    var job by mutableStateOf<JobPageRow?>(null); private set
    /** The job id that was asked for but is not there (closed and not mine, or deleted). */
    var jobMissing by mutableStateOf<String?>(null); private set
    /** Every application on the job for a manager; only mine otherwise (row-level security). */
    var applications by mutableStateOf<List<JobApplicationRow>>(emptyList()); private set
    /** Skill listing id -> listing, for the applicants' skill chips. Pending profiles of other people stay unresolved. */
    val skillProfiles: SnapshotStateMap<String, ListingRow> = mutableStateMapOf()
    var loadingJob by mutableStateOf(false); private set
    val myApplication: JobApplicationRow? get() { val me = social.me?.id ?: return null; return applications.firstOrNull { it.applicantId == me } }

    // ---- me as an applicant ----
    var mySkills by mutableStateOf<List<ListingRow>>(emptyList()); private set
    var myApplications by mutableStateOf<List<MyApplicationRow>>(emptyList()); private set
    var loadingMine by mutableStateOf(false); private set

    // ---- jobs near me (JOBS_NEAR) ----
    var near by mutableStateOf<List<JobNearRow>>(emptyList()); private set
    var loadingNear by mutableStateOf(false); private set

    /** True while a write is in flight, so buttons can't be tapped twice. */
    var busy by mutableStateOf(false); private set

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        val msg = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
        return when {
            msg.contains("duplicate key") -> "You already applied to this job."
            msg.contains("row-level security") -> "You're not allowed to do that."
            else -> msg
        }
    }
    private suspend fun write(block: suspend () -> Unit) { busy = true; try { block() } finally { busy = false } }
    private suspend fun isManager(listingId: String): Boolean { val me = social.me?.id ?: return false; return Backend.members(listingId).any { it.profileId == me && it.role in MANAGER_ROLES } }
    fun nameOf(id: String) = social.nameOf(id)

    // ---------- a listing's jobs ----------
    fun loadListingJobs(listingId: String) = go {
        loadingJobs = true
        try {
            if (listing?.id != listingId) { listing = null; jobs = emptyList(); manager = false }
            listing = Backend.listing(listingId)
            manager = isManager(listingId)
            jobs = Backend.jobsWithCounts(listingId)
        } finally { loadingJobs = false }
    }
    fun postJob(listingId: String, title: String, description: String, pay: String, type: String, then: () -> Unit) = go {
        val me = social.me?.id ?: return@go
        write {
            Backend.postJob(listingId, me, title.trim(), description.trim(), pay.trim(), type)
            toast("Job posted. People nearby can apply now.")
            jobs = Backend.jobsWithCounts(listingId)
            then()
        }
    }
    fun closeJob(jobId: String) = go { write {
        Backend.closeJob(jobId)
        toast("Job closed. No new applications will come in.")
        job?.let { j -> if (j.id == jobId) job = j.copy(open = false) }
        jobs = jobs.map { if (it.id == jobId) it.copy(open = false) else it }
    } }
    fun reopenJob(jobId: String) = go { write {
        Backend.reopenJob(jobId)
        toast("Job reopened. It shows up nearby again.")
        job?.let { j -> if (j.id == jobId) job = j.copy(open = true) }
        jobs = jobs.map { if (it.id == jobId) it.copy(open = true) else it }
    } }

    // ---------- one job ----------
    fun loadJob(jobId: String) = go {
        loadingJob = true
        try {
            if (job?.id != jobId) { job = null; applications = emptyList(); manager = false }
            jobMissing = null
            val page = Backend.jobPage(jobId)
            if (page == null) { jobMissing = jobId; return@go }
            job = page
            manager = isManager(page.listingId)
            val apps = Backend.jobApplications(jobId)
            applications = apps
            social.namesFor(apps.map { it.applicantId })
            val wanted = apps.flatMap { it.skillListingIds }.distinct().filter { it !in skillProfiles }
            Backend.listingsByIds(wanted).forEach { skillProfiles[it.id] = it }
            if (!manager) refreshMySkills()
        } finally { loadingJob = false }
    }
    fun apply(jobId: String, skillIds: List<String>, note: String) = go {
        val me = social.me?.id ?: return@go
        write {
            Backend.apply(jobId, me, skillIds, note.trim())
            toast("Applied. The business will see your application.")
            applications = Backend.jobApplications(jobId)
        }
    }
    fun withdraw(applicationId: String) = go { write {
        Backend.setApplicationStatus(applicationId, "WITHDRAWN")
        toast("Application withdrawn.")
        applications = applications.map { if (it.id == applicationId) it.copy(status = "WITHDRAWN") else it }
        myApplications = myApplications.map { if (it.id == applicationId) it.copy(status = "WITHDRAWN") else it }
    } }
    fun setApplicationStatus(applicationId: String, status: String) = go { write {
        Backend.setApplicationStatus(applicationId, status)
        val who = applications.firstOrNull { it.id == applicationId }?.let { social.nameOf(it.applicantId) } ?: "They"
        toast(when (status) { "SHORTLISTED" -> "$who shortlisted. They can see it in their applications."; "HIRED" -> "$who hired. Close the job when you've filled it."; "REJECTED" -> "$who turned down."; else -> "Updated." })
        applications = applications.map { if (it.id == applicationId) it.copy(status = status) else it }
        job?.let { j -> jobs = jobs.map { if (it.id == j.id) it.copy(newApplications = applications.count { a -> a.status == "APPLIED" }) else it } }
    } }
    /** A manager opens (or reuses) a direct chat with an applicant. Applying lets the business reach them whatever their message setting; blocks still refuse. */
    fun message(applicationId: String, onOpen: (String) -> Unit) = go { onOpen(Backend.startApplicantChat(applicationId)) }
    /** An applicant (or anyone looking at the job) messages the business through its shared listing inbox. */
    fun messageBusiness(listingId: String, onOpen: (String) -> Unit) = go {
        if (messaging) return@go
        messaging = true
        try { onOpen(Backend.startListingChat(listingId)) } finally { messaging = false }
    }
    /** True while the chat with a business is being opened (the button is off, so a double tap can't open it twice). */
    var messaging by mutableStateOf(false); private set

    // ---------- me as an applicant ----------
    suspend fun refreshMySkills() { val me = social.me?.id ?: return; mySkills = Backend.myListings(me).filter { it.kind == "SKILL" } }
    fun loadMySkills() = go { refreshMySkills() }
    fun refreshMyApplications() = go { loadingMine = true; try { myApplications = Backend.myApplications() } finally { loadingMine = false } }

    // ---------- jobs near me ----------
    fun refreshNear() = go { loadingNear = true; try { near = Backend.jobsNear(social.here) } finally { loadingNear = false } }

    fun signedOut() { listing = null; jobs = emptyList(); manager = false; job = null; jobMissing = null; applications = emptyList(); skillProfiles.clear(); mySkills = emptyList(); myApplications = emptyList(); near = emptyList() }

    companion object {
        val MANAGER_ROLES = setOf("OWNER", "ADMIN")
        val TYPES = listOf("FULL_TIME" to "Full time", "PART_TIME" to "Part time", "GIG" to "One-off")
        fun typeLabel(type: String) = TYPES.firstOrNull { it.first == type }?.second ?: type.lowercase().replace('_', ' ').replaceFirstChar { it.uppercase() }
        fun statusLabel(status: String) = when (status) { "APPLIED" -> "Applied"; "SHORTLISTED" -> "Shortlisted"; "HIRED" -> "Hired"; "REJECTED" -> "Not selected"; "WITHDRAWN" -> "Withdrawn"; else -> status }
        /** "450 m" or "2.3 km". */
        fun distance(m: Double) = if (m < 950) "${m.toInt()} m" else "%.1f km".format(m / 1000)
    }
}
