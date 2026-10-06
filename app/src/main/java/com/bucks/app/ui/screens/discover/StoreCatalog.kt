package com.bucks.app.ui.screens.discover

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.ListingProfile
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.str
import kotlinx.coroutines.launch
import com.bucks.app.ui.theme.status

/*
 * The Products tab of a shop: what a shopper needs to find and buy something in a catalogue of hundreds.
 *  - Categories down the left (thumbnail and name), "All" first; searching looks across every category.
 *  - One search box, Sort and Filter (in stock, on sale, price band) with the result count read out as it changes.
 *  - Products, not variants: a product with options (Small / Regular / Set) is one card ("From ₹1,500", "3 options") that opens a sheet
 *    to pick the option; a plain product adds straight from the card and turns into a - / + stepper.
 *  - 24 at a time with "Show more", so a 300-item shop opens fast.
 * Accessibility: every control is at least 48dp, the category rail is a set of selectable tabs, cards read as one sentence, and text
 * follows the phone's font size. The cart itself is in the top bar next to Messages (components/Components.kt) and "View cart" below.
 */

private const val PAGE = 24

private enum class Sort(val label: String) { FEATURED("Featured"), REC("Most recommended"), LOW("Price: low to high"), HIGH("Price: high to low"), NAME("Name: A to Z") }
private val BANDS = listOf("Any price" to (0..Int.MAX_VALUE), "Under ₹1,000" to (0..999), "₹1,000 to ₹3,000" to (1000..3000), "₹3,000 to ₹10,000" to (3001..10_000), "Above ₹10,000" to (10_001..Int.MAX_VALUE))

private fun rs(n: Int) = "₹" + "%,d".format(n)

/** Shopify-sized photos: a small file for a card, a big one for the sheet. Other hosts are used as they are. */
private fun sized(url: String?, width: Int): String? {
    val u = Backend.listingPhoto(url) ?: return null
    return if (u.contains("cdn.shopify.com")) u + (if ('?' in u) "&" else "?") + "width=$width" else u
}
private fun photosOf(i: ItemRow): List<String> = i.photos.map { it.url }.ifEmpty { listOfNotNull(i.photoUrl?.takeIf { it.isNotBlank() }) }

/** One product as the shopper sees it: its options (variants) together, in the store's order. */
private class Product(val key: String, val title: String, val group: String, val options: List<ItemRow>) {
    val photos: List<String> = options.flatMap { photosOf(it) }.distinct().take(8)
    val from = options.minOf { it.price }; val to = options.maxOf { it.price }
    val anyInStock = options.any { it.inStock }
    val multi get() = options.size > 1
    /** The biggest discount among the options, in percent; null when nothing is marked down. */
    val off: Int? = options.mapNotNull { o -> o.mrp?.takeIf { it > o.price }?.let { ((it - o.price) * 100.0 / it).toInt() } }.maxOrNull()?.takeIf { it >= 1 }
    /** The description without the title the shop repeats at its start. */
    val about: String = options.first().description.trim().removePrefix(title).trim().replace(Regex("\n{3,}"), "\n\n")
    private val text = (title + " " + group + " " + options.joinToString(" ") { optionLabel(it) + " " + (it.details.str("sku") ?: "") } + " " + about).lowercase()
    fun matches(q: String) = q.lowercase().split(' ').filter { it.isNotBlank() }.all { it in text }
}
private fun optionLabel(i: ItemRow) = i.details.str("variant") ?: i.unit.ifBlank { i.name }

