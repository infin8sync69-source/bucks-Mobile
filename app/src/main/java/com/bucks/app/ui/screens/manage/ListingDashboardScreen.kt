package com.bucks.app.ui.screens.manage

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.ItemRow
import com.bucks.app.data.ListingRow
import com.bucks.app.data.MediaPhoto
import com.bucks.app.data.Picked
import com.bucks.app.data.PostRow
import com.bucks.app.data.Upload
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.MyListings
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ListingSwitch
import com.bucks.app.ui.screens.SignedImage
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.shareText
import com.bucks.app.ui.theme.status
import kotlinx.serialization.json.JsonObject

/** Tabs of a listing's dashboard. */
private enum class DashTab { OVERVIEW, ITEMS, PHOTOS, FEED, REVIEWS }

private fun tabsFor(kind: String, manage: Boolean): List<Pair<DashTab, String>> = when {
    !manage -> listOf(DashTab.OVERVIEW to "Overview", DashTab.REVIEWS to "Reviews")
    kind == "BUSINESS" -> listOf(DashTab.OVERVIEW to "Overview", DashTab.ITEMS to "Products", DashTab.PHOTOS to "Photos", DashTab.FEED to "Feed", DashTab.REVIEWS to "Reviews")
    kind == "SKILL" -> listOf(DashTab.OVERVIEW to "Overview", DashTab.ITEMS to "Services", DashTab.PHOTOS to "Portfolio", DashTab.FEED to "Feed", DashTab.REVIEWS to "Reviews")
    kind == "ASSET" -> listOf(DashTab.OVERVIEW to "Overview", DashTab.PHOTOS to "Photos", DashTab.REVIEWS to "Reviews")
    else -> listOf(DashTab.OVERVIEW to "Overview", DashTab.PHOTOS to "Photos", DashTab.REVIEWS to "Reviews")
}

/**
 * One listing's control room: how to go live (a checklist of what's missing), the open / available switch, and tabs for
 * everything the owner manages: products or services, photos or portfolio, the listing's feed, and reviews.
 */
