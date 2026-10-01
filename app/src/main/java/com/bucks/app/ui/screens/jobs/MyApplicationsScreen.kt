package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/** Every job I applied to, newest first, with the business and where the application stands (Routes.MY_APPLICATIONS). */
@Composable
fun MyApplicationsScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit, onNear: (() -> Unit)? = null) {
    val jobs = vm.jobs
    LaunchedEffect(Unit) { jobs.refreshMyApplications() }
    val list = jobs.myApplications
    val active = list.filter { it.status in ACTIVE }; val past = list.filter { it.status !in ACTIVE }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("My applications", onBack = onBack, actions = {
            if (onNear != null) IconButton(onNear) { Icon(Icons.Rounded.Work, "Jobs near me") }
            IconButton({ jobs.refreshMyApplications() }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when {
                jobs.loadingMine && list.isEmpty() -> item { JobsLoading("Loading your applications…") }
                list.isEmpty() -> item {
                    Muted("You haven't applied to any job yet. Open Jobs under Services to see what businesses near you are hiring, then apply with your skill profile.", Modifier.padding(top = 8.dp))
                    if (onNear != null) PrimaryButton("See jobs near me", Modifier.padding(top = 16.dp), onClick = onNear)
                }
                else -> {
                    if (active.isEmpty()) item { Muted("Nothing in progress. Your past applications are below.", Modifier.padding(top = 8.dp)) }
                    items(active, key = { it.id }) { a -> ApplicationRow(a.jobTitle, a.listingTitle, a.area, a.pay, a.status, a.createdAt, a.jobOpen) { onOpen(a.jobId) } }
                    if (past.isNotEmpty()) {
                        item { SectionTitle("Past", Modifier.padding(top = 12.dp)) }
                        items(past, key = { it.id }) { a -> ApplicationRow(a.jobTitle, a.listingTitle, a.area, a.pay, a.status, a.createdAt, a.jobOpen) { onOpen(a.jobId) } }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

private val ACTIVE = setOf("APPLIED", "SHORTLISTED", "HIRED")

@Composable
private fun ApplicationRow(jobTitle: String, business: String, area: String, pay: String, status: String, createdAt: String, jobOpen: Boolean, onClick: () -> Unit) {
    BucksCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(jobTitle, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(listOf(business, area).filter { it.isNotBlank() }.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
            Spacer(Modifier.width(10.dp)); ApplicationStatusPill(status)
        }
        Muted(listOf(pay.ifBlank { "" }, "Applied ${timeSince(createdAt)}", if (!jobOpen) "Job closed" else "").filter { it.isNotBlank() }.joinToString(" · "), Modifier.padding(top = 8.dp), maxLines = 2)
    }
}
