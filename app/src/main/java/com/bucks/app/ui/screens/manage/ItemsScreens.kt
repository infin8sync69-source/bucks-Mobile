package com.bucks.app.ui.screens.manage

import android.net.Uri
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bucks.app.data.ItemRow
import com.bucks.app.data.Picked
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

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

@Composable
private fun ItemForm(vm: BucksViewModel, listingId: String, service: Boolean, existing: ItemRow?, onBack: () -> Unit) {
    val m = vm.myListings; val noun = if (service) "service" else "product"
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var price by remember { mutableStateOf(existing?.price?.toString() ?: "") }
    var mrp by remember { mutableStateOf(existing?.mrp?.toString() ?: "") }
    var unit by remember { mutableStateOf(existing?.unit ?: "") }
    var group by remember { mutableStateOf(existing?.group ?: "") }
    var inStock by remember { mutableStateOf(existing?.inStock ?: true) }
    var photo by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val pick = rememberImagePicker { p, u -> photo = p; preview = u }
    val existingGroups = m.items[listingId].orEmpty().map { it.group.trim() }.filter { it.isNotBlank() }.distinct()

    fun save() {
        val n = name.trim(); val p = price.toIntOrNull(); val mp = mrp.toIntOrNull()
        if (n.isBlank()) { vm.toast("Give the $noun a name."); return }
        if (p == null) { vm.toast("Enter the price in rupees."); return }
        if (mp != null && mp < p) { vm.toast("MRP should be the same as or more than the selling price."); return }
        val row = ItemRow(id = existing?.id, listingId = listingId, kind = if (service) "SERVICE" else "PRODUCT", name = n, price = p, mrp = mp, unit = unit.trim(), group = group.trim(),
            photoUrl = existing?.photoUrl, inStock = inStock, sort = existing?.sort ?: m.items[listingId].orEmpty().size)
        m.saveItem(row, photo) { onBack() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (existing == null) "Add $noun" else "Edit $noun", onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                BucksField(name, { name = it.take(80) }, if (service) "Service" else "Product name", if (service) "Tap repair" else "Sugar")
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BucksField(price, { price = it.filter { c -> c.isDigit() }.take(7) }, "Price (₹)", "45", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                    if (!service) BucksField(mrp, { mrp = it.filter { c -> c.isDigit() }.take(7) }, "MRP (₹, optional)", "50", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                if (!service && (mrp.toIntOrNull() ?: 0) > (price.toIntOrNull() ?: 0) && price.isNotBlank()) Muted("Customers see the discount: ₹$price instead of ₹$mrp.", Modifier.padding(bottom = 10.dp))
                BucksField(unit, { unit = it.take(30) }, if (service) "Charged per" else "Pack size or unit", if (service) "per visit" else "1 kg")
                ChipRow(if (service) UNITS.filter { it.startsWith("per") } else UNITS.filter { !it.startsWith("per") }, unit.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { unit = it }
                BucksField(group, { group = it.take(40) }, if (service) "Group (optional)" else "Group or section (optional)", if (service) "Repairs" else "Rice and grains")
                if (existingGroups.isNotEmpty()) ChipRow(existingGroups, group.trim().ifBlank { null }, Modifier.padding(bottom = 14.dp)) { group = it }
                SwitchRow(if (service) "Available now" else "In stock", if (service) "Switch off when you can't take this work for a while." else "Out-of-stock products stay on your profile but can't be ordered.", inStock) { inStock = it }
                Spacer(Modifier.height(8.dp))
                PhotoField("Photo", existing?.photoUrl, preview, if (service) Icons.Rounded.Handyman else Icons.Rounded.ShoppingBag, onPick = pick, onClear = { photo = null; preview = null })
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
