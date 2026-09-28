package com.bucks.app.ui.screens.manage

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
                f == null -> vm.toast("Couldn't read that file. Try a photo of the document.")
                f.bytes.size > MAX_FILE_BYTES -> vm.toast("Documents up to 10 MB. Take a smaller photo.")
                !(f.isImage || f.mime == "application/pdf") -> vm.toast("Photos (JPG, PNG) or PDF only.")
                else -> draft = row to f
            }
        }
    }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Documents", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            if (l != null) {
                Text(l.title, style = MaterialTheme.typography.titleLarge)
                Muted(serviceDef(l.service)?.label?.let { "Listed under $it" } ?: "", Modifier.padding(bottom = 12.dp))
            }
            val required = rows.orEmpty().filter { it.required }; val checked = required.count { it.status == "VERIFIED" }
            BucksCard(Modifier.padding(bottom = 12.dp), tint = true, padding = 14) {
                Text(when {
                    l == null -> "Documents"
                    l.status == "LIVE" -> "Live"
                    l.status == "SUSPENDED" && l.complianceHold -> "Paused for a document"
                    l.status == "SUSPENDED" -> "Suspended"
                    else -> "Not live yet"
                }, style = MaterialTheme.typography.titleMedium)
                Muted(when {
                    l == null -> ""
                    l.status == "LIVE" -> "Keep required documents in date. Seven days after one expires, the listing pauses until a new one is checked."
                    l.status == "SUSPENDED" && l.complianceHold -> "A required document expired. Upload a new one; you go live again as soon as Bucks checks it."
                    l.status == "SUSPENDED" -> "Bucks suspended this listing. Contact support."
                    else -> "Two things take it live: ${MyListingsNeeded} people nearby recommend it in person ($recs so far), and Bucks checks the required documents below ($checked of ${required.size} checked)."
                }, Modifier.padding(top = 4.dp))
            }
            Notice("Only you and Bucks staff can open these files. Customers see a \"checked by Bucks\" tick, plus the number for FSSAI, GST and RERA, which businesses are expected to show.")
            Spacer(Modifier.height(12.dp))
            when {
                rows == null -> Box(Modifier.fillMaxWidth().padding(40.dp)) { BucksLoader() }
                rows.isEmpty() -> Muted("This listing doesn't need any documents.")
                else -> rows.forEachIndexed { i, r ->
                    DocRow(r, uploading = sv.uploading == r.docType, modifier = Modifier.popIn(i),
                        onPick = { pickingFor = r; picker.launch(arrayOf("image/*", "application/pdf")) },
                        onRemove = if (r.status != "MISSING" && !(r.required && r.status == "VERIFIED")) ({ removing = r }) else null)
                }
            }
        }
    }
    draft?.let { (row, file) -> DocDetailsDialog(row, file, busy = sv.uploading != null, onDismiss = { draft = null }) { number, expires -> sv.submit(listingId, row, file, number, expires) { draft = null } } }
    removing?.let { r -> ConfirmDialog("Remove ${r.label}?", "The file is deleted. You can add it again later.", "Remove", onConfirm = { sv.remove(listingId, r); removing = null }, onDismiss = { removing = null }) }
}

/** Local recommendations a listing needs (settings.min_recommendations). */
private val MyListingsNeeded: Int get() = com.bucks.app.ui.MyListings.NEEDED

