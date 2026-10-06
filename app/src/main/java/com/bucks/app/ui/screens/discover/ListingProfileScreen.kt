package com.bucks.app.ui.screens.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.ListingProfile
import com.bucks.app.ui.PageType
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.driverKind
import com.bucks.app.ui.formatDistance
import com.bucks.app.ui.kindLabel
import com.bucks.app.ui.list
import com.bucks.app.ui.proRate
import com.bucks.app.ui.screens.SignedImage
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.screens.commerce.CartSwitchDialog
import com.bucks.app.ui.shareText
import com.bucks.app.ui.str
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private fun plural(n: Int, one: String, many: String = one + "s") = "$n ${if (n == 1) one else many}"
/** Details keys the About tab renders with a proper label; everything else gets a generic row. */
private val KNOWN_DETAILS = setOf("hours", "free_delivery", "delivery_radius_km", "delivery_radius_m", "rate", "level", "languages", "vehicle_kind", "vehicle", "kind", "model", "bio",
    "cod", "ships_india", "ship_fee", "free_ship_above", "dispatch_days", "source", "mode", "price", "price_unit", "deposit", "area_sqft", "bedrooms", "furnishing", "available_from", "year", "km_driven", "negotiable",
    "registration", "affiliation", "org_type")
/** Team tab order: the owner first, then admins. Store riders are not shown on the public page. */
private val TEAM_ORDER = mapOf("OWNER" to 0, "ADMIN" to 1)

/** What a business page's tab is called: the type decides ("Services" or "Catalogue", "Gallery" / "Work" / "Campus", "Volunteer" for an NGO). */
private fun tabLabel(t: PageType, key: String): String = when (key) {
    "products" -> "Products"
    "services" -> t.catalogueLabel ?: "Services"
    "programs" -> "Programs"
    "events" -> "Events"
    "photos" -> when { t.group == "LOCAL_SERVICES" -> "Gallery"; t.group == "COMPANIES" -> "Work"; t.key == "SCHOOL_COLLEGE" -> "Campus"; else -> "Photos" }
    "team" -> "Team"
    "jobs" -> if (t.key == "NGO_CHARITY") "Volunteer" else "Jobs"
    "feed" -> "Feed"
    "about" -> "About"
    "reviews" -> "Reviews"
    else -> key.replaceFirstChar { it.uppercase() }
}
/** Whether a tab has anything in it for a visitor; About and Feed-less tabs that always render say true. */
private fun tabHasContent(p: ListingProfile, key: String): Boolean = when (key) {
    "products" -> p.products.isNotEmpty()
    "services" -> p.services.isNotEmpty()
    "programs" -> p.programs.isNotEmpty()
    "events" -> p.events.isNotEmpty()
    "photos" -> p.listing.gallery.isNotEmpty()
    "jobs" -> p.openJobs > 0
    "team" -> p.members >= 2
    "feed" -> p.posts.isNotEmpty()
    else -> true
}
/**
 * The tabs of a business page, from its type. Reviews only where the type has them, Products only where it sells products,
 * and for visitors only the tabs with something in them; the owner sees every tab so they know what to fill.
 */
private fun businessTabs(t: PageType, p: ListingProfile): List<Pair<String, String>> =
    t.tabs.filter { k -> (k != "reviews" || t.reviews) && (k != "products" || t.sellsProducts) && (p.mine || tabHasContent(p, k)) }.map { it to tabLabel(t, it) }

/**
 * The universal public profile of a listing: the same header for a shop, a pro and a driver, then tabs by kind.
 * BUSINESS: by page type (ui/PageTypes.kt): a shop has Products, a local service Services, an NGO Programs, a group Events, plus Team, Jobs, Feed, About, Reviews
 * where the type says so. SKILL: Services, Feed, About, Reviews. DRIVER: About, Reviews, plus Book.
 */
