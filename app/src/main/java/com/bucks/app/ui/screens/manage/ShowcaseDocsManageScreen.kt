package com.bucks.app.ui.screens.manage

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.discover.DocButton
import com.bucks.app.ui.screens.discover.DocPills
import com.bucks.app.ui.screens.discover.ShowcaseDocViewer
import com.bucks.app.ui.screens.discover.docKindIcon
import com.bucks.app.ui.screens.discover.humanDate
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.coroutines.cancellation.CancellationException

private const val SHOWCASE_MAX_BYTES = 10 * 1024 * 1024
private val SHOWCASE_MIMES = setOf("application/pdf", "image/jpeg", "image/png", "image/webp")

/** The sentence we wrote on the server (for instance "that name could be mistaken for a Bucks check"), or a generic one. */
private fun friendly(e: Throwable) = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(e.message ?: "")?.groupValues?.get(1)?.replace("\\\"", "\"")?.takeIf { it.isNotBlank() }
    ?: Str.get(R.string.g8_generic_error)

/**
 * The documents a business, NGO or institution shows on its profile (showcase_docs.sql). Owner and admins add them, choose who may open
 * each one, answer requests to see locked ones and see who looked. Separate from the compliance documents Bucks staff check
 * (ListingDocsScreen): those never appear here and these never affect going live.
 */
