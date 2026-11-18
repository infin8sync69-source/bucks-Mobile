package com.bucks.app.ui.screens.jobs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Money
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Jobs
import com.bucks.app.ui.components.*


/** Post a job for a listing (Routes.JOB_NEW): title, what the work is, pay in plain words, and the kind of job. */
@Composable
fun JobNewScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onDone: () -> Unit) {
    val jobs = vm.jobs
    var title by rememberSaveable { mutableStateOf("") }; var description by rememberSaveable { mutableStateOf("") }
    var pay by rememberSaveable { mutableStateOf("") }; var type by rememberSaveable { mutableStateOf("FULL_TIME") }
    LaunchedEffect(listingId) { if (jobs.listing?.id != listingId) jobs.loadListingJobs(listingId) }
    val listingTitle = jobs.listing?.takeIf { it.id == listingId }?.title
    val payMonth = stringResource(R.string.g4_job_pay_month, Money.format(15000)); val payDay = stringResource(R.string.g4_job_pay_day, Money.format(500))
    val payExamples = listOf(payMonth, payDay, stringResource(R.string.g4_job_pay_job, Money.format(800)), stringResource(R.string.g4_job_pay_hour, Money.format(120)))
    val needTitle = stringResource(R.string.g4_job_need_title)
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g4_job_new_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter).imePadding()) {
            if (listingTitle != null) Muted(stringResource(R.string.g4_job_new_for, listingTitle), Modifier.padding(bottom = 14.dp))
            BucksField(title, { title = it.take(80) }, stringResource(R.string.g4_job_field_title), stringResource(R.string.g4_job_field_title_hint), keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            BucksField(description, { description = it.take(1000) }, stringResource(R.string.g4_job_field_work), stringResource(R.string.g4_job_field_work_hint), singleLine = false, minLines = 4, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences))
            BucksField(pay, { pay = it.take(60) }, stringResource(R.string.g4_job_field_pay), stringResource(R.string.g4_job_field_pay_hint, payMonth, payDay))
            FlowChips(payExamples) { pay = it }
            Spacer(Modifier.height(16.dp)); Label(stringResource(R.string.g4_job_kind))
            FlowChips(Jobs.TYPES.map { it.second }, selected = setOf(Jobs.typeLabel(type))) { label -> Jobs.TYPES.firstOrNull { it.second == label }?.let { type = it.first } }
            Muted(when (type) { "FULL_TIME" -> stringResource(R.string.g4_job_kind_full); "PART_TIME" -> stringResource(R.string.g4_job_kind_part); else -> stringResource(R.string.g4_job_kind_gig) }, Modifier.padding(top = 8.dp))
            if (pay.isBlank()) Muted(stringResource(R.string.g4_job_pay_empty_note), Modifier.padding(top = 8.dp))
            PrimaryButton(if (jobs.busy) stringResource(R.string.g4_job_posting) else stringResource(R.string.g4_job_post), Modifier.padding(top = 24.dp), enabled = !jobs.busy && title.isNotBlank()) {
                if (title.isBlank()) vm.toast(needTitle) else jobs.postJob(listingId, title, description, pay, type, onDone)
            }
            Muted(stringResource(R.string.g4_job_new_footer), Modifier.padding(top = 10.dp))
            Spacer(Modifier.height(24.dp))
        }
    }
}