@Composable
fun ListingProfileScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onOpenChat: (String) -> Unit, onCart: () -> Unit, onJobs: (String) -> Unit, onBook: (VehicleKind) -> Unit, onOpenListing: (String) -> Unit, onMap: () -> Unit = {}, onShowcaseDocs: (String) -> Unit = {}) {
    val d = vm.discover; val social = vm.social; val ctx = LocalContext.current
    LaunchedEffect(id) { d.open(id) }
    val p = d.profiles[id]
    if (p == null) { ProfilePlaceholder(vm, id, onBack); return }
    val l = p.listing
    /** The page type of a business; null for a pro, an asset or a driver. */
    val type = PageTypes.of(l)
    val ships = l.details.str("ships_india") == "true"
    val sellsProducts = type?.sellsProducts == true
    val photos = l.gallery.isNotEmpty()
    val tabs = when {
        type != null -> businessTabs(type, p)
        l.kind == "SKILL" -> listOfNotNull("services" to "Services", ("photos" to "Portfolio").takeIf { photos }, "feed" to "Feed", "about" to "About", "reviews" to "Reviews")
        l.kind == "ASSET" -> listOfNotNull("about" to "Details", ("photos" to "Photos").takeIf { photos }, "reviews" to "Reviews")
        else -> listOfNotNull("about" to "About", ("photos" to "Photos").takeIf { photos }, "reviews" to "Reviews")
    }
    // A page opens on its catalogue (products, services, programs, events) when it has one; the Feed is often still empty.
    val catalogue = type?.catalogueTab?.takeIf { k -> tabHasContent(p, k) && tabs.any { it.first == k } }
    var tab by rememberSaveable(id) { mutableStateOf(catalogue ?: tabs.first().first) }
    // A remembered tab the page no longer has (content changed since) falls back to the first one.
    val tabKey = if (tabs.any { it.first == tab }) tab else tabs.first().first
    val trust = Trust(l.trustUp, l.trustDown)
    val meId = vm.social.me?.id
    val myDirect = p.reviews.firstOrNull { it.authorId == meId && !it.verified }
    var rateVote by remember { mutableStateOf<Int?>(null) }
    rateVote?.let { v -> RecommendSheet(vm, l, myDirect, v, onDone = { rateVote = null; tab = "reviews"; d.open(id) }, onDismiss = { rateVote = null }) }
    val vk = if (l.kind == "DRIVER") driverKind(l.details, l.category) else null
    val cartCount = vm.commerce.count
    val cartHere = cartCount > 0
    val distance = p.at?.let { formatDistance(Geo.distanceKm(social.here, it) * 1000) }
    val synced = d.isSynced(id)
    fun share() = shareText(ctx, "${l.title} on Bucks" + listOfNotNull(l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(", ").let { if (it.isBlank()) "" else " · $it" } + ". Open Bucks and search \"${l.title}\".")
    fun message() = d.startListingChat(id, onOpenChat)
    fun directions() { p.at?.let { at -> com.bucks.app.ui.screens.MapsPick.place = com.bucks.app.data.MapServices.PlaceHit(l.title, l.area, at); onMap() } }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ListingCover(l, onBack, onShare = { share() })
            Column(Modifier.padding(horizontal = Gutter, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(l.title, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (l.status == "LIVE") { Spacer(Modifier.width(6.dp)); Icon(Icons.Rounded.Verified, "Verified by locals", Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary) }
                }
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    KindBadge(PageTypes.badge(l.kind, l.typeKey, ships), PageTypes.badgeIcon(l.kind, l.typeKey, ships))
                    if (l.category.isNotBlank()) Muted(l.category, maxLines = 1)
                    when (l.status) { "PENDING" -> PillWarn("Not live yet"); "SUSPENDED" -> PillBad("Suspended"); else -> {} }
                }
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    OnlineDot(l.online); Spacer(Modifier.width(6.dp))
                    Muted(listOfNotNull(onlineText(l.kind, l.online), distance?.let { "$it away" }, l.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                }
                if (l.kind == "ASSET") Text(assetPrice(l.details), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
                Row(Modifier.padding(top = 10.dp)) { TrustBadge(trust) }
                // The catalogue count is the type's: products for a shop, services, programs or events for the others.
                val catalogueStat = type?.catalogueTab?.let { k -> val n = when (k) { "products" -> p.products.size; "services" -> p.services.size; "programs" -> p.programs.size; else -> p.events.size }
                    if (n > 0) Triple(n, tabLabel(type, k), { tab = k }) else null }
                StatsRow(listOfNotNull(Triple(p.syncs, "Synced", null), catalogueStat, Triple(l.trustUp, "Recommendations") { tab = "reviews" }, (Triple(p.members, "Team", null)).takeIf { p.members > 1 }), Modifier.padding(top = 10.dp))
                val docCount by rememberShowcaseCount(id)
                docCount?.takeIf { it > 0 }?.let { n -> Box(Modifier.padding(top = 8.dp)) { Chip(if (n == 1) "1 document" else "$n documents", icon = Icons.Rounded.Description) { tab = "about" } } }
                if (!p.mine && (type == null || type.reviews)) Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RateButton(true, myDirect?.vote == 1, Modifier.weight(1f)) { rateVote = 1 }
                    RateButton(false, myDirect?.vote == -1, Modifier.weight(1f)) { rateVote = -1 }
                }
                if (!p.mine && l.kind == "BUSINESS") Muted(if (synced) "You're synced: ${l.title}'s posts show in your Feed and you'll get a notification when they post." else "Sync to see ${l.title}'s posts in your Feed and get notified.", Modifier.padding(top = 6.dp))
                if (p.mine) Notice("This is your listing. Edit it, its ${type?.itemNoun ?: "product"}s and its team from Menu > Bucks Pro.", Modifier.padding(top = 12.dp))
                else {
                    // The page's own action: Book, Get a quote, Volunteer, Join, Directions... A shop has none here; its cart lives in Products.
                    if (type != null && !type.isShop && type.cta != "CART" && (type.cta != "DIRECTIONS" || p.at != null)) PrimaryButton(type.ctaLabel, Modifier.padding(top = 12.dp)) {
                        if (type.cta == "DIRECTIONS") directions() else d.startListingChat(id, onOpenChat, PageTypes.ctaMessage(type, l.title))
                    }
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button({ message() }, Modifier.weight(1f).height(44.dp), shape = MaterialTheme.shapes.small, contentPadding = PaddingValues(horizontal = 12.dp)) {
                            Icon(Icons.Rounded.Sms, null, Modifier.size(18.dp)); Text("Message", style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp)) }
                        SyncButton(synced, busy = id in d.syncing, Modifier.weight(1f)) { d.syncListing(id, !synced) }
                        HeaderIcon(Icons.Rounded.IosShare, "Share") { share() }
                        if (p.at != null) HeaderIcon(Icons.Rounded.Place, "Directions") { directions() }
                        if (sellsProducts && cartHere && l.online) BadgedBox(badge = { Badge { Text("$cartCount") } }) { HeaderIcon(Icons.Rounded.ShoppingCart, "Order", on = true, onClick = onCart) }
                    }
                }
                if (l.kind == "ASSET" && !p.mine) PrimaryButton(if (l.details.str("mode") == "SELL") "Enquire about buying" else "Enquire about renting", Modifier.padding(top = 12.dp)) {
                    d.startListingChat(id, onOpenChat, "Hi, I'm interested in ${l.title}. Is it still available?") }
                if (l.kind == "DRIVER" && !p.mine) {
                    if (vk != null && vk.carriesPassengers) {
                        PrimaryButton("Book a ${vk.label.lowercase()}", Modifier.padding(top = 12.dp)) { onBook(vk) }
                        Muted("Bucks rings the nearest online ${vk.label.lowercase()} rider, so it may not be ${l.title.substringBefore(' ')}. Pay after the trip, cash or UPI.", Modifier.padding(top = 6.dp))
                    } else Notice("Bike riders carry parcels only, never passengers. Order from a shop nearby and a rider delivers it.", Modifier.padding(top = 12.dp))
                }
            }
            val tabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0)
            TabRow(tabIndex, containerColor = MaterialTheme.colorScheme.surface,
                indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tabIndex]), height = 3.dp, color = MaterialTheme.colorScheme.primary) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
                tabs.forEach { (k, label) -> Tab(tab == k, onClick = { tab = k }, modifier = Modifier.height(48.dp), selectedContentColor = MaterialTheme.colorScheme.onSurface, unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant) {
                    Text(label, style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (tab == k) FontWeight.SemiBold else FontWeight.Normal), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp)) } }
            }
            when (tab) {
                "products" -> StoreProducts(vm, p, onMessage = { message() }, onCart = onCart)
                "jobs" -> JobsTab(p) { onJobs(id) }
                "services" -> ServicesTab(vm, p, onOpenChat)
                "feed" -> FeedTab(vm, p)
                "photos" -> GalleryTab(l)
                "about" -> { LaunchedEffect(p.listing.id) { vm.services.loadBadges(p.listing.id) }; AboutTab(p, vk, distance, onOpenListing, vm.services.badges[p.listing.id].orEmpty()); ShowcaseDocsSection(vm, id, p.mine, onManage = { onShowcaseDocs(id) }); if (l.kind == "BUSINESS" && photos) { SectionTitle("Photos", Modifier.padding(start = Gutter, end = Gutter, top = 8.dp)); GalleryTab(l) } }
                "reviews" -> ReviewsTab(vm, p, myDirect) { rateVote = it }
            }
            Spacer(Modifier.height(24.dp))
        }
        if (l.kind == "BUSINESS" && l.online && cartCount > 0 && tab == "products") DarkButton("View cart · ${plural(cartCount, "item")}", Modifier.align(Alignment.BottomCenter).padding(Gutter), onClick = onCart)
    }
    // Commerce: asks "Start a new cart?" when an item from a second shop is added (vm.commerce.pendingSwitch).
    CartSwitchDialog(vm)
}

