package com.bucks.app.ui.screens.manage

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Geo
import com.bucks.app.data.ListingRow
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Create or edit a BUSINESS, SKILL or DRIVER listing. Fields differ by [kind]; kind-specific
 * values go into listings.details. The location is where the phone is when the listing is
 * created (so create it at the shop); on edit it only moves if the owner asks.
 */
@Composable
fun ListingEditScreen(vm: BucksViewModel, kind: String, id: String?, onBack: () -> Unit, onDone: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { if (!m.loaded) m.refresh() }
    val existing = id?.let { m.listing(it) }
    if (id != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Edit ${kindLabel(kind).lowercase()}", onBack = onBack)
            if (m.loaded) Column(Modifier.padding(Gutter)) { Text("Listing not found", style = MaterialTheme.typography.titleMedium); Muted("It may have been deleted, or you're no longer part of it.", Modifier.padding(top = 4.dp)); SmallButton("Back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ListingForm(vm, kind, existing, onBack, onDone) }
}

@Composable
private fun ListingForm(vm: BucksViewModel, kind: String, existing: ListingRow?, onBack: () -> Unit, onDone: () -> Unit) {
    val m = vm.myListings; val social = vm.social
    val d = existing?.details ?: JsonObject(emptyMap())
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var category by remember { mutableStateOf(existing?.category ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var area by remember { mutableStateOf(existing?.area?.ifBlank { null } ?: social.me?.area?.substringBefore(',')?.ifBlank { null } ?: Geo.nearestArea(social.here)) }
    var hours by remember { mutableStateOf(d.str("hours")) }
    var freeDelivery by remember { mutableStateOf(d.bool("free_delivery")) }
    var radius by remember { mutableStateOf(d.int("delivery_radius_km")?.toString() ?: "3") }
    var cod by remember { mutableStateOf(d.bool("cod")) }
    var level by remember { mutableStateOf(d.str("level").ifBlank { "Intermediate" }) }
    var rate by remember { mutableStateOf(d.str("rate")) }
    var languages by remember { mutableStateOf(d.strings("languages").toSet()) }
    var vehicleKind by remember { mutableStateOf(d.str("vehicle_kind").ifBlank { "AUTO" }) }
    var model by remember { mutableStateOf(d.str("model")) }
    var photo by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }
    var moveHere by remember { mutableStateOf(existing == null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val pick = rememberImagePicker { p, u -> photo = p; preview = u }
    val owner = existing == null || m.isOwner(existing.id)
    val driverTitle = "${social.me?.name?.ifBlank { null } ?: "Driver"} - ${vehicleKindLabel(vehicleKind)}"
    val screenTitle = when { existing == null && kind == "BUSINESS" -> "Add a business"; existing == null && kind == "SKILL" -> "Add a skill"; existing == null -> "Your driver profile"; else -> "Edit ${kindLabel(kind).lowercase()}" }

    fun save() {
        val t = if (kind == "DRIVER") driverTitle else title.trim()
        if (t.isBlank()) { vm.toast(if (kind == "SKILL") "Name the skill, like Plumber or Maths tutor." else "Add the business name."); return }
        if (kind != "DRIVER" && category.isBlank()) { vm.toast("Pick a category so people can find you."); return }
        if (kind == "BUSINESS" && (radius.toIntOrNull() ?: 0) !in 1..50) { vm.toast("Delivery radius should be between 1 and 50 km."); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> put(k, v) }   // keep anything other features stored
            when (kind) {
                "BUSINESS" -> { put("hours", hours.trim()); put("free_delivery", freeDelivery); put("delivery_radius_km", radius.toInt()); put("cod", cod) }
                "SKILL" -> { put("level", level); put("rate", rate.trim()); put("languages", buildJsonArray { languages.forEach { add(JsonPrimitive(it)) } }) }
                else -> { put("vehicle_kind", vehicleKind); put("model", model.trim()); put("languages", buildJsonArray { languages.forEach { add(JsonPrimitive(it)) } }) }
            }
        }
        val cat = if (kind == "DRIVER") vehicleKindLabel(vehicleKind) else category
        if (existing == null) m.createListing(kind, t, cat, description.trim(), area.trim(), details, photo) { onDone() }
        else m.updateListing(existing.id, t, cat, description.trim(), area.trim(), if (moveHere) social.here else null, details, photo) { onDone() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(screenTitle, onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                when (kind) {
                    "BUSINESS" -> {
                        BucksField(title, { title = it.take(80) }, "Business name", "Sri Lakshmi Stores")
                        Label("Category"); FlowChips(BUSINESS_CATEGORIES, setOf(category)) { category = it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, "About the business", "What you sell, what you're known for", singleLine = false, minLines = 3)
                        BucksField(hours, { hours = it.take(80) }, "Opening hours", "9 am - 9 pm, closed Sundays")
                        BucksField(area, { area = it.take(60) }, "Area", "Jayanagar")
                        SectionTitle("Delivery and payment", Modifier.padding(top = 6.dp, bottom = 4.dp))
                        SwitchRow("Free delivery", "You pay the rider's fee instead of the customer.", freeDelivery) { freeDelivery = it }
                        BucksField(radius, { radius = it.filter { c -> c.isDigit() }.take(2) }, "Delivery radius (km)", "3", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        SwitchRow("Cash on delivery", "Only with your own store riders, who collect the cash. Add riders under Members.", cod) { cod = it }
                    }
                    "SKILL" -> {
                        BucksField(title, { title = it.take(80) }, "Skill", "Plumber, Maths tutor, Wedding photographer")
                        Label("Category"); FlowChips(SKILL_CATEGORIES, setOf(category)) { category = it }
                        Spacer(Modifier.height(14.dp))
                        Label("Experience"); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { LEVELS.forEach { Chip(it, selected = level == it) { level = it } } }
                        Spacer(Modifier.height(14.dp))
                        BucksField(rate, { rate = it.take(60) }, "Rate", "₹300 per visit + parts")
                        Label("Languages you speak"); FlowChips(LANGUAGES, languages) { languages = if (it in languages) languages - it else languages + it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, "About your work", "Years of experience, what you specialise in", singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, "Area you work in", "Jayanagar")
                    }
                    else -> {
                        BucksCard(Modifier.padding(bottom = 14.dp), padding = 12) { Muted("Shown to riders as"); Text(driverTitle, style = MaterialTheme.typography.titleMedium) }
                        Label("What you drive"); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VEHICLE_KINDS.forEach { (k, l) -> Chip(l, selected = vehicleKind == k, icon = vehicleIcon(k)) { vehicleKind = k } } }
                        Muted(if (vehicleKind == "BIKE") "Bikes carry parcels and food, never passengers." else "Rides and deliveries. Add the vehicle itself under Vehicles; it goes online after Bucks checks its documents.", Modifier.padding(top = 6.dp, bottom = 14.dp))
                        BucksField(model, { model = it.take(60) }, "Vehicle model", "Bajaj RE, Maruti Dzire")
                        Label("Languages you speak"); FlowChips(LANGUAGES, languages) { languages = if (it in languages) languages - it else languages + it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, "About you", "Years driving, areas you know well", singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, "Home area", "Jayanagar")
                    }
                }
                PhotoField(if (kind == "BUSINESS") "Shop photo" else "Profile photo", existing?.photoUrl, preview, if (kind == "BUSINESS") Icons.Rounded.Storefront else Icons.Rounded.Person, onPick = pick, onClear = { photo = null; preview = null })
                Label("Location")
                if (existing == null) Muted("Saved as where you are now: near ${Geo.nearestArea(social.here)}. Neighbours within 3 km of this spot can recommend you, so create it at your shop or where you usually work.")
                else SwitchRow("Move to where I am now", "Near ${Geo.nearestArea(social.here)}. Leave off if you're not at the shop.", moveHere) { moveHere = it }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) "Saving…" else if (existing == null) "Save" else "Save changes", enabled = !m.busy) { save() }
            if (existing != null && owner) BadButton("Delete this ${kindLabel(kind).lowercase()}", Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog("Delete ${existing.title}?", "Its products, members, recommendations and reviews go with it. This can't be undone.", "Delete",
        onConfirm = { m.deleteListing(existing.id) { onDone() } }, onDismiss = { confirmDelete = false })
}
