package com.bucks.app.ui.screens.manage

import com.bucks.app.data.Money
import com.bucks.app.data.Str
import com.bucks.app.R
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Picked
import com.bucks.app.data.Upload
import com.bucks.app.data.VehicleDoc
import com.bucks.app.data.VehicleRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.SignedImage

private const val MAX_DOC_BYTES = 10 * 1024 * 1024

@Composable
private fun StatusPill(v: VehicleRow) { when (v.status) { "ACTIVE" -> PillGood(stringResource(R.string.g5_veh_active)); "SUSPENDED" -> PillBad(stringResource(R.string.g5_veh_suspended)); else -> PillWarn(stringResource(R.string.g5_veh_checking)) } }

/** Vehicles I own or drive: status, who drives them, and the owner dashboard. */
@Composable
fun VehiclesScreen(vm: BucksViewModel, onBack: () -> Unit, onEdit: (id: String?) -> Unit, onStats: () -> Unit, onMembers: (vehicleId: String) -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refresh() }
    LaunchedEffect(m.vehicles) { if (m.vehicles.isNotEmpty()) m.loadAllVehicleMembers() }
    // Taxi licences for the vehicles I own (status only; supabase/migrations/billing.sql). Empty while billing is off.
    val plans = rememberMyLicences(m.vehicles.map { it.id to it.status })
    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(stringResource(R.string.g5_veh_title), onBack = onBack, actions = { IconButton(onClick = onStats) { Icon(Icons.Rounded.Leaderboard, stringResource(R.string.g5_veh_stats)) } })
            if (m.loading && !m.loaded) LinearProgressIndicator(Modifier.fillMaxWidth())
            LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val err = m.error
                if (err != null && !m.loaded && m.vehicles.isEmpty()) item { LoadError(err) { m.refresh() } }
                if (m.vehicles.isEmpty() && m.loaded) item {
                    BucksCard {
                        Text(stringResource(R.string.g5_veh_none), style = MaterialTheme.typography.titleMedium)
                        Muted(stringResource(R.string.g5_veh_none_body), Modifier.padding(top = 4.dp))
                    }
                }
                items(m.vehicles, key = { it.id }) { v ->
                    val owner = v.ownerId == m.me?.id; val people = m.vehicleMembers[v.id]; val docs = m.vehicleDocs[v.id].orEmpty()
                    BucksCard {
                        Row(verticalAlignment = Alignment.Top) {
                            Avatar(icon = vehicleIcon(v.kind), size = 56)
                            Column(Modifier.weight(1f).padding(start = 14.dp)) {
                                Text(v.model.ifBlank { vehicleKindLabel(v.kind) }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Muted(stringResource(R.string.g5_acct_amount_status, vehicleKindLabel(v.kind), v.plate))
                                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { StatusPill(v); if (!owner) PillGrey(stringResource(R.string.g5_veh_driver)) }
                            }
                        }
                        Muted(when (v.status) {
                            "ACTIVE" -> stringResource(if (v.kind == "BIKE") R.string.g5_veh_ready_deliveries else R.string.g5_veh_ready_rides)
                            "SUSPENDED" -> stringResource(R.string.g5_veh_suspended_body)
                            else -> vehicleDocKinds(v.kind).filter { dk -> dk.required && docs.none { it.kind == dk.key } }.takeIf { it.isNotEmpty() && owner }
                                ?.let { missing -> stringResource(R.string.g5_veh_still_needed, missing.joinToString(", ") { it.label }) }
                                ?: stringResource(R.string.g5_veh_checking_body)
                        }, Modifier.padding(top = 10.dp))
                        Muted(when { people == null -> "…"; people.size <= 1 -> stringResource(R.string.g5_veh_only_you); else -> pluralStringResource(R.plurals.g5_veh_people_drive, people.size, people.size) }, Modifier.padding(top = 4.dp))
                        if (owner) plans?.firstOrNull { it.vehicleId == v.id }?.let { PlanStatus(it, vehicle = true, modifier = Modifier.padding(top = 12.dp)) }
                        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (owner) SmallButton(stringResource(R.string.g5_edit), tonal = true) { onEdit(v.id) }
                            SmallButton(stringResource(R.string.g5_veh_drivers), tonal = true) { onMembers(v.id) }
                        }
                    }
                }
                if (m.vehicles.isNotEmpty()) item { GhostButton(stringResource(R.string.g5_veh_stats), onClick = onStats) }
            }
        }
        PrimaryButton(stringResource(R.string.g5_veh_add), Modifier.padding(horizontal = Gutter, vertical = 12.dp)) { onEdit(null) }
    }
}

