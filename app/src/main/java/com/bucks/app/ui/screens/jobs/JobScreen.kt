package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Storefront
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.bucks.app.data.JobApplicationRow
import com.bucks.app.data.JobPageRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Jobs
import com.bucks.app.ui.components.*

/**
 * One job (Routes.JOB). Managers of the business see and decide on the applications; everyone else can apply
 * with their skill profiles, follow their application and withdraw it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JobScreen(vm: BucksViewModel, jobId: String, onBack: () -> Unit, onOpenListing: (String) -> Unit, onOpenChat: (String) -> Unit) {
    val jobs = vm.jobs
    LaunchedEffect(jobId) { jobs.loadJob(jobId) }
    val job = jobs.job?.takeIf { it.id == jobId }
    val manager = job != null && jobs.manager
    var applySheet by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<Confirm?>(null) }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(job?.title ?: "Job", onBack = onBack, actions = { IconButton({ jobs.loadJob(jobId) }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        when {
            job == null && jobs.jobMissing == jobId -> Column(Modifier.padding(Gutter)) {
                Text("This job isn't available", style = MaterialTheme.typography.titleMedium)
                Muted("It was closed or removed by the business. Jobs you applied to stay under My applications.", Modifier.padding(top = 6.dp))
                SmallButton("Go back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack)
            }
            job == null -> JobsLoading("Loading the job…")
            else -> Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter, vertical = 8.dp)) {
                JobDetails(job)
                BusinessCard(job) { onOpenListing(job.listingId) }
                if (manager) ManagerSection(vm, job, onOpenListing, onOpenChat, onConfirm = { confirm = it })
                else ApplicantSection(vm, job, onApply = { applySheet = true }, onOpenChat = onOpenChat, onConfirm = { confirm = it })
                Spacer(Modifier.height(32.dp))
            }
        }
    }
    if (applySheet && job != null) ApplySheet(vm, job) { applySheet = false }
    confirm?.let { c -> AlertDialog(onDismissRequest = { confirm = null }, title = { Text(c.title) }, text = { Text(c.text) },
        confirmButton = { TextButton({ confirm = null; c.run() }) { Text(c.button, color = if (c.destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary) } },
        dismissButton = { TextButton({ confirm = null }) { Text("Cancel") } }) }
}

/** A question asked before an action that can't be taken back. */
private class Confirm(val title: String, val text: String, val button: String, val destructive: Boolean = false, val run: () -> Unit)

@Composable
private fun JobDetails(job: JobPageRow) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) { if (job.open) JobTypePill(job.jobType) else PillGrey("Closed"); Spacer(Modifier.width(8.dp)); Muted("Posted ${timeSince(job.createdAt)}") }
    Text(job.title, style = MaterialTheme.typography.headlineSmall)
    Text(job.pay.ifBlank { "Pay on request" }, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 4.dp))
    if (job.description.isNotBlank()) Text(job.description, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
    else Muted("The business didn't add details. Message them or open their page to ask.", Modifier.padding(top = 12.dp))
}

