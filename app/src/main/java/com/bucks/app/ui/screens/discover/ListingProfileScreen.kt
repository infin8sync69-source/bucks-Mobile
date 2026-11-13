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
import com.bucks.app.ui.Catalogue
import com.bucks.app.ui.ListingProfile
import com.bucks.app.ui.PageType
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.driverKind
import com.bucks.app.ui.formatDistance
import com.bucks.app.ui.kindLabel
import com.bucks.app.ui.list
import com.bucks.app.ui.proRate
import com.bucks.app.ui.screens.ProfileMediaHeader
import com.bucks.app.ui.screens.SignedImage
import com.bucks.app.ui.screens.ago
import com.bucks.app.ui.screens.commerce.CartSwitchDialog
import com.bucks.app.ui.shareText
import com.bucks.app.ui.str
import com.bucks.app.ui.theme.status
import kotlinx.coroutines.launch
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Details keys the About tab renders with a proper label; everything else gets a generic row. */
private val KNOWN_DETAILS = setOf("hours", "free_delivery", "delivery_radius_km", "delivery_radius_m", "rate", "level", "languages", "vehicle_kind", "vehicle", "kind", "model", "bio",
    "cod", "ships_india", "ship_fee", "free_ship_above", "dispatch_days", "delivery_time", "delivery_slot", "source", "mode", "price", "price_unit", "deposit", "area_sqft", "bedrooms", "furnishing", "available_from", "year", "km_driven", "negotiable",
    "registration", "affiliation", "org_type", "catalogue_label")
/** Team tab order: the owner first, then admins. Store riders are not shown on the public page. */
private val TEAM_ORDER = mapOf("OWNER" to 0, "ADMIN" to 1)

/** What a business page's tab is called: the type decides ("Services" or "Catalogue", "Gallery" / "Work" / "Campus", "Volunteer" for an NGO). */
/**
 * Every profile, whatever its kind or type, has the same five tabs in the same order. The fourth is the page's catalogue,
 * named by the owner ("Products", "Products & Services", "Courses & Events"); see [Catalogue].
 */