/** While the profile loads, when the listing isn't there (missing), or when the load itself failed (offline, server error). */
@Composable
private fun ProfilePlaceholder(vm: BucksViewModel, id: String, onBack: () -> Unit) {
    val d = vm.discover
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Listing", onBack = onBack)
        if (id !in d.missing && id !in d.failed) { ProfileSkeleton(); return@ContentColumn }
        Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            when {
                id in d.missing -> {
                    Icon(Icons.Rounded.SearchOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("This listing isn't available", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                    Muted("It may have been removed, or it isn't live yet. A listing goes live once 7 people nearby recommend it in person.", Modifier.padding(top = 6.dp), align = TextAlign.Center)
                    SmallButton("Try again", Modifier.padding(top = 14.dp), tonal = true) { d.open(id) }
                    TextButton(onBack) { Text("Back") }
                }
                id in d.failed -> {
                    Icon(Icons.Rounded.CloudOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Couldn't load this listing", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                    Muted("Check your connection and try again.", Modifier.padding(top = 6.dp), align = TextAlign.Center)
                    SmallButton("Try again", Modifier.padding(top = 14.dp), tonal = true) { d.open(id) }
                    TextButton(onBack) { Text("Back") }
                }
                else -> {}
            }
        }
    }
}

/** Cover band (primary gradient), back and share on top, the photo or initials overlapping the bottom edge. */
@Composable
private fun ListingCover(l: ListingRow, onBack: () -> Unit, onShare: () -> Unit) = Box(Modifier.fillMaxWidth().height(170.dp)) {
    Box(Modifier.fillMaxWidth().height(140.dp).background(Brush.linearGradient(listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimaryContainer)))) {
        // The first gallery photo fills the band, darkened at the top so back and share stay readable.
        l.gallery.firstOrNull()?.let { g -> AsyncImage(g.url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.45f), androidx.compose.ui.graphics.Color.Transparent)))) }
    }
    Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", tint = MaterialTheme.colorScheme.onPrimary) }
        Spacer(Modifier.weight(1f))
        IconButton(onClick = onShare) { Icon(Icons.Rounded.IosShare, "Share", tint = MaterialTheme.colorScheme.onPrimary) }
    }
    Box(Modifier.padding(start = Gutter).align(Alignment.BottomStart).size(96.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface).padding(4.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
        val url = Backend.listingPhoto(l.photoUrl)
        if (url != null) AsyncImage(url, l.title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Text(initials(l.title).ifBlank { "?" }, style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

@Composable
private fun SyncButton(synced: Boolean, busy: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) =
    Row(modifier.minimumInteractiveComponentSize().height(44.dp).clip(MaterialTheme.shapes.small).background(if (synced) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(enabled = !busy, onClick = onClick).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        val c = if (synced) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface
        if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = c) else Icon(if (synced) Icons.Rounded.Check else Icons.Rounded.Sync, null, Modifier.size(18.dp), tint = c)
        Text(if (synced) "Synced" else "Sync", style = MaterialTheme.typography.labelLarge, color = c, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp))
    }

/** Numbers under the name: synced, products, recommendations (opens Reviews) and team size. A stat with an action is tappable. */
@Composable
private fun StatsRow(stats: List<Triple<Int, String, (() -> Unit)?>>, modifier: Modifier = Modifier) = Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
    stats.forEach { (n, label, go) ->
        Column(Modifier.then(if (go != null) Modifier.clip(MaterialTheme.shapes.small).clickable(onClickLabel = "See $label", onClick = go) else Modifier).semantics(mergeDescendants = true) { contentDescription = "$n $label" }) {
            Text("%,d".format(n), style = MaterialTheme.typography.titleMedium); Muted(label, maxLines = 1) }
    }
}

private fun friendly(e: Throwable) = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message ?: "")?.groupValues?.get(1) ?: "Couldn't send that. Check your connection and try again."

/** Recommend / not recommend button; filled when it is my current vote. */
@Composable
private fun RateButton(up: Boolean, mine: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val st = MaterialTheme.status; val c = if (up) st.good else st.bad
    OutlinedButton(onClick, modifier.heightIn(min = 44.dp), shape = MaterialTheme.shapes.small, contentPadding = PaddingValues(horizontal = 10.dp),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (mine) c.copy(alpha = 0.14f) else androidx.compose.ui.graphics.Color.Transparent, contentColor = c)) {
        Icon(if (up) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, null, Modifier.size(18.dp))
        Text(if (up) "Recommend" else "Not recommend", style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp))
    }
}