@Composable
fun ListingDashboardScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onEdit: (kind: String, id: String) -> Unit, onItem: (listingId: String, itemId: String?) -> Unit,
                           onDocs: (String) -> Unit, onMembers: (String) -> Unit, onRecommend: (String) -> Unit, onOrders: (String) -> Unit, onJobs: (String) -> Unit,
                           onOpenProfile: (String) -> Unit, onPaymentQr: () -> Unit, onVehicles: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(id) { if (!m.loaded) m.refresh(); m.loadCounts(id) }
    val l = m.listing(id)
    if (l == null) {
        ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Listing", onBack = onBack)
            val err = m.error
            when { m.loaded -> Column(Modifier.padding(Gutter)) { Text("Listing not found", style = MaterialTheme.typography.titleMedium); Muted("It may have been deleted, or you're no longer part of it.", Modifier.padding(top = 4.dp)) }
                   err != null -> LoadError(err, Modifier.padding(Gutter)) { m.refresh() }
                   else -> CenteredLoading() } }
        return
    }
    val manage = m.canManage(id); val owner = m.isOwner(id); val ctx = LocalContext.current
    LaunchedEffect(id, l.kind) { if (l.kind == "BUSINESS" || l.kind == "SKILL") m.loadItems(id); if (l.kind != "DRIVER" && manage) vm.services.loadCompliance(id) }
    val tabs = tabsFor(l.kind, manage)
    var tab by rememberSaveable(id) { mutableStateOf(DashTab.OVERVIEW) }
    var menu by remember { mutableStateOf(false) }; var confirmDelete by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        BucksTopBar(l.title, onBack = onBack, actions = {
            IconButton(onClick = { onOpenProfile(id) }) { Icon(Icons.Rounded.Visibility, "See it as customers do") }
            IconButton(onClick = { shareText(ctx, "${l.title} on Bucks" + listOfNotNull(l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(", ").let { if (it.isBlank()) "" else " · $it" }) }) { Icon(Icons.Rounded.IosShare, "Share") }
            if (manage) Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, "More") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Edit details") }, { menu = false; onEdit(l.kind, id) }, leadingIcon = { Icon(Icons.Rounded.Edit, null) })
                    if (l.kind != "DRIVER") DropdownMenuItem({ Text("Documents") }, { menu = false; onDocs(id) }, leadingIcon = { Icon(Icons.Rounded.Description, null) })
                    if (l.kind != "DRIVER") DropdownMenuItem({ Text("Team") }, { menu = false; onMembers(id) }, leadingIcon = { Icon(Icons.Rounded.Groups, null) })
                    if (owner) DropdownMenuItem({ Text("Delete", color = MaterialTheme.colorScheme.error) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.error) })
                }
            }
        })
        StatusStrip(m, l, manage)
        if (tabs.size > 1) ScrollableTabRow(selectedTabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0), edgePadding = Gutter, containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) {
            tabs.forEach { (t, label) -> Tab(selected = tab == t, onClick = { tab = t }, text = { Text(label, style = MaterialTheme.typography.labelLarge) }) }
        }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.widthIn(max = 900.dp).fillMaxSize()) {
                when (tab) {
                    DashTab.OVERVIEW -> OverviewTab(vm, l, manage, owner, goTo = { target ->
                        when (target) { "EDIT" -> onEdit(l.kind, id); "PHOTOS" -> tab = DashTab.PHOTOS; "ITEMS" -> tab = DashTab.ITEMS; "VEHICLES" -> onVehicles(); "DOCS" -> onDocs(id); "RECOMMEND" -> onRecommend(id)
                            "MEMBERS" -> onMembers(id); "ORDERS" -> onOrders(id); "JOBS" -> onJobs(id); "PAYMENT" -> onPaymentQr(); "PROFILE" -> onOpenProfile(id) } })
                    DashTab.ITEMS -> ItemsTab(m, l, onItem)
                    DashTab.PHOTOS -> PhotosTab(vm, l)
                    DashTab.FEED -> FeedManageTab(vm, l)
                    DashTab.REVIEWS -> ReviewsManageTab(vm, l)
                }
            }
        }
    }
    if (confirmDelete) ConfirmDialog("Delete ${l.title}?", "Its products, photos, members, recommendations and reviews go with it. Orders customers already placed stay in their history. This can't be undone.", "Delete",
        onConfirm = { m.deleteListing(id) { onBack() } }, onDismiss = { confirmDelete = false })
}

/** Under the top bar on every tab: where the listing stands, and the switch when it's live. */
@Composable
private fun StatusStrip(m: MyListings, l: ListingRow, manage: Boolean) {
    val recs = m.recommendations[l.id] ?: 0
    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            when (l.status) {
                "LIVE" -> { Text(onlineLabel(l.kind, l.online), style = MaterialTheme.typography.titleSmall); Muted(if (l.online) "Customers nearby can find and reach you now." else "Live, but hidden from search until you switch it on.") }
                "SUSPENDED" -> { Text(if (l.complianceHold) "Paused for documents" else "Suspended", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.error); Muted(if (l.complianceHold) "A document expired or is missing. Upload it and it comes back on its own." else "Hidden from customers. Contact Bucks support.") }
                else -> { Text("Not live yet", style = MaterialTheme.typography.titleSmall); Muted("$recs of $NEEDED recommendations. See the checklist in Overview.") }
            }
        }
        if (l.status == "LIVE" && manage) ListingSwitch(l.online) { m.setOnline(l.id, it) } else ListingStatusPill(l, recs)
    }
}

