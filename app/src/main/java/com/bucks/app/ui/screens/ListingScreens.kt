package com.bucks.app.ui.screens

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

@Composable
fun PageHeader(title: String, onBack: () -> Unit) = Column(Modifier.fillMaxWidth().padding(start = 8.dp, end = 20.dp, top = 8.dp)) {
    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", Modifier.size(26.dp)) }
    Text(title, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(start = 12.dp, top = 6.dp, bottom = 16.dp))
}

@Composable
fun ListingSwitch(on: Boolean, onChange: (Boolean) -> Unit) { val h = LocalHapticFeedback.current; Switch(on, { h.performHapticFeedback(HapticFeedbackType.LongPress); onChange(it) }, colors = SwitchDefaults.colors(checkedTrackColor = MaterialTheme.colorScheme.primary, checkedBorderColor = MaterialTheme.colorScheme.primary, uncheckedTrackColor = MaterialTheme.colorScheme.surfaceContainerHigh, uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant, uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant)) }

@Composable
fun ListingThumb(icon: ImageVector, size: Int = 56) = Box(Modifier.size(size.dp).clip(MaterialTheme.shapes.small).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small), contentAlignment = Alignment.Center) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size((size * 0.5).dp)) }

@Composable
fun BrandPill(text: String) = Box(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 12.dp, vertical = 3.dp)) { Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer) }

/** Card from the manage listings design: thumbnail + details, an optional pill, and a toggle / Edit row. */
@Composable
fun ListingCard(thumb: @Composable () -> Unit, title: String, pill: String? = null, online: Boolean? = null, onToggle: (Boolean) -> Unit = {}, onEdit: () -> Unit, details: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surface, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                thumb()
                Column(Modifier.weight(1f).padding(start = 14.dp, top = 4.dp)) { Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); details() }
                pill?.let { BrandPill(it) }
            }
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.Bottom) {
                if (online != null) Column { ListingSwitch(online, onToggle); Muted(if (online) "Go offline" else "Go online") }
                Spacer(Modifier.weight(1f))
                Row(Modifier.clip(MaterialTheme.shapes.small).clickable(onClick = onEdit).padding(6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.EditNote, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp)); Text("Edit", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp)) }
            }
        }
    }
}

private val LISTING_TABS = listOf("vehicles" to "Vehicles", "businesses" to "Businesses", "skills" to "Skillset")

@Composable
fun ManageListingsScreen(vm: BucksViewModel, initialTab: String, onBack: () -> Unit, onVehicle: (String?) -> Unit, onBusiness: (Int?) -> Unit, onSkill: (String?) -> Unit) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState()
    var tab by rememberSaveable(initialTab) { mutableIntStateOf(LISTING_TABS.indexOfFirst { it.first == initialTab }.coerceAtLeast(0)) }
    ContentColumn(Modifier.fillMaxHeight()) {
        PageHeader("Manage listings", onBack)
        TabRow(tab, containerColor = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(horizontal = 8.dp),
            indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tab]), height = 2.dp, color = MaterialTheme.colorScheme.primary) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
            LISTING_TABS.forEachIndexed { i, (_, l) -> Tab(tab == i, onClick = { tab = i }, text = { Text(l, style = MaterialTheme.typography.bodyMedium) }) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (LISTING_TABS[tab].first) {
                "vehicles" -> { val vs = s.pro?.vehicles.orEmpty()
                    if (vs.isEmpty()) Muted("No vehicles yet. Tap + to list one. Once it's verified you can go online and take rides.")
                    vs.forEach { v -> val on = s.online && s.pro?.vehicle?.id == v.id
                        ListingCard({ ListingThumb(v.kind.icon) }, v.model, pill = if (v.verified) v.mode.label else "In progress", online = if (v.verified) on else null, onToggle = { vm.setVehicleOnline(v.id, it) }, onEdit = { onVehicle(v.id) }) {
                            Muted(v.plate); if (!v.verified) Muted("Documents are being verified", Modifier.padding(top = 2.dp)) } } }
                "businesses" -> {
                    if (s.businesses.isEmpty()) Muted("No businesses yet. Tap + to open one. Customers nearby find it in search once it's online.")
                    s.businesses.forEachIndexed { i, b ->
                        ListingCard({ ListingThumb(categoryIcon(b.category)) }, b.name, online = b.online, onToggle = { vm.setBusinessOnline(i, it) }, onEdit = { onBusiness(i) }) {
                            Muted(b.area.ifBlank { b.category }); Muted("Followers: ${b.followers}", Modifier.padding(top = 2.dp)) } } }
                else -> { val ks = s.pro?.skillListings.orEmpty()
                    if (ks.isEmpty()) Muted("No skills yet. Tap + to add one. People nearby can book you once it's online.")
                    ks.forEach { k -> val trust = providers.firstOrNull { it.id == "me-${k.name}" }?.trust ?: Trust(0, 0)
                        ListingCard({ ListingThumb(categoryIcon(k.name)) }, k.name, online = k.online, onToggle = { vm.setSkillOnline(k.name, it) }, onEdit = { onSkill(k.name) }) {
                            Muted(k.level.label); Muted("Portfolio items: ${k.portfolio}", Modifier.padding(top = 2.dp))
                            Row(Modifier.padding(top = 6.dp)) { TrustBadge(trust, compact = true) } } } }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable { when (LISTING_TABS[tab].first) { "vehicles" -> onVehicle(null); "businesses" -> onBusiness(null); else -> onSkill(null) } }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Add, "Add ${LISTING_TABS[tab].second.lowercase()}", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            if (s.incoming.isNotEmpty()) {
                SectionTitle("Incoming", Modifier.padding(top = 10.dp))
                s.incoming.forEach { i -> BucksCard { Row(verticalAlignment = Alignment.CenterVertically) { Avatar(initials(i.who), size = 36); Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(i.who, style = MaterialTheme.typography.titleMedium); Muted(i.text) }; SmallButton("Accept") { vm.acceptIncoming(i) } } } }
            }
        }
    }
}

