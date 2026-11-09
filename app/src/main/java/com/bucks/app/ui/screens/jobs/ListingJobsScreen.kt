package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/**
 * Jobs at one business (Routes.LISTING_JOBS). Everyone sees the open jobs; the owner and admins also see the
 * closed ones, how many people applied, and can post a new job.
 */
@Composable
fun ListingJobsScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onOpen: (String) -> Unit, onNew: () -> Unit) {
    val jobs = vm.jobs
    LaunchedEffect(listingId) { jobs.loadListingJobs(listingId) }
    val forThis = jobs.listing?.id == listingId
    val list = if (forThis) jobs.jobs else emptyList()
    val open = list.filter { it.open }; val closed = list.filter { !it.open }
    val manager = forThis && jobs.manager
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(jobs.listing?.takeIf { forThis }?.let { stringResource(R.string.g4_jobs_at, it.title) } ?: stringResource(R.string.g4_jobs_title), onBack = onBack, actions = { IconButton({ jobs.loadListingJobs(listingId) }) { Icon(Icons.Rounded.Refresh, stringResource(R.string.g4_cd_refresh)) } })
        LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (manager) item { PrimaryButton(stringResource(R.string.g4_job_new_title), Modifier.padding(bottom = 6.dp), onClick = onNew) }
            when {
                jobs.loadingJobs && !forThis -> item { JobsLoading(stringResource(R.string.g4_jobs_loading)) }
                list.isEmpty() -> item {
                    if (manager) Muted(stringResource(R.string.g4_jobs_empty_manager), Modifier.padding(top = 8.dp))
                    else Muted(stringResource(R.string.g4_jobs_empty), Modifier.padding(top = 8.dp))
                }
                else -> {
                    if (open.isEmpty()) item { Muted(if (manager) stringResource(R.string.g4_jobs_all_closed) else stringResource(R.string.g4_jobs_none_open), Modifier.padding(top = 8.dp)) }
                    items(open, key = { it.id }) { j ->
                        JobCard(j.title, j.pay, j.jobType, j.createdAt, details = if (manager) listOf(applicationsLine(j.applications)) else emptyList(),
                            badge = if (manager && j.newApplications > 0) stringResource(R.string.g4_jobs_new_badge, j.newApplications) else null) { onOpen(j.id) }
                    }
                    if (manager && closed.isNotEmpty()) {
                        item { SectionTitle(stringResource(R.string.g4_jobs_closed), Modifier.padding(top = 12.dp)); Muted(stringResource(R.string.g4_jobs_closed_note)) }
                        items(closed, key = { it.id }) { j -> JobCard(j.title, j.pay, j.jobType, j.createdAt, details = listOf(applicationsLine(j.applications)), closed = true) { onOpen(j.id) } }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun applicationsLine(n: Int) = if (n == 0) stringResource(R.string.g4_jobs_no_applications) else pluralStringResource(R.plurals.g4_jobs_applications, n, n)