private fun productsOf(items: List<ItemRow>): List<Product> =
    items.groupBy { it.details.str("product_id") ?: it.id ?: it.name }.map { (k, os) -> Product(k, os.first().details.str("product") ?: os.first().name, os.first().group.ifBlank { "Products" }, os) }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun StoreProducts(vm: BucksViewModel, p: ListingProfile, onMessage: () -> Unit, onCart: () -> Unit) {
    val listing = p.listing
    if (p.products.isEmpty()) {
        Column(Modifier.padding(Gutter)) {
            Muted(if (p.mine) "No products yet. Add them from Menu > Bucks Pro." else "${listing.title} hasn't listed products yet. Message them to ask what's in stock.")
            if (!p.mine) SmallButton("Message", Modifier.padding(top = 12.dp), tonal = true, onClick = onMessage)
        }
        return
    }
    val canAdd = !p.mine && listing.online
    val scopeRatings = rememberCoroutineScope()
    val all = remember(p.products) { productsOf(p.products) }
    val cats = remember(all) { all.groupBy { it.group }.map { (g, l) -> Triple(g, l.size, l.firstNotNullOfOrNull { it.photos.firstOrNull() }) } }
    var query by rememberSaveable { mutableStateOf("") }
    var cat by rememberSaveable { mutableStateOf<String?>(null) }
    var sort by rememberSaveable { mutableStateOf(Sort.FEATURED.ordinal) }
    var inStockOnly by rememberSaveable { mutableStateOf(false) }; var onSaleOnly by rememberSaveable { mutableStateOf(false) }; var band by rememberSaveable { mutableStateOf(0) }
    var shown by rememberSaveable(cat, query, sort, inStockOnly, onSaleOnly, band) { mutableStateOf(PAGE) }
    var sortMenu by remember { mutableStateOf(false) }; var filterSheet by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf<Product?>(null) }
    // Recommend / not-recommend counts for every product in one call; the cards show the share that recommend.
    var ratings by remember(listing.id) { mutableStateOf<Map<String, RatingSummary>>(emptyMap()) }
    fun loadRatings() { scopeRatings.launch { ratings = runCatching { Backend.productRatings(listing.id) }.getOrDefault(emptyList()).associateBy { it.key } } }
    LaunchedEffect(listing.id) { loadRatings() }
    val filtersOn = (if (inStockOnly) 1 else 0) + (if (onSaleOnly) 1 else 0) + (if (band != 0) 1 else 0)

    val result = remember(all, cat, query, sort, inStockOnly, onSaleOnly, band, ratings) {
        val range = BANDS[band].second
        all.filter { pr -> (query.isNotBlank() || cat == null || pr.group == cat) && (query.isBlank() || pr.matches(query)) &&
            (!inStockOnly || pr.anyInStock) && (!onSaleOnly || pr.off != null) && (band == 0 || pr.options.any { it.price in range }) }
            .let { l -> when (Sort.entries[sort]) { Sort.FEATURED -> l; Sort.REC -> l.sortedWith(compareByDescending<Product> { ratings[it.key]?.percent ?: -1 }.thenByDescending { ratings[it.key]?.votes ?: 0 }); Sort.LOW -> l.sortedBy { it.from }; Sort.HIGH -> l.sortedByDescending { it.from }; Sort.NAME -> l.sortedBy { it.title.lowercase() } } }
    }
    val inCart = vm.commerce.count

    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        if (!listing.online && !p.mine) Notice("${listing.title} is closed now. You can order once they open again.", Modifier.padding(horizontal = Gutter, vertical = 4.dp))
        // Search
        Row(Modifier.padding(horizontal = Gutter).fillMaxWidth().heightIn(min = 48.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(start = 14.dp, end = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(10.dp))
            BasicTextField(query, { query = it.take(60) }, Modifier.weight(1f).semantics { contentDescription = "Search ${listing.title}" }, singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { }),
                decorationBox = { inner -> Box { if (query.isEmpty()) Text("Search ${listing.title}", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis); inner() } })
            if (query.isNotEmpty()) IconButton({ query = "" }) { Icon(Icons.Rounded.Close, "Clear search", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        // Sort, Filter and the count
        Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box {
                ToolPill(Icons.Rounded.SwapVert, "Sort: ${Sort.entries[sort].label}", "Sort") { sortMenu = true }
                DropdownMenu(sortMenu, { sortMenu = false }) {
                    Sort.entries.forEach { s -> DropdownMenuItem({ Text(s.label, fontWeight = if (sort == s.ordinal) FontWeight.SemiBold else FontWeight.Normal) }, { sort = s.ordinal; sortMenu = false },
                        leadingIcon = { if (sort == s.ordinal) Icon(Icons.Rounded.Check, "Selected") }) }
                }
            }
            ToolPill(Icons.Rounded.Tune, if (filtersOn > 0) "Filter, $filtersOn on" else "Filter", if (filtersOn > 0) "Filter ($filtersOn)" else "Filter") { filterSheet = true }
            Spacer(Modifier.weight(1f))
            Text(if (result.size == 1) "1 product" else "${result.size} products", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.semantics { contentDescription = "${result.size} products shown" })
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            // Categories: selectable tabs down the left
            if (cats.size > 1) Column(Modifier.width(80.dp).padding(bottom = 8.dp)) {
                CategoryTab("All", all.size, cats.firstNotNullOfOrNull { it.third }, selected = query.isBlank() && cat == null) { cat = null; query = "" }
                cats.forEach { (g, n, photo) -> CategoryTab(g, n, photo, selected = query.isBlank() && cat == g) { cat = g; query = "" } }
            }
            Column(Modifier.weight(1f).padding(end = Gutter, start = if (cats.size > 1) 6.dp else Gutter)) {
                Text(when { query.isNotBlank() -> "Results for “${query.trim()}”"; cat != null -> cat!!; else -> "All products" }, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
                if (result.isEmpty()) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Rounded.SearchOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("Nothing matches", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 10.dp))
                        Muted(if (filtersOn > 0) "Try removing a filter." else "Try another word, or pick a category.", Modifier.padding(top = 4.dp), TextAlign.Center)
                        if (filtersOn > 0 || query.isNotBlank()) SmallButton("Clear filters and search", Modifier.padding(top = 12.dp), tonal = true) { query = ""; inStockOnly = false; onSaleOnly = false; band = 0 }
                    }
                } else {
                    result.take(shown).chunked(2).forEach { row ->
                        Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { pr -> ProductCard(vm, p, pr, ratings[pr.key], canAdd, Modifier.weight(1f)) { open = pr } }
                            if (row.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                    if (result.size > shown) OutlinedButton({ shown += PAGE }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Show more · ${result.size - shown} left") }
                }
            }
        }
    }
    Spacer(Modifier.height(if (inCart > 0) 88.dp else 8.dp))

    open?.let { pr -> ProductSheet(vm, listing, pr, ratings[pr.key], canAdd, p.mine, onRated = { loadRatings() }, onDismiss = { open = null }, onCart = { open = null; onCart() }) }
    if (filterSheet) ModalBottomSheet({ filterSheet = false }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Text("Filter", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            SwitchRow("In stock only", inStockOnly) { inStockOnly = it }
            SwitchRow("On sale", onSaleOnly) { onSaleOnly = it }
            Label("Price")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { BANDS.forEachIndexed { i, (label, _) -> Chip(label, selected = band == i) { band = i } } }
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton({ inStockOnly = false; onSaleOnly = false; band = 0 }, Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Reset") }
                Button({ filterSheet = false }, Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Show ${result.size} products") }
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, on: Boolean, onChange: (Boolean) -> Unit) =
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(on, role = Role.Switch, onClick = { onChange(!on) }), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f)); Switch(on, null)
    }

@Composable
private fun ToolPill(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String, label: String, onClick: () -> Unit) =
    Row(Modifier.heightIn(min = 48.dp).clip(MaterialTheme.shapes.medium).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium).clickable(onClickLabel = description, onClick = onClick).padding(horizontal = 12.dp).semantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(6.dp)); Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1)
    }

