package com.bucks.app.ui.screens.manage

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

private val DOC_KINDS = listOf("RC" to "Registration certificate (RC)", "INSURANCE" to "Insurance", "PERMIT" to "Permit")
private const val MAX_DOC_BYTES = 10 * 1024 * 1024

@Composable
private fun StatusPill(v: VehicleRow) { when (v.status) { "ACTIVE" -> PillGood("Active"); "SUSPENDED" -> PillBad("Suspended"); else -> PillWarn("Documents being checked") } }

/** Vehicles I own or drive: status, who drives them, and the owner dashboard. */
@Composable
fun VehiclesScreen(vm: BucksViewModel, onBack: () -> Unit, onEdit: (id: String?) -> Unit, onStats: () -> Unit, onMembers: (vehicleId: String) -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refresh() }
    LaunchedEffect(m.vehicles) { if (m.vehicles.isNotEmpty()) m.loadAllVehicleMembers() }
    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar("Vehicles", onBack = onBack, actions = { IconButton(onClick = onStats) { Icon(Icons.Rounded.Leaderboard, "Earnings and trips") } })
            if (m.loading && !m.loaded) LinearProgressIndicator(Modifier.fillMaxWidth())
            LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (m.vehicles.isEmpty() && m.loaded) item {
                    BucksCard {
                        Text("No vehicles yet", style = MaterialTheme.typography.titleMedium)
                        Muted("Add the bike, auto or cab you drive with its RC, insurance and permit photos. Bucks checks them, then you can go online and take rides or deliveries. You can also invite other drivers to use your vehicle.", Modifier.padding(top = 4.dp))
                    }
                }
                items(m.vehicles, key = { it.id }) { v ->
                    val owner = v.ownerId == m.me?.id; val people = m.vehicleMembers[v.id]; val docs = m.vehicleDocs[v.id].orEmpty()
                    BucksCard {
                        Row(verticalAlignment = Alignment.Top) {
                            Avatar(icon = vehicleIcon(v.kind), size = 56)
                            Column(Modifier.weight(1f).padding(start = 14.dp)) {
                                Text(v.model.ifBlank { vehicleKindLabel(v.kind) }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Muted("${vehicleKindLabel(v.kind)} · ${v.plate}")
                                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { StatusPill(v); if (!owner) PillGrey("Driver") }
                            }
                        }
                        Muted(when (v.status) {
                            "ACTIVE" -> "Ready. Go online from Home to take " + (if (v.kind == "BIKE") "deliveries." else "rides and deliveries.")
                            "SUSPENDED" -> "Suspended: it can't go online. Contact Bucks support."
                            else -> if (docs.size < 3 && owner) "Upload all three documents (RC, insurance, permit) so Bucks can check the vehicle." else "Bucks is checking the documents. You'll be able to go online once it's active."
                        }, Modifier.padding(top = 10.dp))
                        Muted(when { people == null -> "…"; people.size <= 1 -> "Only you drive it"; else -> "${people.size} people can drive it" }, Modifier.padding(top = 4.dp))
                        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (owner) SmallButton("Edit", tonal = true) { onEdit(v.id) }
                            SmallButton("Drivers", tonal = true) { onMembers(v.id) }
                        }
                    }
                }
                if (m.vehicles.isNotEmpty()) item { GhostButton("Earnings and trips", onClick = onStats) }
            }
        }
        PrimaryButton("Add vehicle", Modifier.padding(horizontal = Gutter, vertical = 12.dp)) { onEdit(null) }
    }
}