private fun profileTabs(cat: Catalogue) = listOf("feed" to Str.get(R.string.g3_lp_tab_feed), "about" to Str.get(R.string.g3_lp_tab_about), "photos" to Str.get(R.string.g3_lp_tab_gallery), "catalogue" to cat.label, "reviews" to Str.get(R.string.g3_lp_tab_reviews))
/** How many entries the catalogue holds across its kinds. */
private fun catalogueCount(p: ListingProfile, cat: Catalogue): Int = cat.kinds.sumOf { k -> kindRows(p, k).size }
private fun kindRows(p: ListingProfile, k: String): List<ItemRow> = when (k) { "PRODUCT" -> p.products; "SERVICE" -> p.services; "PROGRAM" -> p.programs; else -> p.events }

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
    val cat = PageTypes.catalogue(l)
    // Only a business page takes orders (the server checks the same: orders_module_guard).
    val sellsProducts = l.kind == "BUSINESS" && cat.sellsProducts
    val tabs = profileTabs(cat)
    // A page opens on its catalogue when it has something in it, else on About (a new page's Feed is often empty).
    var tab by rememberSaveable(id) { mutableStateOf(if (catalogueCount(p, cat) > 0 || l.kind == "ASSET" || l.kind == "DRIVER") "catalogue" else "about") }
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
    fun share() = shareText(ctx, listOfNotNull(l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(", ").let { if (it.isBlank()) Str.get(R.string.g3_lp_share, l.title) else Str.get(R.string.g3_lp_share_details, l.title, it) })
    fun message() = d.startListingChat(id, onOpenChat)
    // Shown only when the owner turned calls on; the number is fetched, never part of the page.
    var phone by remember(id) { mutableStateOf<String?>(null) }
    LaunchedEffect(id, l.details) { phone = if (!p.mine && l.details["show_phone"]?.toString()?.trim('"') == "true") Backend.listingPhone(id) else null }
    fun directions() { p.at?.let { at -> com.bucks.app.ui.screens.MapsPick.place = com.bucks.app.data.MapServices.PlaceHit(l.title, l.area, at); onMap() } }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            // The page's cover (until one is set, its first gallery photo) and its round picture; owners and admins change both here.
            val white = androidx.compose.ui.graphics.Color.White
            ProfileMediaHeader(vm, l.title, Backend.listingPhoto(l.photoUrl), l.coverUrl ?: l.gallery.firstOrNull()?.url,
                editable = p.mine, busy = d.mediaBusy?.takeIf { it.first == id }?.second,
                onPick = { slot, picked -> d.setListingPicture(id, slot, picked) }, onRemove = { d.clearListingPicture(id, it) },
                coverHeight = 140.dp, topStart = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g3_cd_back), tint = white) } },
                topEnd = { IconButton(onClick = { share() }) { Icon(Icons.Rounded.IosShare, stringResource(R.string.g3_cd_share), tint = white) } })
            Column(Modifier.padding(horizontal = Gutter, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(l.title, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (l.status == "LIVE") { Spacer(Modifier.width(6.dp)); Icon(Icons.Rounded.Verified, stringResource(R.string.g3_cd_verified_locals), Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary) }
                }
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    KindBadge(PageTypes.badge(l.kind, l.typeKey, ships), PageTypes.badgeIcon(l.kind, l.typeKey, ships))
                    if (l.category.isNotBlank()) Muted(l.category, maxLines = 1)
                    when (l.status) { "PENDING" -> PillWarn(stringResource(R.string.g3_lp_not_live)); "SUSPENDED" -> PillBad(stringResource(R.string.g3_listing_suspended)); else -> {} }
                }
                // Every page belongs to a real person: who runs it, and how far their identity has been checked.
                OwnerLine(vm, l, Modifier.padding(top = 4.dp))
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    OnlineDot(l.online); Spacer(Modifier.width(6.dp))
                    Muted(listOfNotNull(onlineText(l.kind, l.online), distance?.let { stringResource(R.string.g3_lp_away, it) }, l.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                }
                if (l.kind == "ASSET") Text(assetPrice(l.details), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
                Row(Modifier.padding(top = 10.dp)) { TrustBadge(trust) }
                // The catalogue count is the type's: products for a shop, services, programs or events for the others.
                val catalogueStat: Triple<Int, String, (() -> Unit)?>? = catalogueCount(p, cat).takeIf { it > 0 }?.let { n -> Triple(n, cat.label, { tab = "catalogue" }) }
                val openReviews: () -> Unit = { tab = "reviews" }
                StatsRow(listOfNotNull(Triple(p.syncs, stringResource(R.string.g3_lp_stat_synced), null), catalogueStat, Triple(l.trustUp, stringResource(R.string.g3_lp_tab_reviews), openReviews), (Triple(p.members, stringResource(R.string.g3_lp_stat_team), null)).takeIf { p.members > 1 }), Modifier.padding(top = 10.dp))
                val docCount by rememberShowcaseCount(id)
                docCount?.takeIf { it > 0 }?.let { n -> Box(Modifier.padding(top = 8.dp)) { Chip(pluralStringResource(R.plurals.g3_lp_documents, n, n), icon = Icons.Rounded.Description) { tab = "about" } } }
                if (!p.mine) Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RateButton(true, myDirect?.vote == 1, Modifier.weight(1f)) { rateVote = 1 }
                    RateButton(false, myDirect?.vote == -1, Modifier.weight(1f)) { rateVote = -1 }
                }
                if (!p.mine && l.kind == "BUSINESS") Muted(if (synced) stringResource(R.string.g3_lp_synced_note, l.title) else stringResource(R.string.g3_lp_sync_note, l.title), Modifier.padding(top = 6.dp))
                if (p.mine) Notice(stringResource(R.string.g3_lp_mine_note), Modifier.padding(top = 12.dp))
                else {
                    // The page's own action: Book, Get a quote, Volunteer, Join, Directions... A shop has none here; its cart lives in Products.
                    if (type != null && !type.isShop && type.cta != "CART" && (type.cta != "DIRECTIONS" || p.at != null)) PrimaryButton(type.ctaLabel, Modifier.padding(top = 12.dp), enabled = type.cta == "DIRECTIONS" || !d.chatStarting) {
                        if (type.cta == "DIRECTIONS") directions() else d.startListingChat(id, onOpenChat, PageTypes.ctaMessage(type, l.title))
                    }
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button({ message() }, Modifier.weight(1f).height(44.dp), enabled = !d.chatStarting, shape = MaterialTheme.shapes.small, contentPadding = PaddingValues(horizontal = 12.dp)) {
                            Icon(Icons.Rounded.Sms, null, Modifier.size(18.dp)); Text(stringResource(R.string.g3_lp_message), style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp)) }
                        SyncButton(synced, busy = id in d.syncing, Modifier.weight(1f)) { d.syncListing(id, !synced) }
                        phone?.let { num -> HeaderIcon(Icons.Rounded.Call, stringResource(R.string.g3_cd_call)) { com.bucks.app.ui.dial(ctx, num) } }
                        HeaderIcon(Icons.Rounded.IosShare, stringResource(R.string.g3_cd_share)) { share() }
                        if (!p.mine) com.bucks.app.ui.social.LocalReporter.current?.let { rep -> HeaderIcon(Icons.Rounded.OutlinedFlag, stringResource(R.string.g3_cd_report_page)) { rep(com.bucks.app.ui.social.ReportTarget("LISTING", id, l.ownerId, l.title)) } }
                        if (p.at != null) HeaderIcon(Icons.Rounded.Place, stringResource(R.string.g3_home_directions)) { directions() }
                        if (sellsProducts && cartHere && l.online) BadgedBox(badge = { Badge { Text("$cartCount") } }) { HeaderIcon(Icons.Rounded.ShoppingCart, stringResource(R.string.g3_cd_order), on = true, onClick = onCart) }
                    }
                }
                if (l.kind == "ASSET" && !p.mine) PrimaryButton(if (l.details.str("mode") == "SELL") stringResource(R.string.g3_lp_enquire_buy) else stringResource(R.string.g3_lp_enquire_rent), Modifier.padding(top = 12.dp), enabled = !d.chatStarting) {
                    d.startListingChat(id, onOpenChat, Str.get(R.string.g3_lp_msg_interested, l.title)) }
                if (l.kind == "DRIVER" && !p.mine) {
                    if (vk != null && vk.carriesPassengers) {
                        PrimaryButton(stringResource(R.string.g3_lp_book, vk.label.lowercase()), Modifier.padding(top = 12.dp)) { onBook(vk) }
                        Muted(stringResource(R.string.g3_lp_driver_note, vk.label.lowercase(), l.title.substringBefore(' ')), Modifier.padding(top = 6.dp))
                    } else Notice(stringResource(R.string.g3_lp_bike_note), Modifier.padding(top = 12.dp))
                }
            }
            val tabIndex = tabs.indexOfFirst { it.first == tabKey }.coerceAtLeast(0)
            // Five tabs on every page; long catalogue names scroll rather than truncate.
            val tabCells: @Composable () -> Unit = {
                tabs.forEach { (k, label) -> Tab(tabKey == k, onClick = { tab = k }, modifier = Modifier.height(48.dp), selectedContentColor = MaterialTheme.colorScheme.onSurface, unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant) {
                    Text(label, style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (tabKey == k) FontWeight.SemiBold else FontWeight.Normal), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp)) } }
            }
            ScrollableTabRow(tabIndex, containerColor = MaterialTheme.colorScheme.surface, edgePadding = Gutter,
                indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tabIndex]), height = 3.dp, color = MaterialTheme.colorScheme.primary) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }, tabs = tabCells)
            when (tabKey) {
                "catalogue" -> CatalogueTab(vm, p, type, cat, sellsProducts, vk, onMessage = { message() }, onCart = onCart, onOpenChat = onOpenChat, onBook = onBook)
                "feed" -> FeedTab(vm, p)
                "photos" -> GalleryTab(vm, l, p.mine)
                "about" -> { LaunchedEffect(p.listing.id) { vm.services.loadBadges(p.listing.id) }; AboutTab(p, type, vk, distance, onOpenListing, vm.services.badges[p.listing.id].orEmpty()); ShowcaseDocsSection(vm, id, p.mine, onManage = { onShowcaseDocs(id) })
                    // Team and openings sit in About on every page, so the five tabs stay the same everywhere.
                    if (l.kind == "BUSINESS" && (p.members >= 2 || p.mine) && type?.tabs?.contains("team") != false) { SectionTitle(stringResource(R.string.g3_lp_stat_team), Modifier.padding(start = Gutter, end = Gutter, top = 8.dp)); TeamTab(vm, p) }
                    if (l.kind == "BUSINESS" && (p.openJobs > 0 || (p.mine && type?.tabs?.contains("jobs") == true))) JobsTab(p, volunteer = type?.key == "NGO_CHARITY") { onJobs(id) } }
                "reviews" -> ReviewsTab(vm, p, myDirect) { rateVote = it }
            }
            Spacer(Modifier.height(24.dp))
        }
        if (sellsProducts && l.online && cartCount > 0 && tabKey == "catalogue") DarkButton(pluralStringResource(R.plurals.g3_lp_view_cart, cartCount, cartCount), Modifier.align(Alignment.BottomCenter).padding(Gutter), onClick = onCart)
    }
    // Commerce: asks "Start a new cart?" when an item from a second shop is added (vm.commerce.pendingSwitch).
    CartSwitchDialog(vm)
}

