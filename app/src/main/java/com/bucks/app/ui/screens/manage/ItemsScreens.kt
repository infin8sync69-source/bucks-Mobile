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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.ItemRow
import com.bucks.app.data.MediaPhoto
import com.bucks.app.data.Upload
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A listing's products (business) or services (skill), grouped by section, with an inline in-stock switch. */
@Composable
fun ItemsScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onEdit: (listingId: String, itemId: String?) -> Unit) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); m.loadItems(listingId) }
    val l = m.listing(listingId); val service = l?.kind == "SKILL"; val noun = if (service) "service" else "product"
    val rows = m.items[listingId]
    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (service) "Services" else "Products", onBack = onBack)
            l?.let { Muted(it.title, Modifier.padding(horizontal = Gutter)) }
            when {
                rows == null -> CenteredLoading()
                rows.isEmpty() -> BucksCard(Modifier.padding(Gutter)) {
                    Text("No ${noun}s yet", style = MaterialTheme.typography.titleMedium)
                    Muted(if (service) "Add each service with a price, like \"Tap repair · ₹300 per visit\". People see them on your profile and can message you about them."
                          else "Add what you sell with a price and pack size, like \"Sugar · ₹45 · 1 kg\". Customers search by product name and order from your profile. Use groups to keep long lists tidy: Rice, Dals, Snacks.", Modifier.padding(top = 4.dp))
                }
                else -> LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 16.dp)) {
                    val groups = rows.groupBy { it.group.trim() }.entries.sortedWith(compareBy({ it.key.isBlank() }, { it.key.lowercase() }))
                    groups.forEach { (g, list) ->
                        item(key = "group-$g") { SectionTitle(if (g.isBlank()) (if (groups.size > 1) "Other" else "All ${noun}s") else g, Modifier.padding(horizontal = Gutter, vertical = 8.dp)) }
                        items(list, key = { it.id ?: it.name }) { row ->
                            val mrpNote = row.mrp?.takeIf { it > row.price }?.let { "  (MRP ₹$it)" } ?: ""
                            ListRow(row.name, listOfNotNull("₹${row.price}$mrpNote", row.unit.ifBlank { null }).joinToString(" · "),
                                leading = { PhotoOrIcon(row.photoUrl, if (service) Icons.Rounded.Handyman else Icons.Rounded.ShoppingBag, size = 48) },
                                trailing = { Column(horizontalAlignment = Alignment.End) { Switch(checked = row.inStock, onCheckedChange = { on -> m.setInStock(row, on) }); Muted(if (row.inStock) (if (service) "Available" else "In stock") else (if (service) "Paused" else "Out of stock")) } },
                                onClick = { onEdit(listingId, row.id) })
                            Divider()
                        }
                    }
                }
            }
        }
        PrimaryButton("Add $noun", Modifier.padding(horizontal = Gutter, vertical = 12.dp)) { onEdit(listingId, null) }
    }
}