/** Add or edit a vehicle; documents go to the private docs bucket under my folder. Only the owner can save. */
@Composable
fun VehicleEditScreen(vm: BucksViewModel, id: String?, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { if (!m.loaded) m.refresh() }
    val existing = id?.let { m.vehicle(it) }
    if (id != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Edit vehicle", onBack = onBack)
            if (m.loaded) Column(Modifier.padding(Gutter)) { Text("Vehicle not found", style = MaterialTheme.typography.titleMedium); Muted("It may have been removed, or you no longer drive it.", Modifier.padding(top = 4.dp)); SmallButton("Back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
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
    val kept = remember { mutableStateListOf<VehicleDoc>().apply { addAll(m.vehicleDocs[existing?.id].orEmpty()) } }
    val added = remember { mutableStateMapOf<String, Picked>() }
    var pickingFor by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val owner = existing == null || existing.ownerId == m.me?.id
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val k = pickingFor; pickingFor = null
        if (uri != null && k != null) {
            val f = Upload.read(ctx, uri)
            when {
                f == null -> vm.toast("Couldn't read that file. Try a photo of the document.")
                f.bytes.size > MAX_DOC_BYTES -> vm.toast("Documents up to 10 MB. Take a smaller photo.")
                !(f.isImage || f.mime == "application/pdf") -> vm.toast("Photos (JPG, PNG) or PDF only.")
                else -> { added[k] = f; kept.removeAll { it.kind == k } }
            }
        }
    }
    fun pickDoc(k: String) { pickingFor = k; picker.launch(arrayOf("image/*", "application/pdf")) }

    fun save() {
        val p = plate.trim().uppercase().replace(" ", "")
        if (kind.isBlank()) { vm.toast("Pick the vehicle type."); return }
        if (p.length < 6) { vm.toast("Enter the full number plate, like KA05AB1234."); return }
        if (existing == null) m.addVehicle(kind, model.trim(), p, added.map { it.key to it.value }) { onBack() }
        else m.updateVehicle(existing.id, kind, model.trim(), p, kept.toList(), added.map { it.key to it.value }) { onBack() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (existing == null) "Add vehicle" else "Edit vehicle", onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                if (!owner) Notice("You drive this vehicle but don't own it, so only the owner can change it.", Modifier.padding(bottom = 14.dp))
                Label("Vehicle type")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VEHICLE_KINDS.forEach { (k, l) -> Chip(l, selected = kind == k, icon = vehicleIcon(k)) { if (owner) kind = k } } }
                Spacer(Modifier.height(14.dp))
                BucksField(model, { if (owner) model = it.take(60) }, "Model", "Honda Activa, Bajaj RE, Maruti Dzire", readOnly = !owner)
                BucksField(plate, { if (owner) plate = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(12) }, "Number plate", "KA05AB1234", readOnly = !owner, keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
                SectionTitle("Documents", Modifier.padding(top = 4.dp, bottom = 2.dp))
                Muted("Photos of the RC, insurance and permit. Bucks checks them before the vehicle can go online; nobody else sees them.", Modifier.padding(bottom = 8.dp))
                DOC_KINDS.forEach { (k, label) ->
                    val have = kept.firstOrNull { it.kind == k }; val new = added[k]
                    val optional = k == "PERMIT" && kind == "BIKE"
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
                            Text(label + if (optional) " (optional for bikes)" else "", style = MaterialTheme.typography.titleSmall)
                            Muted(when { new != null -> "Ready to upload: ${new.name}"; have != null -> "Uploaded"; else -> "Not added yet" })
                        }
                        if (owner) {
                            if (new != null || have != null) IconButton(onClick = { added.remove(k); kept.removeAll { it.kind == k } }) { Icon(Icons.Rounded.Close, "Remove") }
                            SmallButton(if (new != null || have != null) "Replace" else "Add", tonal = true) { pickDoc(k) }
                        }
                    }
                    Divider()
                }
            }
        }
        if (owner) Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) "Uploading…" else if (existing == null) "Add vehicle" else "Save changes", enabled = !m.busy) { save() }
            if (existing != null) BadButton("Remove this vehicle", Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog("Remove ${existing.model.ifBlank { vehicleKindLabel(existing.kind) }} (${existing.plate})?", "Its documents are deleted and drivers you invited lose access. Past trips stay in your records.", "Remove",
        onConfirm = { m.deleteVehicle(existing.id) { onBack() } }, onDismiss = { confirmDelete = false })
}

/** Owner dashboard: per vehicle, the last 30 days from the vehicle_stats view. */
@Composable
fun VehicleStatsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refreshStats(); if (!m.loaded) m.refresh() }
    val rows = m.stats
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Earnings and trips", onBack = onBack)
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                BucksCard(tint = true) {
                    Muted("Last 30 days, all vehicles")
                    Text("₹${rows.sumOf { it.earnings }}", style = MaterialTheme.typography.displaySmall)
                    Muted("${rows.sumOf { it.completed }} trips completed · ${"%.1f".format(rows.sumOf { it.km })} km")
                }
            }
            if (rows.isEmpty()) item {
                BucksCard {
                    Text(if (m.loaded && m.vehicles.isEmpty()) "No vehicles yet" else "Nothing to show yet", style = MaterialTheme.typography.titleMedium)
                    Muted(if (m.loaded && m.vehicles.isEmpty()) "Add a vehicle under Vehicles. Once it's active and online, every ride and delivery lands here." else "Trips taken with your vehicles in the last 30 days appear here: accepted, missed, completed, distance and fares.", Modifier.padding(top = 4.dp))
                }
            }
            items(rows, key = { it.vehicleId }) { s ->
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(icon = vehicleIcon(s.kind), size = 44)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) { Text(s.model.ifBlank { vehicleKindLabel(s.kind) }, style = MaterialTheme.typography.titleMedium); Muted(s.plate) }
                        Text("₹${s.earnings}", style = MaterialTheme.typography.titleLarge)
                    }
                    Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Stat("${s.accepted}", "Accepted"); Stat("${s.rejected}", "Missed"); Stat("${s.completed}", "Completed"); Stat("%.1f".format(s.km), "km")
                    }
                    if (s.accepted + s.rejected > 0 && s.rejected > s.accepted) Muted("More requests missed than accepted. Staying online only when you're free keeps your acceptance up.", Modifier.padding(top = 10.dp))
                }
            }
        }
    }
}
@Composable
private fun RowScope.Stat(value: String, label: String) = Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) { Text(value, style = MaterialTheme.typography.titleLarge); Muted(label) }