/** While the profile loads, when the listing isn't there (missing), or when the load itself failed (offline, server error). */
@Composable
private fun ProfilePlaceholder(vm: BucksViewModel, id: String, onBack: () -> Unit) {
    val d = vm.discover
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g3_lp_listing), onBack = onBack)
        if (id !in d.missing && id !in d.failed) { ProfileSkeleton(); return@ContentColumn }
        Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            when {
                id in d.missing -> {
                    Icon(Icons.Rounded.SearchOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.g3_lp_missing), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                    Muted(stringResource(R.string.g3_lp_missing_body), Modifier.padding(top = 6.dp), align = TextAlign.Center)
                    SmallButton(stringResource(R.string.g3_try_again), Modifier.padding(top = 14.dp), tonal = true) { d.open(id) }
                    TextButton(onBack) { Text(stringResource(R.string.g3_back)) }
                }
                id in d.failed -> {
                    Icon(Icons.Rounded.CloudOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.g3_lp_failed), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                    Muted(stringResource(R.string.g3_check_connection), Modifier.padding(top = 6.dp), align = TextAlign.Center)
                    SmallButton(stringResource(R.string.g3_try_again), Modifier.padding(top = 14.dp), tonal = true) { d.open(id) }
                    TextButton(onBack) { Text(stringResource(R.string.g3_back)) }
                }
                else -> {}
            }
        }
    }
}

/** Cover band (primary gradient), back and share on top, the photo or initials overlapping the bottom edge. */
@Composable
private fun SyncButton(synced: Boolean, busy: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) =
    Row(modifier.minimumInteractiveComponentSize().height(44.dp).clip(MaterialTheme.shapes.small).background(if (synced) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(enabled = !busy, onClick = onClick).padding(horizontal = 12.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        val c = if (synced) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface
        if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = c) else Icon(if (synced) Icons.Rounded.Check else Icons.Rounded.Sync, null, Modifier.size(18.dp), tint = c)
        Text(if (synced) stringResource(R.string.g3_lp_stat_synced) else stringResource(R.string.g3_lp_sync), style = MaterialTheme.typography.labelLarge, color = c, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp))
    }

/** Numbers under the name: synced, products, recommendations (opens Reviews) and team size. A stat with an action is tappable. */
@Composable
private fun StatsRow(stats: List<Triple<Int, String, (() -> Unit)?>>, modifier: Modifier = Modifier) = Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
    stats.forEach { (n, label, go) ->
        val seeLabel = stringResource(R.string.g3_lp_see, label); val cd = stringResource(R.string.g3_lp_stat_cd, n.toString(), label)
        Column(Modifier.then(if (go != null) Modifier.clip(MaterialTheme.shapes.small).clickable(onClickLabel = seeLabel, onClick = go) else Modifier).semantics(mergeDescendants = true) { contentDescription = cd }) {
            Text("%,d".format(n), style = MaterialTheme.typography.titleMedium); Muted(label, maxLines = 1) }
    }
}

private fun friendly(e: Throwable) = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message ?: "")?.groupValues?.get(1) ?: Str.get(R.string.g3_lp_send_failed)

/** Recommend / not recommend button; filled when it is my current vote. */
@Composable
private fun RateButton(up: Boolean, mine: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val st = MaterialTheme.status; val c = if (up) st.good else st.bad
    OutlinedButton(onClick, modifier.heightIn(min = 44.dp), shape = MaterialTheme.shapes.small, contentPadding = PaddingValues(horizontal = 10.dp),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (mine) c.copy(alpha = 0.14f) else androidx.compose.ui.graphics.Color.Transparent, contentColor = c)) {
        Icon(if (up) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (up) stringResource(R.string.g3_cd_recommend) else stringResource(R.string.g3_cd_not_recommend), Modifier.size(22.dp))
    }
}