@Composable
fun ShowcaseDocsManageScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit) {
    val m = vm.myListings; val scope = rememberCoroutineScope()
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh() }
    val allowed = m.loaded && m.canManage(listingId)
    var docs by remember(listingId) { mutableStateOf<List<ShowcaseDoc>?>(null) }
    var requests by remember(listingId) { mutableStateOf<List<DocRequest>>(emptyList()) }
    var views by remember(listingId) { mutableStateOf<List<DocView>>(emptyList()) }
    var loadError by remember(listingId) { mutableStateOf<String?>(null) }
    var sideFailed by remember(listingId) { mutableStateOf(false) }
    var reload by remember(listingId) { mutableIntStateOf(0) }
    var editing by remember { mutableStateOf<ShowcaseDoc?>(null) }
    var adding by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<ShowcaseDoc?>(null) }
    var viewing by remember { mutableStateOf<ShowcaseDoc?>(null) }
    var busyId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(listingId, reload, allowed) {
        if (!allowed) return@LaunchedEffect
        try { docs = Backend.showcaseDocs(listingId); loadError = null } catch (e: CancellationException) { throw e } catch (e: Exception) { loadError = friendly(e) }
        sideFailed = false
        try { requests = Backend.docRequestsFor(listingId) } catch (e: CancellationException) { throw e } catch (e: Exception) { sideFailed = true }
        try { views = Backend.docViewLog(listingId) } catch (e: CancellationException) { throw e } catch (e: Exception) { sideFailed = true }
    }
    /** Runs one team action with its button disabled, shows the server's message when it fails, and reloads on success. */
    fun act(key: String, okText: String, block: suspend () -> Unit) { scope.launch {
        busyId = key
        try { block(); vm.toast(okText); reload++ } catch (e: CancellationException) { throw e } catch (e: Exception) { vm.toast(friendly(e)) }
        busyId = null
    } }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g8_docs_to_show), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            val l = m.listing(listingId)
            if (l != null) Text(l.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp))
            when {
                !m.loaded -> CenteredLoading()
                !allowed -> Muted(stringResource(R.string.g8_docs_owner_only))
                else -> {
                    Notice(stringResource(R.string.g8_docs_notice))
                    val list = docs
                    Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.g8_your_documents), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (list != null) Muted(stringResource(R.string.g8_n_of_20, list.size))
                    }
                    when {
                        list == null && loadError != null -> LoadError(loadError.orEmpty(), Modifier.padding(top = 8.dp)) { loadError = null; reload++ }
                        list == null -> CenteredLoading()
                        else -> {
                            if (list.isEmpty()) Muted(stringResource(R.string.g8_no_docs), Modifier.padding(top = 8.dp))
                            list.forEach { d -> ManageDocCard(d, Modifier.padding(top = 10.dp), onOpen = { viewing = d }, onEdit = { editing = d }, onRemove = { removing = d }) }
                            if (list.size < 20) DocButton(stringResource(R.string.g8_add_document), { adding = true }, Modifier.padding(top = 12.dp), icon = Icons.Rounded.Add)
                            else Muted(stringResource(R.string.g8_docs_limit), Modifier.padding(top = 12.dp))
                        }
                    }

                    SectionTitle(stringResource(R.string.g8_requests), Modifier.padding(top = 24.dp))
                    Muted(stringResource(R.string.g8_requests_sub), Modifier.padding(top = 2.dp, bottom = 4.dp))
                    if (requests.isEmpty() && sideFailed) Muted(stringResource(R.string.g8_requests_failed), Modifier.padding(top = 4.dp))
                    else if (requests.isEmpty()) Muted(stringResource(R.string.g8_no_requests), Modifier.padding(top = 4.dp))
                    requests.forEach { r ->
                        BucksCard(Modifier.padding(top = 10.dp), padding = 14) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(r.requesterName.ifBlank { stringResource(R.string.g8_a_bucks_member) }, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                                if (r.status == "PENDING") PillWarn(stringResource(R.string.g8_waiting)) else PillGood(stringResource(R.string.g8_approved))
                            }
                            Muted(if (r.relation.isNotBlank()) stringResource(R.string.g8_for_doc_relation, r.docTitle, r.relation) else stringResource(R.string.g8_for_doc, r.docTitle), Modifier.padding(top = 2.dp))
                            if (r.message.isNotBlank()) Text("\"${r.message}\"", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                            if (r.status == "PENDING") Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                DocButton(stringResource(R.string.g8_approve_30), { act("a" + r.id, Str.get(R.string.g8_approved_30_told)) { Backend.decideDocRequest(r.id, true, 30) } }, enabled = busyId == null)
                                DocButton(stringResource(R.string.g8_decline), { act("d" + r.id, Str.get(R.string.g8_declined_told)) { Backend.decideDocRequest(r.id, false) } }, tonal = true, enabled = busyId == null)
                            } else {
                                Muted(stringResource(R.string.g8_can_open_until, humanDate(r.expiresAt)), Modifier.padding(top = 6.dp))
                                DocButton(stringResource(R.string.g8_revoke), { act("r" + r.id, Str.get(R.string.g8_access_ended)) { Backend.revokeDocAccess(r.id) } }, Modifier.padding(top = 4.dp), tonal = true, enabled = busyId == null)
                            }
                        }
                    }

                    SectionTitle(stringResource(R.string.g8_who_looked), Modifier.padding(top = 24.dp))
                    Muted(stringResource(R.string.g8_who_looked_sub), Modifier.padding(top = 2.dp, bottom = 4.dp))
                    if (views.isEmpty() && sideFailed) Muted(stringResource(R.string.g8_who_looked_failed), Modifier.padding(top = 4.dp))
                    else if (views.isEmpty()) Muted(stringResource(R.string.g8_nobody_looked), Modifier.padding(top = 4.dp))
                    views.forEach { v ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(v.viewerName.ifBlank { stringResource(R.string.g8_a_bucks_member) }, style = MaterialTheme.typography.bodyMedium)
                                Muted(if (v.times > 1) pluralStringResource(R.plurals.g8_doc_viewed_times, v.times, v.docTitle, humanDate(v.lastAt), v.times) else "${v.docTitle} · ${humanDate(v.lastAt)}")
                            }
                        }
                    }
                }
            }
        }
    }

    viewing?.let { d -> ShowcaseDocViewer(vm, d, mine = true, onClose = { viewing = null }, onChanged = {}) }
    if (adding) DocEditorSheet(vm, listingId, null, onDone = { adding = false; reload++ }, onDismiss = { adding = false })
    editing?.let { d -> DocEditorSheet(vm, listingId, d, onDone = { editing = null; reload++ }, onDismiss = { editing = null }) }
    removing?.let { d ->
        ConfirmDialog(stringResource(R.string.g8_remove_name_q, d.title), stringResource(R.string.g8_remove_doc_body), stringResource(R.string.g8_remove),
            onConfirm = { act("x" + d.id, Str.get(R.string.g8_doc_removed)) { Backend.removeShowcaseFile(Backend.removeShowcaseDoc(d.id)) } }, onDismiss = { removing = null })
    }
}