/** Comment box that opens on a recommend / not recommend tap; the vote and comment land in the Reviews tab. Works for shops, pros, assets and drivers. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecommendSheet(vm: BucksViewModel, l: ListingRow, mine: ReviewRow?, initial: Int, onDone: () -> Unit, onDismiss: () -> Unit) {
    var vote by remember { mutableStateOf(initial) }
    var text by remember { mutableStateOf(mine?.comment.orEmpty()) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope(); val st = MaterialTheme.status
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(if (mine != null) "Your recommendation for ${l.title}" else "Recommend ${l.title}?", style = MaterialTheme.typography.titleLarge)
            Muted("Your vote and comment are shown in Reviews for everyone.", Modifier.padding(top = 4.dp))
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RateButton(true, vote == 1, Modifier.weight(1f)) { vote = 1 }
                RateButton(false, vote == -1, Modifier.weight(1f)) { vote = -1 }
            }
            OutlinedTextField(text, { text = it.take(500) }, Modifier.padding(top = 12.dp).fillMaxWidth(), placeholder = { Text(if (vote > 0) "What did you like? (optional)" else "What went wrong? (optional)") }, minLines = 3, maxLines = 6, supportingText = { Text("${text.length}/500") })
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({ scope.launch { busy = true
                    runCatching { Backend.rateListing(l.id, vote, text.trim()) }.onSuccess { vm.toast("Thanks, your review is posted."); onDone() }.onFailure { vm.toast(friendly(it)) }
                    busy = false } }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(if (busy) "Sending…" else if (mine != null) "Update" else "Submit") }
                if (mine != null) TextButton({ scope.launch { busy = true
                    runCatching { Backend.clearListingRating(l.id) }.onSuccess { vm.toast("Your review was removed."); onDone() }.onFailure { vm.toast(friendly(it)) }
                    busy = false } }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text("Remove mine", color = st.bad) }
            }
        }
    }
}

/** 44dp tonal icon button (48dp touch) for the header's secondary actions; [on] tints it. */
@Composable
private fun HeaderIcon(icon: ImageVector, label: String, on: Boolean = false, onClick: () -> Unit) =
    Box(Modifier.minimumInteractiveComponentSize().size(44.dp).clip(MaterialTheme.shapes.small).background(if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(onClickLabel = label, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, Modifier.size(20.dp), tint = if (on) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface) }

/* ---------- BUSINESS: Products and Jobs ---------- */

@Composable
private fun JobsTab(p: ListingProfile, onJobs: () -> Unit) = Column(Modifier.padding(Gutter)) {
    BucksCard(onClick = onJobs) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Work, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text("Open jobs at ${p.listing.title}", style = MaterialTheme.typography.titleMedium)
                Muted(if (p.openJobs > 0) "${plural(p.openJobs, "opening")} right now. Apply with your skill profile." else "See openings here and apply with your skill profile.")
            }
            Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (p.mine) Muted("Post a job and manage applications from Menu > Bucks Pro.", Modifier.padding(top = 10.dp))
}