/** Comment box that opens on a recommend / not recommend tap; the vote and comment land in the Reviews tab. Works for shops, pros, assets and drivers. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecommendSheet(vm: BucksViewModel, l: ListingRow, mine: ReviewRow?, initial: Int, onDone: () -> Unit, onDismiss: () -> Unit) {
    var vote by remember { mutableStateOf(initial) }
    var text by remember { mutableStateOf(mine?.comment.orEmpty()) }; var reason by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope(); val st = MaterialTheme.status
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(if (mine != null) stringResource(R.string.g3_lp_rec_yours, l.title) else stringResource(R.string.g3_lp_rec_ask, l.title), style = MaterialTheme.typography.titleLarge)
            Muted(stringResource(R.string.g3_lp_rec_public), Modifier.padding(top = 4.dp))
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RateButton(true, vote == 1, Modifier.weight(1f)) { vote = 1 }
                RateButton(false, vote == -1, Modifier.weight(1f)) { vote = -1 }
            }
            if (vote < 0) { Text(stringResource(R.string.g3_lp_rec_wrong), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 14.dp, bottom = 6.dp)); ReasonChips(reason) { reason = it } }
            OutlinedTextField(text, { text = it.take(500) }, Modifier.padding(top = 12.dp).fillMaxWidth(), placeholder = { Text(if (vote > 0) stringResource(R.string.g3_lp_rec_liked) else stringResource(R.string.g3_lp_rec_more)) }, minLines = 3, maxLines = 6, supportingText = { Text("${text.length}/500") })
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button({ scope.launch { busy = true
                    runCatching { Backend.rateListing(l.id, vote, text.trim(), if (vote < 0) reason else null) }.onSuccess { vm.toast(Str.get(R.string.g3_lp_rec_posted)); onDone() }.onFailure { vm.toast(friendly(it)) }
                    busy = false } }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(if (busy) stringResource(R.string.g3_sending) else if (mine != null) stringResource(R.string.g3_lp_update) else stringResource(R.string.g3_lp_submit)) }
                if (mine != null) TextButton({ scope.launch { busy = true
                    runCatching { Backend.clearListingRating(l.id) }.onSuccess { vm.toast(Str.get(R.string.g3_lp_rec_removed)); onDone() }.onFailure { vm.toast(friendly(it)) }
                    busy = false } }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(stringResource(R.string.g3_lp_remove_mine), color = st.bad) }
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

/** Open jobs, or volunteer roles on an NGO page ([volunteer]); the card opens the listing's jobs. */
@Composable
private fun JobsTab(p: ListingProfile, volunteer: Boolean = false, onJobs: () -> Unit) = Column(Modifier.padding(Gutter)) {
    BucksCard(onClick = onJobs) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(if (volunteer) Icons.Rounded.Favorite else Icons.Rounded.Work, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(if (volunteer) stringResource(R.string.g3_lp_volunteer_with, p.listing.title) else stringResource(R.string.g3_lp_jobs_at, p.listing.title), style = MaterialTheme.typography.titleMedium)
                Muted(when {
                    p.openJobs > 0 && volunteer -> pluralStringResource(R.plurals.g3_lp_open_roles, p.openJobs, p.openJobs)
                    p.openJobs > 0 -> pluralStringResource(R.plurals.g3_lp_openings, p.openJobs, p.openJobs)
                    volunteer -> stringResource(R.string.g3_lp_volunteer_empty)
                    else -> stringResource(R.string.g3_lp_jobs_empty)
                })
            }
            Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (p.mine) Muted(if (volunteer) stringResource(R.string.g3_lp_jobs_mine_volunteer) else stringResource(R.string.g3_lp_jobs_mine), Modifier.padding(top = 10.dp))
}

/* ---------- The catalogue tab: whatever the page lists, under the name its owner gave it ---------- */

/**
 * The fourth tab of every profile. A page's catalogue holds one or more kinds (products, services, programs, events) in that order;
 * with more than one, each gets a heading and visitors see only the ones with entries. An asset shows its price, a driver their rides.
 */
@Composable
private fun CatalogueTab(vm: BucksViewModel, p: ListingProfile, type: PageType?, cat: Catalogue, sellsProducts: Boolean, vk: VehicleKind?,
                         onMessage: () -> Unit, onCart: () -> Unit, onOpenChat: (String) -> Unit, onBook: (VehicleKind) -> Unit) {
    val l = p.listing; val det = l.details
    when {
        l.kind == "ASSET" -> Column(Modifier.padding(Gutter)) {
            Text(assetPrice(det), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.primary)
            det.str("deposit")?.toDoubleOrNull()?.takeIf { it > 0 }?.let { AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_deposit), inr(it.toLong())) }
            if (det.str("negotiable") == "true") AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_price), stringResource(R.string.g3_lp_negotiable))
            if (!p.mine) SmallButton(stringResource(R.string.g3_lp_ask), Modifier.padding(top = 14.dp), tonal = true, onClick = onMessage)
        }
        l.kind == "DRIVER" -> Column(Modifier.padding(Gutter)) {
            AboutRow(vk?.icon ?: Icons.Rounded.DirectionsCar, stringResource(R.string.g3_lp_vehicle), listOfNotNull(vk?.label, det.str("model")).joinToString(" · ").ifBlank { stringResource(R.string.g3_lp_not_shared) })
            vk?.let { AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_fare), fareLine(it)) }
            if (!p.mine && vk != null && vk.carriesPassengers) PrimaryButton(stringResource(R.string.g3_lp_book, vk.label.lowercase()), Modifier.padding(top = 14.dp)) { onBook(vk) }
        }
        cat.kinds.isEmpty() -> Muted(if (p.mine) stringResource(R.string.g3_lp_cat_mine_empty) else stringResource(R.string.g3_lp_cat_empty), Modifier.padding(Gutter))
        else -> Column {
            val many = cat.kinds.size > 1
            val shown = if (many && !p.mine) cat.kinds.filter { kindRows(p, it).isNotEmpty() }.ifEmpty { listOf(cat.kinds.first()) } else cat.kinds
            shown.forEach { k ->
                if (many) SectionTitle(PageTypes.kindPlural(k), Modifier.padding(start = Gutter, end = Gutter, top = 12.dp))
                when (k) {
                    "PRODUCT" -> if (sellsProducts) StoreProducts(vm, p, onMessage = onMessage, onCart = onCart)
                    "SERVICE" -> ServicesTab(vm, p, type, onOpenChat)
                    "PROGRAM" -> ProgramsTab(vm, p, type, "PROGRAM", onOpenChat)
                    else -> ProgramsTab(vm, p, type, "EVENT", onOpenChat)
                }
            }
        }
    }
}

