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
import com.bucks.app.ui.screens.areaOf
import com.bucks.app.data.ListingRow
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.BUSINESS_SERVICES
import com.bucks.app.ui.serviceDef
import com.bucks.app.ui.serviceForCategory
import com.bucks.app.ui.knownServiceForCategory
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonNull
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
fun ListingEditScreen(vm: BucksViewModel, kind: String, id: String?, onBack: () -> Unit, onDone: () -> Unit, service: String? = null, onDocs: (String) -> Unit = {}, onCreated: ((String) -> Unit)? = null) {
    val m = vm.myListings
    LaunchedEffect(Unit) { if (!m.loaded) m.refresh() }
    val existing = id?.let { m.listing(it) }
    if (id != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Edit ${kindLabel(kind).lowercase()}", onBack = onBack)
            val err = m.error
            if (m.loaded) Column(Modifier.padding(Gutter)) { Text("Listing not found", style = MaterialTheme.typography.titleMedium); Muted("It may have been deleted, or you're no longer part of it.", Modifier.padding(top = 4.dp)); SmallButton("Back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else if (err != null) LoadError(err, Modifier.padding(Gutter)) { m.refresh() }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ListingForm(vm, kind, existing, onBack, onDone, service, onDocs, onCreated) }
}

@Composable
private fun ListingForm(vm: BucksViewModel, kind: String, existing: ListingRow?, onBack: () -> Unit, onDone: () -> Unit, initialService: String?, onDocs: (String) -> Unit, onCreated: ((String) -> Unit)?) {
    val m = vm.myListings; val social = vm.social; val st by vm.state.collectAsState()
    // A real location fix, null until one arrives (location denied, GPS off, or not yet). social.here would be the map's
    // default centre in that case, which must never become a listing's position: nobody at the real shop could recommend it.
    val fix = st.me
    val d = existing?.details ?: JsonObject(emptyMap())
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var category by remember { mutableStateOf(existing?.category ?: "") }
    var pickCategory by remember { mutableStateOf(false) }
    // Which Services tile a business belongs to; it decides the documents it needs. Fixed once the listing is live.
    var service by remember { mutableStateOf(existing?.service?.takeIf { it in BUSINESS_SERVICES } ?: initialService?.takeIf { it in BUSINESS_SERVICES } ?: existing?.category?.let { serviceForCategory(it) } ?: "FOOD") }
    val serviceLocked = existing != null && existing.status != "PENDING"
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var area by remember { mutableStateOf(existing?.area?.ifBlank { null } ?: social.me?.area?.substringBefore(',')?.ifBlank { null } ?: areaOf(st.hereLabel) ?: "") }
    var hours by remember { mutableStateOf(d.str("hours")) }
    var freeDelivery by remember { mutableStateOf(d.bool("free_delivery")) }
    var radius by remember { mutableStateOf(d.int("delivery_radius_km")?.toString() ?: "3") }
    var cod by remember { mutableStateOf(d.bool("cod")) }
    // E-commerce: ship anywhere in India by courier (customers far away can only order this way).
    var ships by remember { mutableStateOf(d.bool("ships_india")) }
    var shipFee by remember { mutableStateOf(d.int("ship_fee")?.toString() ?: "") }
    var freeAbove by remember { mutableStateOf(d.int("free_ship_above")?.toString() ?: "") }
    var dispatch by remember { mutableStateOf(d.str("dispatch_days")) }
    var level by remember { mutableStateOf(d.str("level").ifBlank { "Intermediate" }) }
    var rate by remember { mutableStateOf(d.str("rate")) }
    var languages by remember { mutableStateOf(d.strings("languages").toSet()) }
    var vehicleKind by remember { mutableStateOf(d.str("vehicle_kind").ifBlank { "AUTO" }) }
    var model by remember { mutableStateOf(d.str("model")) }
    // Assets: what it is, what the owner wants (sell / rent / lease / PG), the price and the facts buyers ask first.
    var mode by remember { mutableStateOf(d.str("mode").ifBlank { "SELL" }) }
    var price by remember { mutableStateOf(d.num("price")?.toLong()?.takeIf { it > 0 }?.toString() ?: "") }
    var priceUnit by remember { mutableStateOf(d.str("price_unit").ifBlank { "TOTAL" }) }
    var deposit by remember { mutableStateOf(d.num("deposit")?.toLong()?.takeIf { it > 0 }?.toString() ?: "") }
    var areaSqft by remember { mutableStateOf(d.num("area_sqft")?.toLong()?.takeIf { it > 0 }?.toString() ?: "") }
    var bedrooms by remember { mutableStateOf(d.int("bedrooms")?.toString() ?: "") }
    var furnishing by remember { mutableStateOf(d.str("furnishing")) }
    var availableFrom by remember { mutableStateOf(d.str("available_from")) }
    var year by remember { mutableStateOf(d.int("year")?.toString() ?: "") }
    var kmDriven by remember { mutableStateOf(d.int("km_driven")?.toString() ?: "") }
    var negotiable by remember { mutableStateOf(d.bool("negotiable")) }
    var photo by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }
    var moveHere by remember { mutableStateOf(existing == null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val pick = rememberImagePicker(onUnusable = { vm.toast("Couldn't read that image. Try a JPG or PNG photo.") }) { p, u -> photo = p; preview = u }
    val owner = existing == null || m.isOwner(existing.id)
    val driverTitle = "${social.me?.name?.ifBlank { null } ?: "Driver"} - ${vehicleKindLabel(vehicleKind)}"
    val screenTitle = when { existing == null && kind == "BUSINESS" -> "Add a business"; existing == null && kind == "SKILL" -> "Add a skill"; existing == null && kind == "ASSET" -> "List an asset"; existing == null -> "Your driver profile"; else -> "Edit ${kindLabel(kind).lowercase()}" }

    fun save() {
        val t = if (kind == "DRIVER") driverTitle else title.trim()
        if (t.isBlank()) { vm.toast(when (kind) { "SKILL" -> "Name the skill, like Plumber or Maths tutor."; "ASSET" -> "Give it a title, like 2BHK flat in 4th Block."; else -> "Add the business name." }); return }
        if (kind != "DRIVER" && category.isBlank()) { vm.toast(if (kind == "ASSET") "Pick what it is: house, flat, shop, vehicle…" else "Pick a category so people can find you."); return }
        if (kind == "ASSET" && price.isNotBlank() && price.toLongOrNull() == null) { vm.toast("Enter the price in rupees, numbers only."); return }
        if (kind == "ASSET" && year.isNotBlank() && (year.toIntOrNull() ?: 0) !in 1950..2100) { vm.toast("Enter the year it was made, like 2019."); return }
        if (kind == "BUSINESS" && (radius.toIntOrNull() ?: 0) !in 1..50) { vm.toast("Delivery radius should be between 1 and 50 km."); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> put(k, v) }   // keep anything other features stored
            when (kind) {
                "BUSINESS" -> { put("hours", hours.trim()); put("free_delivery", freeDelivery); put("delivery_radius_km", radius.toInt()); put("cod", cod)
                    put("ships_india", ships)
                    if (ships) { put("ship_fee", shipFee.toIntOrNull() ?: 0); put("free_ship_above", freeAbove.toIntOrNull() ?: 0); put("dispatch_days", dispatch.trim()) }
                }
                "SKILL" -> { put("level", level); put("rate", rate.trim()); put("languages", buildJsonArray { languages.forEach { add(JsonPrimitive(it)) } }) }
                "ASSET" -> {
                    put("mode", mode); put("price", price.toLongOrNull() ?: 0L); put("price_unit", priceUnit); put("negotiable", negotiable)
                    // Blank facts are removed, not saved as empty: the profile only shows what the owner filled in.
                    for ((k, v) in listOf("deposit" to deposit, "area_sqft" to areaSqft, "bedrooms" to bedrooms, "year" to year, "km_driven" to kmDriven)) {
                        val n = v.toLongOrNull()
                        if (n != null && n > 0) put(k, n) else put(k, JsonNull)
                    }
                    for ((k, v) in listOf("furnishing" to furnishing, "available_from" to availableFrom)) { if (v.isNotBlank()) put(k, v.trim()) else put(k, JsonNull) }
                }
                else -> { put("vehicle_kind", vehicleKind); put("model", model.trim()); put("languages", buildJsonArray { languages.forEach { add(JsonPrimitive(it)) } }) }
            }
        }
        val cat = if (kind == "DRIVER") vehicleKindLabel(vehicleKind) else category
        if (existing == null) {
            val at = fix ?: run { vm.toast("Turn on location so Bucks can save where your shop is."); return }
            // A new business or skill goes straight on to its documents: they are the other half of going live.
            m.createListing(kind, t, cat, description.trim(), area.trim(), at, details.withoutNulls(), photo, if (kind == "BUSINESS") service else null) { row -> when { onCreated != null -> onCreated(row.id); kind == "DRIVER" -> onDone(); else -> onDocs(row.id) } }
        } else m.updateListing(existing.id, t, cat, description.trim(), area.trim(), if (moveHere) fix else null, details.withoutNulls(), photo,
            if (kind == "BUSINESS" && service != existing.service && !serviceLocked) service else null) { onDone() }
    }

    if (pickCategory) CategoryPickerSheet(kind, category, onPick = { c -> category = c; if (kind == "BUSINESS" && !serviceLocked) service = knownServiceForCategory(c) ?: service; pickCategory = false }, onDismiss = { pickCategory = false })

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(screenTitle, onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                when (kind) {
                    "BUSINESS" -> {
                        BucksField(title, { title = it.take(80) }, "Business name", "Sri Lakshmi Stores")
                        Label("Type of business")
                        CategoryField(category, "Pick a type, or add your own") { pickCategory = true }
                        Muted("Shows under ${serviceDef(service)!!.label} in Services." + (if (serviceLocked) " That can't change while you're live, but you can rename your type." else " It decides the documents Bucks checks."), Modifier.padding(top = 6.dp, bottom = 4.dp))
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, "About the business", "What you sell, what you're known for", singleLine = false, minLines = 3)
                        BucksField(hours, { hours = it.take(80) }, "Opening hours", "9 am - 9 pm, closed Sundays")
                        BucksField(area, { area = it.take(60) }, "Area", "Jayanagar")
                        SectionTitle("Delivery and payment", Modifier.padding(top = 6.dp, bottom = 4.dp))
                        SwitchRow("Free delivery", "You pay the rider's fee instead of the customer.", freeDelivery) { freeDelivery = it }
                        BucksField(radius, { radius = it.filter { c -> c.isDigit() }.take(2) }, "Delivery radius (km)", "3", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        SwitchRow("Cash on delivery", "With your own store riders, or with the courier on shipped orders. You collect the cash.", cod) { cod = it }
                        SectionTitle("Ship across India", Modifier.padding(top = 14.dp, bottom = 4.dp))
                        SwitchRow("Ship by courier", "Customers anywhere can find you and order. You accept, pack, hand it to a courier and enter the tracking number.", ships) { ships = it }
                        if (ships) {
                            BucksField(shipFee, { shipFee = it.filter { c -> c.isDigit() }.take(5) }, "Shipping fee (₹)", "99, or 0 for free shipping", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            BucksField(freeAbove, { freeAbove = it.filter { c -> c.isDigit() }.take(6) }, "Free shipping above (₹)", "1999, or leave empty for none", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            BucksField(dispatch, { dispatch = it.take(30) }, "Ships in (days)", "2 to 4")
                            Muted("Buyers pay the items and the shipping to you (UPI, or cash on delivery if you turned it on). You have 24 hours to accept each order.", Modifier.padding(bottom = 8.dp))
                        }
                    }
                    "SKILL" -> {
                        BucksField(title, { title = it.take(80) }, "Skill", "Plumber, Maths tutor, Wedding photographer")
                        Label("What do you do?"); CategoryField(category, "Pick a field, or add your own") { pickCategory = true }
                        Spacer(Modifier.height(14.dp))
                        Label("Experience"); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { LEVELS.forEach { Chip(it, selected = level == it) { level = it } } }
                        Spacer(Modifier.height(14.dp))
                        BucksField(rate, { rate = it.take(60) }, "Rate", "₹300 per visit + parts")
                        Label("Languages you speak"); FlowChips(LANGUAGES, languages) { languages = if (it in languages) languages - it else languages + it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, "About your work", "Years of experience, what you specialise in", singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, "Area you work in", "Jayanagar")
                    }
                    "ASSET" -> {
                        Label("What is it?")
                        FlowChips(ASSET_TYPES, setOf(category)) { category = it }
                        Muted(if (category in PROPERTY_TYPES) "Property: Bucks checks the owner's ID (and RERA for builders) before it goes live. Files stay private." else "Vehicles and equipment need no documents to go live.", Modifier.padding(top = 6.dp, bottom = 14.dp))
                        Label("You want to")
                        Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ASSET_MODES.filter { (k, _) -> k != "PG" || category in RESIDENTIAL_TYPES }.forEach { (k, l) -> Chip(l, selected = mode == k) { mode = k; priceUnit = when (k) { "SELL" -> "TOTAL"; "LEASE" -> "YEAR"; else -> "MONTH" } } }
                        }
                        Spacer(Modifier.height(14.dp))
                        BucksField(title, { title = it.take(80) }, "Title", when (category) { "Vehicle" -> "Honda Activa 2019, single owner"; "Plot / Land" -> "30x40 plot near Kanakapura Road"; "Shop", "Office", "Commercial space" -> "Ground-floor shop on 11th Main"; else -> "2BHK flat in 4th Block, east facing" })
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(price, { price = it.filter { c -> c.isDigit() }.take(10) }, if (mode == "SELL") "Price (₹)" else "Rent (₹)", if (mode == "SELL") "4500000" else "28000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            if (mode != "SELL") BucksField(deposit, { deposit = it.filter { c -> c.isDigit() }.take(10) }, "Deposit (₹)", "150000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        }
                        price.toLongOrNull()?.takeIf { it > 0 }?.let { Muted(rupees(it) + (PRICE_UNITS.firstOrNull { u -> u.first == priceUnit }?.second?.takeIf { u -> u != "Total" }?.let { u -> " $u" } ?: ""), Modifier.padding(bottom = 6.dp)) }
                            ?: Muted("Leave the price empty to show \"Price on request\".", Modifier.padding(bottom = 6.dp))
                        ChipRow(PRICE_UNITS.map { it.second }, PRICE_UNITS.firstOrNull { it.first == priceUnit }?.second, Modifier.padding(bottom = 6.dp)) { picked -> priceUnit = PRICE_UNITS.first { it.second == picked }.first }
                        SwitchRow("Price is negotiable", null, negotiable) { negotiable = it }
                        SectionTitle("Details", Modifier.padding(top = 8.dp, bottom = 4.dp))
                        if (category == "Vehicle") Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(year, { year = it.filter { c -> c.isDigit() }.take(4) }, "Year", "2019", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            BucksField(kmDriven, { kmDriven = it.filter { c -> c.isDigit() }.take(7) }, "Km driven", "18000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        } else if (category !in setOf("Equipment", "Other")) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(areaSqft, { areaSqft = it.filter { c -> c.isDigit() }.take(7) }, "Size (sq ft)", "1100", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            if (category in RESIDENTIAL_TYPES) BucksField(bedrooms, { bedrooms = it.filter { c -> c.isDigit() }.take(2) }, "Bedrooms", "2", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        }
                        if (category in RESIDENTIAL_TYPES || category in setOf("Office", "Shop", "Commercial space")) { Label("Furnishing"); ChipRow(FURNISHING, furnishing.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { furnishing = if (furnishing == it) "" else it } }
                        if (mode != "SELL") BucksField(availableFrom, { availableFrom = it.take(40) }, "Available from", "Immediately, or 1 November")
                        BucksField(description, { description = it.take(600) }, "Description", "Condition, what's included, nearby landmarks, who it suits", singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, "Area / locality", "Jayanagar 4th Block")
                        Muted("Add more photos from the listing's Photos tab after saving.", Modifier.padding(bottom = 10.dp))
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
                PhotoField(when (kind) { "BUSINESS" -> "Cover photo"; "ASSET" -> "Cover photo"; else -> "Profile photo" }, existing?.photoUrl, preview, when (kind) { "BUSINESS" -> Icons.Rounded.Storefront; "ASSET" -> assetIcon(category); else -> Icons.Rounded.Person }, onPick = pick, onClear = { photo = null; preview = null })
                Label("Location")
                when {
                    existing == null && fix != null -> Muted("Saved as where you are now: near ${areaOf(st.hereLabel) ?: "your current location"}. People within 3 km of this spot can recommend you, so create it " + (if (kind == "ASSET") "at the property or where the asset is kept." else "at your shop or where you usually work."))
                    existing == null -> Notice(if (st.locationGranted) "Waiting for your location… Bucks saves the listing where you are, so create it at your shop or where you usually work."
                                               else "Turn on location so Bucks can save where your shop is. Neighbours within 3 km of that spot can recommend you, so create it at your shop or where you usually work.")
                    fix != null -> SwitchRow("Move to where I am now", "Near ${areaOf(st.hereLabel) ?: "your current location"}. Leave off if you're not at the shop.", moveHere) { moveHere = it }
                    else -> Muted(if (st.locationGranted) "Stays where it is. Waiting for your location before it can move to where you are now." else "Stays where it is. Turn on location to move it to where you are now.")
                }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) "Saving…" else if (existing == null) "Save" else "Save changes", enabled = !m.busy && (existing != null || fix != null)) { save() }
            if (existing != null && kind != "DRIVER" && m.canManage(existing.id)) SmallButton("Documents for Bucks to check", Modifier.padding(bottom = 6.dp), tonal = true) { onDocs(existing.id) }
            if (existing != null && owner) BadButton("Delete this ${kindLabel(kind).lowercase()}", Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog("Delete ${existing.title}?", "Its products, members, recommendations and reviews go with it. Orders customers already placed stay in their history. This can't be undone.", "Delete",
        onConfirm = { m.deleteListing(existing.id) { onDone() } }, onDismiss = { confirmDelete = false })
}

/** Drops keys set to null (facts the owner cleared), so they leave the listing instead of being stored as null. */
private fun JsonObject.withoutNulls() = JsonObject(filterValues { it !is JsonNull })