/* ---------- SKILL: Services and Feed ---------- */

@Composable
private fun ServicesTab(vm: BucksViewModel, p: ListingProfile, onOpenChat: (String) -> Unit) {
    val d = vm.discover; val l = p.listing; val services = p.services; val first = l.title.substringBefore(' ')
    Column(Modifier.padding(Gutter)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Payments, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(proRate(l.details, services.minOfOrNull { it.price }), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp)) }
        if (services.isEmpty()) {
            Muted(if (p.mine) "No services listed yet. Add them from Menu > Bucks Pro." else "No services listed yet. Describe what you need; $first confirms the price before starting.", Modifier.padding(top = 8.dp))
            if (!p.mine) PrimaryButton("Request a visit", Modifier.padding(top = 14.dp)) { d.startListingChat(l.id, onOpenChat, "Hi, I need help with ${l.category.ifBlank { "a job" }.lowercase()}. Are you available?") }
        } else {
            Column(Modifier.padding(top = 8.dp)) {
                services.forEachIndexed { i, s ->
                    if (i > 0) Divider()
                    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(s.name, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis); Muted(servicePrice(s), maxLines = 1)
                            if (s.description.isNotBlank()) Muted(s.description, maxLines = 2) }
                        if (!p.mine) SmallButton("Request", tonal = true) { d.startListingChat(l.id, onOpenChat, "Hi, I'd like to request: ${s.name} (₹${s.price}${if (s.unit.isNotBlank()) " " + s.unit else ""}). When are you free?") }
                    }
                }
            }
            if (!p.mine) Notice("Request opens a chat with $first, who confirms the price before starting.", Modifier.padding(top = 14.dp))
        }
    }
}

