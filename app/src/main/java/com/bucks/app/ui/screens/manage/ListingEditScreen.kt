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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Money
import com.bucks.app.data.Str
import com.bucks.app.data.Geo
import com.bucks.app.data.DeliveryBackend
import com.bucks.app.ui.screens.areaOf
import com.bucks.app.data.ListingRow
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.BUSINESS_SERVICES
import com.bucks.app.ui.PageType
import com.bucks.app.ui.PageTypes
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
 * [typeKey]: the page type a new business starts as (ui/PageTypes.kt), from the type picker; the form shows the type and
 * adapts its fields to it (shops take orders and deliver; every other page takes requests and shows contact details).
 */
@Composable
fun ListingEditScreen(vm: BucksViewModel, kind: String, id: String?, onBack: () -> Unit, onDone: () -> Unit, service: String? = null, typeKey: String? = null, onDocs: (String) -> Unit = {}, onCreated: ((String) -> Unit)? = null) {
    val m = vm.myListings
    LaunchedEffect(Unit) { if (!m.loaded) m.refresh() }
    val existing = id?.let { m.listing(it) }
    if (id != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g4_le_edit_kind, kindLabel(kind).lowercase()), onBack = onBack)
            val err = m.error
            if (m.loaded) Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g4_le_not_found), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g4_le_not_found_body), Modifier.padding(top = 4.dp)); SmallButton(stringResource(R.string.g4_cd_back), Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else if (err != null) LoadError(err, Modifier.padding(Gutter)) { m.refresh() }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ListingForm(vm, kind, existing, onBack, onDone, service, typeKey, onDocs, onCreated) }
}

/** A sample name for the page-name field, by group. */
private fun pageNamePlaceholder(t: PageType) = when (t.group) { "SHOPS" -> "Sri Lakshmi Stores"; "LOCAL_SERVICES" -> "Glow Family Salon"; "COMPANIES" -> "Nimbus Software"; "COMMUNITY" -> "Sunrise Foundation"; else -> "St Mary's School" }