/** Add or edit one product or service. */
@Composable
fun ItemEditScreen(vm: BucksViewModel, listingId: String, itemId: String?, onBack: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); if (m.items[listingId] == null) m.loadItems(listingId) }
    val l = m.listing(listingId); val service = l?.kind == "SKILL"
    val existing = itemId?.let { id -> m.items[listingId]?.firstOrNull { it.id == id } }
    if (itemId != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(if (service) "Edit service" else "Edit product", onBack = onBack)
            if (m.items[listingId] != null) Column(Modifier.padding(Gutter)) { Text("Not found", style = MaterialTheme.typography.titleMedium); Muted("This ${if (service) "service" else "product"} was removed.", Modifier.padding(top = 4.dp)); SmallButton("Back", Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ItemForm(vm, listingId, service, existing, onBack) }
}

/** How a service is priced; stored in items.details.pricing and shown next to the price. */
internal val SERVICE_PRICING = listOf("FIXED" to "Fixed price", "HOURLY" to "Per hour", "VISIT" to "Per visit", "FROM" to "Starting from", "QUOTE" to "On quote")

@Composable
private fun ItemForm(vm: BucksViewModel, listingId: String, service: Boolean, existing: ItemRow?, onBack: () -> Unit) {
    val m = vm.myListings; val noun = if (service) "service" else "product"; val ctx = LocalContext.current
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
        val n = name.trim(); val p = price.toIntOrNull(); val mp = mrp.toIntOrNull(); val st = stock.toIntOrNull()
        if (n.isBlank()) { vm.toast("Give the $noun a name."); return }
        if (p == null && !(service && pricing == "QUOTE")) { vm.toast("Enter the price in rupees."); return }
        if (mp != null && p != null && mp < p) { vm.toast("MRP should be the same as or more than the selling price."); return }
        if (countStock && st == null) { vm.toast("Enter how many you have, or switch off stock counting."); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> if (k !in setOf("pricing", "duration", "brand")) put(k, v) }
            if (service) { put("pricing", pricing); if (duration.isNotBlank()) put("duration", duration.trim()) }
            else if (brand.isNotBlank()) put("brand", brand.trim())
        }
        val row = ItemRow(id = existing?.id, listingId = listingId, kind = if (service) "SERVICE" else "PRODUCT", name = n, price = p ?: 0, mrp = if (service) null else mp, unit = unit.trim(), group = group.trim(),
            photoUrl = existing?.photoUrl, inStock = inStock, sort = existing?.sort ?: m.items[listingId].orEmpty().size,
            description = description.trim(), stock = if (countStock) st else null, photos = existing?.photos.orEmpty(), details = details)
        m.saveItem(row, keep.toList(), added.map { it.first }) { onBack() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (existing == null) "Add $noun" else "Edit $noun", onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                // Photos first: they sell the item.
                Label("Photos (up to 8, the first is the main one)")
                Row(Modifier.horizontalScrollIfNeeded().padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    keep.forEachIndexed { i, ph -> PhotoThumb(ph.url, main = i == 0, onMain = { keep.removeAt(i); keep.add(0, ph) }) { keep.removeAt(i) } }
                    added.forEachIndexed { i, (_, u) -> PhotoThumb(u, main = keep.isEmpty() && i == 0, onMain = null) { added.removeAt(i) } }
                    if (keep.size + added.size < 8) Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium)
                        .clickable { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.AddPhotoAlternate, null, tint = MaterialTheme.colorScheme.primary); Text("Add", style = MaterialTheme.typography.labelSmall) }
                    }
                }
                BucksField(name, { name = it.take(80) }, if (service) "Service" else "Product name", if (service) "Tap repair" else "Sona masoori rice")
                BucksField(description, { description = it.take(1000) }, "Description (optional)", if (service) "What's included, what isn't, how long it takes" else "Size, material, taste, what's in the box", singleLine = false, minLines = 2)
                if (service) { Label("Pricing"); ChipRow(SERVICE_PRICING.map { it.second }, SERVICE_PRICING.firstOrNull { it.first == pricing }?.second, Modifier.padding(bottom = 12.dp)) { picked -> pricing = SERVICE_PRICING.first { it.second == picked }.first } }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BucksField(price, { price = it.filter { c -> c.isDigit() }.take(7) }, if (service && pricing == "QUOTE") "Typical price (₹, optional)" else "Price (₹)", "45", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                    if (!service) BucksField(mrp, { mrp = it.filter { c -> c.isDigit() }.take(7) }, "MRP (₹, optional)", "50", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                if (!service && (mrp.toIntOrNull() ?: 0) > (price.toIntOrNull() ?: 0) && price.isNotBlank()) Muted("Customers see the discount: ₹$price instead of ₹$mrp.", Modifier.padding(bottom = 10.dp))
                BucksField(unit, { unit = it.take(30) }, if (service) "Charged per" else "Pack size or unit", if (service) "per visit" else "1 kg")
                ChipRow(if (service) UNITS.filter { it.startsWith("per") } else UNITS.filter { !it.startsWith("per") }, unit.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { unit = it }
                if (service) BucksField(duration, { duration = it.take(40) }, "Takes about (optional)", "1 hour, 2 days")
                else BucksField(brand, { brand = it.take(40) }, "Brand (optional)", "Aashirvaad, Nandini")
                BucksField(group, { group = it.take(40) }, if (service) "Group (optional)" else "Group or section (optional)", if (service) "Repairs" else "Rice and grains")
                if (existingGroups.isNotEmpty()) ChipRow(existingGroups, group.trim().ifBlank { null }, Modifier.padding(bottom = 14.dp)) { group = it }
                SectionTitle("Availability", Modifier.padding(top = 4.dp, bottom = 2.dp))
                SwitchRow(if (service) "Available now" else "In stock", if (service) "Switch off when you can't take this work for a while." else "Out-of-stock products stay on your profile but can't be ordered.", inStock) { inStock = it }
                if (!service) {
                    SwitchRow("Count stock", "Bucks takes each order off the count and stops orders at 0. Cancelled orders go back.", countStock) { countStock = it }
                    if (countStock) BucksField(stock, { stock = it.filter { c -> c.isDigit() }.take(6) }, "How many you have", "25", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) "Saving…" else if (existing == null) "Add $noun" else "Save changes", enabled = !m.busy) { save() }
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
