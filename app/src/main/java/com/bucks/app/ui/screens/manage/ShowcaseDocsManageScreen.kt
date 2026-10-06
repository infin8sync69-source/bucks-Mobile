package com.bucks.app.ui.screens.manage

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
    ?: "Couldn't do that. Check your connection and try again."

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
        BucksTopBar("Documents to show", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            val l = m.listing(listingId)
            if (l != null) Text(l.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp))
            when {
                !m.loaded -> CenteredLoading()
                !allowed -> Muted("Only the owner or an admin can manage the documents shown on this profile.")
                else -> {
                    Notice("These appear on your public profile, as you choose below. They are separate from the checks Bucks does for going live: nothing here is \"checked by Bucks\" unless Bucks staff say so.")
                    val list = docs
                    Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Your documents", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (list != null) Muted("${list.size} of 20")
                    }
                    when {
                        list == null && loadError != null -> LoadError(loadError.orEmpty(), Modifier.padding(top = 8.dp)) { loadError = null; reload++ }
                        list == null -> CenteredLoading()
                        else -> {
                            if (list.isEmpty()) Muted("No documents yet. Registrations, licences, certificates and awards help people trust a page.", Modifier.padding(top = 8.dp))
                            list.forEach { d -> ManageDocCard(d, Modifier.padding(top = 10.dp), onOpen = { viewing = d }, onEdit = { editing = d }, onRemove = { removing = d }) }
                            if (list.size < 20) DocButton("Add a document", { adding = true }, Modifier.padding(top = 12.dp), icon = Icons.Rounded.Add)
                            else Muted("You have reached 20 documents. Remove one to add another.", Modifier.padding(top = 12.dp))
                        }
                    }

                    SectionTitle("Requests", Modifier.padding(top = 24.dp))
                    Muted("People ask to see documents marked On request. You choose; approving lasts 30 days and you can revoke it any time.", Modifier.padding(top = 2.dp, bottom = 4.dp))
                    if (requests.isEmpty() && sideFailed) Muted("Couldn't load requests. Check your connection and pull to retry.", Modifier.padding(top = 4.dp))
                    else if (requests.isEmpty()) Muted("No requests right now.", Modifier.padding(top = 4.dp))
                    requests.forEach { r ->
                        BucksCard(Modifier.padding(top = 10.dp), padding = 14) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(r.requesterName.ifBlank { "A Bucks member" }, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                                if (r.status == "PENDING") PillWarn("Waiting") else PillGood("Approved")
                            }
                            Muted("For ${r.docTitle}" + if (r.relation.isNotBlank()) " · ${r.relation}" else "", Modifier.padding(top = 2.dp))
                            if (r.message.isNotBlank()) Text("\"${r.message}\"", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                            if (r.status == "PENDING") Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                DocButton("Approve 30 days", { act("a" + r.id, "Approved for 30 days. They've been told.") { Backend.decideDocRequest(r.id, true, 30) } }, enabled = busyId == null)
                                DocButton("Decline", { act("d" + r.id, "Declined. They've been told.") { Backend.decideDocRequest(r.id, false) } }, tonal = true, enabled = busyId == null)
                            } else {
                                Muted("Can open until ${humanDate(r.expiresAt)}", Modifier.padding(top = 6.dp))
                                DocButton("Revoke", { act("r" + r.id, "Access ended.") { Backend.revokeDocAccess(r.id) } }, Modifier.padding(top = 4.dp), tonal = true, enabled = busyId == null)
                            }
                        }
                    }

                    SectionTitle("Who looked", Modifier.padding(top = 24.dp))
                    Muted("The last 50 people who opened one of your documents. Team members are not listed.", Modifier.padding(top = 2.dp, bottom = 4.dp))
                    if (views.isEmpty() && sideFailed) Muted("Couldn't load who looked.", Modifier.padding(top = 4.dp))
                    else if (views.isEmpty()) Muted("Nobody has opened a document yet.", Modifier.padding(top = 4.dp))
                    views.forEach { v ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(v.viewerName.ifBlank { "A Bucks member" }, style = MaterialTheme.typography.bodyMedium)
                                Muted("${v.docTitle} · ${humanDate(v.lastAt)}" + if (v.times > 1) " · ${v.times} times" else "")
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
        ConfirmDialog("Remove ${d.title}?", "The file is deleted and anyone who had access loses it. You can add it again later.", "Remove",
            onConfirm = { act("x" + d.id, "Document removed.") { Backend.removeShowcaseFile(Backend.removeShowcaseDoc(d.id)) } }, onDismiss = { removing = null })
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
        if (d.pendingRequests > 0) PillWarn("${d.pendingRequests} waiting")
    }
    DocPills(d, Modifier.padding(top = 10.dp), selfLabelled = d.kind == "OTHER")
    if (d.number.isNotBlank()) Text("No. ${d.number}" + (Registries.all.firstOrNull { it.first == d.registry }?.let { " · ${it.second} link shown" } ?: ""), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 6.dp))
    Muted(if (d.checks == 0) "No viewer opinions yet." else "Viewer opinions (not a Bucks check): ${d.checksUp} say it looks genuine, ${d.checksDown} say it doesn't look right.", Modifier.padding(top = 4.dp))
    FlowRow(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        DocButton("Open", onOpen, tonal = true)
        DocButton("Edit", onEdit, tonal = true)
        DocButton("Remove", onRemove, tonal = true)
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
                f == null -> vm.toast("Couldn't read that file. Try a photo of the document.")
                f.bytes.size > SHOWCASE_MAX_BYTES -> vm.toast("Documents up to 10 MB. Take a smaller photo.")
                f.mime !in SHOWCASE_MIMES -> vm.toast("PDF, JPG or PNG only.")
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
                vm.toast("Saved.")
            } else {
                val me = vm.social.me?.id; val f = file
                if (me == null || f == null) { vm.toast("Choose a file first."); busy = false; return@launch }
                val path = Backend.uploadShowcaseFile(me, f.bytes, f.mime)
                uploaded = path
                Backend.addShowcaseDoc(listingId, kind, title.trim(), issuer.trim(), number.trim(), registry, path, f.mime, f.bytes.size, visibility, expires?.toString())
                vm.toast("Document added.")
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
            Text(if (existing == null) "Add a document" else "Edit document", style = MaterialTheme.typography.titleLarge)
            if (existing == null) {
                Text("What is it?", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 12.dp, bottom = 6.dp))
                FlowChips(ShowcaseKinds.all.map { it.second }, setOf(ShowcaseKinds.label(kind))) { label ->
                    val k = ShowcaseKinds.all.first { it.second == label }.first
                    if (!titleTouched || title.isBlank()) title = if (k == "OTHER") "" else label
                    kind = k; visibility = ShowcaseKinds.defaultVisibility(k)
                }
                Muted(ShowcaseKinds.all.first { it.first == kind }.third, Modifier.padding(top = 6.dp))
                OutlinedButton({ picker.launch(arrayOf("image/*", "application/pdf")) }, Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 48.dp), enabled = !busy) {
                    Text(file?.let { "File: ${it.name}" } ?: "Choose the file (PDF, JPG or PNG, up to 10 MB)") }
            } else Muted("${ShowcaseKinds.label(existing.kind)}. To use a different file, remove this document and add it again.", Modifier.padding(top = 4.dp))

            OutlinedTextField(title, { title = it.take(60); titleTouched = true }, Modifier.padding(top = 12.dp).fillMaxWidth(), singleLine = true,
                label = { Text(if (kind == "OTHER") "Name of the document" else "Title") },
                supportingText = { Text(if (kind == "OTHER") "You choose the name, 2 to 60 characters. It is shown as self-labelled. Names with \"verified\" or \"Bucks\" are not allowed." else "2 to 60 characters. Names with \"verified\" or \"Bucks\" are not allowed.") })
            OutlinedTextField(issuer, { issuer = it.take(80) }, Modifier.padding(top = 4.dp).fillMaxWidth(), singleLine = true, label = { Text("Issued by (optional)") }, placeholder = { Text("Registrar of Companies, FSSAI, a university...") })
            if (showNumber) {
                OutlinedTextField(number, { number = it.take(40) }, Modifier.padding(top = 4.dp).fillMaxWidth(), singleLine = true, label = { Text("Registration number (optional)") },
                    supportingText = { Text("People who may open the document see it. It is shown only as you typed it; Bucks does not check it.") })
                Text("Where can people check it?", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
                FlowChips(listOf("None") + Registries.all.map { it.second }, setOf(Registries.all.firstOrNull { it.first == registry }?.second ?: "None")) { label ->
                    registry = Registries.all.firstOrNull { it.second == label }?.first
                }
                Muted(if (registry == null) "Pick a registry to add a \"Check on official site\" link. It opens the registry's own website; viewers search there." else "Needs the number above. GST: 15 characters. FSSAI: 14 digits.", Modifier.padding(top = 6.dp))
            }

            Text("Who can open it?", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp))
            listOf(
                Triple("PUBLIC", "Public", "Anyone signed in can open it."),
                Triple("ON_REQUEST", "On request", "People see it is there and ask you. You approve for 30 days or decline, and can revoke."),
                Triple("PRIVATE", "Team only", "Only your team sees it. Choosing this ends any access already given.")).forEach { (v, label, hint) ->
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(visibility == v, role = Role.RadioButton, onClick = { visibility = v }), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(visibility == v, onClick = null, modifier = Modifier.padding(end = 12.dp))
                    Column { Text(label, style = MaterialTheme.typography.bodyLarge); Muted(hint) }
                }
            }

            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton({ choosing = true }, Modifier.heightIn(min = 48.dp).weight(1f)) { Text(expires?.let { "Valid till ${humanDate(it.toString())}" } ?: "Expiry date (optional)") }
                if (expires != null) TextButton({ expires = null }, Modifier.heightIn(min = 48.dp)) { Text("Clear") }
            }
            Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                DocButton(if (busy) "Saving…" else "Save", { save() }, enabled = valid && !busy)
                TextButton(onDismiss, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text("Cancel") }
            }
        }
    }
    if (choosing) {
        val today = LocalDate.now().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= today })
        DatePickerDialog(onDismissRequest = { choosing = false },
            confirmButton = { TextButton({ state.selectedDateMillis?.let { expires = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; choosing = false }) { Text("OK") } },
            dismissButton = { TextButton({ choosing = false }) { Text("Cancel") } }) { DatePicker(state) }
    }
}
