package com.bucks.app.ui.screens.manage

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.ItemRow
import com.bucks.app.data.ListingRow
import com.bucks.app.data.MediaPhoto
import com.bucks.app.data.Upload
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * A listing's catalogue. What it holds comes from the page type (ui/PageTypes.kt): products for a shop, services for a skill,
 * a local service or a company, programs for an NGO or a school, events for a group or a place of worship. The server refuses
 * an item whose kind the type does not hold, so the kind here always comes from the listing, never from the form.
 */

/** The items.kind a new catalogue entry gets by default: the first kind the page's catalogue holds (owner's choice, else its type's). */
internal fun itemKindOf(l: ListingRow?): String = l?.let { PageTypes.catalogue(it).newItemKind } ?: "PRODUCT"

/** The kind the next new entry gets, set by [AddItemButton] when the catalogue holds more than one kind; the item form reads it. */
internal object NewItemKind { var next: String? = null }

/** "Add a product", or, when the catalogue holds several kinds, a menu: Add a product / Add a service / Add an event. */
@Composable
internal fun AddItemButton(l: ListingRow?, modifier: Modifier = Modifier, onAdd: () -> Unit) {
    val cat = l?.let { PageTypes.catalogue(it) }
    val kinds = cat?.kinds.orEmpty()
    var menu by remember { mutableStateOf(false) }
    if (kinds.size <= 1) PrimaryButton(addItemTitle(itemNoun(itemKindOf(l))), modifier) { NewItemKind.next = null; onAdd() }
    else Box(modifier) {
        PrimaryButton("Add to ${cat?.label ?: "catalogue"}") { menu = true }
        DropdownMenu(menu, { menu = false }) {
            kinds.forEach { k -> DropdownMenuItem(text = { Text(addItemTitle(itemNoun(k))) }, leadingIcon = { Icon(itemIcon(k), null) }, onClick = { menu = false; NewItemKind.next = k; onAdd() }) }
        }
    }
}
internal fun itemNoun(kind: String) = when (kind) { "SERVICE" -> "service"; "PROGRAM" -> "program"; "EVENT" -> "event"; else -> "product" }
internal fun itemIcon(kind: String): ImageVector = when (kind) { "SERVICE" -> Icons.Rounded.Handyman; "PROGRAM" -> Icons.Rounded.Assignment; "EVENT" -> Icons.Rounded.CalendarMonth; else -> Icons.Rounded.ShoppingBag }
/** "Add a program", "Add an event". */
internal fun addItemTitle(noun: String) = if (noun == "event") "Add an event" else "Add a $noun"
/** What the switch on an item means, on and off, for each kind. */
internal fun itemOnLabel(kind: String, on: Boolean) = when (kind) {
    "SERVICE" -> if (on) "Available" else "Paused"
    "PROGRAM" -> if (on) "Open" else "Closed"
    "EVENT" -> if (on) "Shown" else "Hidden"
    else -> if (on) "In stock" else "Out of stock"
}
/** "₹1,500", or "Free" for a program or event at 0. Products and services keep the number. */
internal fun itemPriceLabel(kind: String, price: Int) = if (price == 0 && (kind == "PROGRAM" || kind == "EVENT")) "Free" else rupees(price)
internal fun itemEmptyCopy(kind: String) = when (kind) {
    "SERVICE" -> "Add each service with a price, like \"Tap repair · ₹300 per visit\". People see them on your page and can book or ask about them."
    "PROGRAM" -> "Add each program, course or class with a price or free, like \"Evening tuition · ₹1,500 per month\". People see them on your page and can enquire or join."
    "EVENT" -> "Add upcoming events with the date and time, like \"Sunday clean-up · Sun 7am\". People see them on your page and turn up."
    else -> "Add what you sell with a price and pack size, like \"Sugar · ₹45 · 1 kg\". Customers search by product name and order from your profile. Use groups to keep long lists tidy: Rice, Dals, Snacks."
}
/** How a program is charged. */
internal val PROGRAM_UNITS = listOf("per month", "per batch", "per year", "per session", "free")