/* ---------- Overview ---------- */

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OverviewTab(vm: BucksViewModel, l: ListingRow, manage: Boolean, owner: Boolean, goTo: (String) -> Unit) {
    val m = vm.myListings; val recs = m.recommendations[l.id] ?: 0; val c = m.counts[l.id]
    val hasVehicle = m.vehicles.any { it.status != "SUSPENDED" }
    val steps = goLiveSteps(l, if (l.kind == "BUSINESS" || l.kind == "SKILL") m.items[l.id] else emptyList(), if (l.kind == "DRIVER") emptyList() else vm.services.compliance[l.id], recs, hasVehicle)
    val noUpi = vm.dispatch.enabled && vm.dispatch.paymentLinkLoaded && vm.dispatch.paymentLink == null
    LaunchedEffect(Unit) { if (vm.dispatch.enabled && !vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
    LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            BucksCard(padding = 0) {
                ListingCover(l, Modifier.fillMaxWidth().height(170.dp))
                Column(Modifier.padding(16.dp)) {
                    Text(l.title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
                    Muted(listOfNotNull(kindLabel(l.kind), l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(" · "))
                    if (l.kind == "ASSET") Text(assetPriceLine(l.details), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
        if (manage && l.status != "LIVE") item {
            val done = steps.count { it.done }
            BucksCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Go live", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Muted("$done of ${steps.size} done")
                }
                LinearProgressIndicator(progress = { done.toFloat() / steps.size }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp).height(6.dp).clip(CircleShape))
                Muted("Two things take it live: $NEEDED people nearby recommending it in person and Bucks checking any documents it needs. The rest makes people pick you.", Modifier.padding(bottom = 4.dp))
                steps.forEach { s -> GoLiveRow(s) { goTo(s.target) } }
            }
        }
        if (manage && l.kind == "BUSINESS" && noUpi && owner) item {
            Notice("Add your UPI QR so customers can pay your orders by UPI. Until then they have to pay you directly.")
            SmallButton("Add payment QR", Modifier.padding(top = 8.dp)) { goTo("PAYMENT") }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(Modifier.weight(1f), "$recs", "Recommended")
                StatTile(Modifier.weight(1f), "${c?.syncs ?: "–"}", "Synced")
                StatTile(Modifier.weight(1f), trustPct(l.trustUp, l.trustDown), "Positive")
                if (l.kind != "DRIVER") StatTile(Modifier.weight(1f), "${c?.members ?: "–"}", "Team")
            }
        }
        item { AboutCard(l, manage) { goTo("EDIT") } }
        if (manage) item {
            SectionTitle("Manage", Modifier.padding(bottom = 4.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ManageTile(Icons.Rounded.Edit, "Edit details") { goTo("EDIT") }
                if (l.kind != "DRIVER") ManageTile(Icons.Rounded.Description, "Documents") { goTo("DOCS") }
                if (l.kind != "DRIVER") ManageTile(Icons.Rounded.Groups, "Team") { goTo("MEMBERS") }
                if (l.kind == "BUSINESS") { ManageTile(Icons.Rounded.Assignment, "Orders") { goTo("ORDERS") }; ManageTile(Icons.Rounded.Work, "Jobs") { goTo("JOBS") } }
                if (l.kind == "BUSINESS" && owner) ManageTile(Icons.Rounded.QrCode2, "Payment QR") { goTo("PAYMENT") }
                if (l.kind == "DRIVER") ManageTile(Icons.Rounded.TwoWheeler, "Vehicles") { goTo("VEHICLES") }
                ManageTile(Icons.Rounded.ThumbUp, if (l.status == "PENDING") "Get recommended" else "Recommend code") { goTo("RECOMMEND") }
                ManageTile(Icons.Rounded.Visibility, "Customer view") { goTo("PROFILE") }
            }
        } else item { Notice("You're a store rider here: you deliver its orders. Only the owner and admins change the listing.") }
    }
}

private fun trustPct(up: Int, down: Int) = if (up + down == 0) "–" else "${(up * 100) / (up + down)}%"

@Composable
private fun StatTile(modifier: Modifier, value: String, label: String) = Column(modifier.clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold)); Muted(label, maxLines = 1)
}

@Composable
private fun ManageTile(icon: ImageVector, label: String, onClick: () -> Unit) = Column(Modifier.width(104.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(vertical = 14.dp, horizontal = 6.dp),
    horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Text(label, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.padding(top = 6.dp))
}

/** The listing's public facts, read-only, with Edit. */
@Composable
private fun AboutCard(l: ListingRow, manage: Boolean, onEdit: () -> Unit) = BucksCard {
    val d = l.details
    Row(verticalAlignment = Alignment.CenterVertically) { Text("About", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); if (manage) TextButton(onClick = onEdit) { Text("Edit") } }
    if (l.description.isNotBlank()) Text(l.description, style = MaterialTheme.typography.bodyMedium) else Muted("No description yet. A few lines about what you offer helps people choose you.")
    val facts = buildList<Pair<String, String>> {
        when (l.kind) {
            "BUSINESS" -> { d.str("hours").ifBlank { null }?.let { add("Hours" to it) }; d.int("delivery_radius_km")?.let { add("Delivers within" to "$it km") }
                add("Delivery" to if (d.bool("free_delivery")) "Free for customers" else "Customer pays"); if (d.bool("cod")) add("Cash on delivery" to "With your own riders") }
            "SKILL" -> { d.str("rate").ifBlank { null }?.let { add("Rate" to it) }; d.str("level").ifBlank { null }?.let { add("Experience" to it) }; d.strings("languages").takeIf { it.isNotEmpty() }?.let { add("Languages" to it.joinToString(", ")) } }
            "ASSET" -> { add("Listing" to assetPriceLine(d)); d.num("deposit")?.takeIf { it > 0 }?.let { add("Deposit" to rupees(it.toLong())) }
                d.num("area_sqft")?.takeIf { it > 0 }?.let { add("Size" to "${it.toLong()} sq ft") }; d.int("bedrooms")?.let { add("Bedrooms" to "$it") }
                d.str("furnishing").ifBlank { null }?.let { add("Furnishing" to it) }; d.str("available_from").ifBlank { null }?.let { add("Available from" to it) }
                d.int("year")?.let { add("Year" to "$it") }; d.int("km_driven")?.let { add("Driven" to "${rupees(it).removePrefix("₹")} km") }
                if (d.bool("negotiable")) add("Price" to "Negotiable") }
            "DRIVER" -> { d.str("vehicle_kind").ifBlank { null }?.let { add("Drives" to vehicleKindLabel(it)) }; d.str("model").ifBlank { null }?.let { add("Model" to it) }; d.strings("languages").takeIf { it.isNotEmpty() }?.let { add("Languages" to it.joinToString(", ")) } }
        }
    }
    facts.forEach { (k, v) -> Row(Modifier.padding(top = 8.dp)) { Muted(k, Modifier.width(120.dp)); Text(v, style = MaterialTheme.typography.bodyMedium) } }
}

/* ---------- Products / services ---------- */

@Composable
private fun ItemsTab(m: MyListings, l: ListingRow, onItem: (String, String?) -> Unit) {
    val service = l.kind == "SKILL"; val noun = if (service) "service" else "product"
    val rows = m.items[l.id]
    var q by rememberSaveable(l.id) { mutableStateOf("") }; var group by rememberSaveable(l.id) { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf<ItemRow?>(null) }
    val groups = rows.orEmpty().map { it.group.trim() }.filter { it.isNotBlank() }.distinct().sorted()
    val shown = rows.orEmpty().filter { (q.isBlank() || it.name.contains(q.trim(), true)) && (group == null || it.group.trim() == group) }
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Column(Modifier.padding(horizontal = Gutter, vertical = 12.dp)) {
                PrimaryButton("Add $noun") { onItem(l.id, null) }
                if (rows.orEmpty().size > 6) BucksField(q, { q = it }, placeholder = "Search your ${noun}s", modifier = Modifier.padding(top = 12.dp))
                if (groups.size > 1) ChipRow(listOf("All") + groups, group ?: "All", Modifier.padding(top = 4.dp)) { group = if (it == "All") null else it }
                if (rows != null && rows.isNotEmpty()) Muted("${rows.size} ${noun}s · ${rows.count { it.inStock }} ${if (service) "available" else "in stock"}", Modifier.padding(top = 8.dp))
            }
        }
        when {
            rows == null -> item { CenteredLoading() }
            rows.isEmpty() -> item {
                BucksCard(Modifier.padding(horizontal = Gutter)) {
                    Text("No ${noun}s yet", style = MaterialTheme.typography.titleMedium)
                    Muted(if (service) "Add each service with its price, like \"Tap repair · ₹300 per visit\" or \"Logo design · ₹4,000\". People request straight from this list."
                          else "Add what you sell with a price, photos and pack size, like \"Sona masoori rice · ₹62 · 1 kg\". Count stock if you want Bucks to stop orders when you run out.", Modifier.padding(top = 4.dp))
                }
            }
            shown.isEmpty() -> item { Muted("Nothing matches.", Modifier.padding(Gutter)) }
            else -> items(shown, key = { it.id ?: it.name }) { row -> ItemManageRow(m, row, service, onEdit = { onItem(l.id, row.id) }, onDelete = { deleting = row }); Divider() }
        }
    }
    deleting?.let { r -> ConfirmDialog("Remove ${r.name}?", "It disappears from your profile and search. Orders already placed aren't affected.", "Remove", onConfirm = { m.deleteItem(r) {} }, onDismiss = { deleting = null }) }
}

