package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Jobs
import com.bucks.app.ui.components.*

private val PAY_EXAMPLES = listOf("Rs 15,000/month", "Rs 500/day", "Rs 800 per job", "Rs 120/hour")

/** Post a job for a listing (Routes.JOB_NEW): title, what the work is, pay in plain words, and the kind of job. */
@Composable
fun JobNewScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onDone: () -> Unit) {
    val jobs = vm.jobs
    var title by rememberSaveable { mutableStateOf("") }; var description by rememberSaveable { mutableStateOf("") }
    var pay by rememberSaveable { mutableStateOf("") }; var type by rememberSaveable { mutableStateOf("FULL_TIME") }
    LaunchedEffect(listingId) { if (jobs.listing?.id != listingId) jobs.loadListingJobs(listingId) }
    val listingTitle = jobs.listing?.takeIf { it.id == listingId }?.title
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Post a job", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter).imePadding()) {
            if (listingTitle != null) Muted("For $listingTitle. People nearby see it under Jobs and apply with their skill profile.", Modifier.padding(bottom = 14.dp))
            BucksField(title, { title = it.take(80) }, "Job title", "Delivery rider, Billing staff, Tailor", keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            BucksField(description, { description = it.take(1000) }, "What the work is", "Timings, area, what they need to bring (own bike, licence), who to ask for", singleLine = false, minLines = 4, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            BucksField(pay, { pay = it.take(60) }, "Pay", "Rs 15,000/month, Rs 500/day")
            FlowChips(PAY_EXAMPLES) { pay = it }
            Spacer(Modifier.height(16.dp)); Label("Kind of job")
            FlowChips(Jobs.TYPES.map { it.second }, selected = setOf(Jobs.typeLabel(type))) { label -> Jobs.TYPES.firstOrNull { it.second == label }?.let { type = it.first } }
            Muted(when (type) { "FULL_TIME" -> "Regular work, every day."; "PART_TIME" -> "A few hours or a few days a week."; else -> "One task or a short stint, paid once it's done." }, Modifier.padding(top = 8.dp))
            if (pay.isBlank()) Muted("Leave pay empty and the job shows \"Pay on request\". Jobs that say the pay get more applications.", Modifier.padding(top = 8.dp))
            PrimaryButton(if (jobs.busy) "Posting…" else "Post job", Modifier.padding(top = 24.dp), enabled = !jobs.busy && title.isNotBlank()) {
                if (title.isBlank()) vm.toast("Give the job a title.") else jobs.postJob(listingId, title, description, pay, type, onDone)
            }
            Muted("You can close the job any time. Applications reach you here in the app, not by phone.", Modifier.padding(top = 10.dp))
            Spacer(Modifier.height(24.dp))
        }
    }
}