@Composable
private fun BusinessCard(job: JobPageRow, onClick: () -> Unit) {
    BucksCard(Modifier.padding(top = 16.dp), onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(icon = Icons.Rounded.Storefront)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(job.listingTitle, style = MaterialTheme.typography.titleMedium); Muted(job.area.ifBlank { "Open the business page for reviews and directions" }) }
            Icon(Icons.Rounded.ChevronRight, "Open business", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/* ---------- the business side: applications and decisions ---------- */

@Composable
private fun ManagerSection(vm: BucksViewModel, job: JobPageRow, onOpenListing: (String) -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs
    val apps = jobs.applications.filter { it.jobId == job.id }
    val active = apps.filter { it.status != "WITHDRAWN" }; val withdrawn = apps.filter { it.status == "WITHDRAWN" }
    SectionTitle(when (active.size) { 0 -> "Applications"; 1 -> "1 application"; else -> "${active.size} applications" }, Modifier.padding(top = 24.dp, bottom = 4.dp))
    if (jobs.loadingJob && apps.isEmpty()) JobsLoading("Loading applications…")
    else if (active.isEmpty()) Muted(if (job.open) "Nobody has applied yet. The job is visible to people within 15 km; give it a day or two." else "Nobody applied before the job was closed.", Modifier.padding(vertical = 8.dp))
    active.sortedWith(compareBy<JobApplicationRow> { statusRank(it.status) }.thenBy { it.createdAt }).forEach { a -> ApplicationCard(vm, a, onOpenListing, onOpenChat, onConfirm) }
    if (withdrawn.isNotEmpty()) Muted("${withdrawn.size} withdrew their application.", Modifier.padding(top = 8.dp))

    SectionTitle("This job", Modifier.padding(top = 24.dp, bottom = 4.dp))
    if (job.open) {
        Muted("Hiring someone doesn't close the job. Close it once you have the people you need; you can reopen it later.")
        BadButton(if (jobs.busy) "Working…" else "Close this job", Modifier.padding(top = 8.dp)) {
            if (!jobs.busy) onConfirm(Confirm("Close this job?", "It disappears from Jobs near me and nobody new can apply. People who already applied keep their status, and you can still shortlist or hire them.", "Close job", destructive = true) { jobs.closeJob(job.id) })
        }
    } else {
        Muted("This job is closed. Nobody new can apply, but you can still decide on the applications above.")
        SmallButton("Reopen job", Modifier.padding(top = 10.dp), tonal = true, enabled = !jobs.busy) { jobs.reopenJob(job.id) }
    }
}

private fun statusRank(s: String) = when (s) { "HIRED" -> 0; "SHORTLISTED" -> 1; "APPLIED" -> 2; "REJECTED" -> 3; else -> 4 }

@Composable
private fun ApplicationCard(vm: BucksViewModel, a: JobApplicationRow, onOpenListing: (String) -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs; val name = jobs.nameOf(a.applicantId)
    BucksCard(Modifier.padding(top = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name.ifBlank { "?" }), size = 40)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(name, style = MaterialTheme.typography.titleMedium); Muted("Applied ${timeSince(a.createdAt)}") }
            ApplicationStatusPill(a.status)
        }
        if (a.note.isNotBlank()) Text(a.note, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        if (a.skillListingIds.isNotEmpty()) {
            Spacer(Modifier.height(10.dp)); Label("Skill profiles")
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                a.skillListingIds.forEach { id -> val l = jobs.skillProfiles[id]
                    if (l != null) Chip(l.title + (if (l.status != "LIVE") " · not live yet" else "")) { onOpenListing(id) }
                    else Chip("Skill profile not public yet") { vm.toast("Their skill profile isn't live yet, so it can't be opened. Message them to ask about it.") } }
            }
        } else Muted("Applied without a skill profile.", Modifier.padding(top = 8.dp))
        Row(Modifier.padding(top = 12.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val busy = jobs.busy
            if (a.status == "APPLIED" || a.status == "REJECTED") SmallButton("Shortlist", tonal = true, enabled = !busy) { jobs.setApplicationStatus(a.id, "SHORTLISTED") }
            if (a.status != "HIRED") SmallButton("Hire", enabled = !busy) { onConfirm(Confirm("Hire $name?", "They'll see \"Hired\" on their application. Agree the start and pay with them in chat. The job stays open until you close it.", "Hire") { jobs.setApplicationStatus(a.id, "HIRED") }) }
            SmallButton("Message", tonal = true, enabled = !busy) { jobs.message(a.id, onOpenChat) }
            if (a.status == "APPLIED" || a.status == "SHORTLISTED") SmallButton("Reject", tonal = true, enabled = !busy) { onConfirm(Confirm("Turn down $name?", "They'll see \"Not selected\". You can still shortlist them later if you change your mind.", "Turn down", destructive = true) { jobs.setApplicationStatus(a.id, "REJECTED") }) }
        }
    }
}

/* ---------- the applicant side ---------- */

