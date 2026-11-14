package com.bucks.app.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import coil.compose.AsyncImage
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Chair
import androidx.compose.material.icons.rounded.Devices
import androidx.compose.material.icons.rounded.ShoppingBasket
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status

private val PROFILE_TABS = listOf("feed" to R.string.g4_prov_tab_feed, "about" to R.string.g4_prov_tab_about, "items" to R.string.g4_prov_tab_products, "votes" to R.string.g4_prov_tab_recommendations)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProviderScreen(vm: BucksViewModel, id: String, initialTab: String, onBack: () -> Unit, onRequest: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, onCart: () -> Unit, onMessages: () -> Unit) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState(); val posts by vm.repo.posts.collectAsState(); val chats by vm.repo.chats.collectAsState()
    val p = providers.firstOrNull { it.id == id } ?: return
    val ctx = LocalContext.current
    val tabs = if (p.type == ProviderType.BUSINESS) PROFILE_TABS else PROFILE_TABS.map { if (it.first == "items") "services" to R.string.g4_prov_tab_services else it }
    var tab by remember { mutableStateOf(when (initialTab) { "" -> if (p.type == ProviderType.BUSINESS && p.items.isNotEmpty()) "items" else "about"; "about", "feed", "votes", "services" -> initialTab; "items" -> if (p.type == ProviderType.BUSINESS) "items" else "services"; else -> "items" }.let { t -> if (tabs.any { it.first == t }) t else tabs[2].first }) }
    var voteSheet by remember { mutableStateOf<Boolean?>(null) }; var comment by remember { mutableStateOf("") }; var howRanked by remember { mutableStateOf(false) }; var comments by remember { mutableStateOf<String?>(null) }
    val lensTrust = vm.trustFor(p); val variant = variantFor(p.category)
    val followed = p.id in s.followedProviders
    val cartCount = s.cart.filterKeys { it.startsWith("${p.id}:") }.values.sum()
    Box(Modifier.fillMaxSize()) { Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        // Compact header for businesses and individuals alike: avatar, name once, trust badge (opens the ranking explainer), one action row.
        val skill = p.type == ProviderType.SKILL
        BucksTopBar(onBack = onBack, unread = vm.unreadCount(chats), onChat = onMessages)
        Column(Modifier.padding(horizontal = Gutter, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (skill) Avatar(initials(p.name), size = 64) else Avatar(icon = categoryIcon(p.category), size = 64)
                Column(Modifier.weight(1f).padding(start = 14.dp)) {
                    Text(p.name, style = MaterialTheme.typography.headlineSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Muted(if (skill) stringResource(R.string.g4_prov_meta_skill, p.category, Geo.nearestArea(p.pos), p.distanceKm.toString()) else stringResource(R.string.g4_prov_meta_business, Geo.nearestArea(p.pos), p.distanceKm.toString()), Modifier.padding(top = 2.dp))
                }
            }
            Row(Modifier.padding(top = 4.dp)) { TrustBadge(lensTrust) { howRanked = true } }
            // One weighted main action plus 48dp icon buttons, so the row fits 360dp phones and large font scales.
            Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (skill) { Button(onRequest, Modifier.weight(1f).height(44.dp), shape = MaterialTheme.shapes.small, contentPadding = PaddingValues(horizontal = 14.dp)) { Text(stringResource(R.string.g4_prov_book_visit), style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    HeaderIcon(if (followed) Icons.Rounded.HowToReg else Icons.Rounded.PersonAddAlt, if (followed) stringResource(R.string.g4_prov_following) else stringResource(R.string.g4_prov_follow), on = followed) { vm.followProvider(p.id) } }
                else FollowButton(followed, Modifier.weight(1f)) { vm.followProvider(p.id) }
                HeaderIcon(Icons.Rounded.Call, stringResource(R.string.g4_prov_call)) { onCall(p.name, p.phone) }
                HeaderIcon(Icons.Rounded.Sms, stringResource(R.string.g4_profile_message)) { onChatWith(p.name, p.category) }
            }
        }
        // Fixed tabs: all four always fit and the divider spans the full width. Content-slot Tabs skip the 16dp text padding so "Products" fits a 90dp tab on 360dp phones.
        val tabIndex = tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0)
        TabRow(tabIndex, containerColor = MaterialTheme.colorScheme.surface,
            indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tabIndex]), height = 3.dp, color = MaterialTheme.colorScheme.primary) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
            tabs.forEach { (k, l) -> Tab(tab == k, onClick = { tab = k }, modifier = Modifier.height(48.dp), selectedContentColor = MaterialTheme.colorScheme.onSurface, unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant) {
                Text(stringResource(l), style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (tab == k) FontWeight.SemiBold else FontWeight.Normal), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp)) } }
        }
        when (tab) {
            "feed" -> { val mine = posts.filter { it.who == p.name }
                if (mine.isEmpty()) Muted(stringResource(R.string.g4_prov_no_posts, p.name), Modifier.padding(Gutter))
                mine.forEach { post -> PostCard(post, s.postVotes[post.id] ?: 0, onVote = { vm.votePost(post.id, it) }, onComments = { comments = post.id }, onShare = { sharePost(ctx, post) }) } }
            "about" -> Column {
                Column(Modifier.padding(Gutter)) {
                    Text(stringResource(R.string.g4_prov_details), style = MaterialTheme.typography.titleMedium)
                    Text(p.bio, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
                    AboutRow(Icons.Rounded.LocationOn, stringResource(R.string.g4_prov_location), stringResource(R.string.g4_prov_area_city, Geo.nearestArea(p.pos)))
                    AboutRow(Icons.Rounded.Category, stringResource(R.string.g4_prov_category), if (p.scope == Scope.LOCAL) stringResource(R.string.g4_prov_category_local, p.category) else stringResource(R.string.g4_prov_category_ships, p.category))
                    p.rate?.let { AboutRow(Icons.Rounded.Payments, stringResource(R.string.g4_prov_rate), it) }
                }
                if (p.type == ProviderType.SKILL) { Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
                    Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g4_prov_specialties), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 10.dp))
                        p.tags.filter { !it.equals(p.category, true) }.forEach { t -> Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(40.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer) }
                            Text(t.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp)) } } } }
                Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
                TextButton(onClick = { howRanked = true }, Modifier.padding(horizontal = Gutter, vertical = 8.dp), contentPadding = PaddingValues(0.dp)) { Text(stringResource(R.string.g4_prov_how_ranked)) }
            }
            "items" -> { ProductsTab(p, variant, s.cart, onAdd = { i, d -> vm.cartAdd(p.id, i, d) }, onMessage = { onChatWith(p.name, p.category) }); Spacer(Modifier.height(if (cartCount > 0) 96.dp else 24.dp)) }
            "services" -> Column(Modifier.padding(Gutter)) {
                Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) { Row(Modifier.padding(8.dp)) {
                    Box(Modifier.size(96.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)) }
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text(stringResource(R.string.g4_prov_category_services, p.category), style = MaterialTheme.typography.titleSmall); Muted(stringResource(R.string.g4_prov_services_offered), Modifier.padding(top = 4.dp))
                        p.tags.filter { !it.equals(p.category, true) }.take(4).forEach { Muted("•  " + it.replaceFirstChar { c -> c.uppercase() }) }
                        Text(p.rate ?: stringResource(R.string.g4_prov_rate_on_request), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 6.dp))
                    } } }
                Notice(stringResource(R.string.g4_prov_describe_job, p.name.substringBefore(' ')), Modifier.padding(top = 12.dp)); PrimaryButton(stringResource(R.string.g4_prov_book_visit), Modifier.padding(top = 14.dp), onClick = onRequest) }
            "votes" -> Column(Modifier.padding(Gutter)) {
                val mine = s.myVotes[p.id]
                Text(stringResource(R.string.g4_prov_whose_reviews), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(R.string.g4_prov_reviews_from), Modifier.padding(top = 4.dp))
                Row(Modifier.padding(vertical = 12.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { Lens.entries.forEach { l -> Chip(l.label, selected = s.lens == l) { vm.setLens(l) } } }
                if (vm.canVote(p.id)) BucksCard(Modifier.padding(bottom = 12.dp), tint = true) { Text(stringResource(R.string.g4_prov_your_review), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g4_prov_can_review))
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { VoteButton(stringResource(R.string.g4_vote_recommend), mine == 1, true) { if (mine == null) voteSheet = true }; VoteButton(stringResource(R.string.g4_vote_not_recommend), mine == -1, false) { if (mine == null) voteSheet = false } } }
                else Notice(stringResource(R.string.g4_prov_order_first), Modifier.padding(bottom = 12.dp))
                // Same lens as the header badge (vm.trustFor), so the list and the number always agree.
                val reviews = vm.reviewsFor(p)
                if (reviews.isEmpty()) Muted(if (s.lens == Lens.ALL) stringResource(R.string.g4_prov_no_reviews) else stringResource(R.string.g4_prov_no_reviews_lens), Modifier.padding(vertical = 12.dp))
                reviews.forEach { c ->
                    Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.Top) {
                        Avatar(initials(c.who), size = 40)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(c.who, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false)); if (c.verified) { Spacer(Modifier.width(6.dp)); PillGrey(stringResource(R.string.g4_prov_id_verified)) } }; Text(c.text, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 2.dp)) }
                        if (c.vote > 0) PillGood(stringResource(R.string.g4_prov_recommends)) else PillBad(stringResource(R.string.g4_prov_doesnt_recommend))
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline) }
            }
        }
    }
        if (cartCount > 0 && tab == "items") DarkButton(pluralStringResource(R.plurals.g4_prov_view_cart, cartCount, cartCount), Modifier.align(Alignment.BottomCenter).padding(Gutter), onClick = onCart)
    }
    if (howRanked) ModalBottomSheet(onDismissRequest = { howRanked = false }) { Column(Modifier.padding(Gutter).padding(bottom = 24.dp)) {
        Text(stringResource(R.string.g4_prov_ranked_title, p.name), style = MaterialTheme.typography.titleLarge)
        Muted(stringResource(R.string.g4_prov_ranked_intro), Modifier.padding(top = 8.dp))
        BucksCard(Modifier.padding(vertical = 12.dp)) { Text(stringResource(R.string.g4_prov_rule_1), style = MaterialTheme.typography.bodyMedium); Text(stringResource(R.string.g4_prov_rule_2), style = MaterialTheme.typography.bodyMedium); Text(stringResource(R.string.g4_prov_rule_3), style = MaterialTheme.typography.bodyMedium); Text(stringResource(R.string.g4_prov_rule_4, s.lens.label, s.lens.explain.lowercase()), style = MaterialTheme.typography.bodyMedium) }
        Stat(stringResource(R.string.g4_prov_reviews_counted), "${lensTrust.total}"); Stat(stringResource(R.string.g4_prov_rec_rate), lensTrust.pct?.let { stringResource(R.string.g4_percent, it) } ?: "—"); Stat(stringResource(R.string.g4_prov_distance), stringResource(R.string.g4_prov_distance_value, p.distanceKm.toString()))
        Muted(stringResource(R.string.g4_prov_fraud_note), Modifier.padding(top = 10.dp)) } }
    comments?.let { id -> PostCommentsSheet(vm, id) { comments = null } }
    voteSheet?.let { up -> ModalBottomSheet(onDismissRequest = { voteSheet = null }) { Column(Modifier.padding(Gutter).padding(bottom = 24.dp)) {
        Text(if (up) stringResource(R.string.g4_prov_recommend_name, p.name) else stringResource(R.string.g4_prov_dont_recommend_name, p.name), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g4_prov_vote_why))
        BucksField(comment, { comment = it }, placeholder = if (up) stringResource(R.string.g4_prov_vote_up_hint) else stringResource(R.string.g4_prov_vote_down_hint), modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 2)
        PrimaryButton(if (up) stringResource(R.string.g4_prov_post_recommendation) else stringResource(R.string.g4_prov_post_review)) { if (vm.vote(p.id, up, comment.trim())) { voteSheet = null; comment = "" } } } } }
}