@Composable
private fun FeedTab(vm: BucksViewModel, p: ListingProfile) {
    if (p.posts.isEmpty()) { Muted(if (p.mine) "No posts yet. Post as ${p.listing.title} from the feed." else "${p.listing.title} hasn't posted yet. Sync to see their posts in your feed when they do.", Modifier.padding(Gutter)); return }
    p.posts.forEach { post -> ListingPost(vm, post, p.listing.title); Divider() }
}

/** A listing's post, laid out like the feed: who and when, text, the first photo, and its counts. */
@Composable
private fun ListingPost(vm: BucksViewModel, post: PostRow, title: String) = Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 14.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(title).ifBlank { "?" }, size = 40)
        Column(Modifier.padding(start = 10.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); Muted(listOfNotNull(vm.social.nameOf(post.authorId).takeIf { it != "…" }, ago(post.createdAt)).joinToString(" · ")) }
    }
    if (post.body.isNotBlank()) Text(post.body, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
    (post.media.firstOrNull() as? JsonObject)?.str("path")?.let { path -> SignedImage(vm, "posts", path, Modifier.padding(top = 10.dp).fillMaxWidth().height(260.dp).clip(MaterialTheme.shapes.medium)) }
    Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        val c = MaterialTheme.colorScheme.onSurfaceVariant
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(18.dp), tint = c); Text(" ${post.up}", color = c, style = MaterialTheme.typography.labelLarge) }
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowDownward, null, Modifier.size(18.dp), tint = c); Text(" ${post.down}", color = c, style = MaterialTheme.typography.labelLarge) }
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ChatBubbleOutline, null, Modifier.size(16.dp), tint = c); Text(" ${post.comments}", color = c, style = MaterialTheme.typography.labelLarge) }
    }
}

/* ---------- About and Reviews (every kind) ---------- */

