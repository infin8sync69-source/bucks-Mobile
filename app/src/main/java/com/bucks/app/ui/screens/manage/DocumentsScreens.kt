package com.bucks.app.ui.screens.manage

import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import com.bucks.app.data.Str
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.ComplianceRow
import com.bucks.app.data.Picked
import com.bucks.app.data.ReviewItem
import com.bucks.app.data.Upload
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.discover.humanDate
import com.bucks.app.ui.serviceDef
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

private const val MAX_FILE_BYTES = 10 * 1024 * 1024

/**
 * The documents a listing's service asks for (services.sql, docs/SERVICES_UNLOCK.md): what each is for, whether customers see
 * anything of it, and where it stands with Bucks. Files go to the private docs bucket; only the uploader and Bucks staff can
 * open them.
 */
@Composable
fun ListingDocsScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit) {
    val sv = vm.services; val m = vm.myListings; val ctx = LocalContext.current
    LaunchedEffect(listingId) { sv.loadCompliance(listingId); if (!m.loaded) m.refresh() }
    val rows = sv.compliance[listingId]; val l = m.listing(listingId); val recs = m.recommendations[listingId] ?: 0
    var pickingFor by remember { mutableStateOf<ComplianceRow?>(null) }
    var draft by remember { mutableStateOf<Pair<ComplianceRow, Picked>?>(null) }
    var removing by remember { mutableStateOf<ComplianceRow?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val row = pickingFor; pickingFor = null
        if (uri != null && row != null) {
            val f = Upload.read(ctx, uri)
            when {
                f == null -> vm.toast(Str.get(R.string.g2_doc_read_failed))
                f.bytes.size > MAX_FILE_BYTES -> vm.toast(Str.get(R.string.g2_doc_too_big))
                !(f.isImage || f.mime == "application/pdf") -> vm.toast(Str.get(R.string.g2_doc_types))
                else -> draft = row to f
            }
        }
    }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g2_ml_documents), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            if (l != null) {
                Text(l.title, style = MaterialTheme.typography.titleLarge)
                Muted(serviceDef(l.service)?.label?.let { stringResource(R.string.g2_doc_listed_under, it) } ?: "", Modifier.padding(bottom = 12.dp))
            }
            val required = rows.orEmpty().filter { it.required }; val checked = required.count { it.status == "VERIFIED" }
            BucksCard(Modifier.padding(bottom = 12.dp), tint = true, padding = 14) {
                Text(when {
                    l == null -> stringResource(R.string.g2_ml_documents)
                    l.status == "LIVE" -> stringResource(R.string.g2_live)
                    l.status == "SUSPENDED" && l.complianceHold -> stringResource(R.string.g2_doc_paused)
                    l.status == "SUSPENDED" -> stringResource(R.string.g2_suspended)
                    else -> stringResource(R.string.g2_doc_not_live)
                }, style = MaterialTheme.typography.titleMedium)
                Muted(when {
                    l == null -> ""
                    l.status == "LIVE" -> stringResource(R.string.g2_doc_live_info)
                    l.status == "SUSPENDED" && l.complianceHold -> stringResource(R.string.g2_doc_hold_info)
                    l.status == "SUSPENDED" -> stringResource(R.string.g2_doc_suspended_info)
                    else -> stringResource(R.string.g2_doc_pending_info, MyListingsNeeded, recs, checked, required.size)
                }, Modifier.padding(top = 4.dp))
            }
            Notice(stringResource(R.string.g2_doc_privacy))
            Spacer(Modifier.height(12.dp))
            when {
                rows == null -> Box(Modifier.fillMaxWidth().padding(40.dp)) { BucksLoader() }
                rows.isEmpty() -> Muted(stringResource(R.string.g2_doc_none_needed))
                else -> rows.forEachIndexed { i, r ->
                    DocRow(r, uploading = sv.uploading == r.docType, modifier = Modifier.popIn(i),
                        onPick = { pickingFor = r; picker.launch(arrayOf("image/*", "application/pdf")) },
                        onRemove = if (r.status != "MISSING" && !(r.required && r.status == "VERIFIED")) ({ removing = r }) else null)
                }
            }
        }
    }
    draft?.let { (row, file) -> DocDetailsDialog(row, file, busy = sv.uploading != null, onDismiss = { draft = null }) { number, expires -> sv.submit(listingId, row, file, number, expires) { draft = null } } }
    removing?.let { r -> ConfirmDialog(stringResource(R.string.g2_remove_member_q, r.label), stringResource(R.string.g2_doc_remove_body), stringResource(R.string.g2_remove), onConfirm = { sv.remove(listingId, r); removing = null }, onDismiss = { removing = null }) }
}