@Composable
private fun FollowButton(followed: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) = Row(modifier.minimumInteractiveComponentSize().height(44.dp).clip(MaterialTheme.shapes.small).background(if (followed) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.primary).clickable(onClick = onClick).padding(horizontal = 14.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
    val c = if (followed) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onPrimary
    Icon(if (followed) Icons.Rounded.HowToReg else Icons.Rounded.PersonAddAlt, null, Modifier.size(18.dp), tint = c); Text(if (followed) stringResource(R.string.g4_prov_following) else stringResource(R.string.g4_prov_follow), color = c, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp)) }

/** 44dp tonal icon button (48dp touch) for the header's secondary actions; [on] tints it for toggles such as Follow. */
@Composable
private fun HeaderIcon(icon: ImageVector, label: String, on: Boolean = false, onClick: () -> Unit) = Box(Modifier.minimumInteractiveComponentSize().size(44.dp).clip(MaterialTheme.shapes.small).background(if (on) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(onClickLabel = label, onClick = onClick), contentAlignment = Alignment.Center) {
    Icon(icon, label, Modifier.size(20.dp), tint = if (on) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface) }

@Composable
private fun AboutRow(icon: ImageVector, label: String, value: String) = Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Column(Modifier.padding(start = 12.dp)) { Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(value, style = MaterialTheme.typography.bodyMedium) } }

