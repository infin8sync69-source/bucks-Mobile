package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Assignment
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Jobs
import com.bucks.app.ui.components.*

/** Open jobs within 15 km of me, nearest first, with a filter by kind of job (Routes.JOBS_NEAR). */
@Composable
fun JobsNearScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit, onMyApplications: (() -> Unit)? = null) {
    val jobs = vm.jobs; val s by vm.state.collectAsState()
    var type by rememberSaveable { mutableStateOf("") }   // "" = every kind
    LaunchedEffect(s.me) { jobs.refreshNear() }
    val list = jobs.near.filter { type.isEmpty() || it.jobType == type }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Jobs near me", onBack = onBack, actions = {
            if (onMyApplications != null) IconButton(onMyApplications) { Icon(Icons.Rounded.Assignment, "My applications") }
            IconButton({ jobs.refreshNear() }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        Row(Modifier.padding(horizontal = Gutter, vertical = 4.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip("All", selected = type.isEmpty()) { type = "" }
            Jobs.TYPES.forEach { (k, label) -> Chip(label, selected = type == k) { type = if (type == k) "" else k } }
        }
        LazyColumn(contentPadding = PaddingValues(horizontal = Gutter, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!s.locationGranted) item { Notice("Location is off, so this shows jobs around the city centre. Allow location in Settings to see jobs around you.") }
            when {
                jobs.loadingNear && jobs.near.isEmpty() -> item { JobsLoading("Finding jobs near you…") }
                jobs.near.isEmpty() -> item { Muted("No open jobs within 15 km right now. Businesses post here when they need people; check back in a day or two. Meanwhile, add a skill profile under Menu > Studio so they can find you.", Modifier.padding(top = 8.dp)) }
                list.isEmpty() -> item { Muted("No ${Jobs.typeLabel(type).lowercase()} jobs nearby. Tap All to see every job.", Modifier.padding(top = 8.dp)) }
                else -> items(list, key = { it.id }) { j ->
                    JobCard(j.title, j.pay, j.jobType, j.createdAt, details = listOf(j.listingTitle, listOf(j.area, Jobs.distance(j.distanceM)).filter { it.isNotBlank() }.joinToString(", "))) { onOpen(j.id) }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