/** Read-only field that opens a menu of [options]. */
@Composable
private fun PickerField(label: String, value: String, placeholder: String, options: List<String>, chevron: Boolean, onPick: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box { BucksField(value, {}, label, placeholder, readOnly = true, trailing = if (chevron) ({ Icon(Icons.Rounded.KeyboardArrowDown, null) }) else null)
        Box(Modifier.matchParentSize().clickable { open = true })
        DropdownMenu(open, { open = false }) { options.forEachIndexed { i, o -> DropdownMenuItem(text = { Text(o) }, onClick = { open = false; onPick(i) }) } }
    }
}

private fun displayName(ctx: android.content.Context, uri: Uri): String = runCatching { ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } }.getOrNull() ?: "Document"

@Composable
fun VehicleFormScreen(vm: BucksViewModel, editId: String?, onBack: () -> Unit, onDone: () -> Unit) {
    val s by vm.state.collectAsState(); val ctx = LocalContext.current
    val edit = remember(editId) { s.pro?.vehicles?.firstOrNull { it.id == editId } }
    var kind by remember { mutableStateOf(edit?.kind) }; var model by remember { mutableStateOf(edit?.model ?: "") }; var plate by remember { mutableStateOf(edit?.plate ?: "") }; var mode by remember { mutableStateOf(edit?.mode) }
    val docs = remember { mutableStateListOf<Pair<Uri, String>>() }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> uris.forEach { u -> if (docs.none { it.first == u }) docs.add(u to displayName(ctx, u)) } }
    val docCount = docs.size + (edit?.docs ?: 0)
    Column(Modifier.fillMaxSize()) {
        PageHeader(if (edit == null) "List your vehicle" else "Edit vehicle", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            PickerField("Vehicle type", kind?.label ?: "", "eg., Car, Auto", VehicleKind.entries.map { "${it.label} · ${it.wheels} wheels" }, chevron = false) { kind = VehicleKind.entries[it] }
            BucksField(model, { model = it }, "Model", "eg., Honda City")
            BucksField(plate, { plate = it.uppercase() }, "License plate", "eg., KA00XX0000")
            PickerField("Listing mode", mode?.label ?: "", "Select a mode", ListingMode.entries.map { it.label }, chevron = true) { mode = ListingMode.entries[it] }
            Label("Upload your documents")
            Muted("Registration certificate, insurance and driving licence.", Modifier.padding(bottom = 10.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                docs.forEachIndexed { i, (_, name) -> Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(8.dp)) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.primary); Text(name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                    Icon(Icons.Rounded.Close, "Remove", Modifier.align(Alignment.TopEnd).size(16.dp).clickable { docs.removeAt(i) }, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
                Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable { picker.launch(arrayOf("image/*", "application/pdf")) }, contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Add, "Upload a document", Modifier.size(32.dp)) }
            }
            if (edit != null && edit.docs > 0) Muted("${edit.docs} document${if (edit.docs == 1) "" else "s"} already on file", Modifier.padding(top = 8.dp))
        }
        DarkButton("Verify and submit", Modifier.padding(20.dp), enabled = kind != null && plate.isNotBlank() && mode != null && docCount > 0) {
            vm.saveVehicle(kind!!, model.trim(), plate.trim(), mode!!, docCount, replacing = edit?.id); onDone() }
    }
}

private val SKILL_SUGGESTIONS = listOf("React", "JavaScript", "Python programming", "SQL", "Figma", "Photoshop", "Market research", "Business strategy")

@Composable
fun AddSkillScreen(vm: BucksViewModel, editName: String?, onBack: () -> Unit) {
    val s by vm.state.collectAsState()
    var skill by remember { mutableStateOf(editName ?: "") }
    val have = s.pro?.skills.orEmpty().toSet()
    val suggestions = (SKILL_SUGGESTIONS + Seed.SKILLS).distinct().filter { it !in have && (skill.isBlank() || it.contains(skill.trim(), true)) && !it.equals(skill.trim(), true) }.take(if (skill.isBlank()) 8 else 12)
    Column(Modifier.fillMaxSize()) {
        PageHeader(if (editName == null) "Add skill" else "Edit skill", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            BucksField(skill, { skill = it }, "Skill", "Skill (ex. web development)")
            if (suggestions.isNotEmpty()) Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.padding(16.dp)) {
                    Text("Skill suggestions", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(bottom = 14.dp))
                    FlowRowChips(suggestions) { skill = it }
                }
            }
        }
        DarkButton("Save", Modifier.padding(20.dp), enabled = skill.isNotBlank() && (skill.trim() !in have || skill.trim() == editName)) { vm.addSkill(skill, replacing = editName); onBack() }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FlowRowChips(items: List<String>, onClick: (String) -> Unit) = FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
    items.forEach { t -> Row(Modifier.clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { onClick(t) }.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Add, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(t, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 6.dp)) } }
}