@Composable
private fun ItemManageRow(m: MyListings, row: ItemRow, service: Boolean, onEdit: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable(onClick = onEdit).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        PhotoOrIcon(row.photos.firstOrNull()?.url ?: row.photoUrl, if (service) Icons.Rounded.Handyman else Icons.Rounded.ShoppingBag, size = 56)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(row.name, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(rupees(row.price), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold))
                row.mrp?.takeIf { it > row.price }?.let { Text(rupees(it), style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (row.unit.isNotBlank()) Muted(row.unit, maxLines = 1)
            }
            Muted(listOfNotNull(row.group.ifBlank { null }, row.stock?.let { if (it == 0) "Sold out" else "$it left" }, if (row.photos.size > 1) "${row.photos.size} photos" else null).joinToString(" · "), maxLines = 1)
        }
        Switch(checked = row.inStock, onCheckedChange = { on -> m.setInStock(row, on) })
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, "More") }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Edit") }, { menu = false; onEdit() }, leadingIcon = { Icon(Icons.Rounded.Edit, null) })
                DropdownMenuItem({ Text("Duplicate") }, { menu = false; m.duplicateItem(row) }, leadingIcon = { Icon(Icons.Rounded.ContentCopy, null) })
                DropdownMenuItem({ Text("Remove", color = MaterialTheme.colorScheme.error) }, { menu = false; onDelete() }, leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.error) })
            }
        }
    }
}