/** Products: filter chips, a category rail on the left, then a two-column grid for items with photos and compact rows for the rest (all business types share it). */
@Composable
private fun ProductsTab(p: Provider, variant: BusinessVariant, cart: Map<String, Int>, onAdd: (Int, Int) -> Unit, onMessage: () -> Unit) {
    if (p.items.isEmpty()) { Column(Modifier.padding(Gutter)) { Muted(stringResource(R.string.g4_prov_no_products, p.name)); SmallButton(stringResource(R.string.g4_profile_message), Modifier.padding(top = 12.dp), tonal = true, onClick = onMessage) }; return }
    val groups = p.items.map { it.group.ifBlank { p.category } }.distinct()
    var group by remember { mutableStateOf(groups.firstOrNull() ?: "") }
    var veg by remember { mutableStateOf(false) }; var nonVeg by remember { mutableStateOf(false) }; var cheapest by remember { mutableStateOf(false) }
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (variant == BusinessVariant.RESTAURANT) { Chip(stringResource(R.string.g4_prov_veg), veg, Icons.Rounded.Circle) { veg = !veg }; Chip(stringResource(R.string.g4_prov_non_veg), nonVeg, Icons.Rounded.Circle) { nonVeg = !nonVeg } }
        Chip(if (cheapest) stringResource(R.string.g4_prov_price_low_high) else stringResource(R.string.g4_prov_sort), cheapest, Icons.Rounded.SwapVert) { cheapest = !cheapest }
    }
    val shown = p.items.withIndex().filter { (it.value.group.ifBlank { p.category }) == group || groups.size <= 1 }
        .filter { !(veg || nonVeg) || (veg && it.value.tag == "Veg") || (nonVeg && it.value.tag == "Non-veg") }
        .let { if (cheapest) it.sortedBy { e -> e.value.price } else it }
    Row(Modifier.fillMaxWidth()) {
        if (groups.size > 1) Column(Modifier.padding(start = Gutter).width(84.dp).clip(MaterialTheme.shapes.large).background(MaterialTheme.colorScheme.surfaceContainer).padding(vertical = 8.dp)) {
            groups.forEach { g -> val on = g == group
                Row(Modifier.fillMaxWidth().then(if (on) Modifier.background(MaterialTheme.colorScheme.primaryContainer) else Modifier).clickable { group = g }) {
                    Column(Modifier.weight(1f).padding(vertical = 10.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(22.dp), tint = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(g, style = MaterialTheme.typography.labelSmall, color = if (on) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) }
                    if (on) Box(Modifier.width(4.dp).height(64.dp).align(Alignment.CenterVertically).background(MaterialTheme.colorScheme.primary, RoundedCornerShape(topStart = 4.dp, bottomStart = 4.dp)))
                } }
        }
        Column(Modifier.weight(1f).padding(start = if (groups.size > 1) 12.dp else Gutter, end = Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (shown.isEmpty()) Muted(stringResource(R.string.g4_prov_no_match))
            // Photo grid only for items that have a photo; the rest are compact rows, so a catalogue without photos isn't a wall of empty boxes.
            val (pics, plain) = shown.partition { it.value.image.isNotBlank() }
            pics.chunked(2).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { row.forEach { (i, it) -> ProductCard(it, variant, cart["${p.id}:$i"] ?: 0, Modifier.weight(1f)) { d -> onAdd(i, d) } }; if (row.size == 1) Spacer(Modifier.weight(1f)) } }
            if (plain.isNotEmpty()) Column { plain.forEachIndexed { k, (i, it) -> if (k > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant); ProductRow(it, variant, cart["${p.id}:$i"] ?: 0) { d -> onAdd(i, d) } } }
        }
    }
}