/** Local recommendations a listing needs (settings.min_recommendations). */
private val MyListingsNeeded: Int get() = com.bucks.app.ui.MyListings.NEEDED

@Composable
private fun DocRow(r: ComplianceRow, uploading: Boolean, modifier: Modifier, onPick: () -> Unit, onRemove: (() -> Unit)?) = BucksCard(modifier.padding(bottom = 10.dp), padding = 14) {
    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(r.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        when (r.status) {
            "VERIFIED" -> PillGood(stringResource(R.string.g2_doc_checked)); "PENDING" -> PillWarn(stringResource(R.string.g2_doc_being_checked)); "REJECTED" -> PillBad(stringResource(R.string.g2_doc_rejected)); "EXPIRED" -> PillBad(stringResource(R.string.g2_doc_expired))
            else -> if (r.required) PillPurple(stringResource(R.string.g2_doc_required)) else PillGrey(stringResource(R.string.g2_doc_optional))
        }
    }
    if (r.hint.isNotBlank()) Muted(r.hint, Modifier.padding(top = 4.dp))
    if (r.status == "REJECTED" && r.note.isNotBlank()) Text(stringResource(R.string.g2_doc_bucks_note, r.note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.status.bad, modifier = Modifier.padding(top = 6.dp))
    val facts = listOfNotNull(r.number.ifBlank { null }?.let { stringResource(R.string.g2_doc_number, it) }, r.expiresOn?.let { stringResource(R.string.g2_doc_valid_till_lc, humanDate(it)) })
    if (facts.isNotEmpty()) Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp))
    Muted(stringResource(if (r.publicNumber) R.string.g2_doc_customers_number else R.string.g2_doc_customers_tick), Modifier.padding(top = 6.dp))
    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        SmallButton(stringResource(if (uploading) R.string.g2_uploading else if (r.status == "MISSING") R.string.g2_add else R.string.g2_doc_replace), tonal = r.status != "MISSING", enabled = !uploading, onClick = onPick)
        if (onRemove != null) SmallButton(stringResource(R.string.g2_remove), tonal = true, onClick = onRemove)
    }
}

/** After picking a file: the number (when the document has one Bucks keeps) and the expiry date (when it expires). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DocDetailsDialog(r: ComplianceRow, file: Picked, busy: Boolean, onDismiss: () -> Unit, onSubmit: (String, String?) -> Unit) {
    var number by remember { mutableStateOf("") }
    var expires by remember { mutableStateOf<LocalDate?>(null) }
    var choosing by remember { mutableStateOf(false) }
    val needsNumber = r.asksNumber && r.publicNumber
    AlertDialog(onDismissRequest = { if (!busy) onDismiss() }, title = { Text(r.label) },
        text = { Column {
            Muted(stringResource(R.string.g2_doc_file, file.name))
            if (r.asksNumber) OutlinedTextField(number, { number = it.take(40) }, label = { Text(stringResource(if (needsNumber) R.string.g2_doc_number_label else R.string.g2_doc_number_optional)) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = if (r.docType == "FSSAI") KeyboardType.Number else KeyboardType.Ascii), modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
            if (r.hasExpiry) OutlinedButton({ choosing = true }, Modifier.fillMaxWidth().padding(top = 12.dp)) { Text(expires?.let { stringResource(R.string.g2_doc_valid_till, humanDate(it.toString())) } ?: stringResource(R.string.g2_doc_choose_expiry)) }
            if (!r.asksNumber) Muted(stringResource(R.string.g2_doc_no_number_kept), Modifier.padding(top = 12.dp))
        } },
        confirmButton = { TextButton(enabled = !busy && (!needsNumber || number.isNotBlank()) && (!r.hasExpiry || expires != null), onClick = { onSubmit(number, expires?.toString()) }) { Text(stringResource(if (busy) R.string.g2_sending else R.string.g2_doc_send)) } },
        dismissButton = { TextButton(enabled = !busy, onClick = onDismiss) { Text(stringResource(R.string.g2_cancel)) } })
    if (choosing) {
        val today = LocalDate.now(ZoneOffset.UTC).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today })
        DatePickerDialog(onDismissRequest = { choosing = false },
            confirmButton = { TextButton({ state.selectedDateMillis?.let { expires = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; choosing = false }) { Text(stringResource(R.string.g2_ok)) } },
            dismissButton = { TextButton({ choosing = false }) { Text(stringResource(R.string.g2_cancel)) } }) { DatePicker(state) }
    }
}

/**
 * Bucks staff only (the staff table): documents waiting for a decision, oldest first. Approving the last required document
 * of a listing that already has its recommendations takes it live.
 */