/** A listing's catalogue (products, services, programs or events by its type), grouped by section, with an inline switch. */
@Composable
fun ItemsScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onEdit: (listingId: String, itemId: String?) -> Unit) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); m.loadItems(listingId) }
    val l = m.listing(listingId); val itemKind = itemKindOf(l); val noun = itemNoun(itemKind)
    val title = l?.let { PageTypes.catalogue(it).label } ?: "${noun.replaceFirstChar { it.uppercase() }}s"
    val rows = m.items[listingId]
    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(title, onBack = onBack)
            l?.let { Muted(it.title, Modifier.padding(horizontal = Gutter)) }
            when {
                rows == null -> CenteredLoading()
                rows.isEmpty() -> BucksCard(Modifier.padding(Gutter)) {
                    Text("No ${noun}s yet", style = MaterialTheme.typography.titleMedium)
                    Muted(itemEmptyCopy(itemKind), Modifier.padding(top = 4.dp))
                }
                else -> LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 16.dp)) {
                    val groups = rows.groupBy { it.group.trim() }.entries.sortedWith(compareBy({ it.key.isBlank() }, { it.key.lowercase() }))
                    groups.forEach { (g, list) ->
                        item(key = "group-$g") { SectionTitle(if (g.isBlank()) (if (groups.size > 1) "Other" else "All ${noun}s") else g, Modifier.padding(horizontal = Gutter, vertical = 8.dp)) }
                        items(list, key = { it.id ?: it.name }) { row ->
                            val mrpNote = row.mrp?.takeIf { it > row.price }?.let { "  (MRP ₹$it)" } ?: ""
                            ListRow(row.name, listOfNotNull("${itemPriceLabel(row.kind, row.price)}$mrpNote", row.unit.ifBlank { null }).joinToString(" · "),
                                leading = { PhotoOrIcon(row.photoUrl, itemIcon(row.kind), size = 48) },
                                trailing = { Column(horizontalAlignment = Alignment.End) { Switch(checked = row.inStock, onCheckedChange = { on -> m.setInStock(row, on) }); Muted(itemOnLabel(row.kind, row.inStock)) } },
                                onClick = { onEdit(listingId, row.id) })
                            Divider()
                        }
                    }
                }
            }
        }
        AddItemButton(l, Modifier.padding(horizontal = Gutter, vertical = 12.dp)) { onEdit(listingId, null) }
    }
}

