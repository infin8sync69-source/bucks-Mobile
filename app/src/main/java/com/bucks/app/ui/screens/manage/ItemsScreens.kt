package com.bucks.app.ui.screens.manage

import com.bucks.app.data.Money
import com.bucks.app.data.Str
import androidx.annotation.StringRes
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
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
internal object NewItemKind { var next: String? = null
    /** "Add another option": the product a new item becomes an option (size, colour) of; taken once by the new form. */
    var optionOf: ItemRow? = null }

/** "Add a product", or, when the catalogue holds several kinds, a menu: Add a product / Add a service / Add an event. */
@Composable
internal fun AddItemButton(l: ListingRow?, modifier: Modifier = Modifier, onAdd: () -> Unit) {
    val cat = l?.let { PageTypes.catalogue(it) }
    val kinds = cat?.kinds.orEmpty()
    var menu by remember { mutableStateOf(false) }
    if (kinds.size <= 1) PrimaryButton(addItemTitle(itemNoun(itemKindOf(l))), modifier) { NewItemKind.next = null; onAdd() }
    else Box(modifier) {
        PrimaryButton(cat?.label?.let { stringResource(R.string.g8_add_to, it) } ?: stringResource(R.string.g8_add_to_catalogue)) { menu = true }
        DropdownMenu(menu, { menu = false }) {
            kinds.forEach { k -> DropdownMenuItem(text = { Text(addItemTitle(itemNoun(k))) }, leadingIcon = { Icon(itemIcon(k), null) }, onClick = { menu = false; NewItemKind.next = k; onAdd() }) }
        }
    }
}
internal fun itemNoun(kind: String) = when (kind) { "SERVICE" -> "service"; "PROGRAM" -> "program"; "EVENT" -> "event"; else -> "product" }
internal fun itemIcon(kind: String): ImageVector = when (kind) { "SERVICE" -> Icons.Rounded.Handyman; "PROGRAM" -> Icons.Rounded.Assignment; "EVENT" -> Icons.Rounded.CalendarMonth; else -> Icons.Rounded.ShoppingBag }
/** "Add a program", "Add an event". */
internal fun addItemTitle(noun: String) = Str.get(when (noun) { "service" -> R.string.g8_add_service; "program" -> R.string.g8_add_program; "event" -> R.string.g8_add_event; else -> R.string.g8_add_product })
/** One whole sentence per kind (word order differs by language, so nouns are never spliced in). */
private fun kindStr(kind: String, @StringRes product: Int, @StringRes service: Int, @StringRes program: Int, @StringRes event: Int, vararg args: Any): String =
    Str.get(when (kind) { "SERVICE" -> service; "PROGRAM" -> program; "EVENT" -> event; else -> product }, *args)
/** What the switch on an item means, on and off, for each kind. */
internal fun itemOnLabel(kind: String, on: Boolean) = when (kind) {
    "SERVICE" -> Str.get(if (on) R.string.g8_item_available else R.string.g8_item_paused)
    "PROGRAM" -> Str.get(if (on) R.string.g8_item_open else R.string.g8_item_closed)
    "EVENT" -> Str.get(if (on) R.string.g8_item_shown else R.string.g8_item_hidden)
    else -> Str.get(if (on) R.string.g8_item_in_stock else R.string.g8_item_out_of_stock)
}
/** "₹1,500", or "Free" for a program or event at 0. Products and services keep the number. */
internal fun itemPriceLabel(kind: String, price: Int) = if (price == 0 && (kind == "PROGRAM" || kind == "EVENT")) Str.get(R.string.g8_free) else rupees(price)
internal fun itemEmptyCopy(kind: String) = when (kind) {
    "SERVICE" -> Str.get(R.string.g8_empty_service, Money.format(300))
    // Play Billing: only live or in-person teaching paid person to person; recorded courses and downloads would be digital goods.
    "PROGRAM" -> Str.get(R.string.g8_empty_program, Money.format(1500))
    "EVENT" -> Str.get(R.string.g8_empty_event)
    else -> Str.get(R.string.g8_empty_product, Money.format(45))
}
/** How a program is charged. */
internal val PROGRAM_UNITS get() = listOf(Str.get(R.string.g8_unit_per_month), Str.get(R.string.g8_unit_per_batch), Str.get(R.string.g8_unit_per_year), Str.get(R.string.g8_unit_per_session), Str.get(R.string.g8_unit_free))

