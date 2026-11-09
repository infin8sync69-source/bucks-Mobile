package com.bucks.app.ui.screens.jobs

import com.bucks.app.data.Str
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.OutlinedFlag
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
        val report = com.bucks.app.ui.social.LocalReporter.current
        BucksTopBar(job?.title ?: stringResource(R.string.g1_job_title), onBack = onBack, actions = {
            job?.let { j -> if (report != null && !vm.myListings.listings.any { it.id == j.listingId }) IconButton({ report(com.bucks.app.ui.social.ReportTarget("JOB", j.id, null, j.title)) }) { Icon(Icons.Rounded.OutlinedFlag, stringResource(R.string.g1_cd_report_job)) } }
            IconButton({ jobs.loadJob(jobId) }) { Icon(Icons.Rounded.Refresh, stringResource(R.string.g1_cd_refresh)) } })
        when {
            job == null && jobs.jobMissing == jobId -> Column(Modifier.padding(Gutter)) {
                Text(stringResource(R.string.g1_job_gone_title), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(R.string.g1_job_gone_body), Modifier.padding(top = 6.dp))
                SmallButton(stringResource(R.string.g1_action_go_back), Modifier.padding(top = 14.dp), tonal = true, onClick = onBack)
            }
            job == null -> JobsLoading(stringResource(R.string.g1_job_loading))
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
        dismissButton = { TextButton({ confirm = null }) { Text(stringResource(R.string.g1_action_cancel)) } }) }
}

/** A question asked before an action that can't be taken back. */
private class Confirm(val title: String, val text: String, val button: String, val destructive: Boolean = false, val run: () -> Unit)

@Composable
private fun JobDetails(job: JobPageRow) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) { if (job.open) JobTypePill(job.jobType) else PillGrey(stringResource(R.string.g1_job_closed)); Spacer(Modifier.width(8.dp)); Muted(stringResource(R.string.g1_job_posted, timeSince(job.createdAt))) }
    Text(job.title, style = MaterialTheme.typography.headlineSmall)
    Text(job.pay.ifBlank { stringResource(R.string.g1_job_pay_on_request) }, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 4.dp))
    if (job.description.isNotBlank()) Text(job.description, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
    else Muted(stringResource(R.string.g1_job_no_details), Modifier.padding(top = 12.dp))
}