@Composable
private fun AboutTab(p: ListingProfile, vk: VehicleKind?, distance: String?, onOpenListing: (String) -> Unit, badges: List<com.bucks.app.data.BadgeRow> = emptyList()) = Column {
    val l = p.listing; val det = l.details
    Column(Modifier.padding(Gutter)) {
        if (l.description.isNotBlank()) Text(l.description, style = MaterialTheme.typography.bodyMedium) else Muted("No description yet.")
        AboutRow(Icons.Rounded.LocationOn, "Area", listOfNotNull(l.area.ifBlank { null }, distance?.let { "$it from you" }).joinToString(" · ").ifBlank { "Not shared" })
        if (l.category.isNotBlank()) AboutRow(Icons.Rounded.Category, "Category", l.category)
        when (l.kind) {
            "BUSINESS" -> {
                det.str("hours")?.let { AboutRow(Icons.Rounded.Schedule, "Hours", it) }
                det.str("free_delivery")?.let { AboutRow(Icons.Rounded.DeliveryDining, "Delivery", if (it == "true") "Free delivery" else "Delivery charged") }
                (det.str("delivery_radius_km")?.let { "$it km" } ?: det.str("delivery_radius_m")?.toDoubleOrNull()?.let { formatDistance(it) })?.let { AboutRow(Icons.Rounded.MyLocation, "Delivers within", it) }
                if (det.str("ships_india") == "true") {
                    val fee = det.str("ship_fee")?.toIntOrNull() ?: 0; val above = det.str("free_ship_above")?.toIntOrNull() ?: 0
                    AboutRow(Icons.Rounded.LocalShipping, "Ships across India", listOfNotNull(if (fee == 0) "Free shipping" else "Shipping ${inr(fee.toLong())}", if (fee > 0 && above > 0) "free above ${inr(above.toLong())}" else null,
                        det.str("dispatch_days")?.let { "ships in $it days" }, if (det.str("cod") == "true") "cash on delivery available" else null).joinToString(" · "))
                }
            }
            "SKILL" -> {
                AboutRow(Icons.Rounded.Payments, "Rate", proRate(det, p.services.minOfOrNull { it.price }))
                det.str("level")?.let { AboutRow(Icons.Rounded.WorkspacePremium, "Experience", it.lowercase().replaceFirstChar { c -> c.uppercase() }) }
                det.list("languages").takeIf { it.isNotEmpty() }?.let { AboutRow(Icons.Rounded.Language, "Languages", it.joinToString(", ")) }
            }
            "ASSET" -> {
                AboutRow(Icons.Rounded.Apartment, "Listing", assetPrice(det))
                det.str("deposit")?.toDoubleOrNull()?.takeIf { it > 0 }?.let { AboutRow(Icons.Rounded.Payments, "Deposit", inr(it.toLong())) }
                det.str("area_sqft")?.let { AboutRow(Icons.Rounded.Category, "Size", "$it sq ft") }
                det.str("bedrooms")?.let { AboutRow(Icons.Rounded.Home, "Bedrooms", it) }
                det.str("furnishing")?.let { AboutRow(Icons.Rounded.Chair, "Furnishing", it) }
                det.str("available_from")?.let { AboutRow(Icons.Rounded.CalendarMonth, "Available from", it) }
                det.str("year")?.let { AboutRow(Icons.Rounded.CalendarMonth, "Year", it) }
                det.str("km_driven")?.let { AboutRow(Icons.Rounded.DirectionsCar, "Driven", "$it km") }
                if (det.str("negotiable") == "true") AboutRow(Icons.Rounded.Payments, "Price", "Negotiable")
            }
            "DRIVER" -> {
                AboutRow(vk?.icon ?: Icons.Rounded.DirectionsCar, "Vehicle", listOfNotNull(vk?.label, det.str("model")).joinToString(" · ").ifBlank { "Not shared" })
                vk?.let { AboutRow(Icons.Rounded.Payments, "Fare", "₹${it.farePerKm} per km, plus ₹20 base fare" + if (it.carriesPassengers) "" else " · parcels only") }
                det.list("languages").takeIf { it.isNotEmpty() }?.let { AboutRow(Icons.Rounded.Language, "Languages", it.joinToString(", ")) }
                det.str("bio")?.let { AboutRow(Icons.Rounded.Person, "About", it) }
            }
        }
        // Anything else the owner filled in, as a labelled row: "delivery_note" -> "Delivery note".
        det.entries.filter { (k, v) -> k !in KNOWN_DETAILS && v is JsonPrimitive }.forEach { (k, _) ->
            det.str(k)?.let { v -> AboutRow(Icons.Rounded.Info, k.replace('_', ' ').replaceFirstChar { c -> c.uppercase() }, when (v) { "true" -> "Yes"; "false" -> "No"; else -> v }) }
        }
        // Checked documents: a tick for each, with the number only where the law wants customers to see it (FSSAI, GST, RERA).
        // The files themselves are private to the owner and Bucks.
        badges.forEach { b -> AboutRow(Icons.Rounded.VerifiedUser, b.label, listOfNotNull(b.number.ifBlank { null }, "checked by Bucks", b.expiresOn?.let { "valid till ${humanDate(it)}" }).joinToString(" · ")) }
        AboutRow(Icons.Rounded.Verified, "Status", when (l.status) { "LIVE" -> "Live: ${p.recommendations} people nearby recommended it in person"; "PENDING" -> "Not live yet: ${p.recommendations} of ${com.bucks.app.ui.MyListings.NEEDED} recommendations"; else -> "Suspended" })
    }
    if (p.similar.isNotEmpty()) {
        Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
        SectionTitle("More ${l.category.ifBlank { kindLabel(l.kind) + "s" }.lowercase()} nearby", Modifier.padding(start = Gutter, end = Gutter, top = 16.dp, bottom = 4.dp))
        p.similar.forEach { h ->
            ListRow(h.title, listOfNotNull(formatDistance(h.distanceM), h.area.ifBlank { null }, onlineText(h.kind, h.online)).joinToString(" · "), leading = { ListingPhoto(Backend.listingPhoto(h.photoUrl), h.title, size = 40) },
                trailing = { TrustBadge(Trust(h.trustUp, h.trustDown), compact = true) }, onClick = { onOpenListing(h.id) })
            Divider()
        }
    }
}

@Composable
private fun AboutRow(icon: ImageVector, label: String, value: String) = Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    Column(Modifier.padding(start = 12.dp)) { Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(value, style = MaterialTheme.typography.bodyMedium) }
}