/** Add or edit one catalogue entry; its kind comes from the listing (an existing item keeps its own). */
@Composable
fun ItemEditScreen(vm: BucksViewModel, listingId: String, itemId: String?, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); if (m.items[listingId] == null) m.loadItems(listingId) }
    val l = m.listing(listingId)
    val existing = itemId?.let { id -> m.items[listingId]?.firstOrNull { it.id == id } }
    // A new entry takes the kind picked in the Add menu, when it is one this catalogue holds.
    val itemKind = existing?.kind ?: NewItemKind.next?.takeIf { k -> l == null || k in PageTypes.catalogue(l).kinds } ?: itemKindOf(l); val noun = itemNoun(itemKind)
    if (itemId != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Edit $noun", onBack = onBack)
            if (m.items[listingId] != null) Column(Modifier.padding(Gutter)) { Text("Not found", style = MaterialTheme.typography.titleMedium); Muted("This $noun was removed.", Modifier.padding(top = 4.dp)); SmallButton("Back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ItemForm(vm, listingId, itemKind, existing, onBack) }
}

/** How a service is priced; stored in items.details.pricing and shown next to the price. */
internal val SERVICE_PRICING = listOf("FIXED" to "Fixed price", "HOURLY" to "Per hour", "VISIT" to "Per visit", "FROM" to "Starting from", "QUOTE" to "On quote")

@Composable
private fun ItemForm(vm: BucksViewModel, listingId: String, itemKind: String, existing: ItemRow?, onBack: () -> Unit) {
    val m = vm.myListings; val ctx = LocalContext.current
    val service = itemKind == "SERVICE"; val product = itemKind == "PRODUCT"; val program = itemKind == "PROGRAM"; val event = itemKind == "EVENT"
    val noun = itemNoun(itemKind)
    val d = existing?.details ?: JsonObject(emptyMap())
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var price by remember { mutableStateOf(existing?.price?.toString() ?: "") }
    var mrp by remember { mutableStateOf(existing?.mrp?.toString() ?: "") }
    var unit by remember { mutableStateOf(existing?.unit ?: "") }
    var group by remember { mutableStateOf(existing?.group ?: "") }
    var inStock by remember { mutableStateOf(existing?.inStock ?: true) }
    var countStock by remember { mutableStateOf(existing?.stock != null) }
    var stock by remember { mutableStateOf(existing?.stock?.toString() ?: "") }
    var pricing by remember { mutableStateOf(d.str("pricing").ifBlank { "FIXED" }) }
    var duration by remember { mutableStateOf(d.str("duration")) }
    var brand by remember { mutableStateOf(d.str("brand")) }
    // Photos it already has (older items only have photo_url) and new ones picked here; the first is the main photo.
    val keep = remember { mutableStateListOf<MediaPhoto>().apply { addAll(existing?.photos?.ifEmpty { null } ?: listOfNotNull(existing?.photoUrl?.takeIf { it.isNotBlank() }?.let { MediaPhoto(it) })) } }
    val added = remember { mutableStateListOf<Pair<Picked, Uri>>() }
    var confirmDelete by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(8)) { uris ->
        val room = 8 - keep.size - added.size
        val picked = uris.take(room.coerceAtLeast(0)).mapNotNull { u -> Upload.read(ctx, u)?.asListingPhoto()?.let { it to u } }
        if (uris.size > room) vm.toast("Up to 8 photos per $noun.")
        added.addAll(picked)
    }
    val existingGroups = m.items[listingId].orEmpty().map { it.group.trim() }.filter { it.isNotBlank() }.distinct()

    fun save() {
        // A program or an event may be free: an empty price is 0 and shows as "Free".
        val n = name.trim(); val p = price.toIntOrNull() ?: if (program || event) 0 else null; val mp = if (product) mrp.toIntOrNull() else null; val st = stock.toIntOrNull()
        if (n.isBlank()) { vm.toast("Give the $noun a name."); return }
        if (p == null && !(service && pricing == "QUOTE")) { vm.toast("Enter the price in rupees."); return }
        if (mp != null && p != null && mp < p) { vm.toast("MRP should be the same as or more than the selling price."); return }
        if (product && countStock && st == null) { vm.toast("Enter how many you have, or switch off stock counting."); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> if (k !in setOf("pricing", "duration", "brand")) put(k, v) }
            if (service) { put("pricing", pricing); if (duration.isNotBlank()) put("duration", duration.trim()) }
            else if (product && brand.isNotBlank()) put("brand", brand.trim())
        }
        val row = ItemRow(id = existing?.id, listingId = listingId, kind = itemKind, name = n, price = p ?: 0, mrp = mp, unit = unit.trim(), group = group.trim(),
            photoUrl = existing?.photoUrl, inStock = inStock, sort = existing?.sort ?: m.items[listingId].orEmpty().size,
            description = description.trim(), stock = if (product && countStock) st else null, photos = existing?.photos.orEmpty(), details = details)
        m.saveItem(row, keep.toList(), added.map { it.first }) { onBack() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (existing == null) addItemTitle(noun) else "Edit $noun", onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                // Photos first: they sell the item.
                Label("Photos (up to 8, the first is the main one)")
                Row(Modifier.horizontalScrollIfNeeded().padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    keep.forEachIndexed { i, ph -> PhotoThumb(ph.url, main = i == 0, onMain = { keep.removeAt(i); keep.add(0, ph) }) { keep.removeAt(i) } }
                    added.forEachIndexed { i, (_, u) -> PhotoThumb(u, main = keep.isEmpty() && i == 0, onMain = null) { added.removeAt(i) } }
                    if (keep.size + added.size < 8) Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium)
                        .clickable { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.PhotoCamera, null, tint = MaterialTheme.colorScheme.primary); Text("Add", style = MaterialTheme.typography.labelSmall) }
                    }
                }
                BucksField(name, { name = it.take(80) }, when (itemKind) { "SERVICE" -> "Service"; "PROGRAM" -> "Program name"; "EVENT" -> "Event name"; else -> "Product name" },
                    when (itemKind) { "SERVICE" -> "Tap repair"; "PROGRAM" -> "Evening tuition, class 10"; "EVENT" -> "Sunday clean-up drive"; else -> "Sona masoori rice" })
                BucksField(description, { description = it.take(1000) }, if (event) "Where to meet" else "Description (optional)",
                    when (itemKind) { "SERVICE" -> "What's included, what isn't, how long it takes"; "PROGRAM" -> "What it covers, who it's for, how to join"; "EVENT" -> "Gate 2, Lalbagh. Bring gloves and water."; else -> "Size, material, taste, what's in the box" }, singleLine = false, minLines = 2)
                if (service) { Label("Pricing"); ChipRow(SERVICE_PRICING.map { it.second }, SERVICE_PRICING.firstOrNull { it.first == pricing }?.second, Modifier.padding(bottom = 12.dp)) { picked -> pricing = SERVICE_PRICING.first { it.second == picked }.first } }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BucksField(price, { price = it.filter { c -> c.isDigit() }.take(7) }, when { service && pricing == "QUOTE" -> "Typical price (₹, optional)"; program || event -> "Price (₹, 0 for free)"; else -> "Price (₹)" },
                        when (itemKind) { "PROGRAM" -> "1500"; "EVENT" -> "0"; else -> "45" }, Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                    if (product) BucksField(mrp, { mrp = it.filter { c -> c.isDigit() }.take(7) }, "MRP (₹, optional)", "50", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                if (product && (mrp.toIntOrNull() ?: 0) > (price.toIntOrNull() ?: 0) && price.isNotBlank()) Muted("Customers see the discount: ₹$price instead of ₹$mrp.", Modifier.padding(bottom = 10.dp))
                if ((program || event) && (price.toIntOrNull() ?: 0) == 0) Muted("Shown as Free.", Modifier.padding(bottom = 10.dp))
                BucksField(unit, { unit = it.take(30) }, when (itemKind) { "SERVICE", "PROGRAM" -> "Charged per"; "EVENT" -> "Date and time"; else -> "Pack size or unit" },
                    when (itemKind) { "SERVICE" -> "per visit"; "PROGRAM" -> "per month / per batch / free"; "EVENT" -> "Sun 7am, or 15 Aug 6 pm"; else -> "1 kg" })
                val unitChips = when (itemKind) { "SERVICE" -> UNITS.filter { it.startsWith("per") }; "PROGRAM" -> PROGRAM_UNITS; "EVENT" -> emptyList(); else -> UNITS.filter { !it.startsWith("per") } }
                if (unitChips.isNotEmpty()) ChipRow(unitChips, unit.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { unit = it } else Spacer(Modifier.height(6.dp))
                if (service) BucksField(duration, { duration = it.take(40) }, "Takes about (optional)", "1 hour, 2 days")
                else if (product) BucksField(brand, { brand = it.take(40) }, "Brand (optional)", "Aashirvaad, Nandini")
                BucksField(group, { group = it.take(40) }, when (itemKind) { "SERVICE" -> "Group (optional)"; "PROGRAM", "EVENT" -> "Section (optional)"; else -> "Group or section (optional)" },
                    when (itemKind) { "SERVICE" -> "Repairs"; "PROGRAM" -> "Classes"; "EVENT" -> "This month"; else -> "Rice and grains" })
                if (existingGroups.isNotEmpty()) ChipRow(existingGroups, group.trim().ifBlank { null }, Modifier.padding(bottom = 14.dp)) { group = it }
                SectionTitle("Availability", Modifier.padding(top = 4.dp, bottom = 2.dp))
                SwitchRow(when (itemKind) { "SERVICE" -> "Available now"; "PROGRAM" -> "Open to join"; "EVENT" -> "Shown on the page"; else -> "In stock" },
                    when (itemKind) { "SERVICE" -> "Switch off when you can't take this work for a while."; "PROGRAM" -> "Switch off when the batch is full or the program has ended."; "EVENT" -> "Switch off once it's over, or remove it."; else -> "Out-of-stock products stay on your profile but can't be ordered." }, inStock) { inStock = it }
                if (product) {
                    SwitchRow("Count stock", "Bucks takes each order off the count and stops orders at 0. Cancelled orders go back.", countStock) { countStock = it }
                    if (countStock) BucksField(stock, { stock = it.filter { c -> c.isDigit() }.take(6) }, "How many you have", "25", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) "Saving…" else if (existing == null) addItemTitle(noun) else "Save changes", enabled = !m.busy) { save() }
            if (existing != null) BadButton("Remove this $noun", Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog("Remove ${existing.name}?", "It disappears from your profile and search. Orders already placed aren't affected.", "Remove",
        onConfirm = { m.deleteItem(existing) { onBack() } }, onDismiss = { confirmDelete = false })
}

/** One photo in the item form: "Main" on the first, tap another to make it main, x to take it out. */
@Composable
private fun PhotoThumb(model: Any, main: Boolean, onMain: (() -> Unit)?, onRemove: () -> Unit) = Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).clickable(enabled = onMain != null && !main) { onMain?.invoke() }) {
    AsyncImage(model, null, Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer), contentScale = ContentScale.Crop)
    if (main) Box(Modifier.align(Alignment.BottomStart).padding(4.dp)) { Pill("Main", MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary) }
    IconButton(onClick = onRemove, modifier = Modifier.align(Alignment.TopEnd).size(28.dp).padding(2.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f))) { Icon(Icons.Rounded.Close, "Remove photo", Modifier.size(16.dp), tint = Color.White) }
}