@Composable
private fun BusinessCard(job: JobPageRow, onClick: () -> Unit) {
    BucksCard(Modifier.padding(top = 16.dp), onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(icon = Icons.Rounded.Storefront)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(job.listingTitle, style = MaterialTheme.typography.titleMedium); Muted(job.area.ifBlank { stringResource(R.string.g1_job_open_business) }) }
            Icon(Icons.Rounded.ChevronRight, stringResource(R.string.g1_cd_open_business), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/* ---------- the business side: applications and decisions ---------- */

@Composable
private fun ManagerSection(vm: BucksViewModel, job: JobPageRow, onOpenListing: (String) -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs
    val apps = jobs.applications.filter { it.jobId == job.id }
    val active = apps.filter { it.status != "WITHDRAWN" }; val withdrawn = apps.filter { it.status == "WITHDRAWN" }
    SectionTitle(if (active.size == 0) stringResource(R.string.g1_job_applications_title) else pluralStringResource(R.plurals.g1_job_applications, active.size, active.size), Modifier.padding(top = 24.dp, bottom = 4.dp))
    if (jobs.loadingJob && apps.isEmpty()) JobsLoading(stringResource(R.string.g1_job_loading_apps))
    else if (active.isEmpty()) Muted(if (job.open) stringResource(R.string.g1_job_no_apps_open) else stringResource(R.string.g1_job_no_apps_closed), Modifier.padding(vertical = 8.dp))
    active.sortedWith(compareBy<JobApplicationRow> { statusRank(it.status) }.thenBy { it.createdAt }).forEach { a -> ApplicationCard(vm, a, onOpenListing, onOpenChat, onConfirm) }
    if (withdrawn.isNotEmpty()) Muted(pluralStringResource(R.plurals.g1_job_withdrawn, withdrawn.size, withdrawn.size), Modifier.padding(top = 8.dp))

    SectionTitle(stringResource(R.string.g1_job_this_job), Modifier.padding(top = 24.dp, bottom = 4.dp))
    if (job.open) {
        Muted(stringResource(R.string.g1_job_close_hint))
        BadButton(if (jobs.busy) stringResource(R.string.g1_job_working) else stringResource(R.string.g1_job_close), Modifier.padding(top = 8.dp)) {
            if (!jobs.busy) onConfirm(Confirm(Str.get(R.string.g1_job_close_title), Str.get(R.string.g1_job_close_body), Str.get(R.string.g1_job_close), destructive = true) { jobs.closeJob(job.id) })
        }
    } else {
        Muted(stringResource(R.string.g1_job_closed_note))
        SmallButton(stringResource(R.string.g1_job_reopen), Modifier.padding(top = 10.dp), tonal = true, enabled = !jobs.busy) { jobs.reopenJob(job.id) }
    }
}

private fun statusRank(s: String) = when (s) { "HIRED" -> 0; "SHORTLISTED" -> 1; "APPLIED" -> 2; "REJECTED" -> 3; else -> 4 }

@Composable
private fun ApplicationCard(vm: BucksViewModel, a: JobApplicationRow, onOpenListing: (String) -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs; val name = jobs.nameOf(a.applicantId)
    BucksCard(Modifier.padding(top = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(initials(name.ifBlank { "?" }), size = 40)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(name, style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g1_job_applied_ago, timeSince(a.createdAt))) }
            ApplicationStatusPill(a.status)
        }
        if (a.note.isNotBlank()) Text(a.note, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
        if (a.skillListingIds.isNotEmpty()) {
            Spacer(Modifier.height(10.dp)); Label(stringResource(R.string.g1_job_skill_profiles))
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                a.skillListingIds.forEach { id -> val l = jobs.skillProfiles[id]
                    if (l != null) Chip(if (l.status != "LIVE") stringResource(R.string.g1_job_skill_not_live, l.title) else l.title) { onOpenListing(id) }
                    else Chip(stringResource(R.string.g1_job_skill_private)) { vm.toast(Str.get(R.string.g1_job_skill_private_toast)) } }
            }
        } else Muted(stringResource(R.string.g1_job_no_skill), Modifier.padding(top = 8.dp))
        Row(Modifier.padding(top = 12.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val busy = jobs.busy
            if (a.status == "APPLIED" || a.status == "REJECTED") SmallButton(stringResource(R.string.g1_job_shortlist), tonal = true, enabled = !busy) { jobs.setApplicationStatus(a.id, "SHORTLISTED") }
            if (a.status != "HIRED") SmallButton(stringResource(R.string.g1_job_hire), enabled = !busy) { onConfirm(Confirm(Str.get(R.string.g1_job_hire_title, name), Str.get(R.string.g1_job_hire_body), Str.get(R.string.g1_job_hire)) { jobs.setApplicationStatus(a.id, "HIRED") }) }
            SmallButton(stringResource(R.string.g1_job_message), tonal = true, enabled = !busy) { jobs.message(a.id, onOpenChat) }
            if (a.status == "APPLIED" || a.status == "SHORTLISTED") SmallButton(stringResource(R.string.g1_job_reject), tonal = true, enabled = !busy) { onConfirm(Confirm(Str.get(R.string.g1_job_reject_title, name), Str.get(R.string.g1_job_reject_body), Str.get(R.string.g1_job_turn_down), destructive = true) { jobs.setApplicationStatus(a.id, "REJECTED") }) }
        }
    }
}

/* ---------- the applicant side ---------- */

@Composable
private fun ApplicantSection(vm: BucksViewModel, job: JobPageRow, onApply: () -> Unit, onOpenChat: (String) -> Unit, onConfirm: (Confirm) -> Unit) {
    val jobs = vm.jobs; val mine = jobs.myApplication?.takeIf { it.jobId == job.id }
    SectionTitle(stringResource(R.string.g1_job_your_app), Modifier.padding(top = 24.dp, bottom = 4.dp))
    when {
        jobs.loadingJob && mine == null -> JobsLoading(stringResource(R.string.g1_job_checking))
        mine == null && job.open -> {
            Muted(stringResource(R.string.g1_job_apply_hint))
            PrimaryButton(stringResource(R.string.g1_job_apply), Modifier.padding(top = 12.dp), enabled = !jobs.busy, onClick = onApply)
        }
        mine == null -> Muted(stringResource(R.string.g1_job_closed_applicant))
        else -> BucksCard(tint = mine.status == "HIRED") {
            Row(verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(stringResource(R.string.g1_job_applied_ago, timeSince(mine.createdAt)), style = MaterialTheme.typography.titleSmall); if (mine.note.isNotBlank()) Muted(mine.note, Modifier.padding(top = 4.dp), maxLines = 3) }; Spacer(Modifier.width(8.dp)); ApplicationStatusPill(mine.status) }
            Muted(when (mine.status) {
                "APPLIED" -> stringResource(R.string.g1_job_status_applied)
                "SHORTLISTED" -> stringResource(R.string.g1_job_status_shortlisted)
                "HIRED" -> stringResource(R.string.g1_job_status_hired)
                "REJECTED" -> stringResource(R.string.g1_job_status_rejected)
                else -> stringResource(R.string.g1_job_status_withdrawn)
            }, Modifier.padding(top = 10.dp))
            if (mine.status in setOf("APPLIED", "SHORTLISTED", "HIRED")) BadButton(if (jobs.busy) stringResource(R.string.g1_job_working) else stringResource(R.string.g1_job_withdraw_app), Modifier.padding(top = 8.dp)) {
                if (!jobs.busy) onConfirm(Confirm(Str.get(R.string.g1_job_withdraw_title), Str.get(R.string.g1_job_withdraw_body), Str.get(R.string.g1_job_withdraw), destructive = true) { jobs.withdraw(mine.id) })
            }
        }
    }
    // Questions before applying, or agreeing the start and pay after: the business's shared inbox, where every owner and admin sees it.
    if (!(jobs.loadingJob && mine == null)) SmallButton(stringResource(R.string.g1_job_message_business), Modifier.padding(top = 12.dp), tonal = true, enabled = !jobs.messaging) { jobs.messageBusiness(job.listingId, onOpenChat) }
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
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
        Text(stringResource(R.string.g1_job_apply_title, job.title), style = MaterialTheme.typography.titleLarge)
        Muted(stringResource(R.string.g1_job_business_pay, job.listingTitle, job.pay.ifBlank { stringResource(R.string.g1_job_pay_on_request) }), Modifier.padding(top = 2.dp, bottom = 14.dp))
        Label(stringResource(R.string.g1_job_apply_with))
        if (skills.isEmpty()) Notice(stringResource(R.string.g1_job_no_skill_notice))
        else FlowChips(skills.map { it.title }, selected = skills.filter { it.id in selected }.map { it.title }.toSet()) { title -> skills.firstOrNull { it.title == title }?.let { s -> selected = if (s.id in selected) selected - s.id else selected + s.id } }
        BucksField(note, { note = it.take(500) }, stringResource(R.string.g1_job_note_label), stringResource(R.string.g1_job_note_hint), modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 3, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
        PrimaryButton(if (jobs.busy) stringResource(R.string.g1_job_sending) else stringResource(R.string.g1_job_send), enabled = !jobs.busy && (selected.isNotEmpty() || note.isNotBlank())) {
            jobs.apply(job.id, selected.toList(), note); onDismiss()
        }
        if (selected.isEmpty() && note.isBlank()) Muted(stringResource(R.string.g1_job_pick_hint), Modifier.padding(top = 8.dp))
    } }
}
