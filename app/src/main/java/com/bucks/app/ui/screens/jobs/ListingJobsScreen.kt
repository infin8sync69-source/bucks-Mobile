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
import androidx.compose.ui.unit.dp
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
        BucksTopBar(jobs.listing?.takeIf { forThis }?.let { "Jobs at ${it.title}" } ?: "Jobs", onBack = onBack, actions = { IconButton({ jobs.loadListingJobs(listingId) }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (manager) item { PrimaryButton("Post a job", Modifier.padding(bottom = 6.dp), onClick = onNew) }
            when {
                jobs.loadingJobs && !forThis -> item { JobsLoading("Loading jobs…") }
                list.isEmpty() -> item {
                    if (manager) Muted("No jobs yet. Post one and people nearby with the right skills can apply. You'll see every application here.", Modifier.padding(top = 8.dp))
                    else Muted("No open jobs here right now. Check back later, or look at jobs near you under Services.", Modifier.padding(top = 8.dp))
                }
                else -> {
                    if (open.isEmpty()) item { Muted(if (manager) "All your jobs are closed. Post a new one when you need people." else "No open jobs here right now. Check back later.", Modifier.padding(top = 8.dp)) }
                    items(open, key = { it.id }) { j ->
                        JobCard(j.title, j.pay, j.jobType, j.createdAt, details = if (manager) listOf(applicationsLine(j.applications)) else emptyList(),
                            badge = if (manager && j.newApplications > 0) "${j.newApplications} new" else null) { onOpen(j.id) }
                    }
                    if (manager && closed.isNotEmpty()) {
                        item { SectionTitle("Closed", Modifier.padding(top = 12.dp)); Muted("Closed jobs take no new applications. Open one to see who applied or to reopen it.") }
                        items(closed, key = { it.id }) { j -> JobCard(j.title, j.pay, j.jobType, j.createdAt, details = listOf(applicationsLine(j.applications)), closed = true) { onOpen(j.id) } }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

private fun applicationsLine(n: Int) = when (n) { 0 -> "No applications yet"; 1 -> "1 application"; else -> "$n applications" }