@Composable
private fun ReviewsTab(vm: BucksViewModel, p: ListingProfile, mine: ReviewRow?, onWrite: (Int) -> Unit) = Column(Modifier.padding(Gutter)) {
    val st = MaterialTheme.status; val l = p.listing
    val total = l.trustUp + l.trustDown
    Row(verticalAlignment = Alignment.CenterVertically) {
        TrustBadge(Trust(l.trustUp, l.trustDown))
        if (total > 0) Muted("  ${l.trustUp * 100 / total}% recommend · $total ${if (total == 1) "vote" else "votes"}")
    }
    if (p.mine) Muted("Reviews come from customers. You can't rate or remove them.", Modifier.padding(top = 8.dp))
    else PrimaryButton(if (mine != null) "Edit my review" else "Write a review", Modifier.padding(top = 12.dp)) { onWrite(mine?.vote ?: 1) }
    if (p.reviews.isEmpty()) Muted(if (p.mine) "No reviews yet." else "No reviews yet. Be the first to recommend ${l.title}.", Modifier.padding(vertical = 16.dp))
    p.reviews.forEach { r ->
        val up = r.vote > 0
        Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.Top) {
            Avatar(initials(vm.social.nameOf(r.authorId)).ifBlank { "?" }, size = 40)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(vm.social.nameOf(r.authorId), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)); Muted("  ${ago(r.createdAt)}") }
                if (r.comment.isNotBlank()) Text(r.comment, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 2.dp))
                else Muted(if (up) "Recommended, no comment." else "Not recommended, no comment.", Modifier.padding(top = 2.dp))
                if (r.verified) Text("Verified ${if (r.orderId != null) "order" else "trip"}", style = MaterialTheme.typography.labelSmall, color = st.good, modifier = Modifier.padding(top = 4.dp))
            }
            Column(horizontalAlignment = Alignment.End) {
                Icon(if (up) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (up) "Recommends" else "Doesn't recommend", Modifier.size(20.dp), tint = if (up) st.good else st.bad)
                Spacer(Modifier.height(4.dp)); if (up) PillGood("Recommends") else PillBad("Doesn't recommend")
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
    }
}

/** "2027-03-12" -> "12 Mar 2027"; anything unparseable comes back unchanged. */
internal fun humanDate(iso: String): String = runCatching {
    java.time.LocalDate.parse(iso.take(10)).format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", java.util.Locale.ENGLISH))
}.getOrDefault(iso)

/* ---------- Studio additions: gallery, asset prices, product details ---------- */

private fun assetPrice(d: JsonObject) = com.bucks.app.ui.screens.manage.assetPriceLine(d)
private fun inr(n: Long) = com.bucks.app.ui.screens.manage.rupees(n)

/** "Starting from ₹500 · per visit · about 1 hour", or "Price on quote". */
private fun servicePrice(s: ItemRow): String {
    val pricing = s.details.str("pricing") ?: "FIXED"
    val money = when { pricing == "QUOTE" && s.price == 0 -> "Price on quote"; pricing == "FROM" -> "From ${inr(s.price.toLong())}"; pricing == "QUOTE" -> "Usually ${inr(s.price.toLong())}"; else -> inr(s.price.toLong()) }
    return listOfNotNull(money, s.unit.ifBlank { null } ?: when (pricing) { "HOURLY" -> "per hour"; "VISIT" -> "per visit"; else -> null }, s.details.str("duration")?.let { "about $it" }).joinToString(" · ")
}

/** A listing's photos (portfolio for a pro) in a grid; tap for full size with the caption. */
@Composable
private fun GalleryTab(l: ListingRow) {
    var open by remember { mutableStateOf<Int?>(null) }
    val g = l.gallery
    Column(Modifier.padding(Gutter)) {
        g.chunked(3).forEachIndexed { row, photos ->
            Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                photos.forEachIndexed { i, ph ->
                    AsyncImage(ph.url, ph.caption.ifBlank { null }, Modifier.weight(1f).aspectRatio(1f).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable { open = row * 3 + i }, contentScale = ContentScale.Crop)
                }
                repeat(3 - photos.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    open?.let { i -> val ph = g.getOrNull(i) ?: return@let
        androidx.compose.ui.window.Dialog(onDismissRequest = { open = null }, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
            Column(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black).systemBarsPadding()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { open = null }) { Icon(Icons.Rounded.Close, "Close", tint = androidx.compose.ui.graphics.Color.White) }
                    Text("${i + 1} of ${g.size}", color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.labelLarge)
                }
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    AsyncImage(ph.url, ph.caption.ifBlank { null }, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                    if (i > 0) IconButton(onClick = { open = i - 1 }, modifier = Modifier.align(Alignment.CenterStart)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Previous", tint = androidx.compose.ui.graphics.Color.White) }
                    if (i < g.lastIndex) IconButton(onClick = { open = i + 1 }, modifier = Modifier.align(Alignment.CenterEnd)) { Icon(Icons.Rounded.ChevronRight, "Next", tint = androidx.compose.ui.graphics.Color.White) }
                }
                if (ph.caption.isNotBlank()) Text(ph.caption, color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(Gutter))
            }
        }
    }
}