/** One document in the team's list: what it is, who can open it, its number and expiry, what viewers said, and requests waiting. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ManageDocCard(d: ShowcaseDoc, modifier: Modifier, onOpen: () -> Unit, onEdit: () -> Unit, onRemove: () -> Unit) = BucksCard(modifier, padding = 14) {
    Row(verticalAlignment = Alignment.Top) {
        Avatar(icon = docKindIcon(d.kind), size = 40)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(d.title, style = MaterialTheme.typography.titleSmall)
            Muted(listOfNotNull(ShowcaseKinds.label(d.kind), d.issuer.ifBlank { null }).joinToString(" · "))
        }
        if (d.pendingRequests > 0) PillWarn(stringResource(R.string.g8_n_waiting, d.pendingRequests))
    }
    DocPills(d, Modifier.padding(top = 10.dp), selfLabelled = d.kind == "OTHER")
    if (d.number.isNotBlank()) Text(Registries.all.firstOrNull { it.first == d.registry }?.let { stringResource(R.string.g8_doc_number_link, d.number, it.second) } ?: stringResource(R.string.g8_doc_number, d.number), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp))
    Muted(if (d.checks == 0) stringResource(R.string.g8_no_opinions) else stringResource(R.string.g8_opinions, d.checksUp, d.checksDown), Modifier.padding(top = 4.dp))
    FlowRow(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        DocButton(stringResource(R.string.g8_open), onOpen, tonal = true)
        DocButton(stringResource(R.string.g8_edit), onEdit, tonal = true)
        DocButton(stringResource(R.string.g8_remove), onRemove, tonal = true)
    }
}

/** Add (existing == null: choose a file first) or edit one document's details and who may open it. The file itself cannot be swapped: remove and add again. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DocEditorSheet(vm: BucksViewModel, listingId: String, existing: ShowcaseDoc?, onDone: () -> Unit, onDismiss: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf(existing?.kind ?: "REGISTRATION") }
    var title by remember { mutableStateOf(existing?.title ?: ShowcaseKinds.label("REGISTRATION")) }
    var titleTouched by remember { mutableStateOf(existing != null) }
    var issuer by remember { mutableStateOf(existing?.issuer.orEmpty()) }
    var number by remember { mutableStateOf(existing?.number.orEmpty()) }
    var registry by remember { mutableStateOf(existing?.registry?.takeIf { it.isNotBlank() }) }
    var visibility by remember { mutableStateOf(existing?.visibility ?: ShowcaseKinds.defaultVisibility("REGISTRATION")) }
    var expires by remember { mutableStateOf(existing?.expiresOn?.let { runCatching { LocalDate.parse(it.take(10)) }.getOrNull() }) }
    var file by remember { mutableStateOf<Picked?>(null) }
    var choosing by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val f = withContext(kotlinx.coroutines.Dispatchers.IO) { Upload.read(ctx, uri, maxPx = 2400) }
            when {
                f == null -> vm.toast(Str.get(R.string.g8_file_unreadable))
                f.bytes.size > SHOWCASE_MAX_BYTES -> vm.toast(Str.get(R.string.g8_file_too_big))
                f.mime !in SHOWCASE_MIMES -> vm.toast(Str.get(R.string.g8_file_types))
                else -> file = f
            }
        }
    }
    val showNumber = ShowcaseKinds.hasNumber(kind) || number.isNotBlank() || registry != null
    val valid = title.trim().length in 2..60 && (existing != null || file != null) && (registry == null || number.isNotBlank())

    fun save() { scope.launch {
        busy = true
        var uploaded: String? = null
        try {
            if (existing != null) {
                Backend.updateShowcaseDoc(existing.id, title.trim(), issuer.trim(), number.trim(), registry, visibility, expires?.toString())
                vm.toast(Str.get(R.string.g8_saved))
            } else {
                val me = vm.social.me?.id; val f = file
                if (me == null || f == null) { vm.toast(Str.get(R.string.g8_choose_file_first)); busy = false; return@launch }
                val path = Backend.uploadShowcaseFile(me, f.bytes, f.mime)
                uploaded = path
                Backend.addShowcaseDoc(listingId, kind, title.trim(), issuer.trim(), number.trim(), registry, path, f.mime, f.bytes.size, visibility, expires?.toString())
                vm.toast(Str.get(R.string.g8_doc_added))
            }
            onDone()
        } catch (e: CancellationException) { throw e } catch (e: Exception) {
            vm.toast(friendly(e))
            // The file went up but the server refused the document (for instance a name it rejects): don't leave the file behind.
            // A timeout or lost reply says nothing about whether the row was saved, so the file stays then.
            if (e is io.github.jan.supabase.exceptions.RestException) uploaded?.let { Backend.removeShowcaseFile(it) }
        }
        busy = false
    } }

    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(if (existing == null) stringResource(R.string.g8_add_document) else stringResource(R.string.g8_edit_document), style = MaterialTheme.typography.titleLarge)
            if (existing == null) {
                Text(stringResource(R.string.g8_what_is_it), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp))
                FlowChips(ShowcaseKinds.all.map { it.second }, setOf(ShowcaseKinds.label(kind))) { label ->
                    val k = ShowcaseKinds.all.first { it.second == label }.first
                    if (!titleTouched || title.isBlank()) title = if (k == "OTHER") "" else label
                    kind = k; visibility = ShowcaseKinds.defaultVisibility(k)
                }
                Muted(ShowcaseKinds.all.first { it.first == kind }.third, Modifier.padding(top = 6.dp))
                OutlinedButton({ picker.launch(arrayOf("image/*", "application/pdf")) }, Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 48.dp), enabled = !busy) {
                    Text(file?.let { stringResource(R.string.g8_file_name, it.name) } ?: stringResource(R.string.g8_choose_file)) }
            } else Muted(stringResource(R.string.g8_doc_change_file, ShowcaseKinds.label(existing.kind)), Modifier.padding(top = 4.dp))

            OutlinedTextField(title, { title = it.take(60); titleTouched = true }, Modifier.padding(top = 12.dp).fillMaxWidth(), singleLine = true,
                label = { Text(if (kind == "OTHER") stringResource(R.string.g8_doc_name) else stringResource(R.string.g8_title)) },
                supportingText = { Text(if (kind == "OTHER") stringResource(R.string.g8_doc_name_help_other) else stringResource(R.string.g8_doc_name_help)) })
            OutlinedTextField(issuer, { issuer = it.take(80) }, Modifier.padding(top = 4.dp).fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.g8_issued_by)) }, placeholder = { Text(stringResource(R.string.g8_issued_by_hint)) })
            if (showNumber) {
                OutlinedTextField(number, { number = it.take(40) }, Modifier.padding(top = 4.dp).fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.g8_reg_number)) },
                    supportingText = { Text(stringResource(R.string.g8_reg_number_help)) })
                Text(stringResource(R.string.g8_where_check), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
                val noneLabel = stringResource(R.string.g8_none)
                FlowChips(listOf(noneLabel) + Registries.all.map { it.second }, setOf(Registries.all.firstOrNull { it.first == registry }?.second ?: noneLabel)) { label ->
                    registry = Registries.all.firstOrNull { it.second == label }?.first
                }
                Muted(if (registry == null) stringResource(R.string.g8_registry_help) else stringResource(R.string.g8_registry_needs_number), Modifier.padding(top = 6.dp))
            }

            Text(stringResource(R.string.g8_who_can_open), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp))
            listOf(
                Triple("PUBLIC", stringResource(R.string.g8_vis_public), stringResource(R.string.g8_vis_public_sub)),
                Triple("ON_REQUEST", stringResource(R.string.g8_vis_request), stringResource(R.string.g8_vis_request_sub)),
                Triple("PRIVATE", stringResource(R.string.g8_vis_team), stringResource(R.string.g8_vis_team_sub))).forEach { (v, label, hint) ->
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(visibility == v, role = Role.RadioButton, onClick = { visibility = v }), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(visibility == v, onClick = null, modifier = Modifier.padding(end = 12.dp))
                    Column { Text(label, style = MaterialTheme.typography.bodyLarge); Muted(hint) }
                }
            }

            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton({ choosing = true }, Modifier.heightIn(min = 48.dp).weight(1f)) { Text(expires?.let { stringResource(R.string.g8_valid_till_date, humanDate(it.toString())) } ?: stringResource(R.string.g8_expiry_optional)) }
                if (expires != null) TextButton({ expires = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.g8_cd_clear)) }
            }
            Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                DocButton(if (busy) stringResource(R.string.g8_saving) else stringResource(R.string.g8_save), { save() }, enabled = valid && !busy)
                TextButton(onDismiss, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(stringResource(R.string.g8_cancel)) }
            }
        }
    }
    if (choosing) {
        val today = LocalDate.now().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today })
        DatePickerDialog(onDismissRequest = { choosing = false },
            confirmButton = { TextButton({ state.selectedDateMillis?.let { expires = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; choosing = false }) { Text(stringResource(R.string.g8_ok)) } },
            dismissButton = { TextButton({ choosing = false }) { Text(stringResource(R.string.g8_cancel)) } }) { DatePicker(state) }
    }
}