/* ---------- Photos / portfolio ---------- */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhotosTab(vm: BucksViewModel, l: ListingRow) {
    val m = vm.myListings; val ctx = LocalContext.current
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris ->
        val picked = uris.mapNotNull { u -> Upload.read(ctx, u)?.asListingPhoto() }
        if (uris.isNotEmpty() && picked.isEmpty()) vm.toast("Couldn't read those images. Try JPG or PNG photos.")
        if (picked.isNotEmpty()) m.addGalleryPhotos(l.id, picked)
    }
    var open by remember { mutableStateOf<MediaPhoto?>(null) }
    val g = l.gallery
    LazyVerticalGrid(GridCells.Adaptive(112.dp), contentPadding = PaddingValues(Gutter), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
            Column(Modifier.padding(bottom = 6.dp)) {
                Text(if (l.kind == "SKILL") "Portfolio" else "Photos", style = MaterialTheme.typography.titleMedium)
                Muted(when (l.kind) { "SKILL" -> "Photos of work you've done, with a line about each. Customers see them on your profile."
                    "ASSET" -> "Every room or angle, in daylight. The cover is the first thing people see."
                    else -> "The shop front, the inside, your best products. Tap a photo to caption it, reorder it or make it the cover." } + " ${g.size} of 20.")
                if (m.busy) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
            }
        }
        if (g.size < 20) item {
            Box(Modifier.aspectRatio(1f).clip(MaterialTheme.shapes.medium).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.medium).clickable(enabled = !m.busy) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                contentAlignment = Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.PhotoCamera, null, tint = MaterialTheme.colorScheme.primary); Text("Add photos", style = MaterialTheme.typography.labelMedium) } }
        }
        items(g, key = { it.url }) { p ->
            Box(Modifier.aspectRatio(1f).clip(MaterialTheme.shapes.medium).clickable { open = p }) {
                AsyncImage(p.url, p.caption.ifBlank { null }, Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer), contentScale = ContentScale.Crop)
                if (p.url == l.photoUrl) Box(Modifier.padding(6.dp)) { Pill("Cover", MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary) }
                if (p.caption.isNotBlank()) Text(p.caption, style = MaterialTheme.typography.labelSmall, color = androidx.compose.ui.graphics.Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.45f)).padding(horizontal = 6.dp, vertical = 3.dp))
            }
        }
    }
    open?.let { p ->
        var caption by remember(p.url) { mutableStateOf(p.caption) }; var confirm by remember(p.url) { mutableStateOf(false) }
        val i = g.indexOfFirst { it.url == p.url }
        ModalBottomSheet(onDismissRequest = { open = null }) {
            Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
                AsyncImage(p.url, null, Modifier.fillMaxWidth().heightIn(max = 320.dp).clip(MaterialTheme.shapes.medium), contentScale = ContentScale.Fit)
                BucksField(caption, { caption = it.take(200) }, if (l.kind == "SKILL") "What was the job?" else "Caption", if (l.kind == "SKILL") "Bathroom re-tiling, Koramangala" else "Optional", Modifier.padding(top = 12.dp))
                PrimaryButton("Save caption", enabled = caption.trim() != p.caption) { m.setCaption(l.id, p.url, caption); open = null }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SmallButton("Make cover", Modifier.weight(1f), tonal = true, enabled = p.url != l.photoUrl) { m.setCover(l.id, p.url); open = null }
                    IconButton(onClick = { m.moveGalleryPhoto(l.id, p.url, -1); open = null }, enabled = i > 0) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Move earlier") }
                    IconButton(onClick = { m.moveGalleryPhoto(l.id, p.url, 1); open = null }, enabled = i in 0 until g.lastIndex) { Icon(Icons.Rounded.ChevronRight, "Move later") }
                }
                BadButton("Remove photo", Modifier.padding(top = 4.dp)) { confirm = true }
            }
        }
        if (confirm) ConfirmDialog("Remove this photo?", if (p.url == l.photoUrl) "It stays as the cover until you pick another." else "It's deleted from your listing.", "Remove",
            onConfirm = { m.removeGalleryPhoto(l.id, p.url); open = null }, onDismiss = { confirm = false })
    }
}