@Composable
private fun ListingForm(vm: BucksViewModel, kind: String, existing: ListingRow?, onBack: () -> Unit, onDone: () -> Unit, initialService: String?, initialType: String?, onDocs: (String) -> Unit, onCreated: ((String) -> Unit)?) {
    val m = vm.myListings; val social = vm.social; val st by vm.state.collectAsState()
    // A real location fix, null until one arrives (location denied, GPS off, or not yet). social.here would be the map's
    // default centre in that case, which must never become a listing's position: nobody at the real shop could recommend it.
    val fix = st.me
    val d = existing?.details ?: JsonObject(emptyMap())
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var category by remember { mutableStateOf(existing?.category ?: "") }
    var pickCategory by remember { mutableStateOf(false) }
    // Which Services tile a business belongs to; it decides the documents it needs. Fixed once the listing is live.
    var service by remember { mutableStateOf(existing?.service?.takeIf { it in BUSINESS_SERVICES } ?: initialService?.takeIf { it in BUSINESS_SERVICES } ?: existing?.category?.let { serviceForCategory(it) } ?: "SHOPPING") }   // never Food by default: Food asks for an FSSAI licence
    val serviceLocked = existing != null && existing.status != "PENDING"
    // What the business is (ui/PageTypes.kt). Shops derive their service from the category above; every other type gets it from
    // the server, which also fixes the type once the page is live (same rule as the service).
    var typeKey by remember { mutableStateOf(existing?.let { PageTypes.of(it) }?.key ?: PageTypes.byKey(initialType)?.key ?: "RETAIL_SHOP") }
    val type: PageType = PageTypes.byKey(typeKey) ?: PageTypes.all.first()
    // A page that takes requests (service, company, NGO, institution) rather than orders: no delivery, contact details instead.
    val orgPage = kind == "BUSINESS" && !type.isShop
    var pickType by remember { mutableStateOf(false) }
    // The catalogue tab (4th of the five on every page): its name and what it holds. Blank name and null kinds follow the type.
    var catLabel by remember { mutableStateOf(d.str("catalogue_label")) }
    var catKinds by remember { mutableStateOf(d.strings("catalogue_kinds").filter { it in PageTypes.itemKinds }.toSet().ifEmpty { null }) }
    val catType = if (kind == "BUSINESS") type else null
    val catDefault = PageTypes.defaultKinds(kind, catType).toSet()
    val catEffective = catKinds ?: catDefault
    var registration by remember { mutableStateOf(d.str("registration")) }
    var website by remember { mutableStateOf(d.str("website")) }
    var email by remember { mutableStateOf(d.str("email")) }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var area by remember { mutableStateOf(existing?.area?.ifBlank { null } ?: social.me?.area?.substringBefore(',')?.ifBlank { null } ?: areaOf(st.hereLabel) ?: "") }
    var hours by remember { mutableStateOf(d.str("hours")) }
    var freeDelivery by remember { mutableStateOf(d.bool("free_delivery")) }
    var radius by remember { mutableStateOf(d.int("delivery_radius_km")?.toString() ?: "3") }
    var cod by remember { mutableStateOf(d.bool("cod")) }
    // Off by default: people message first; the owner opts in to calls (listing_phone shows their verified number only then).
    var showPhone by remember { mutableStateOf(d.bool("show_phone")) }
    /** The shop's store riders, for the cash-on-delivery note; null while unknown (no warning then). */
    var riderCount by remember { mutableStateOf<Int?>(if (existing == null) 0 else null) }
    LaunchedEffect(existing?.id) { existing?.id?.let { id -> riderCount = runCatching { DeliveryBackend.storeRiders(id).size }.getOrNull() } }
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
    val pick = rememberImagePicker(onUnusable = { vm.toast(Str.get(R.string.g4_le_bad_image)) }) { p, u -> photo = p; preview = u }
    val owner = existing == null || m.isOwner(existing.id)
    val driverTitle = "${social.me?.name?.ifBlank { null } ?: stringResource(R.string.g4_le_driver)} - ${vehicleKindLabel(vehicleKind)}"
    val screenTitle = when { existing == null && kind == "BUSINESS" -> if (orgPage) stringResource(R.string.g4_le_title_page) else stringResource(R.string.g4_le_title_business); existing == null && kind == "SKILL" -> stringResource(R.string.g4_le_title_skill); existing == null && kind == "ASSET" -> stringResource(R.string.g4_le_title_asset); existing == null -> stringResource(R.string.g4_le_title_driver); else -> stringResource(R.string.g4_le_edit_kind, kindLabel(kind).lowercase()) }

    fun save() {
        val t = if (kind == "DRIVER") driverTitle else title.trim()
        // Every page is shown "by <name>": a profile without a name cannot run one.
        if (social.me?.name.isNullOrBlank()) { vm.toast(Str.get(R.string.g4_le_need_name)); return }
        if (t.isBlank()) { vm.toast(when { kind == "SKILL" -> Str.get(R.string.g4_le_need_skill); kind == "ASSET" -> Str.get(R.string.g4_le_need_asset_title); orgPage -> Str.get(R.string.g4_le_need_page_name); else -> Str.get(R.string.g4_le_need_business_name) }); return }
        if (kind != "DRIVER" && category.isBlank()) { vm.toast(if (kind == "ASSET") Str.get(R.string.g4_le_need_asset_type) else Str.get(R.string.g4_le_need_category)); return }
        if (kind == "ASSET" && price.isNotBlank() && price.toLongOrNull() == null) { vm.toast(Str.get(R.string.g4_le_bad_price)); return }
        if (kind == "ASSET" && year.isNotBlank() && (year.toIntOrNull() ?: 0) !in 1950..2100) { vm.toast(Str.get(R.string.g4_le_bad_year)); return }
        if (kind == "BUSINESS" && !orgPage && (radius.toIntOrNull() ?: 0) !in 1..50) { vm.toast(Str.get(R.string.g4_le_bad_radius)); return }
        if ((kind == "BUSINESS" || kind == "SKILL") && catEffective.isEmpty()) { vm.toast(Str.get(R.string.g4_le_need_catalogue)); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> put(k, v) }   // keep anything other features stored
            if (kind == "BUSINESS" || kind == "SKILL") put("show_phone", showPhone)
            if (kind == "BUSINESS" || kind == "SKILL") {
                // Saved only when the owner changed them, so a page keeps following its type's defaults until then.
                if (catLabel.isNotBlank()) put("catalogue_label", catLabel.trim().take(PageTypes.CATALOGUE_LABEL_MAX)) else put("catalogue_label", JsonNull)
                if (catKinds != null && catEffective != catDefault) put("catalogue_kinds", buildJsonArray { PageTypes.itemKinds.filter { it in catEffective }.forEach { add(JsonPrimitive(it)) } })
                else put("catalogue_kinds", JsonNull)
            }
            when (kind) {
                "BUSINESS" -> { put("hours", hours.trim())
                    if (orgPage) {
                        // No delivery on a page that takes requests: the delivery keys leave (a shop that changed type while pending) and the contact facts come in; blanks are removed, not saved empty.
                        for (k in listOf("free_delivery", "delivery_radius_km", "cod", "ships_india", "ship_fee", "free_ship_above", "dispatch_days")) put(k, JsonNull)
                        for ((k, v) in listOf("registration" to registration, "website" to website, "email" to email)) { if (v.isNotBlank()) put(k, v.trim()) else put(k, JsonNull) }
                    } else {
                        put("free_delivery", freeDelivery); put("delivery_radius_km", radius.toInt()); put("cod", cod)
                        put("ships_india", ships)
                        if (ships) { put("ship_fee", shipFee.toIntOrNull() ?: 0); put("free_ship_above", freeAbove.toIntOrNull() ?: 0); put("dispatch_days", dispatch.trim()) }
                    }
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
            val at = fix ?: run { vm.toast(Str.get(R.string.g4_le_need_location)); return }
            // A new business or skill goes straight on to its documents: they are the other half of going live.
            // Only a shop sends its service (derived from the category); the server sets it from the type for every other page.
            m.createListing(kind, t, cat, description.trim(), area.trim(), at, details.withoutNulls(), photo, if (kind == "BUSINESS" && type.isShop) service else null, if (kind == "BUSINESS") typeKey else null) { row -> when { onCreated != null -> onCreated(row.id); kind == "DRIVER" -> onDone(); else -> onDocs(row.id) } }
        } else m.updateListing(existing.id, t, cat, description.trim(), area.trim(), if (moveHere) fix else null, details.withoutNulls(), photo,
            if (kind == "BUSINESS" && type.isShop && service != existing.service && !serviceLocked) service else null,
            if (kind == "BUSINESS" && !serviceLocked && typeKey != PageTypes.of(existing)?.key) typeKey else null) { onDone() }
    }

    if (pickCategory) CategoryPickerSheet(kind, category, onPick = { c -> category = c; if (kind == "BUSINESS" && type.isShop && !serviceLocked) service = knownServiceForCategory(c) ?: initialService?.takeIf { it in BUSINESS_SERVICES } ?: "SHOPPING"; pickCategory = false }, onDismiss = { pickCategory = false })
    if (pickType) PageTypePickerSheet(initialGroup = type.group, selected = typeKey, onPick = { picked -> typeKey = picked.key; if (picked.isShop && !serviceLocked) service = knownServiceForCategory(category) ?: service; pickType = false }, onDismiss = { pickType = false })

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(screenTitle, onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                when (kind) {
                    "BUSINESS" -> {
                        PageTypeCard(type, locked = serviceLocked) { pickType = true }
                        BucksField(title, { title = it.take(80) }, if (orgPage) stringResource(R.string.g4_le_page_name) else stringResource(R.string.g4_le_business_name), pageNamePlaceholder(type))
                        Label(pageCategoryLabel(type))
                        CategoryField(category, if (orgPage) stringResource(R.string.g4_le_pick_one) else stringResource(R.string.g4_le_pick_type)) { pickCategory = true }
                        Muted(if (orgPage) (if (serviceLocked) stringResource(R.string.g4_le_shows_under_org_locked, PageTypes.group(type.group)?.label ?: stringResource(R.string.g4_tab_services)) else stringResource(R.string.g4_le_shows_under_org, PageTypes.group(type.group)?.label ?: stringResource(R.string.g4_tab_services)))
                              else (if (serviceLocked) stringResource(R.string.g4_le_shows_under_shop_locked, serviceDef(service)!!.label) else stringResource(R.string.g4_le_shows_under_shop, serviceDef(service)!!.label)), Modifier.padding(top = 6.dp, bottom = 4.dp))
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, if (orgPage) stringResource(R.string.g4_le_about_page) else stringResource(R.string.g4_le_about_business), if (orgPage) stringResource(R.string.g4_le_about_page_hint) else stringResource(R.string.g4_le_about_business_hint), singleLine = false, minLines = 3)
                        BucksField(hours, { hours = it.take(80) }, if (orgPage) stringResource(R.string.g4_le_timings) else stringResource(R.string.g4_le_opening_hours), if (orgPage) stringResource(R.string.g4_le_timings_hint) else stringResource(R.string.g4_le_hours_hint))
                        BucksField(area, { area = it.take(60) }, stringResource(R.string.g4_le_area), "Jayanagar")
                        CatalogueTabEditor(kind, catType, catLabel, catEffective, onLabel = { catLabel = it }, onKinds = { catKinds = it })
                        if (orgPage) {
                            SectionTitle(stringResource(R.string.g4_le_contact_registration), Modifier.padding(top = 6.dp, bottom = 4.dp))
                            BucksField(registration, { registration = it.take(40) }, stringResource(R.string.g4_le_optional_field, pageRegistrationLabel(type)), if (type.key == "SCHOOL_COLLEGE") stringResource(R.string.g4_le_affiliation_hint) else stringResource(R.string.g4_le_registration_hint))
                            BucksField(website, { website = it.trim().take(120) }, stringResource(R.string.g4_le_website), "www.example.org", keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri))
                            BucksField(email, { email = it.trim().take(120) }, stringResource(R.string.g4_le_email), "hello@example.org", keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
                            Muted(stringResource(R.string.g4_le_contact_note), Modifier.padding(bottom = 8.dp))
                        } else {
                            SectionTitle(stringResource(R.string.g4_le_delivery_payment), Modifier.padding(top = 6.dp, bottom = 4.dp))
                            SwitchRow(stringResource(R.string.g4_le_free_delivery), stringResource(R.string.g4_le_free_delivery_note), freeDelivery) { freeDelivery = it }
                            BucksField(radius, { radius = it.filter { c -> c.isDigit() }.take(2) }, stringResource(R.string.g4_le_radius), "3", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            SwitchRow(stringResource(R.string.g4_prov_cod), stringResource(R.string.g4_le_cod_note), cod) { cod = it }
                            // Bucks riders never carry cash, so without a store rider or courier shipping nobody can offer it.
                            if (cod && !ships && riderCount == 0) Text(stringResource(R.string.g4_le_cod_hidden), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(bottom = 6.dp))
                            SectionTitle(stringResource(R.string.g4_le_ship_india), Modifier.padding(top = 14.dp, bottom = 4.dp))
                            SwitchRow(stringResource(R.string.g4_le_ship_courier), stringResource(R.string.g4_le_ship_courier_note), ships) { ships = it }
                            if (ships) {
                                BucksField(shipFee, { shipFee = it.filter { c -> c.isDigit() }.take(5) }, stringResource(R.string.g4_le_ship_fee, Money.symbol), stringResource(R.string.g4_le_ship_fee_hint), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                                BucksField(freeAbove, { freeAbove = it.filter { c -> c.isDigit() }.take(6) }, stringResource(R.string.g4_le_free_above, Money.symbol), stringResource(R.string.g4_le_free_above_hint), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                                BucksField(dispatch, { dispatch = it.take(30) }, stringResource(R.string.g4_le_ships_in), stringResource(R.string.g4_le_ships_in_hint))
                                Muted(stringResource(R.string.g4_le_ship_payment_note), Modifier.padding(bottom = 8.dp))
                            }
                        }
                    }
                    "SKILL" -> {
                        BucksField(title, { title = it.take(80) }, stringResource(R.string.g4_le_skill), stringResource(R.string.g4_le_skill_hint))
                        Label(stringResource(R.string.g4_le_what_do_you_do)); CategoryField(category, stringResource(R.string.g4_le_pick_field)) { pickCategory = true }
                        Spacer(Modifier.height(14.dp))
                        Label(stringResource(R.string.g4_le_experience)); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { LEVELS.forEach { Chip(it, selected = level == it) { level = it } } }
                        Spacer(Modifier.height(14.dp))
                        BucksField(rate, { rate = it.take(60) }, stringResource(R.string.g4_prov_rate), stringResource(R.string.g4_le_rate_hint, Money.format(300)))
                        Label(stringResource(R.string.g4_le_languages)); FlowChips(LANGUAGES, languages) { languages = if (it in languages) languages - it else languages + it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, stringResource(R.string.g4_le_about_work), stringResource(R.string.g4_le_about_work_hint), singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, stringResource(R.string.g4_le_area_work), "Jayanagar")
                        CatalogueTabEditor(kind, null, catLabel, catEffective, onLabel = { catLabel = it }, onKinds = { catKinds = it })
                    }
                    "ASSET" -> {
                        Label(stringResource(R.string.g4_le_what_is_it))
                        FlowChips(ASSET_TYPES, setOf(category)) { category = it }
                        Muted(if (category in PROPERTY_TYPES) stringResource(R.string.g4_le_property_docs) else stringResource(R.string.g4_le_vehicle_no_docs), Modifier.padding(top = 6.dp, bottom = 14.dp))
                        Label(stringResource(R.string.g4_le_you_want_to))
                        Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ASSET_MODES.filter { (k, _) -> k != "PG" || category in RESIDENTIAL_TYPES }.forEach { (k, l) -> Chip(l, selected = mode == k) { mode = k; priceUnit = when (k) { "SELL" -> "TOTAL"; "LEASE" -> "YEAR"; else -> "MONTH" } } }
                        }
                        Spacer(Modifier.height(14.dp))
                        BucksField(title, { title = it.take(80) }, stringResource(R.string.g4_le_title), when (category) { "Vehicle" -> stringResource(R.string.g4_le_title_hint_vehicle); "Plot / Land" -> stringResource(R.string.g4_le_title_hint_plot); "Shop", "Office", "Commercial space" -> stringResource(R.string.g4_le_title_hint_shop); else -> stringResource(R.string.g4_le_title_hint_flat) })
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(price, { price = it.filter { c -> c.isDigit() }.take(10) }, if (mode == "SELL") stringResource(R.string.g4_le_price, Money.symbol) else stringResource(R.string.g4_le_rent, Money.symbol), if (mode == "SELL") "4500000" else "28000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            if (mode != "SELL") BucksField(deposit, { deposit = it.filter { c -> c.isDigit() }.take(10) }, stringResource(R.string.g4_le_deposit, Money.symbol), "150000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        }
                        price.toLongOrNull()?.takeIf { it > 0 }?.let { Muted(PRICE_UNITS.firstOrNull { u -> u.first == priceUnit }?.takeIf { u -> u.first != "TOTAL" }?.let { u -> stringResource(R.string.g4_le_price_per_unit, rupees(it), u.second) } ?: rupees(it), Modifier.padding(bottom = 6.dp)) }
                            ?: Muted(stringResource(R.string.g4_le_price_empty), Modifier.padding(bottom = 6.dp))
                        ChipRow(PRICE_UNITS.map { it.second }, PRICE_UNITS.firstOrNull { it.first == priceUnit }?.second, Modifier.padding(bottom = 6.dp)) { picked -> priceUnit = PRICE_UNITS.first { it.second == picked }.first }
                        SwitchRow(stringResource(R.string.g4_le_negotiable), null, negotiable) { negotiable = it }
                        SectionTitle(stringResource(R.string.g4_prov_details), Modifier.padding(top = 8.dp, bottom = 4.dp))
                        if (category == "Vehicle") Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(year, { year = it.filter { c -> c.isDigit() }.take(4) }, stringResource(R.string.g4_le_year), "2019", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            BucksField(kmDriven, { kmDriven = it.filter { c -> c.isDigit() }.take(7) }, stringResource(R.string.g4_le_km_driven), "18000", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        } else if (category !in setOf("Equipment", "Other")) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            BucksField(areaSqft, { areaSqft = it.filter { c -> c.isDigit() }.take(7) }, stringResource(R.string.g4_le_size_sqft), "1100", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                            if (category in RESIDENTIAL_TYPES) BucksField(bedrooms, { bedrooms = it.filter { c -> c.isDigit() }.take(2) }, stringResource(R.string.g4_le_bedrooms), "2", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                        }
                        if (category in RESIDENTIAL_TYPES || category in setOf("Office", "Shop", "Commercial space")) { Label(stringResource(R.string.g4_le_furnishing)); ChipRow(FURNISHING, furnishing.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { furnishing = if (furnishing == it) "" else it } }
                        if (mode != "SELL") BucksField(availableFrom, { availableFrom = it.take(40) }, stringResource(R.string.g4_le_available_from), stringResource(R.string.g4_le_available_from_hint))
                        BucksField(description, { description = it.take(600) }, stringResource(R.string.g4_le_description), stringResource(R.string.g4_le_description_hint), singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, stringResource(R.string.g4_le_area_locality), "Jayanagar 4th Block")
                        Muted(stringResource(R.string.g4_le_more_photos), Modifier.padding(bottom = 10.dp))
                    }
                    else -> {
                        BucksCard(Modifier.padding(bottom = 14.dp), padding = 12) { Muted(stringResource(R.string.g4_le_shown_to_riders)); Text(driverTitle, style = MaterialTheme.typography.titleMedium) }
                        Label(stringResource(R.string.g4_le_what_you_drive)); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VEHICLE_KINDS.forEach { (k, l) -> Chip(l, selected = vehicleKind == k, icon = vehicleIcon(k)) { vehicleKind = k } } }
                        Muted(if (vehicleKind == "BIKE") stringResource(R.string.g4_le_bike_note) else stringResource(R.string.g4_le_passenger_note), Modifier.padding(top = 6.dp, bottom = 14.dp))
                        BucksField(model, { model = it.take(60) }, stringResource(R.string.g4_le_vehicle_model), "Bajaj RE, Maruti Dzire")
                        Label(stringResource(R.string.g4_le_languages)); FlowChips(LANGUAGES, languages) { languages = if (it in languages) languages - it else languages + it }
                        Spacer(Modifier.height(14.dp))
                        BucksField(description, { description = it.take(600) }, stringResource(R.string.g4_le_about_you), stringResource(R.string.g4_le_about_you_hint), singleLine = false, minLines = 3)
                        BucksField(area, { area = it.take(60) }, stringResource(R.string.g4_le_home_area), "Jayanagar")
                    }
                }
                if (kind == "BUSINESS" || kind == "SKILL") SwitchRow(stringResource(R.string.g4_le_show_call), stringResource(R.string.g4_le_show_call_note), showPhone) { showPhone = it }
                PhotoField(when (kind) { "BUSINESS" -> stringResource(R.string.g4_le_cover_photo); "ASSET" -> stringResource(R.string.g4_le_cover_photo); else -> stringResource(R.string.g4_le_profile_photo) }, existing?.photoUrl, preview, when (kind) { "BUSINESS" -> type.icon; "ASSET" -> assetIcon(category); else -> Icons.Rounded.Person }, onPick = pick, onClear = { photo = null; preview = null })
                Label(stringResource(R.string.g4_prov_location))
                when {
                    existing == null && fix != null -> Muted(if (kind == "ASSET") stringResource(R.string.g4_le_saved_here_asset, areaOf(st.hereLabel) ?: stringResource(R.string.g4_le_your_current_location)) else stringResource(R.string.g4_le_saved_here, areaOf(st.hereLabel) ?: stringResource(R.string.g4_le_your_current_location)))
                    existing == null -> Notice(if (st.locationGranted) stringResource(R.string.g4_le_waiting_location)
                                               else stringResource(R.string.g4_le_turn_on_location))
                    fix != null -> SwitchRow(stringResource(R.string.g4_le_move_here), stringResource(R.string.g4_le_move_here_note, areaOf(st.hereLabel) ?: stringResource(R.string.g4_le_your_current_location)), moveHere) { moveHere = it }
                    else -> Muted(if (st.locationGranted) stringResource(R.string.g4_le_stays_waiting) else stringResource(R.string.g4_le_stays_turn_on))
                }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) stringResource(R.string.g4_saving) else if (existing == null) stringResource(R.string.g4_fb_save) else stringResource(R.string.g4_le_save_changes), enabled = !m.busy && (existing != null || fix != null)) { save() }
            if (existing != null && kind != "DRIVER" && m.canManage(existing.id)) SmallButton(stringResource(R.string.g4_le_documents), Modifier.padding(bottom = 6.dp), tonal = true) { onDocs(existing.id) }
            if (existing != null && owner) BadButton(stringResource(R.string.g4_le_delete_kind, kindLabel(kind).lowercase()), Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog(stringResource(R.string.g4_le_delete_title, existing.title), stringResource(R.string.g4_le_delete_body), stringResource(R.string.g4_fb_delete),
        onConfirm = { m.deleteListing(existing.id) { onDone() } }, onDismiss = { confirmDelete = false })
}

/** Drops keys set to null (facts the owner cleared), so they leave the listing instead of being stored as null. */
private fun JsonObject.withoutNulls() = JsonObject(filterValues { it !is JsonNull })

/**
 * The fourth tab of the page: what it is called and what it lists. Every page has Feed, About, Gallery, this tab and
 * Recommendations, in that order. Only a business can list products (orders need a shop); a skill lists the rest.
 */
@Composable
private fun CatalogueTabEditor(kind: String, type: PageType?, label: String, kinds: Set<String>, onLabel: (String) -> Unit, onKinds: (Set<String>) -> Unit) {
    val options = if (kind == "BUSINESS") PageTypes.itemKinds else PageTypes.itemKinds - "PRODUCT"
    val default = PageTypes.defaultLabel(kind, type, PageTypes.itemKinds.filter { it in kinds })
    SectionTitle(stringResource(R.string.g4_le_catalogue_tab), Modifier.padding(top = 6.dp, bottom = 4.dp))
    Muted(stringResource(R.string.g4_le_catalogue_note), Modifier.padding(bottom = 8.dp))
    FlowChips(options.map { PageTypes.kindPlural(it) }, kinds.map { PageTypes.kindPlural(it) }.toSet()) { picked ->
        val k = options.first { PageTypes.kindPlural(it) == picked }
        onKinds(if (k in kinds) kinds - k else kinds + k)
    }
    BucksField(label, { onLabel(it.take(PageTypes.CATALOGUE_LABEL_MAX)) }, stringResource(R.string.g4_le_tab_name), default)
    Muted(listOf(stringResource(R.string.g4_prov_tab_feed), stringResource(R.string.g4_prov_tab_about), stringResource(R.string.g4_le_tab_gallery), label.trim().ifBlank { default }, stringResource(R.string.g4_prov_tab_recommendations)).joinToString(" · ") +
        (if (kind == "BUSINESS" && "PRODUCT" !in kinds) "\n" + stringResource(R.string.g4_le_no_products_note) else ""), Modifier.padding(bottom = 10.dp))
}