/** A listing's catalogue (products, services, programs or events by its type), grouped by section, with an inline switch. */
@Composable
fun ItemsScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit, onEdit: (listingId: String, itemId: String?) -> Unit) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); m.loadItems(listingId) }
    val l = m.listing(listingId); val itemKind = itemKindOf(l); val noun = itemNoun(itemKind)
    val title = l?.let { PageTypes.catalogue(it).label } ?: kindStr(itemKind, R.string.g8_items_product, R.string.g8_items_service, R.string.g8_items_program, R.string.g8_items_event)
    val rows = m.items[listingId]
    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(title, onBack = onBack)
            l?.let { Muted(it.title, Modifier.padding(horizontal = Gutter)) }
            when {
                rows == null -> CenteredLoading()
                rows.isEmpty() -> BucksCard(Modifier.padding(Gutter)) {
                    Text(kindStr(itemKind, R.string.g8_no_items_product, R.string.g8_no_items_service, R.string.g8_no_items_program, R.string.g8_no_items_event), style = MaterialTheme.typography.titleMedium)
                    Muted(itemEmptyCopy(itemKind), Modifier.padding(top = 4.dp))
                }
                else -> LazyColumn(contentPadding = PaddingValues(top = 8.dp, bottom = 16.dp)) {
                    val groups = rows.groupBy { it.group.trim() }.entries.sortedWith(compareBy({ it.key.isBlank() }, { it.key.lowercase() }))
                    groups.forEach { (g, list) ->
                        item(key = "group-$g") { SectionTitle(if (g.isBlank()) (if (groups.size > 1) stringResource(R.string.g8_other) else kindStr(itemKind, R.string.g8_all_items_product, R.string.g8_all_items_service, R.string.g8_all_items_program, R.string.g8_all_items_event)) else g, Modifier.padding(horizontal = Gutter, vertical = 8.dp)) }
                        items(list, key = { it.id ?: it.name }) { row ->
                            val mrpNote = row.mrp?.takeIf { it > row.price }?.let { "  " + stringResource(R.string.g8_mrp_note, rupees(it)) } ?: ""
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
fun ItemEditScreen(vm: BucksViewModel, listingId: String, itemId: String?, onBack: () -> Unit, onAddOption: () -> Unit = {}) {
    val m = vm.myListings
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); if (m.items[listingId] == null) m.loadItems(listingId) }
    val l = m.listing(listingId)
    val existing = itemId?.let { id -> m.items[listingId]?.firstOrNull { it.id == id } }
    // A new entry takes the kind picked in the Add menu, when it is one this catalogue holds.
    val itemKind = existing?.kind ?: NewItemKind.next?.takeIf { k -> l == null || k in PageTypes.catalogue(l).kinds } ?: itemKindOf(l); val noun = itemNoun(itemKind)
    if (itemId != null && existing == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(kindStr(itemKind, R.string.g8_edit_item_product, R.string.g8_edit_item_service, R.string.g8_edit_item_program, R.string.g8_edit_item_event), onBack = onBack)
            if (m.items[listingId] != null) Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g8_not_found), style = MaterialTheme.typography.titleMedium); Muted(kindStr(itemKind, R.string.g8_item_removed_product, R.string.g8_item_removed_service, R.string.g8_item_removed_program, R.string.g8_item_removed_event), Modifier.padding(top = 4.dp)); SmallButton(stringResource(R.string.g8_back), Modifier.padding(top = 14.dp), tonal = true, onClick = onBack) }
            else CenteredLoading() }
        return
    }
    key(existing?.id) { ItemForm(vm, listingId, itemKind, existing, onBack, onAddOption) }
}

/** How a service is priced; stored in items.details.pricing and shown next to the price. */
internal val SERVICE_PRICING get() = listOf("FIXED" to Str.get(R.string.g8_pricing_fixed), "HOURLY" to Str.get(R.string.g8_pricing_hourly), "VISIT" to Str.get(R.string.g8_pricing_visit), "FROM" to Str.get(R.string.g8_pricing_from), "QUOTE" to Str.get(R.string.g8_pricing_quote))