/* ---------- Feed ---------- */

@Composable
private fun FeedManageTab(vm: BucksViewModel, l: ListingRow) {
    val m = vm.myListings
    LaunchedEffect(l.id) { m.loadPosts(l.id) }
    var text by rememberSaveable(l.id) { mutableStateOf("") }; var photo by remember { mutableStateOf<Picked?>(null) }; var preview by remember { mutableStateOf<Uri?>(null) }
    var deleting by remember { mutableStateOf<PostRow?>(null) }
    val pick = rememberImagePicker(onUnusable = { vm.toast("Couldn't read that image. Try a JPG or PNG photo.") }) { p, u -> photo = p; preview = u }
    val posts = m.posts[l.id]
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            BucksCard(Modifier.padding(Gutter)) {
                Text("Post as ${l.title}", style = MaterialTheme.typography.titleMedium)
                Muted("Offers, new stock, finished work. People nearby and everyone synced with you see it in their feed.", Modifier.padding(bottom = 8.dp))
                BucksField(text, { text = it.take(1000) }, placeholder = if (l.kind == "SKILL") "Just finished a kitchen rewiring in Jayanagar…" else "Fresh stock in today…", singleLine = false, minLines = 3)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (preview != null) Box { AsyncImage(preview, null, Modifier.size(64.dp).clip(MaterialTheme.shapes.small), contentScale = ContentScale.Crop)
                        IconButton(onClick = { photo = null; preview = null }, modifier = Modifier.align(Alignment.TopEnd).size(24.dp)) { Icon(Icons.Rounded.Close, "Remove photo", Modifier.size(16.dp)) } }
                    else SmallButton("Add photo", tonal = true, onClick = pick)
                    Spacer(Modifier.weight(1f))
                    SmallButton(if (m.busy) "Posting…" else "Post", enabled = !m.busy && (text.isNotBlank() || photo != null)) { m.postAs(l.id, text, photo) { text = ""; photo = null; preview = null } }
                }
            }
        }
        when {
            posts == null -> item { CenteredLoading() }
            posts.isEmpty() -> item { Muted("Nothing posted yet. Your first post shows here and on your profile.", Modifier.padding(horizontal = Gutter)) }
            else -> items(posts, key = { it.id }) { p ->
                Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Muted(listOfNotNull(ago(p.createdAt), vm.social.nameOf(p.authorId).takeIf { it != "…" }?.let { "by $it" }).joinToString(" · "), Modifier.weight(1f))
                        IconButton(onClick = { deleting = p }) { Icon(Icons.Rounded.DeleteOutline, "Delete post") }
                    }
                    if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyMedium)
                    (p.media.firstOrNull() as? JsonObject)?.str("path")?.takeIf { it.isNotBlank() }?.let { path -> SignedImage(vm, "posts", path, Modifier.padding(top = 8.dp).fillMaxWidth().height(220.dp).clip(MaterialTheme.shapes.medium)) }
                    Muted("${p.up} up · ${p.down} down · ${p.comments} comments", Modifier.padding(top = 6.dp))
                }
                Divider()
            }
        }
    }
    deleting?.let { p -> ConfirmDialog("Delete this post?", "It leaves your profile and everyone's feed.", "Delete", onConfirm = { m.deletePost(p) }, onDismiss = { deleting = null }) }
}