/** Add or edit a vehicle; documents go to the private docs bucket under my folder. Only the owner can save. */
@Composable
fun VehicleEditScreen(vm: BucksViewModel, id: String?, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { if (!m.loaded) m.refresh() }
    val existing = id?.let { m.vehicle(it) }
    // The form snapshots the documents once, and Save writes that list back, so it must not open before they are known:
    // an empty snapshot would wipe the RC, insurance and permit references (and their files) on the next Save.
    if (id != null && (existing == null || !m.vehicleDocs.containsKey(id))) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g5_veh_edit), onBack = onBack)
            val err = m.error
            if (m.loaded && existing == null) Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g5_veh_not_found), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g5_veh_not_found_body), Modifier.padding(top = 4.dp)); SmallButton(stringResource(R.string.g5_back), Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else if (err != null && !m.loaded) LoadError(err, Modifier.padding(Gutter)) { m.refresh() }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { VehicleForm(vm, existing, onBack) }
}

@Composable
private fun VehicleForm(vm: BucksViewModel, existing: VehicleRow?, onBack: () -> Unit) {
    val m = vm.myListings; val ctx = LocalContext.current
    var kind by remember { mutableStateOf(existing?.kind ?: "") }
    var model by remember { mutableStateOf(existing?.model ?: "") }
    var plate by remember { mutableStateOf(existing?.plate ?: "") }
    /** The documents the form opened with; Save deletes the files among these that the owner removed, nothing else. */
    val before = remember { m.vehicleDocs[existing?.id].orEmpty() }
    val kept = remember { mutableStateListOf<VehicleDoc>().apply { addAll(before) } }
    val added = remember { mutableStateMapOf<String, Picked>() }
    var pickingFor by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val owner = existing == null || existing.ownerId == m.me?.id
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val k = pickingFor; pickingFor = null
        if (uri != null && k != null) {
            val f = Upload.read(ctx, uri)
            when {
                f == null -> vm.toast(Str.get(R.string.g5_doc_read_failed))
                f.bytes.size > MAX_DOC_BYTES -> vm.toast(Str.get(R.string.g5_doc_too_big))
                !(f.isImage || f.mime == "application/pdf") -> vm.toast(Str.get(R.string.g5_doc_types))
                else -> { added[k] = f; kept.removeAll { it.kind == k } }
            }
        }
    }
    fun pickDoc(k: String) { pickingFor = k; picker.launch(arrayOf("image/*", "application/pdf")) }

    fun save() {
        val p = plate.trim().uppercase().replace(" ", "")
        if (kind.isBlank()) { vm.toast(Str.get(R.string.g5_veh_pick_type)); return }
        if (p.length < 6) { vm.toast(Str.get(R.string.g5_veh_plate_short)); return }
        if (existing == null) m.addVehicle(kind, model.trim(), p, added.map { it.key to it.value }) { onBack() }
        else m.updateVehicle(existing.id, kind, model.trim(), p, before, kept.toList(), added.map { it.key to it.value }) { onBack() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(stringResource(if (existing == null) R.string.g5_veh_add else R.string.g5_veh_edit), onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                if (!owner) Notice(stringResource(R.string.g5_veh_not_owner), Modifier.padding(bottom = 14.dp))
                else if (existing?.status == "ACTIVE") Notice(stringResource(R.string.g5_veh_active_warn), Modifier.padding(bottom = 14.dp))
                Label(stringResource(R.string.g5_veh_type))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VEHICLE_KINDS.forEach { (k, l) -> Chip(l, selected = kind == k, icon = vehicleIcon(k)) { if (owner) kind = k } } }
                Spacer(Modifier.height(14.dp))
                BucksField(model, { if (owner) model = it.take(60) }, stringResource(R.string.g5_veh_model), stringResource(R.string.g5_veh_model_hint), readOnly = !owner)
                BucksField(plate, { if (owner) plate = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(12) }, stringResource(R.string.g5_veh_plate), "KA05AB1234", readOnly = !owner, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
                val kinds = vehicleDocKinds(kind.ifBlank { "CAB" })
                val requiredDone = kinds.count { dk -> dk.required && (added.containsKey(dk.key) || kept.any { it.kind == dk.key }) }; val requiredAll = kinds.count { it.required }
                Row(Modifier.padding(top = 4.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionTitle(stringResource(R.string.g5_veh_documents), Modifier.weight(1f)); if (requiredDone == requiredAll) PillGood(stringResource(R.string.g5_veh_all_required)) else PillWarn(stringResource(R.string.g5_veh_n_of_m_required, requiredDone, requiredAll))
                }
                LinearProgressIndicator(progress = { requiredDone.toFloat() / requiredAll }, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp).height(4.dp).clip(MaterialTheme.shapes.small))
                Muted(stringResource(R.string.g5_veh_docs_note), Modifier.padding(bottom = 8.dp))
                kinds.forEach { dk -> val k = dk.key; val label = dk.label
                    val have = kept.firstOrNull { it.kind == k }; val new = added[k]
                    val optional = !dk.required
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(56.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                            when {
                                new != null -> Icon(if (new.isImage) Icons.Rounded.Image else Icons.Rounded.PictureAsPdf, null, tint = MaterialTheme.colorScheme.primary)
                                have != null && !have.path.endsWith(".pdf") -> SignedImage(vm, "docs", have.path, Modifier.fillMaxSize())
                                have != null -> Icon(Icons.Rounded.PictureAsPdf, null, tint = MaterialTheme.colorScheme.primary)
                                else -> Icon(Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            Text(if (optional) stringResource(R.string.g5_optional_label, label) else label, style = MaterialTheme.typography.titleSmall)
                            Muted(when { new != null -> stringResource(R.string.g5_ready_to_upload, new.name); have != null -> stringResource(R.string.g5_uploaded); else -> dk.hint })
                        }
                        if (owner) {
                            if (new != null || have != null) IconButton(onClick = { added.remove(k); kept.removeAll { it.kind == k } }) { Icon(Icons.Rounded.Close, stringResource(R.string.g5_remove)) }
                            SmallButton(stringResource(if (new != null || have != null) R.string.g5_replace else R.string.g5_add), tonal = true) { pickDoc(k) }
                        }
                    }
                    Divider()
                }
            }
        }
        if (owner) Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(stringResource(if (m.busy) R.string.g5_uploading else if (existing == null) R.string.g5_veh_add else R.string.g5_save_changes), enabled = !m.busy) { save() }
            if (existing != null) BadButton(stringResource(R.string.g5_veh_remove), Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog(stringResource(R.string.g5_veh_remove_title, existing.model.ifBlank { vehicleKindLabel(existing.kind) }, existing.plate), stringResource(R.string.g5_veh_remove_body), stringResource(R.string.g5_remove),
        onConfirm = { m.deleteVehicle(existing.id) { onBack() } }, onDismiss = { confirmDelete = false })
}

/** Owner dashboard: per vehicle, the last 30 days from the vehicle_stats view. */
@Composable
fun VehicleStatsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refreshStats(); if (!m.loaded) m.refresh() }
    val rows = m.stats
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g5_veh_stats), onBack = onBack)
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                BucksCard(tint = true) {
                    Muted(stringResource(R.string.g5_veh_last30))
                    Text(Money.format(rows.sumOf { it.earnings }), style = MaterialTheme.typography.displaySmall)
                    Muted(pluralStringResource(R.plurals.g5_veh_trips_km, rows.sumOf { it.completed }, rows.sumOf { it.completed }, "%.1f".format(rows.sumOf { it.km })))
                }
            }
            if (rows.isEmpty()) item {
                BucksCard {
                    Text(stringResource(if (m.loaded && m.vehicles.isEmpty()) R.string.g5_veh_none else R.string.g5_nothing_yet), style = MaterialTheme.typography.titleMedium)
                    Muted(stringResource(if (m.loaded && m.vehicles.isEmpty()) R.string.g5_veh_stats_no_vehicle else R.string.g5_veh_stats_empty), Modifier.padding(top = 4.dp))
                }
            }
            items(rows, key = { it.vehicleId }) { s ->
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(icon = vehicleIcon(s.kind), size = 44)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) { Text(s.model.ifBlank { vehicleKindLabel(s.kind) }, style = MaterialTheme.typography.titleMedium); Muted(s.plate) }
                        Text(Money.format(s.earnings), style = MaterialTheme.typography.titleLarge)
                    }
                    Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Stat("${s.accepted}", stringResource(R.string.g5_stat_accepted)); Stat("${s.rejected}", stringResource(R.string.g5_stat_missed)); Stat("${s.completed}", stringResource(R.string.g5_stat_completed)); Stat("%.1f".format(s.km), stringResource(R.string.g5_stat_km))
                    }
                    if (s.accepted + s.rejected > 0 && s.rejected > s.accepted) Muted(stringResource(R.string.g5_veh_missed_warn), Modifier.padding(top = 10.dp))
                }
            }
        }
    }
}
@Composable
private fun RowScope.Stat(value: String, label: String) = Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Text(value, style = MaterialTheme.typography.titleLarge); Muted(label) }