@Composable
fun StaffReviewScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val sv = vm.services; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { sv.loadReviewQueue() }
    var rejecting by remember { mutableStateOf<ReviewItem?>(null) }
    // Vehicles waiting for a check: approving one lets its owner and drivers go online (nothing else can).
    var vehicles by remember { mutableStateOf<List<com.bucks.app.data.VehicleToReview>?>(null) }
    var rejectingVehicle by remember { mutableStateOf<com.bucks.app.data.VehicleToReview?>(null) }
    var vBusy by remember { mutableStateOf(false) }
    fun loadVehicles() = scope.launch { vehicles = runCatching { com.bucks.app.data.DeliveryBackend.vehiclesToReview() }.getOrElse { vm.toast(com.bucks.app.data.friendlyError(it)); emptyList() } }
    fun decide(v: com.bucks.app.data.VehicleToReview, approve: Boolean, note: String) = scope.launch {
        vBusy = true
        runCatching { com.bucks.app.data.DeliveryBackend.reviewVehicle(v.id, approve, note) }
            .onSuccess { vm.toast(Str.get(if (approve) R.string.g2_staff_vehicle_approved else R.string.g2_staff_vehicle_sent_back, v.plate)); vehicles = vehicles?.filterNot { it.id == v.id } }
            .onFailure { vm.toast(com.bucks.app.data.friendlyError(it)) }
        vBusy = false
    }
    LaunchedEffect(Unit) { loadVehicles() }
    fun openPath(path: String) = scope.launch {
        runCatching { Backend.signedUrl("docs", path) }.onSuccess { url -> runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }.onFailure { vm.toast(Str.get(R.string.g2_no_app_open_file)) } }
            .onFailure { vm.toast(Str.get(R.string.g2_file_open_connection)) }
    }
    fun open(item: ReviewItem) = scope.launch {
        runCatching { Backend.signedUrl("docs", item.path) }.onSuccess { url -> runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }.onFailure { vm.toast(Str.get(R.string.g2_no_app_open_file)) } }
            .onFailure { vm.toast(Str.get(R.string.g2_file_open_connection)) }
    }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g2_staff_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            SectionTitle(stringResource(R.string.g2_ml_tab_vehicles), Modifier.padding(top = 8.dp, bottom = 6.dp))
            val vs = vehicles
            when {
                vs == null -> Box(Modifier.fillMaxWidth().padding(24.dp)) { BucksLoader() }
                vs.isEmpty() -> Muted(stringResource(R.string.g2_staff_no_vehicles), Modifier.padding(bottom = 12.dp))
                else -> vs.forEach { v ->
                    BucksCard(Modifier.padding(bottom = 10.dp), padding = 14) {
                        Text(stringResource(R.string.g2_staff_plate_kind, v.plate, stringResource(when (v.kind) { "BIKE" -> R.string.g2_vk_bike_deliveries; "AUTO" -> R.string.g2_vk_auto; else -> R.string.g2_vk_cab })), style = MaterialTheme.typography.titleSmall)
                        Muted(listOfNotNull(v.model.ifBlank { null }, v.ownerName, stringResource(R.string.g2_staff_added, humanDate(v.createdAt))).joinToString(" · "))
                        val files = v.files
                        if (files.isEmpty()) Text(stringResource(R.string.g2_staff_no_docs), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 4.dp))
                        else Row(Modifier.padding(top = 8.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            files.forEachIndexed { i, (kind, path) -> SmallButton(kind.ifBlank { stringResource(R.string.g2_staff_document_n, i + 1) }, tonal = true) { openPath(path) } } }
                        Muted(stringResource(R.string.g2_staff_check_vehicle), Modifier.padding(top = 6.dp))
                        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SmallButton(stringResource(R.string.g2_approve), enabled = !vBusy && files.isNotEmpty()) { decide(v, true, "") }
                            SmallButton(stringResource(R.string.g2_reject), tonal = true, enabled = !vBusy) { rejectingVehicle = v }
                        }
                    }
                }
            }
            SectionTitle(stringResource(R.string.g2_ml_documents), Modifier.padding(top = 8.dp, bottom = 6.dp))
            when {
                !sv.reviewLoaded -> Box(Modifier.fillMaxWidth().padding(40.dp)) { BucksLoader() }
                sv.reviewQueue.isEmpty() -> Muted(stringResource(R.string.g2_staff_nothing))
                else -> sv.reviewQueue.forEach { item ->
                    BucksCard(Modifier.padding(bottom = 10.dp), padding = 14) {
                        Text(item.label, style = MaterialTheme.typography.titleSmall)
                        Muted(listOfNotNull(item.listingTitle, serviceDef(item.service)?.label).joinToString(" · "))
                        val facts = listOfNotNull(item.number.ifBlank { null }?.let { stringResource(R.string.g2_doc_number, it) }, item.expiresOn?.let { stringResource(R.string.g2_doc_valid_till_lc, humanDate(it)) })
                        if (facts.isNotEmpty()) Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
                        Muted(stringResource(R.string.g2_staff_check_doc), Modifier.padding(top = 4.dp))
                        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SmallButton(stringResource(R.string.g2_staff_open_file), tonal = true) { open(item) }
                            SmallButton(stringResource(R.string.g2_approve)) { sv.review(item, true, "") }
                            SmallButton(stringResource(R.string.g2_reject), tonal = true) { rejecting = item }
                        }
                    }
                }
            }
        }
    }
    rejectingVehicle?.let { v ->
        var reason by remember(v.id) { mutableStateOf("") }
        AlertDialog(onDismissRequest = { rejectingVehicle = null }, title = { Text(stringResource(R.string.g2_staff_send_back_q, v.plate)) },
            text = { OutlinedTextField(reason, { reason = it.take(300) }, label = { Text(stringResource(R.string.g2_staff_fix_label)) }, placeholder = { Text(stringResource(R.string.g2_staff_fix_hint)) }, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(enabled = reason.isNotBlank() && !vBusy, onClick = { decide(v, false, reason.trim()); rejectingVehicle = null }) { Text(stringResource(R.string.g2_staff_send_back)) } },
            dismissButton = { TextButton({ rejectingVehicle = null }) { Text(stringResource(R.string.g2_cancel)) } })
    }
    rejecting?.let { item ->
        var reason by remember(item.id) { mutableStateOf("") }
        AlertDialog(onDismissRequest = { rejecting = null }, title = { Text(stringResource(R.string.g2_staff_reject_q, item.label)) },
            text = { OutlinedTextField(reason, { reason = it.take(200) }, label = { Text(stringResource(R.string.g2_staff_reason_label)) }, placeholder = { Text(stringResource(R.string.g2_staff_reason_hint)) }, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(enabled = reason.isNotBlank(), onClick = { sv.review(item, false, reason.trim()); rejecting = null }) { Text(stringResource(R.string.g2_reject)) } },
            dismissButton = { TextButton({ rejecting = null }) { Text(stringResource(R.string.g2_cancel)) } })
    }
}