/* ---------- Services (a pro, or a service / company / hospital page), programs, events, team ---------- */

/** The type's message for its primary action with one catalogue entry named at the end: "Hi, I'd like to book with X. When are you free? Service: Haircut". */
private fun itemMessage(t: PageType, title: String, noun: String, name: String): String {
    val base = PageTypes.ctaMessage(t, title).trim().trimEnd(':').trimEnd()
    return base + (if (base.endsWith('?') || base.endsWith('.')) "" else ".") + " " + Str.get(R.string.g3_lp_item_line, noun.replaceFirstChar { it.uppercase() }, name)
}

/**
 * Services with prices and a button per row. For a pro ([type] null) the button requests a visit; on a business page it says
 * what the type does (Book, Get quote, Enquire) and opens the chat with the type's message.
 */
@Composable
private fun ServicesTab(vm: BucksViewModel, p: ListingProfile, type: PageType?, onOpenChat: (String) -> Unit) {
    val d = vm.discover; val l = p.listing; val services = p.services; val first = l.title.substringBefore(' ')
    val min = services.filter { it.price > 0 }.minOfOrNull { it.price }
    val action = when (type?.cta) { null -> stringResource(R.string.g3_lp_act_request); "BOOK" -> stringResource(R.string.g3_lp_act_book); "QUOTE" -> stringResource(R.string.g3_lp_act_quote); "HIRE" -> stringResource(R.string.g3_lp_act_hire); else -> stringResource(R.string.g3_lp_act_enquire) }
    Column(Modifier.padding(Gutter)) {
        val rate = if (type == null) proRate(l.details, min) else min?.let { stringResource(R.string.g3_lp_from, inr(it.toLong())) } ?: if (type.cta == "QUOTE") stringResource(R.string.g3_lp_quotes_on_request) else stringResource(R.string.g3_lp_prices_on_request)
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Payments, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Text(rate, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp)) }
        if (services.isEmpty()) {
            Muted(when {
                p.mine -> stringResource(R.string.g3_lp_svc_mine_empty)
                type != null -> stringResource(R.string.g3_lp_svc_empty_page, l.title)
                else -> stringResource(R.string.g3_lp_svc_empty_pro, first)
            }, Modifier.padding(top = 8.dp))
            if (!p.mine) {
                if (type != null) PrimaryButton(type.ctaLabel, Modifier.padding(top = 14.dp), enabled = !d.chatStarting) { d.startListingChat(l.id, onOpenChat, PageTypes.ctaMessage(type, l.title)) }
                else PrimaryButton(stringResource(R.string.g3_lp_request_visit), Modifier.padding(top = 14.dp), enabled = !d.chatStarting) { d.startListingChat(l.id, onOpenChat, l.category.ifBlank { null }?.let { Str.get(R.string.g3_lp_msg_need_help, it.lowercase()) } ?: Str.get(R.string.g3_lp_msg_need_help_job)) }
            }
        } else {
            Column(Modifier.padding(top = 8.dp)) {
                services.forEachIndexed { i, s ->
                    if (i > 0) Divider()
                    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(s.name, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis); Muted(servicePrice(s), maxLines = 1)
                            if (s.description.isNotBlank()) Muted(s.description, maxLines = 2) }
                        if (!p.mine) SmallButton(action, tonal = true, enabled = !d.chatStarting) {
                            d.startListingChat(l.id, onOpenChat, if (type != null) itemMessage(type, l.title, Str.get(R.string.g3_lp_noun_service), s.name)
                                else Str.get(R.string.g3_lp_msg_request, s.name, Money.format(s.price) + if (s.unit.isNotBlank()) " " + s.unit else "")) }
                    }
                }
            }
            if (!p.mine) Notice(if (type != null) stringResource(R.string.g3_lp_svc_note, action, l.title) else stringResource(R.string.g3_lp_svc_note_pro, action, first), Modifier.padding(top = 14.dp))
        }
    }
}

/**
 * Programs (an NGO, a school) or events (a group, an association, a place of worship): name, price or Free, unit, description,
 * and Enquire / Join, which opens the chat with the type's message and the entry's name.
 */