/** One category down the left: a round thumbnail, its name and how many products; the selected one has a bar on its right edge. */
@Composable
private fun CategoryTab(name: String, count: Int, photo: String?, selected: Boolean, onClick: () -> Unit) {
    val c = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Row(Modifier.fillMaxWidth().heightIn(min = 88.dp).selectable(selected, role = Role.Tab, onClick = onClick).semantics { contentDescription = "$name, $count products" }) {
        Column(Modifier.weight(1f).padding(vertical = 8.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(52.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).border(if (selected) 2.dp else 0.dp, if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, CircleShape), contentAlignment = Alignment.Center) {
                sized(photo, 150)?.let { ShimmerImage(it, null, Modifier.fillMaxSize()) } ?: Icon(Icons.Rounded.Storefront, null, tint = c)
            }
            Text(name, style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp), color = c, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
        }
        Box(Modifier.width(3.dp).fillMaxHeight().background(if (selected) MaterialTheme.colorScheme.primary else Color.Transparent))
    }
}

/** A product card: photo, name, price (with the marked-down price struck through), then Add / a stepper / Choose / Sold out. */
@Composable
private fun ProductCard(vm: BucksViewModel, p: ListingProfile, pr: Product, rating: RatingSummary?, canAdd: Boolean, modifier: Modifier, onOpen: () -> Unit) {
    val one = pr.options.first(); val qty = pr.options.sumOf { vm.commerce.qty(it.id ?: "") }
    val dim = if (pr.anyInStock) 1f else 0.5f
    val price = if (pr.multi && pr.from != pr.to) "From ${rs(pr.from)}" else rs(pr.from)
    val say = listOfNotNull(pr.title, price, if (pr.multi) "${pr.options.size} options" else null, pr.off?.let { "$it percent off" }, if (!pr.anyInStock) "sold out" else null, rating?.percent?.let { "$it percent recommend, ${rating.votes} ${if (rating.votes == 1) "vote" else "votes"}" }, if (qty > 0) "$qty in your cart" else null).joinToString(", ")
    Column(modifier.clip(RoundedCornerShape(12.dp)).border(BorderStroke(1.dp, MaterialTheme.colorScheme.outline), RoundedCornerShape(12.dp)).clickable(onClickLabel = "Open ${pr.title}", onClick = onOpen).semantics(mergeDescendants = true) { contentDescription = say }) {
        Box {
            val url = sized(pr.photos.firstOrNull(), 400)
            if (url != null) ShimmerImage(url, null, Modifier.fillMaxWidth().aspectRatio(1f).alpha(dim))
            else Box(Modifier.fillMaxWidth().aspectRatio(1f).background(MaterialTheme.colorScheme.surfaceContainer), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Image, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            pr.off?.let { Surface(Modifier.padding(6.dp).align(Alignment.TopStart), shape = RoundedCornerShape(6.dp), color = MaterialTheme.status.good) { Text("$it% off", Modifier.padding(horizontal = 6.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = Color.White) } }
            if (qty > 0) Surface(Modifier.padding(6.dp).align(Alignment.TopEnd), shape = CircleShape, color = MaterialTheme.colorScheme.primary) { Text("$qty", Modifier.padding(horizontal = 8.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimary) }
        }
        Column(Modifier.padding(horizontal = 8.dp, vertical = 8.dp)) {
            Text(pr.title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.alpha(dim))
            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(price, style = MaterialTheme.typography.titleSmall, modifier = Modifier.alpha(dim))
                if (!pr.multi) one.mrp?.takeIf { it > one.price }?.let { Text(rs(it), style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            rating?.percent?.let { pct ->
                Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    val tone = if (pct >= 50) MaterialTheme.status.good else MaterialTheme.status.bad
                    Icon(if (pct >= 50) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, null, Modifier.size(14.dp), tint = tone)
                    Text(" $pct%", style = MaterialTheme.typography.labelMedium, color = tone); Muted(" (${rating.votes})", maxLines = 1)
                }
            }
            if (pr.multi) Muted("${pr.options.size} options", Modifier.padding(top = 2.dp), maxLines = 1)
            Box(Modifier.padding(top = 8.dp).fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
                when {
                    !pr.anyInStock -> PillGrey("Sold out")
                    !canAdd -> {}
                    pr.multi -> OutlinedButton(onOpen, Modifier.fillMaxWidth().heightIn(min = 48.dp), contentPadding = PaddingValues(horizontal = 8.dp)) { Text(if (qty > 0) "In cart · Change" else "Choose", style = MaterialTheme.typography.labelLarge, maxLines = 1) }
                    else -> AddStepper(qty) { d -> vm.commerce.add(p.listing, one, d) }
                }
            }
        }
    }
}

/** The product page in a sheet: photos, price, the option chips, description, add to cart, then what people say with recommend / not recommend. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun ProductSheet(vm: BucksViewModel, listing: ListingRow, pr: Product, rating: RatingSummary?, canAdd: Boolean, isOwner: Boolean, onRated: () -> Unit, onDismiss: () -> Unit, onCart: () -> Unit) {
    var pick by remember(pr.key) { mutableStateOf(pr.options.firstOrNull { it.inStock }?.id ?: pr.options.first().id) }
    val item = pr.options.firstOrNull { it.id == pick } ?: pr.options.first()
    // The catalogue carries one photo and no description; the full row (all photos, description) is fetched for the option being looked at.
    var full by remember(pick) { mutableStateOf<ItemRow?>(null) }; var fullFailed by remember(pick) { mutableStateOf(false) }
    LaunchedEffect(pick) { full = pick?.let { runCatching { Backend.itemById(it) }.getOrNull() }; fullFailed = full == null }
    val loaded = full
    val photos = ((loaded?.let { photosOf(it) } ?: photosOf(item)) + pr.photos).distinct().take(8)
    val about = (loaded?.description ?: "").trim().removePrefix(pr.title).trim().replace(Regex("\n{3,}"), "\n\n")
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            if (photos.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()).padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                photos.forEachIndexed { i, u -> ShimmerImage(sized(u, 900), "${pr.title}, photo ${i + 1} of ${photos.size}", Modifier.size(if (photos.size == 1) 300.dp else 240.dp).clip(MaterialTheme.shapes.medium)) }
                if (loaded == null && !fullFailed) repeat(2) { SkeletonBox(Modifier.size(240.dp), MaterialTheme.shapes.medium) }
            }
            Text(pr.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            Muted(listOfNotNull(pr.group.takeIf { it != "Products" }, item.details.str("vendor")).joinToString(" · "))
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(rs(item.price), style = MaterialTheme.typography.headlineSmall)
                item.mrp?.takeIf { it > item.price }?.let { Text(rs(it), style = MaterialTheme.typography.bodyMedium.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant); Text("${((it - item.price) * 100.0 / it).toInt()}% off", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.status.good) }
            }
            rating?.takeIf { it.votes > 0 }?.let { r -> Muted("▲ ${r.up} upvotes · ▼ ${r.down} downvotes", Modifier.padding(top = 2.dp)) }
            if (pr.multi) {
                Label("Choose an option")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    pr.options.forEach { o -> Chip(optionLabel(o) + " · " + rs(o.price) + if (!o.inStock) " · sold out" else "", selected = o.id == pick) { pick = o.id } }
                }
            }
            when { !item.inStock -> Box(Modifier.padding(top = 8.dp)) { PillGrey("Sold out") }; item.stock != null && item.stock!! <= 5 -> Text("Only ${item.stock} left", color = MaterialTheme.status.warn, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp)) }
            when {
                about.isNotBlank() -> Text(about, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
                loaded == null && !fullFailed -> SkeletonLines(4, Modifier.padding(top = 14.dp))
            }
            if (canAdd && item.inStock) Row(Modifier.fillMaxWidth().padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                val qty = vm.commerce.qty(item.id ?: "")
                Text(if (qty > 0) "In your cart" else "Add to cart", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                AddStepper(qty) { d -> vm.commerce.add(listing, item, d) }
            }
            if (vm.commerce.count > 0) DarkButton("View cart · ${vm.commerce.count} item${if (vm.commerce.count == 1) "" else "s"}", Modifier.padding(top = 14.dp), onClick = onCart)
            ProductFeedback(vm, listing, pr, rating, isOwner, onRated)
        }
    }
}

/** Recommend or not recommend a product, with an optional comment, and what others wrote. One rating per person, changeable and removable. */
@Composable
private fun ProductFeedback(vm: BucksViewModel, listing: ListingRow, pr: Product, rating: RatingSummary?, isOwner: Boolean, onRated: () -> Unit) {
    val scope = rememberCoroutineScope()
    var draft by remember(pr.key) { mutableStateOf(0) }; var text by remember(pr.key) { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    var comments by remember(pr.key) { mutableStateOf<List<ProductComment>?>(null) }; var more by remember(pr.key) { mutableStateOf(false) }
    fun load(before: String? = null) { scope.launch {
        val page = runCatching { Backend.productComments(listing.id, pr.key, before) }.getOrDefault(emptyList())
        comments = if (before == null) page else comments.orEmpty() + page; more = page.size >= 20 } }
    LaunchedEffect(pr.key) { load() }
    fun friendly(e: Throwable) = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message ?: "")?.groupValues?.get(1) ?: "Couldn't send that. Check your connection and try again."
    val mine = rating?.mine
    HorizontalDivider(Modifier.padding(top = 20.dp), color = MaterialTheme.colorScheme.outlineVariant)
    Text("What people say", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp).semantics { heading() })
    Muted(rating?.takeIf { it.votes > 0 }?.let { "▲ ${it.up} upvotes · ▼ ${it.down} downvotes" } ?: "No votes yet. Be the first.", Modifier.padding(top = 2.dp))
    rating?.percent?.let { pct -> Box(Modifier.padding(top = 8.dp).fillMaxWidth().height(6.dp).clip(CircleShape).background(MaterialTheme.status.bad.copy(alpha = 0.35f))) { Box(Modifier.fillMaxWidth(pct / 100f).fillMaxHeight().background(MaterialTheme.status.good)) } }
    if (isOwner) Muted("This is your product. Customers' feedback and comments show here, and you get a notification for each comment.", Modifier.padding(top = 10.dp))
    else {
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(1 to ("Recommend" to Icons.Rounded.ArrowUpward), -1 to ("Not recommend" to Icons.Rounded.ArrowDownward)).forEach { (v, lab) ->
                val on = (draft == v) || (draft == 0 && mine == v)
                val tone = if (v == 1) MaterialTheme.status.good else MaterialTheme.status.bad
                OutlinedButton({ draft = if (draft == v) 0 else v }, Modifier.weight(1f).heightIn(min = 48.dp).semantics { selected = on }, colors = ButtonDefaults.outlinedButtonColors(containerColor = if (on) tone.copy(alpha = 0.15f) else Color.Transparent, contentColor = if (on) tone else MaterialTheme.colorScheme.onSurface),
                    border = BorderStroke(if (on) 2.dp else 1.dp, if (on) tone else MaterialTheme.colorScheme.outline), contentPadding = PaddingValues(horizontal = 8.dp)) {
                    Icon(lab.second, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text(lab.first, style = MaterialTheme.typography.labelLarge, maxLines = 1)
                }
            }
        }
        if (draft != 0 || mine != null) {
            OutlinedTextField(text, { text = it.take(500) }, Modifier.padding(top = 10.dp).fillMaxWidth(), placeholder = { Text("Add a comment (optional)") }, minLines = 2, maxLines = 5, supportingText = { Text("${text.length}/500") })
            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({
                    val vote = if (draft != 0) draft else (mine ?: 1)
                    scope.launch { busy = true
                        runCatching { Backend.rateProduct(listing.id, pr.key, vote, text.trim()) }.onSuccess { vm.toast("Thanks, your feedback is posted."); draft = 0; text = ""; onRated(); load() }.onFailure { vm.toast(friendly(it)) }
                        busy = false }
                }, Modifier.heightIn(min = 48.dp), enabled = !busy && (draft != 0 || text.isNotBlank())) { Text(if (busy) "Sending…" else if (mine != null) "Update my feedback" else "Post feedback") }
                if (mine != null) TextButton({ scope.launch { busy = true; runCatching { Backend.clearProductRating(listing.id, pr.key) }.onSuccess { vm.toast("Your rating was removed."); draft = 0; text = ""; onRated(); load() }; busy = false } }, Modifier.heightIn(min = 48.dp)) { Text("Remove mine") }
            }
        }
    }
    val list = comments
    when {
        list == null -> Column(Modifier.padding(top = 14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) { repeat(2) { Row { SkeletonBox(Modifier.size(36.dp), CircleShape); SkeletonLines(2, Modifier.padding(start = 10.dp).weight(1f)) } } }
        list.isEmpty() -> Muted("No comments yet.", Modifier.padding(top = 12.dp))
        else -> {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                list.forEach { c ->
                    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "${c.name.ifBlank { "Someone" }}, ${if (c.vote == 1) "recommends" else "does not recommend"}, ${ago(c.updatedAt)}. ${c.comment}" }) {
                        Avatar(c.name.split(' ').mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString("").ifBlank { "?" }, size = 36)
                        Column(Modifier.padding(start = 10.dp).weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(c.name.ifBlank { "Someone" }, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                Icon(if (c.vote == 1) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, null, Modifier.padding(start = 6.dp).size(14.dp), tint = if (c.vote == 1) MaterialTheme.status.good else MaterialTheme.status.bad)
                                Muted(" · " + ago(c.updatedAt), maxLines = 1)
                            }
                            Text(c.comment, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 2.dp))
                        }
                    }
                }
            }
            if (more) OutlinedButton({ load(list.last().updatedAt) }, Modifier.padding(top = 12.dp).fillMaxWidth().heightIn(min = 48.dp)) { Text("Show more comments") }
        }
    }
}