@Composable
private fun ItemForm(vm: BucksViewModel, listingId: String, itemKind: String, existing: ItemRow?, onBack: () -> Unit, onAddOption: () -> Unit) {
    val m = vm.myListings; val ctx = LocalContext.current
    val service = itemKind == "SERVICE"; val product = itemKind == "PRODUCT"; val program = itemKind == "PROGRAM"; val event = itemKind == "EVENT"
    val noun = itemNoun(itemKind)
    // A new option of a product starts as a copy of it (name, price, group, brand, description), with its own option label left blank.
    val template = remember { if (existing == null && product) NewItemKind.optionOf.also { NewItemKind.optionOf = null } else null }
    val src = existing ?: template
    val d = existing?.details ?: JsonObject(emptyMap())
    val td = src?.details ?: JsonObject(emptyMap())
    var name by remember { mutableStateOf(src?.name ?: "") }
    var description by remember { mutableStateOf(src?.description ?: "") }
    var price by remember { mutableStateOf(src?.price?.toString() ?: "") }
    var mrp by remember { mutableStateOf(src?.mrp?.toString() ?: "") }
    var unit by remember { mutableStateOf(existing?.unit ?: "") }
    var group by remember { mutableStateOf(src?.group ?: "") }
    // The option this row is (Small, Red, 500 g); options of one product share details.product_id and show as one card.
    var variant by remember { mutableStateOf(d.str("variant")) }
    var inStock by remember { mutableStateOf(existing?.inStock ?: true) }
    var countStock by remember { mutableStateOf(existing?.stock != null) }
    var stock by remember { mutableStateOf(existing?.stock?.toString() ?: "") }
    var pricing by remember { mutableStateOf(d.str("pricing").ifBlank { "FIXED" }) }
    var duration by remember { mutableStateOf(d.str("duration")) }
    var brand by remember { mutableStateOf(td.str("brand")) }
    // Photos it already has (older items only have photo_url) and new ones picked here; the first is the main photo.
    val keep = remember { mutableStateListOf<MediaPhoto>().apply { addAll(existing?.photos?.ifEmpty { null } ?: listOfNotNull(existing?.photoUrl?.takeIf { it.isNotBlank() }?.let { MediaPhoto(it) })) } }
    val added = remember { mutableStateListOf<Pair<Picked, Uri>>() }
    var confirmDelete by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(8)) { uris ->
        val room = 8 - keep.size - added.size
        val picked = uris.take(room.coerceAtLeast(0)).mapNotNull { u -> Upload.read(ctx, u)?.asListingPhoto()?.let { it to u } }
        if (uris.size > room) vm.toast(kindStr(itemKind, R.string.g8_photos_limit_product, R.string.g8_photos_limit_service, R.string.g8_photos_limit_program, R.string.g8_photos_limit_event))
        added.addAll(picked)
    }
    val existingGroups = m.items[listingId].orEmpty().map { it.group.trim() }.filter { it.isNotBlank() }.distinct()

    fun save(after: () -> Unit = onBack) {
        // A program or an event may be free: an empty price is 0 and shows as "Free".
        val n = name.trim(); val p = price.toIntOrNull() ?: if (program || event) 0 else null; val mp = if (product) mrp.toIntOrNull() else null; val st = stock.toIntOrNull()
        if (n.isBlank()) { vm.toast(kindStr(itemKind, R.string.g8_name_needed_product, R.string.g8_name_needed_service, R.string.g8_name_needed_program, R.string.g8_name_needed_event)); return }
        if (p == null && !(service && pricing == "QUOTE")) { vm.toast(Str.get(R.string.g8_enter_price)); return }
        if (mp != null && p != null && mp < p) { vm.toast(Str.get(R.string.g8_mrp_too_low)); return }
        if (product && countStock && st == null) { vm.toast(Str.get(R.string.g8_stock_needed)); return }
        val details = buildJsonObject {
            d.forEach { (k, v) -> if (k !in setOf("pricing", "duration", "brand", "variant", "product_id", "product")) put(k, v) }
            if (product) {
                // Same key as the server's item_product_key: product_id, else the first row's own id, so that row needs no change.
                val pid = d.str("product_id").ifBlank { null } ?: template?.let { t -> t.details.str("product_id").ifBlank { null } ?: t.id }
                if (pid != null) { put("product_id", pid); put("product", (d.str("product").ifBlank { null } ?: template?.let { t -> t.details.str("product").ifBlank { null } ?: t.name } ?: n)) }
                if (variant.isNotBlank()) put("variant", variant.trim())
            }
            if (service) { put("pricing", pricing); if (duration.isNotBlank()) put("duration", duration.trim()) }
            else if (product && brand.isNotBlank()) put("brand", brand.trim())
        }
        val row = ItemRow(id = existing?.id, listingId = listingId, kind = itemKind, name = n, price = p ?: 0, mrp = mp, unit = unit.trim(), group = group.trim(),
            photoUrl = existing?.photoUrl, inStock = inStock, sort = existing?.sort ?: m.items[listingId].orEmpty().size,
            description = description.trim(), stock = if (product && countStock) st else null, photos = existing?.photos.orEmpty(), details = details)
        m.saveItem(row, keep.toList(), added.map { it.first }) { after() }
    }

    Column(Modifier.fillMaxSize()) {
        ContentColumn(Modifier.weight(1f)) {
            BucksTopBar(if (existing == null) addItemTitle(noun) else kindStr(itemKind, R.string.g8_edit_item_product, R.string.g8_edit_item_service, R.string.g8_edit_item_program, R.string.g8_edit_item_event), onBack = onBack)
            if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(top = 8.dp, bottom = 16.dp)) {
                // Photos first: they sell the item.
                Label(stringResource(R.string.g8_photos_label))
                Row(Modifier.horizontalScrollIfNeeded().padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    keep.forEachIndexed { i, ph -> PhotoThumb(ph.url, main = i == 0, onMain = { keep.removeAt(i); keep.add(0, ph) }) { keep.removeAt(i) } }
                    added.forEachIndexed { i, (_, u) -> PhotoThumb(u, main = keep.isEmpty() && i == 0, onMain = null) { added.removeAt(i) } }
                    if (keep.size + added.size < 8) Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium)
                        .clickable { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.PhotoCamera, null, tint = MaterialTheme.colorScheme.primary); Text(stringResource(R.string.g8_add), style = MaterialTheme.typography.labelSmall) }
                    }
                }
                BucksField(name, { name = it.take(80) }, kindStr(itemKind, R.string.g8_name_label_product, R.string.g8_name_label_service, R.string.g8_name_label_program, R.string.g8_name_label_event),
                    kindStr(itemKind, R.string.g8_name_hint_product, R.string.g8_name_hint_service, R.string.g8_name_hint_program, R.string.g8_name_hint_event))
                BucksField(description, { description = it.take(1000) }, if (event) stringResource(R.string.g8_where_to_meet) else stringResource(R.string.g8_description_optional),
                    kindStr(itemKind, R.string.g8_desc_hint_product, R.string.g8_desc_hint_service, R.string.g8_desc_hint_program, R.string.g8_desc_hint_event), singleLine = false, minLines = 2)
                if (service) { Label(stringResource(R.string.g8_pricing)); ChipRow(SERVICE_PRICING.map { it.second }, SERVICE_PRICING.firstOrNull { it.first == pricing }?.second, Modifier.padding(bottom = 12.dp)) { picked -> pricing = SERVICE_PRICING.first { it.second == picked }.first } }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BucksField(price, { price = it.filter { c -> c.isDigit() }.take(7) }, when { service && pricing == "QUOTE" -> stringResource(R.string.g8_price_typical, Money.symbol); program || event -> stringResource(R.string.g8_price_free_ok, Money.symbol); else -> stringResource(R.string.g8_price, Money.symbol) },
                        when (itemKind) { "PROGRAM" -> "1500"; "EVENT" -> "0"; else -> "45" }, Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                    if (product) BucksField(mrp, { mrp = it.filter { c -> c.isDigit() }.take(7) }, stringResource(R.string.g8_mrp_optional, Money.symbol), "50", Modifier.weight(1f), keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                if (product && (mrp.toIntOrNull() ?: 0) > (price.toIntOrNull() ?: 0) && price.isNotBlank()) Muted(stringResource(R.string.g8_discount_note, rupees(price.toIntOrNull() ?: 0), rupees(mrp.toIntOrNull() ?: 0)), Modifier.padding(bottom = 10.dp))
                if ((program || event) && (price.toIntOrNull() ?: 0) == 0) Muted(stringResource(R.string.g8_shown_free), Modifier.padding(bottom = 10.dp))
                BucksField(unit, { unit = it.take(30) }, kindStr(itemKind, R.string.g8_unit_label_product, R.string.g8_unit_label_service, R.string.g8_unit_label_program, R.string.g8_unit_label_event),
                    kindStr(itemKind, R.string.g8_unit_hint_product, R.string.g8_unit_hint_service, R.string.g8_unit_hint_program, R.string.g8_unit_hint_event))
                val unitChips = when (itemKind) { "SERVICE" -> UNITS.filter { it.startsWith("per") }; "PROGRAM" -> PROGRAM_UNITS; "EVENT" -> emptyList(); else -> UNITS.filter { !it.startsWith("per") } }
                if (unitChips.isNotEmpty()) ChipRow(unitChips, unit.ifBlank { null }, Modifier.padding(bottom = 14.dp)) { unit = it } else Spacer(Modifier.height(6.dp))
                if (service) BucksField(duration, { duration = it.take(40) }, stringResource(R.string.g8_takes_about), stringResource(R.string.g8_takes_about_hint))
                else if (product) {
                    BucksField(variant, { variant = it.take(30) }, if (template != null || d.str("product_id").isNotBlank()) stringResource(R.string.g8_this_option) else stringResource(R.string.g8_option_optional), stringResource(R.string.g8_option_hint))
                    BucksField(brand, { brand = it.take(40) }, stringResource(R.string.g8_brand_optional), "Aashirvaad, Nandini")
                }
                BucksField(group, { group = it.take(40) }, kindStr(itemKind, R.string.g8_group_label_product, R.string.g8_group_label_service, R.string.g8_group_label_program, R.string.g8_group_label_event),
                    kindStr(itemKind, R.string.g8_group_hint_product, R.string.g8_group_hint_service, R.string.g8_group_hint_program, R.string.g8_group_hint_event))
                if (existingGroups.isNotEmpty()) ChipRow(existingGroups, group.trim().ifBlank { null }, Modifier.padding(bottom = 14.dp)) { group = it }
                SectionTitle(stringResource(R.string.g8_availability), Modifier.padding(top = 4.dp, bottom = 2.dp))
                SwitchRow(kindStr(itemKind, R.string.g8_switch_label_product, R.string.g8_switch_label_service, R.string.g8_switch_label_program, R.string.g8_switch_label_event),
                    kindStr(itemKind, R.string.g8_switch_sub_product, R.string.g8_switch_sub_service, R.string.g8_switch_sub_program, R.string.g8_switch_sub_event), inStock) { inStock = it }
                if (product) {
                    SwitchRow(stringResource(R.string.g8_count_stock), stringResource(R.string.g8_count_stock_sub), countStock) { countStock = it }
                    if (countStock) BucksField(stock, { stock = it.filter { c -> c.isDigit() }.take(6) }, stringResource(R.string.g8_how_many), "25", keyboard = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
            }
        }
        Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
            PrimaryButton(if (m.busy) stringResource(R.string.g8_saving) else if (existing == null) addItemTitle(noun) else stringResource(R.string.g8_save_changes), enabled = !m.busy) { save() }
            // Sizes, colours, weights: each option is its own row (price, stock) shown together on one product card.
            if (product && existing != null) SmallButton(stringResource(R.string.g8_add_option), Modifier.padding(bottom = 6.dp), tonal = true) {
                if (variant.isBlank()) vm.toast(Str.get(R.string.g8_name_option_first)) else save { NewItemKind.next = "PRODUCT"; NewItemKind.optionOf = existing; onBack(); onAddOption() }
            }
            if (existing != null) BadButton(kindStr(itemKind, R.string.g8_remove_item_product, R.string.g8_remove_item_service, R.string.g8_remove_item_program, R.string.g8_remove_item_event), Modifier.padding(top = 4.dp)) { confirmDelete = true }
        }
    }
    if (confirmDelete && existing != null) ConfirmDialog(stringResource(R.string.g8_remove_name_q, existing.name), stringResource(R.string.g8_remove_item_body), stringResource(R.string.g8_remove),
        onConfirm = { m.deleteItem(existing) { onBack() } }, onDismiss = { confirmDelete = false })
}

/** One photo in the item form: "Main" on the first, tap another to make it main, x to take it out. */
@Composable
private fun PhotoThumb(model: Any, main: Boolean, onMain: (() -> Unit)?, onRemove: () -> Unit) = Box(Modifier.size(84.dp).clip(MaterialTheme.shapes.medium).clickable(enabled = onMain != null && !main) { onMain?.invoke() }) {
    AsyncImage(model, null, Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer), contentScale = ContentScale.Crop)
    if (main) Box(Modifier.align(Alignment.BottomStart).padding(4.dp)) { Pill(stringResource(R.string.g8_main), MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary) }
    IconButton(onClick = onRemove, modifier = Modifier.align(Alignment.TopEnd).size(28.dp).padding(2.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f))) { Icon(Icons.Rounded.Close, stringResource(R.string.g8_cd_remove_photo), Modifier.size(16.dp), tint = Color.White) }
}