@Composable
private fun ApplicantSection(vm: BucksViewModel, job: JobPageRow, onApply: () -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs; val mine = jobs.myApplication?.takeIf { it.jobId == job.id }
    SectionTitle("Your application", Modifier.padding(top = 24.dp, bottom = 4.dp))
    when {
        jobs.loadingJob && mine == null -> JobsLoading("Checking…")
        mine == null && job.open -> {
            Muted("Apply with your skill profile and a short note. The business sees your name and profile, not your phone number, until you chat.")
            PrimaryButton("Apply for this job", Modifier.padding(top = 12.dp), enabled = !jobs.busy, onClick = onApply)
        }
        mine == null -> Muted("This job is closed and takes no new applications. Look for others under Jobs near me.")
        else -> BucksCard(tint = mine.status == "HIRED") {
            Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("Applied ${timeSince(mine.createdAt)}", style = MaterialTheme.typography.titleSmall); if (mine.note.isNotBlank()) Muted(mine.note, Modifier.padding(top = 4.dp), maxLines = 3) }; Spacer(Modifier.width(8.dp)); ApplicationStatusPill(mine.status) }
            Muted(when (mine.status) {
                "APPLIED" -> "Waiting for the business to look at it. They'll message you here if they want to talk."
                "SHORTLISTED" -> "You're on the shortlist. Keep an eye on your messages."
                "HIRED" -> "Congratulations, you're hired. Agree the start day and pay with the business in chat."
                "REJECTED" -> "Not selected this time. Other jobs nearby are under Jobs near me."
                else -> "You withdrew this application. You can't apply again to the same job."
            }, Modifier.padding(top = 10.dp))
            if (mine.status in setOf("APPLIED", "SHORTLISTED", "HIRED")) BadButton(if (jobs.busy) "Working…" else "Withdraw application", Modifier.padding(top = 8.dp)) {
                if (!jobs.busy) onConfirm(Confirm("Withdraw your application?", "The business will see you withdrew. You won't be able to apply again to this job.", "Withdraw", destructive = true) { jobs.withdraw(mine.id) })
            }
        }
    }
    // Questions before applying, or agreeing the start and pay after: the business's shared inbox, where every owner and admin sees it.
    if (!(jobs.loadingJob && mine == null)) SmallButton("Message the business", Modifier.padding(top = 12.dp), tonal = true) { jobs.messageBusiness(job.listingId, onOpenChat) }
}

/** Pick one or more of my skill profiles and add a note. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ApplySheet(vm: BucksViewModel, job: JobPageRow, onDismiss: () -> Unit) {
    val jobs = vm.jobs
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }; var note by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { jobs.loadMySkills() }
    val skills = jobs.mySkills
    LaunchedEffect(skills.size) { if (selected.isEmpty() && skills.size == 1) selected = setOf(skills.first().id) }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
        Text("Apply: ${job.title}", style = MaterialTheme.typography.titleLarge)
        Muted("${job.listingTitle} · ${job.pay.ifBlank { "Pay on request" }}", Modifier.padding(top = 2.dp, bottom = 14.dp))
        Label("Apply with")
        if (skills.isEmpty()) Notice("You don't have a skill profile yet. Add one under Menu > Studio > Create > Skill profile (for example Delivery driver, Tailor, Electrician) so businesses can see your experience and reviews. You can still apply now with a note.")
        else FlowChips(skills.map { it.title }, selected = skills.filter { it.id in selected }.map { it.title }.toSet()) { title -> skills.firstOrNull { it.title == title }?.let { s -> selected = if (s.id in selected) selected - s.id else selected + s.id } }
        BucksField(note, { note = it.take(500) }, "Note to the business", "When you can start, experience, what you'd like to know", modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 3, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
        PrimaryButton(if (jobs.busy) "Sending…" else "Send application", enabled = !jobs.busy && (selected.isNotEmpty() || note.isNotBlank())) {
            jobs.apply(job.id, selected.toList(), note); onDismiss()
        }
        if (selected.isEmpty() && note.isBlank()) Muted("Pick a skill profile or write a line about yourself.", Modifier.padding(top = 8.dp))
    } }
}