@Composable
private fun ProgramsTab(vm: BucksViewModel, p: ListingProfile, type: PageType?, kind: String, onOpenChat: (String) -> Unit) {
    val d = vm.discover; val l = p.listing
    val events = kind == "EVENT"
    val rows = if (events) p.events else p.programs
    val noun = if (events) stringResource(R.string.g3_lp_noun_event) else stringResource(R.string.g3_lp_noun_program)
    val action = if (events) stringResource(R.string.g3_lp_act_join) else stringResource(R.string.g3_lp_act_enquire)
    val icon = if (events) Icons.Rounded.CalendarMonth else Icons.Rounded.Favorite
    Column(Modifier.padding(Gutter)) {
        if (rows.isEmpty()) {
            Muted(if (p.mine) { if (events) stringResource(R.string.g3_lp_events_mine_empty) else stringResource(R.string.g3_lp_programs_mine_empty) } else { if (events) stringResource(R.string.g3_lp_events_empty, l.title) else stringResource(R.string.g3_lp_programs_empty, l.title) })
            if (!p.mine) SmallButton(stringResource(R.string.g3_lp_message), Modifier.padding(top = 12.dp), tonal = true) { d.startListingChat(l.id, onOpenChat) }
        } else {
            rows.forEachIndexed { i, s ->
                if (i > 0) Divider()
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer) }
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text(s.name, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Muted(programPrice(s), maxLines = 1)
                        if (s.description.isNotBlank()) Muted(s.description, Modifier.padding(top = 2.dp), maxLines = 3)
                    }
                    if (!p.mine) SmallButton(action, tonal = true) {
                        d.startListingChat(l.id, onOpenChat, if (type != null) itemMessage(type, l.title, noun, s.name) else Str.get(R.string.g3_lp_msg_know_more, l.title, s.name)) }
                }
            }
            if (p.mine) Muted(if (events) stringResource(R.string.g3_lp_events_mine) else stringResource(R.string.g3_lp_programs_mine), Modifier.padding(top = 10.dp))
            else Notice(stringResource(R.string.g3_lp_prog_note, action, l.title), Modifier.padding(top = 14.dp))
        }
    }
}

/** "Free", or "₹500 · per month", with a date or duration when the owner gave one. */
private fun programPrice(s: ItemRow): String = listOfNotNull(if (s.price <= 0) Str.get(R.string.g3_lp_free) else inr(s.price.toLong()), s.unit.ifBlank { null },
    s.details.str("date") ?: s.details.str("schedule"), s.details.str("duration")?.let { Str.get(R.string.g3_lp_about_duration, it) }).joinToString(" · ")

private fun teamRole(role: String) = when (role) { "OWNER" -> Str.get(R.string.g3_lp_role_owner); "ADMIN" -> Str.get(R.string.g3_lp_role_admin); else -> Str.get(R.string.g3_lp_role_member) }

/** "₹12 per km, plus ₹20 base fare" in the person's currency; bikes add "parcels only". */
private fun fareLine(k: VehicleKind) = if (k.carriesPassengers) Str.get(R.string.g3_lp_fare_line, Money.format(k.farePerKm), Money.format(20)) else Str.get(R.string.g3_lp_fare_line_parcels, Money.format(k.farePerKm), Money.format(20))

/** Who runs the page: owner and admins from listing_members (readable by everyone), with their names; store riders stay off the public page. */
@Composable
private fun TeamTab(vm: BucksViewModel, p: ListingProfile) {
    val social = vm.social; val l = p.listing; val meId = social.me?.id
    var rows by remember(l.id) { mutableStateOf<List<MemberRow>?>(null) }
    var failed by remember(l.id) { mutableStateOf(false) }
    LaunchedEffect(l.id) {
        val got = runCatching { Backend.publicMembers(l.id) }.getOrNull()
        if (got == null) failed = true
        else {
            runCatching { social.namesFor(got.map { it.profileId }) }
            rows = got.filter { it.role != "STORE_RIDER" }.sortedWith(compareBy({ TEAM_ORDER[it.role] ?: 9 }, { social.nameOf(it.profileId).lowercase() }))
        }
    }
    Column(Modifier.padding(Gutter)) {
        val list = rows
        when {
            list == null && !failed -> Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { repeat(3) { Row { SkeletonBox(Modifier.size(40.dp), CircleShape); SkeletonLines(2, Modifier.padding(start = 12.dp).weight(1f)) } } }
            list == null -> Muted(stringResource(R.string.g3_lp_team_failed))
            list.isEmpty() -> Muted(if (p.mine) stringResource(R.string.g3_lp_team_mine_empty) else stringResource(R.string.g3_lp_team_empty, l.title))
            else -> list.forEachIndexed { i, m ->
                if (i > 0) Divider()
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(social.nameOf(m.profileId)).ifBlank { "?" }, size = 40)
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        Text(if (m.profileId == meId) stringResource(R.string.g3_lp_you_suffix, social.nameOf(m.profileId)) else social.nameOf(m.profileId), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Muted(teamRole(m.role), maxLines = 1)
                    }
                }
            }
        }
        if (p.mine) Muted(stringResource(R.string.g3_lp_team_mine), Modifier.padding(top = 10.dp))
    }
}