@Composable
private fun DocRow(r: ComplianceRow, uploading: Boolean, modifier: Modifier, onPick: () -> Unit, onRemove: (() -> Unit)?) = BucksCard(modifier.padding(bottom = 10.dp), padding = 14) {
    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(r.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        when (r.status) {
            "VERIFIED" -> PillGood("Checked"); "PENDING" -> PillWarn("Being checked"); "REJECTED" -> PillBad("Rejected"); "EXPIRED" -> PillBad("Expired")
            else -> if (r.required) PillPurple("Required") else PillGrey("Optional")
        }
    }
    if (r.hint.isNotBlank()) Muted(r.hint, Modifier.padding(top = 4.dp))
    if (r.status == "REJECTED" && r.note.isNotBlank()) Text("Bucks: ${r.note}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.status.bad, modifier = Modifier.padding(top = 6.dp))
    val facts = listOfNotNull(r.number.ifBlank { null }?.let { "No. $it" }, r.expiresOn?.let { "valid till ${humanDate(it)}" })
    if (facts.isNotEmpty()) Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp))
    Muted(if (r.publicNumber) "Customers see: a tick and the number" else "Customers see: a tick only", Modifier.padding(top = 6.dp))
    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        SmallButton(if (uploading) "Uploading…" else if (r.status == "MISSING") "Add" else "Replace", tonal = r.status != "MISSING", enabled = !uploading, onClick = onPick)
        if (onRemove != null) SmallButton("Remove", tonal = true, onClick = onRemove)
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
            Muted("File: ${file.name}")
            if (r.asksNumber) OutlinedTextField(number, { number = it.take(40) }, label = { Text(if (needsNumber) "Number" else "Number (optional)") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = if (r.docType == "FSSAI") KeyboardType.Number else KeyboardType.Ascii), modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
            if (r.hasExpiry) OutlinedButton({ choosing = true }, Modifier.fillMaxWidth().padding(top = 12.dp)) { Text(expires?.let { "Valid till ${humanDate(it.toString())}" } ?: "Choose the expiry date") }
            if (!r.asksNumber) Muted("Bucks doesn't keep this document's number, only the file for checking.", Modifier.padding(top = 12.dp))
        } },
        confirmButton = { TextButton(enabled = !busy && (!needsNumber || number.isNotBlank()) && (!r.hasExpiry || expires != null), onClick = { onSubmit(number, expires?.toString()) }) { Text(if (busy) "Sending…" else "Send to Bucks") } },
        dismissButton = { TextButton(enabled = !busy, onClick = onDismiss) { Text("Cancel") } })
    if (choosing) {
        val today = LocalDate.now(ZoneOffset.UTC).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today })
        DatePickerDialog(onDismissRequest = { choosing = false },
            confirmButton = { TextButton({ state.selectedDateMillis?.let { expires = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; choosing = false }) { Text("OK") } },
            dismissButton = { TextButton({ choosing = false }) { Text("Cancel") } }) { DatePicker(state) }
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
    fun open(item: ReviewItem) = scope.launch {
        runCatching { Backend.signedUrl("docs", item.path) }.onSuccess { url -> runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }.onFailure { vm.toast("No app on this phone can open that file.") } }
            .onFailure { vm.toast("Couldn't open the file. Check your connection.") }
    }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Review documents", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            when {
                !sv.reviewLoaded -> Box(Modifier.fillMaxWidth().padding(40.dp)) { BucksLoader() }
                sv.reviewQueue.isEmpty() -> Muted("Nothing to review. New uploads show up here.")
                else -> sv.reviewQueue.forEach { item ->
                    BucksCard(Modifier.padding(bottom = 10.dp), padding = 14) {
                        Text(item.label, style = MaterialTheme.typography.titleSmall)
                        Muted(listOfNotNull(item.listingTitle, serviceDef(item.service)?.label).joinToString(" · "))
                        val facts = listOfNotNull(item.number.ifBlank { null }?.let { "No. $it" }, item.expiresOn?.let { "valid till ${humanDate(it)}" })
                        if (facts.isNotEmpty()) Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
                        Muted("Check the name, number and dates on the file match what they entered.", Modifier.padding(top = 4.dp))
                        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SmallButton("Open file", tonal = true) { open(item) }
                            SmallButton("Approve") { sv.review(item, true, "") }
                            SmallButton("Reject", tonal = true) { rejecting = item }
                        }
                    }
                }
            }
        }
    }
    rejecting?.let { item ->
        var reason by remember(item.id) { mutableStateOf("") }
        AlertDialog(onDismissRequest = { rejecting = null }, title = { Text("Reject ${item.label}?") },
            text = { OutlinedTextField(reason, { reason = it.take(200) }, label = { Text("Reason they will see") }, placeholder = { Text("The name on the licence doesn't match the shop") }, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(enabled = reason.isNotBlank(), onClick = { sv.review(item, false, reason.trim()); rejecting = null }) { Text("Reject") } },
            dismissButton = { TextButton({ rejecting = null }) { Text("Cancel") } })
    }
}