/* ---------- Reviews and recommendations ---------- */

@Composable
private fun ReviewsManageTab(vm: BucksViewModel, l: ListingRow) {
    val m = vm.myListings; val st = MaterialTheme.status
    LaunchedEffect(l.id) { m.loadReviews(l.id); m.loadCounts(l.id) }
    val rows = m.reviews[l.id]; val recs = m.recommendations[l.id] ?: 0
    LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(Modifier.weight(1f), trustPct(l.trustUp, l.trustDown), "Positive")
                StatTile(Modifier.weight(1f), "${l.trustUp}", "Recommend")
                StatTile(Modifier.weight(1f), "${l.trustDown}", "Don't")
            }
        }
        item {
            BucksCard(tint = true) {
                Text("$recs ${if (recs == 1) "person" else "people"} nearby recommended you in person", style = MaterialTheme.typography.titleSmall)
                Muted(if (l.status == "PENDING") "${(NEEDED - recs).coerceAtLeast(0)} more take you live. Show your code to people who know your work." else "Recommendations are how you went live. Reviews below come from completed orders and trips.")
            }
        }
        item { Notice("Reviews come only from customers after a completed order, visit or trip. Nobody can add or remove them by hand, including you.") }
        when {
            rows == null -> item { CenteredLoading() }
            rows.isEmpty() -> item { Muted("No reviews yet. They arrive as customers complete orders and trips with you.") }
            else -> items(rows, key = { it.id }) { r ->
                val up = r.vote > 0
                Row(verticalAlignment = Alignment.Top) {
                    Avatar(initials(vm.social.nameOf(r.authorId)).ifBlank { "?" }, size = 40)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text(vm.social.nameOf(r.authorId), style = MaterialTheme.typography.titleSmall); Muted(ago(r.createdAt))
                        Text(r.comment, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 4.dp))
                    }
                    Icon(if (up) Icons.Rounded.ThumbUp else Icons.Rounded.ArrowDownward, if (up) "Recommends" else "Doesn't recommend", tint = if (up) st.good else st.bad)
                }
            }
        }
    }
}