/** Indian veg / non-veg mark: a dot inside a square outline. */
@Composable
private fun FoodMark(color: Color) = Box(Modifier.size(14.dp).border(1.5.dp, color, RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) { Box(Modifier.size(7.dp).background(color, CircleShape)) }

/** An item without a photo, as in search results: name, detail and price on the left, Add (then a -/qty/+ stepper) on the right. Price sits under the name so the name keeps room beside the category rail. */
@Composable
private fun ProductRow(item: Item, variant: BusinessVariant, qty: Int, onAdd: (Int) -> Unit) = Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f).padding(end = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (variant == BusinessVariant.RESTAURANT && item.tag.isNotBlank()) { FoodMark(if (item.tag == "Veg") MaterialTheme.status.good else MaterialTheme.status.bad); Spacer(Modifier.width(6.dp)) }
            Text(item.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        if (item.detail.isNotBlank()) Muted(item.detail, maxLines = 1)
        Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(Money.format(item.price), style = MaterialTheme.typography.titleMedium)
            if (item.mrp > item.price) Text(Money.format(item.mrp), style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    AddStepper(qty, onAdd)
}

/** An item with a photo, in the two-column grid. */
@Composable
private fun ProductCard(item: Item, variant: BusinessVariant, qty: Int, modifier: Modifier, onAdd: (Int) -> Unit) = Column(modifier.clip(MaterialTheme.shapes.small).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).padding(6.dp)) {
    Box(Modifier.fillMaxWidth().aspectRatio(1.3f).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
        AsyncImage(item.image, item.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
    if (variant == BusinessVariant.RESTAURANT && item.tag.isNotBlank()) Row(Modifier.padding(top = 6.dp)) { FoodMark(if (item.tag == "Veg") MaterialTheme.status.good else MaterialTheme.status.bad) }
    Text(item.name, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(Money.format(item.price), style = MaterialTheme.typography.titleSmall)
        if (item.mrp > item.price) Text(Money.format(item.mrp), style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(if (variant == BusinessVariant.RESTAURANT) "" else item.detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        AddStepper(qty, onAdd)
    }
}

@Composable
private fun Stat(label: String, value: String, color: androidx.compose.ui.graphics.Color? = null) = Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { Muted(label, Modifier.weight(1f)); Text(value, style = MaterialTheme.typography.titleMedium, color = color ?: MaterialTheme.colorScheme.onSurface) }

@Composable
fun CartScreen(vm: BucksViewModel, onBack: () -> Unit, onPlaced: (String) -> Unit) {
    val s by vm.state.collectAsState()
    val cl = vm.cartLines(); val p = cl.first; val lines = cl.second; val total = cl.third
    ContentColumn { BucksTopBar(stringResource(R.string.g4_cd_cart), onBack = onBack)
        if (p == null) Muted(stringResource(R.string.g4_prov_cart_empty), Modifier.fillMaxWidth().padding(top = 80.dp), TextAlign.Center)
        else {
            val fee = if (p.scope == Scope.LOCAL && p.distanceKm <= 3) 0 else 30
            Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                ListRow(p.name, stringResource(R.string.g4_km, p.distanceKm.toString()), leading = { Avatar(icon = p.icon, tinted = false) }, trailing = { TrustBadge(vm.trustFor(p), compact = true) })
                BucksCard(Modifier.padding(top = 10.dp)) {
                    lines.forEach { ln -> Row(Modifier.padding(vertical = 4.dp)) { Text("${ln.first} × ${ln.third}", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium); Text(Money.format(ln.second * ln.third), style = MaterialTheme.typography.titleMedium) } }
                    Row(Modifier.padding(vertical = 4.dp)) { Muted(stringResource(R.string.g4_prov_delivery), Modifier.weight(1f)); Muted(if (fee == 0) stringResource(R.string.g4_prov_delivery_free) else Money.format(fee)) }
                    Divider(); Row(Modifier.padding(top = 8.dp)) { Text(stringResource(R.string.g4_prov_total), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Text(Money.format(total), style = MaterialTheme.typography.titleLarge) }
                }
                BucksField(s.user?.area ?: "", {}, stringResource(R.string.g4_prov_deliver_to), modifier = Modifier.padding(top = 16.dp), readOnly = true)
                Label(stringResource(R.string.g4_prov_pay_with)); val cod = stringResource(R.string.g4_prov_cod); ChipRow(listOf(cod, "UPI"), cod, Modifier.padding(bottom = 20.dp)) {}
                PrimaryButton(stringResource(R.string.g4_prov_review_order, Money.format(total))) { vm.placeOrder() }
            }
        }
    }
}

@Composable
fun OrderScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onVote: (String) -> Unit, onChatWith: (String, String) -> Unit, onHome: () -> Unit) {
    val s by vm.state.collectAsState(); val o = s.orders.firstOrNull { it.id == id } ?: return
    val i = OrderStatus.entries.indexOf(o.status)
    ContentColumn { BucksTopBar(stringResource(R.string.g4_prov_order), onBack = onBack)
        Column(Modifier.padding(Gutter)) {
            Text(o.providerName, style = MaterialTheme.typography.headlineSmall); Muted(stringResource(R.string.g4_prov_order_summary, o.items.joinToString(", "), Money.format(o.total)))
            Column(Modifier.padding(vertical = 22.dp)) { OrderStatus.entries.forEachIndexed { k, st -> StatusLine(st.label, if (k == 4) stringResource(R.string.g4_prov_status_review) else stringResource(R.string.g4_prov_status_live), done = k < i, now = k == i, last = k == 4) } }
            if (o.status == OrderStatus.DELIVERED) PrimaryButton(stringResource(R.string.g4_prov_leave_review)) { onVote(o.providerId) } else { val vendor = stringResource(R.string.g4_prov_vendor); GhostButton(stringResource(R.string.g4_prov_message_vendor)) { onChatWith(o.providerName, vendor) } }
            TextButton(onClick = onHome, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text(stringResource(R.string.g4_prov_back_home)) }
        }
    }
}

@Composable
fun RequestScreen(vm: BucksViewModel, providerId: String, onBack: () -> Unit, onSent: (String) -> Unit) {
    val s by vm.state.collectAsState(); val p = vm.provider(providerId) ?: return
    val whenNow = stringResource(R.string.g4_prov_when_now)
    var text by remember { mutableStateOf("") }; var whenSel by remember { mutableStateOf(whenNow) }
    ContentColumn { BucksTopBar(stringResource(R.string.g4_prov_request_service), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ListRow(p.name, stringResource(R.string.g4_prov_category_rate, p.category, p.rate ?: ""), leading = { Avatar(icon = p.icon, tinted = false) })
            BucksField(text, { text = it }, stringResource(R.string.g4_prov_need), stringResource(R.string.g4_prov_need_hint), Modifier.padding(top = 12.dp), singleLine = false, minLines = 3)
            Label(stringResource(R.string.g4_prov_when)); ChipRow(listOf(whenNow, stringResource(R.string.g4_prov_when_evening), stringResource(R.string.g4_prov_when_tomorrow)), whenSel, Modifier.padding(bottom = 14.dp)) { whenSel = it }
            BucksField(s.user?.area ?: "", {}, stringResource(R.string.g4_prov_where), readOnly = true)
            PrimaryButton(stringResource(R.string.g4_prov_send_request)) { onSent(vm.sendRequest(p.id, text.trim())) }
            Muted(stringResource(R.string.g4_prov_request_note, p.name, p.category.lowercase()), Modifier.padding(top = 14.dp).fillMaxWidth(), TextAlign.Center)
        }
    }
}

@Composable
fun RequestStatusScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onVote: (String) -> Unit, onChatWith: (String, String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.requests.firstOrNull { it.id == id } ?: return
    val i = RequestStatus.entries.indexOf(r.status)
    ContentColumn { BucksTopBar(stringResource(R.string.g4_prov_request), onBack = onBack)
        Column(Modifier.padding(Gutter)) {
            Text(r.providerName, style = MaterialTheme.typography.headlineSmall); Muted("${r.category} · \"${r.text}\"")
            Column(Modifier.padding(vertical = 22.dp)) { RequestStatus.entries.forEachIndexed { k, st -> StatusLine(st.label, null, done = k < i, now = k == i, last = k == 3) } }
            when (r.status) {
                RequestStatus.ACCEPTED -> DarkButton(stringResource(R.string.g4_prov_arrived)) { vm.setRequestStatus(r.id, RequestStatus.IN_PROGRESS) }
                RequestStatus.IN_PROGRESS -> GoodButton(stringResource(R.string.g4_prov_mark_completed)) { vm.setRequestStatus(r.id, RequestStatus.COMPLETED) }
                RequestStatus.COMPLETED -> PrimaryButton(stringResource(R.string.g4_prov_leave_review)) { onVote(r.providerId) }
                else -> {}
            }
            GhostButton(stringResource(R.string.g4_profile_message), Modifier.padding(top = 10.dp)) { onChatWith(r.providerName, r.category) }
        }
    }
}