@Composable
private fun FeedTab(vm: BucksViewModel, p: ListingProfile) {
    if (p.posts.isEmpty()) { Muted(if (p.mine) stringResource(R.string.g3_lp_feed_mine_empty, p.listing.title) else stringResource(R.string.g3_lp_feed_empty, p.listing.title), Modifier.padding(Gutter)); return }
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

/** [type]: the page type of a business (shop rows like delivery and shipping show only for shops; the others show registration details). */
@Composable
private fun AboutTab(p: ListingProfile, type: PageType?, vk: VehicleKind?, distance: String?, onOpenListing: (String) -> Unit, badges: List<com.bucks.app.data.BadgeRow> = emptyList()) = Column {
    val l = p.listing; val det = l.details
    Column(Modifier.padding(Gutter)) {
        if (l.description.isNotBlank()) Text(l.description, style = MaterialTheme.typography.bodyMedium) else Muted(stringResource(R.string.g3_lp_no_description))
        AboutRow(Icons.Rounded.LocationOn, stringResource(R.string.g3_lp_area), listOfNotNull(l.area.ifBlank { null }, distance?.let { stringResource(R.string.g3_lp_from_you, it) }).joinToString(" · ").ifBlank { stringResource(R.string.g3_lp_not_shared) })
        if (l.category.isNotBlank()) AboutRow(Icons.Rounded.Category, stringResource(R.string.g3_lp_category), l.category)
        when (l.kind) {
            "BUSINESS" -> {
                det.str("hours")?.let { AboutRow(Icons.Rounded.Schedule, stringResource(R.string.g3_lp_hours), it) }
                if (type == null || type.isShop) {
                    det.str("free_delivery")?.let { AboutRow(Icons.Rounded.DeliveryDining, stringResource(R.string.g3_mode_delivery), if (it == "true") stringResource(R.string.g3_lp_free_delivery) else stringResource(R.string.g3_lp_delivery_charged)) }
                    (det.str("delivery_radius_km")?.let { stringResource(R.string.g3_dt_km, it) } ?: det.str("delivery_radius_m")?.toDoubleOrNull()?.let { formatDistance(it) })?.let { AboutRow(Icons.Rounded.MyLocation, stringResource(R.string.g3_lp_delivers_within), it) }
                    com.bucks.app.ui.DeliveryTimes.summary(l.details)?.let { AboutRow(Icons.Rounded.Timer, stringResource(R.string.g7_dtime_label), it) }
                    if (det.str("ships_india") == "true") {
                        val fee = det.str("ship_fee")?.toIntOrNull() ?: 0; val above = det.str("free_ship_above")?.toIntOrNull() ?: 0
                        AboutRow(Icons.Rounded.LocalShipping, stringResource(R.string.g3_lp_ships_india), listOfNotNull(if (fee == 0) stringResource(R.string.g3_lp_free_shipping) else stringResource(R.string.g3_lp_shipping, inr(fee.toLong())), if (fee > 0 && above > 0) stringResource(R.string.g3_lp_free_above, inr(above.toLong())) else null,
                            det.str("dispatch_days")?.let { stringResource(R.string.g3_lp_ships_in, it) }, if (det.str("cod") == "true") stringResource(R.string.g3_lp_cod) else null).joinToString(" · "))
                    }
                }
                // Organisations: what they are registered as, who they are affiliated to (a school's board, a college's university).
                det.str("org_type")?.let { AboutRow(Icons.Rounded.Apartment, stringResource(R.string.g3_lp_org_type), it) }
                det.str("registration")?.let { AboutRow(Icons.Rounded.Description, stringResource(R.string.g3_doc_registration), it) }
                det.str("affiliation")?.let { AboutRow(Icons.Rounded.WorkspacePremium, stringResource(R.string.g3_doc_affiliation), it) }
            }
            "SKILL" -> {
                AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_rate), proRate(det, p.services.minOfOrNull { it.price }))
                det.str("level")?.let { AboutRow(Icons.Rounded.WorkspacePremium, stringResource(R.string.g3_lp_experience), it.lowercase().replaceFirstChar { c -> c.uppercase() }) }
                det.list("languages").takeIf { it.isNotEmpty() }?.let { AboutRow(Icons.Rounded.Language, stringResource(R.string.g3_lp_languages), it.joinToString(", ")) }
            }
            "ASSET" -> {
                AboutRow(Icons.Rounded.Apartment, stringResource(R.string.g3_lp_listing), assetPrice(det))
                det.str("deposit")?.toDoubleOrNull()?.takeIf { it > 0 }?.let { AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_deposit), inr(it.toLong())) }
                det.str("area_sqft")?.let { AboutRow(Icons.Rounded.Category, stringResource(R.string.g3_lp_size), stringResource(R.string.g3_lp_sqft, it)) }
                det.str("bedrooms")?.let { AboutRow(Icons.Rounded.Home, stringResource(R.string.g3_lp_bedrooms), it) }
                det.str("furnishing")?.let { AboutRow(Icons.Rounded.Chair, stringResource(R.string.g3_lp_furnishing), it) }
                det.str("available_from")?.let { AboutRow(Icons.Rounded.CalendarMonth, stringResource(R.string.g3_lp_available_from), it) }
                det.str("year")?.let { AboutRow(Icons.Rounded.CalendarMonth, stringResource(R.string.g3_lp_year), it) }
                det.str("km_driven")?.let { AboutRow(Icons.Rounded.DirectionsCar, stringResource(R.string.g3_lp_driven), stringResource(R.string.g3_dt_km, it)) }
                if (det.str("negotiable") == "true") AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_price), stringResource(R.string.g3_lp_negotiable))
            }
            "DRIVER" -> {
                AboutRow(vk?.icon ?: Icons.Rounded.DirectionsCar, stringResource(R.string.g3_lp_vehicle), listOfNotNull(vk?.label, det.str("model")).joinToString(" · ").ifBlank { stringResource(R.string.g3_lp_not_shared) })
                vk?.let { AboutRow(Icons.Rounded.Payments, stringResource(R.string.g3_lp_fare), fareLine(it)) }
                det.list("languages").takeIf { it.isNotEmpty() }?.let { AboutRow(Icons.Rounded.Language, stringResource(R.string.g3_lp_languages), it.joinToString(", ")) }
                det.str("bio")?.let { AboutRow(Icons.Rounded.Person, stringResource(R.string.g3_lp_tab_about), it) }
            }
        }
        // Anything else the owner filled in, as a labelled row: "delivery_note" -> "Delivery note".
        det.entries.filter { (k, v) -> k !in KNOWN_DETAILS && v is JsonPrimitive }.forEach { (k, _) ->
            det.str(k)?.let { v -> AboutRow(Icons.Rounded.Info, k.replace('_', ' ').replaceFirstChar { c -> c.uppercase() }, when (v) { "true" -> stringResource(R.string.g3_yes); "false" -> stringResource(R.string.g3_no); else -> v }) }
        }
        // Checked documents: a tick for each, with the number only where the law wants customers to see it (FSSAI, GST, RERA).
        // The files themselves are private to the owner and Bucks.
        badges.forEach { b -> AboutRow(Icons.Rounded.VerifiedUser, b.label, listOfNotNull(b.number.ifBlank { null }, stringResource(R.string.g3_lp_checked_by_bucks), b.expiresOn?.let { stringResource(R.string.g3_lp_valid_till, humanDate(it)) }).joinToString(" · ")) }
        AboutRow(Icons.Rounded.Verified, stringResource(R.string.g3_lp_status), when (l.status) { "LIVE" -> pluralStringResource(R.plurals.g3_lp_status_live, p.recommendations, p.recommendations); "PENDING" -> stringResource(R.string.g3_lp_status_pending, p.recommendations, com.bucks.app.ui.MyListings.NEEDED); else -> stringResource(R.string.g3_listing_suspended) })
    }
    if (p.similar.isNotEmpty()) {
        Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
        SectionTitle(stringResource(R.string.g3_lp_more_nearby), Modifier.padding(start = Gutter, end = Gutter, top = 16.dp, bottom = 4.dp))
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
        if (total > 0) Muted("  " + pluralStringResource(R.plurals.g3_lp_people, total, total))
    }
    if (p.mine) Muted(stringResource(R.string.g3_lp_reviews_mine), Modifier.padding(top = 8.dp))
    else Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        VoteArrow(true, mine?.vote == 1, Modifier.weight(1f)) { onWrite(1) }; VoteArrow(false, mine?.vote == -1, Modifier.weight(1f)) { onWrite(-1) } }
    if (p.reviews.isEmpty()) Muted(if (p.mine) stringResource(R.string.g3_lp_no_votes) else stringResource(R.string.g3_lp_reviews_empty, l.title), Modifier.padding(vertical = 16.dp))
    p.reviews.forEach { r ->
        val up = r.vote > 0
        Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.Top) {
            Avatar(initials(vm.social.nameOf(r.authorId)).ifBlank { "?" }, size = 40)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(vm.social.nameOf(r.authorId), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)); Muted("  ${ago(r.createdAt)}") }
                if (r.comment.isNotBlank()) Text(r.comment, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 2.dp))
                else Muted(if (up) stringResource(R.string.g3_lp_rec_no_comment) else stringResource(R.string.g3_lp_notrec_no_comment), Modifier.padding(top = 2.dp))
                r.reason?.let { code -> VOTE_REASONS.firstOrNull { it.first == code }?.let { Text(it.second, style = MaterialTheme.typography.labelSmall, color = st.bad, modifier = Modifier.padding(top = 4.dp)) } }
                if (r.verified) Text(if (r.orderId != null) stringResource(R.string.g3_lp_verified_customer) else stringResource(R.string.g3_lp_verified_rider), style = MaterialTheme.typography.labelSmall, color = st.good, modifier = Modifier.padding(top = 4.dp))
            }
            Column(horizontalAlignment = Alignment.End) {
                Icon(if (up) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (up) stringResource(R.string.g3_cd_recommends) else stringResource(R.string.g3_cd_not_recommends), Modifier.size(20.dp), tint = if (up) st.good else st.bad)
                if (r.authorId != vm.social.me?.id && r.comment.isNotBlank()) com.bucks.app.ui.social.LocalReporter.current?.let { rep ->
                    IconButton({ rep(com.bucks.app.ui.social.ReportTarget("REVIEW", r.id, r.authorId, vm.social.nameOf(r.authorId))) }, Modifier.size(40.dp)) {
                        Icon(Icons.Rounded.OutlinedFlag, stringResource(R.string.g3_cd_report_rec), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) } }

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
    val money = when { pricing == "QUOTE" && s.price == 0 -> Str.get(R.string.g3_lp_price_on_quote); pricing == "FROM" -> Str.get(R.string.g3_lp_from, inr(s.price.toLong())); pricing == "QUOTE" -> Str.get(R.string.g3_lp_usually, inr(s.price.toLong())); else -> inr(s.price.toLong()) }
    return listOfNotNull(money, s.unit.ifBlank { null } ?: when (pricing) { "HOURLY" -> Str.get(R.string.g3_lp_per_hour); "VISIT" -> Str.get(R.string.g3_lp_per_visit); else -> null }, s.details.str("duration")?.let { Str.get(R.string.g3_lp_about_duration, it) }).joinToString(" · ")
}

/** A listing's photos (portfolio for a pro, gallery or campus for a page) in a grid; tap for full size with the caption. Owners see a hint when it is empty. */
@Composable
private fun GalleryTab(vm: BucksViewModel, l: ListingRow, mine: Boolean = false) {
    var open by remember { mutableStateOf<Int?>(null) }
    val g = l.gallery
    Column(Modifier.padding(Gutter)) {
        if (g.isEmpty()) Muted(if (mine) stringResource(R.string.g3_lp_gallery_mine_empty) else stringResource(R.string.g3_lp_gallery_empty, l.title))
        g.chunked(3).forEachIndexed { row, photos ->
            Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                photos.forEachIndexed { i, ph ->
                    AsyncImage(ph.url, ph.caption.ifBlank { null }, Modifier.weight(1f).aspectRatio(1f).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable { open = row * 3 + i }, contentScale = ContentScale.Crop)
                }
                repeat(3 - photos.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    open?.let { i -> com.bucks.app.ui.MediaViewer(vm, g.map { com.bucks.app.ui.ViewerMedia.Url(it.url, caption = it.caption) }, start = i, title = l.title) { open = null } }
}
