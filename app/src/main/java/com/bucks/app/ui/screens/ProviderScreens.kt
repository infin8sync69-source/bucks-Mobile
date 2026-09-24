package com.bucks.app.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
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
import com.bucks.app.ui.theme.Brand
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
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Bad
import com.bucks.app.ui.theme.Good

private val PROFILE_TABS = listOf("feed" to "Feed", "about" to "About", "items" to "Products", "votes" to "Recommendations")
private fun plural(n: Int, one: String, many: String = one + "s") = "$n ${if (n == 1) one else many}"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProviderScreen(vm: BucksViewModel, id: String, initialTab: String, onBack: () -> Unit, onRequest: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit, onCart: () -> Unit, onMessages: () -> Unit) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState(); val posts by vm.repo.posts.collectAsState()
    val p = providers.firstOrNull { it.id == id } ?: return
    val ctx = LocalContext.current
    val tabs = if (p.type == ProviderType.BUSINESS) PROFILE_TABS else PROFILE_TABS.map { if (it.first == "items") "services" to "Services" else it }
    var tab by remember { mutableStateOf(when (initialTab) { "about", "feed", "votes", "services" -> initialTab; "items" -> if (p.type == ProviderType.BUSINESS) "items" else "services"; else -> "items" }.let { t -> if (tabs.any { it.first == t }) t else tabs[2].first }) }
    var voteSheet by remember { mutableStateOf<Boolean?>(null) }; var comment by remember { mutableStateOf("") }; var howRanked by remember { mutableStateOf(false) }
    val lensTrust = vm.trustFor(p); val variant = variantFor(p.category)
    val followed = p.id in s.followedProviders
    val cartCount = s.cart.filterKeys { it.startsWith("${p.id}:") }.values.sum()
    Box(Modifier.fillMaxSize()) { Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        if (p.type == ProviderType.SKILL) {
            // Professional profile: cover + avatar, skill as the title, the person below.
            ProfileCover(initials(p.name), onBack = onBack)
            Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(p.category, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)); Text(p.name, style = MaterialTheme.typography.bodyMedium) }
                    UpPill(lensTrust.up) { howRanked = true } }
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${Geo.nearestArea(p.pos)}, Bengaluru · ${p.distanceKm} km · ${if (p.scope == Scope.LOCAL) "Local" else "Remote or on-site"}") }
                Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlineAction("Book an Appointment", Icons.Rounded.CalendarMonth, onRequest); OutlineAction("Schedule Intro call", Icons.Rounded.PhoneInTalk) { onCall(p.name, p.phone) } }
                Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    SyncButton(followed) { vm.followProvider(p.id) }; ProfileAction("Contact", Icons.Rounded.Call) { onCall(p.name, p.phone) }; ProfileAction("Enquiry", Icons.Rounded.Sms) { onChatWith(p.name, p.category) } }
            }
        } else {
        // Hero: cover photo slot. No cover images in the data yet, so the business mark stands in.
        Box(Modifier.fillMaxWidth().height(220.dp).background(MaterialTheme.colorScheme.surfaceContainer)) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(categoryIcon(p.category), null, Modifier.size(64.dp), tint = Brand)
                Text(p.name, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold), color = Brand, modifier = Modifier.padding(top = 8.dp)) }
            IconButton(onClick = onBack, modifier = Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", Modifier.size(26.dp)) }
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(p.name, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                UpPill(lensTrust.up) { howRanked = true }
            }
            Text(p.bio, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${Geo.nearestArea(p.pos)}, Bengaluru · ${p.distanceKm} km") }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                ProfileStat(if (followed) 1 else 0, "Followers"); ProfileStat(p.comments.size, "Reviews"); ProfileStat(lensTrust.pct ?: 0, "% recommend")
            }
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                SyncButton(followed) { vm.followProvider(p.id) }
                ProfileAction("Contact", Icons.Rounded.Call) { onCall(p.name, p.phone) }
                ProfileAction("Enquiry", Icons.Rounded.Sms) { onChatWith(p.name, p.category) }
            }
        }
        }
        ScrollableTabRow(tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0), containerColor = MaterialTheme.colorScheme.surface, edgePadding = 12.dp,
            indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[tabs.indexOfFirst { it.first == tab }.coerceAtLeast(0)]), height = 3.dp, color = Brand) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
            tabs.forEach { (k, l) -> Tab(tab == k, onClick = { tab = k }, selectedContentColor = MaterialTheme.colorScheme.onSurface, unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                text = { Text(l, style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (tab == k) FontWeight.SemiBold else FontWeight.Normal)) }) }
        }
        when (tab) {
            "feed" -> { val mine = posts.filter { it.who == p.name }
                if (mine.isEmpty()) Muted("${p.name} hasn't posted yet.", Modifier.padding(20.dp))
                mine.forEach { post -> val my = s.postVotes[post.id] ?: 0
                    Column(Modifier.padding(20.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(icon = p.icon, size = 40, tinted = false); Column(Modifier.padding(start = 10.dp).weight(1f)) { Text(p.name, style = MaterialTheme.typography.titleSmall); Muted(post.ago) } }
                        Text(post.text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
                        if (post.hasImage) Box(Modifier.padding(top = 12.dp).fillMaxWidth().height(260.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Image, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            IconButton({ vm.votePost(post.id, 1) }) { Icon(Icons.Rounded.ArrowUpward, "Recommend post", tint = if (my == 1) Good else Good.copy(alpha = 0.6f)) }; Text("${post.up}", color = Good, style = MaterialTheme.typography.labelLarge)
                            IconButton({ vm.votePost(post.id, -1) }) { Icon(Icons.Rounded.ArrowDownward, "Not recommended", tint = if (my == -1) Bad else Bad.copy(alpha = 0.6f)) }; Text("${post.down}", color = Bad, style = MaterialTheme.typography.labelLarge)
                            Icon(Icons.Rounded.ChatBubbleOutline, null, Modifier.padding(start = 20.dp).size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${plural(post.comments.size, "comment")}")
                            Spacer(Modifier.weight(1f))
                            IconButton({ ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "${p.name} on Bucks: ${post.text}") }, "Share post")) }) { Icon(Icons.Rounded.IosShare, "Share") }
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline) } }
            "about" -> Column {
                Column(Modifier.padding(20.dp)) {
                    Text("About ${p.name}", style = MaterialTheme.typography.titleMedium)
                    Text(p.bio, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
                    AboutRow(Icons.Rounded.LocationOn, "Location", "${Geo.nearestArea(p.pos)}, Bengaluru")
                    AboutRow(Icons.Rounded.Category, "Category", "${p.category} · ${if (p.scope == Scope.LOCAL) "Local, within 5 km" else "Ships anywhere"}")
                    p.rate?.let { AboutRow(Icons.Rounded.Payments, "Rate", it) }
                }
                if (p.type == ProviderType.SKILL) { Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
                    Column(Modifier.padding(20.dp)) { Text("Specialties", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 10.dp))
                        p.tags.filter { !it.equals(p.category, true) }.forEach { t -> Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)).background(Brand.copy(alpha = 0.08f)), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(20.dp), tint = Brand) }
                            Text(t.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp)) } } } }
                Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
                Column(Modifier.padding(20.dp)) {
                    Text("Trust", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 6.dp))
                    Stat("Recommended by", lensTrust.pct?.let { "$it%" } ?: "—"); Stat("Recommend", "${lensTrust.up}", Good); Stat("Not recommended", "${lensTrust.down}", Bad); Stat("Verified reviews", "${p.comments.size}")
                    TextButton(onClick = { howRanked = true }, contentPadding = PaddingValues(0.dp)) { Text("How is this ranked?", color = Brand) }
                }
            }
            "items" -> { ProductsTab(p, variant, s.cart, onAdd = { i, d -> vm.cartAdd(p.id, i, d) }); Spacer(Modifier.height(if (cartCount > 0) 96.dp else 24.dp)) }
            "services" -> Column(Modifier.padding(16.dp)) {
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) { Row(Modifier.padding(8.dp)) {
                    Box(Modifier.size(96.dp).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)) }
                    Column(Modifier.weight(1f).padding(start = 12.dp)) {
                        Text("${p.category} services", style = MaterialTheme.typography.titleSmall); Muted("Services offered:", Modifier.padding(top = 4.dp))
                        p.tags.filter { !it.equals(p.category, true) }.take(4).forEach { Muted("•  " + it.replaceFirstChar { c -> c.uppercase() }) }
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text(p.rate ?: "Rate on request", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                            Box(Modifier.clip(RoundedCornerShape(4.dp)).border(1.dp, Brand, RoundedCornerShape(4.dp)).clickable { onChatWith(p.name, p.category) }.padding(horizontal = 10.dp, vertical = 3.dp)) { Text("Enquire", style = MaterialTheme.typography.labelMedium, color = Brand) } }
                    } } }
                Notice("Describe the job when you request; ${p.name.substringBefore(' ')} confirms the price before starting.", Modifier.padding(top = 12.dp)); PrimaryButton("Book an Appointment", Modifier.padding(top = 14.dp), onClick = onRequest) }
            "votes" -> Column(Modifier.padding(20.dp)) {
                val mine = s.myVotes[p.id]
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Overall recommendation", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(18.dp), tint = Good); Text(lensTrust.pct?.let { "$it%" } ?: "—", color = Good, style = MaterialTheme.typography.titleMedium) }
                Muted("${lensTrust.up} recommend · ${lensTrust.down} don't · all from people who ordered or booked here", Modifier.padding(top = 4.dp))
                Row(Modifier.padding(vertical = 12.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { Lens.entries.forEach { l -> Chip(l.label, selected = s.lens == l) { vm.setLens(l) } } }
                if (vm.canVote(p.id)) BucksCard(Modifier.padding(bottom = 12.dp), tint = true) { Text("Your review", style = MaterialTheme.typography.titleMedium); Muted("You ordered or booked here, so you can review once.")
                    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { VoteButton("Recommend", mine == 1, true) { if (mine == null) voteSheet = true }; VoteButton("Not recommended", mine == -1, false) { if (mine == null) voteSheet = false } } }
                else Notice("Order or book here first. Then you can leave a review.", Modifier.padding(bottom = 12.dp))
                p.comments.filter { c -> when (s.lens) { Lens.ALL -> true; Lens.VERIFIED -> c.verified; Lens.FOLLOWING -> true } }.forEach { c ->
                    Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.Top) {
                        Avatar(initials(c.who), size = 40)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(c.who, style = MaterialTheme.typography.titleSmall); if (c.verified) { Spacer(Modifier.width(6.dp)); PillGrey("ID verified") } }; Text(c.text, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 2.dp)) }
                        Icon(if (c.vote > 0) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (c.vote > 0) "Recommends" else "Doesn't recommend", Modifier.size(26.dp), tint = if (c.vote > 0) Good else Bad)
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline) }
            }
        }
    }
        if (cartCount > 0 && tab == "items") DarkButton("View cart · ${plural(cartCount, "item")}", Modifier.align(Alignment.BottomCenter).padding(20.dp), onClick = onCart)
    }
    if (howRanked) ModalBottomSheet(onDismissRequest = { howRanked = false }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text("How ${p.name} is ranked", style = MaterialTheme.typography.titleLarge)
        Muted("Bucks has no ranking algorithm. Everyone sees the same published formula:", Modifier.padding(top = 8.dp))
        BucksCard(Modifier.padding(vertical = 12.dp)) { Text("1. Recommendation rate = recommended ÷ (recommended + not recommended)", style = MaterialTheme.typography.bodyMedium); Text("2. Ties broken by number of reviews", style = MaterialTheme.typography.bodyMedium); Text("3. Only reviews tied to a completed, signed transaction count", style = MaterialTheme.typography.bodyMedium); Text("4. Your filter (${s.lens.label}) chooses whose reviews count: ${s.lens.explain.lowercase()}", style = MaterialTheme.typography.bodyMedium) }
        Stat("Reviews counted", "${lensTrust.total}"); Stat("Recommendation rate", lensTrust.pct?.let { "$it%" } ?: "—"); Stat("Distance", "${p.distanceKm} km (used only when you sort by Nearest)")
        Muted("Fraud checks (accounts reviewing each other in a ring, many accounts on one phone) put reviews on hold with a public reason. Nobody is demoted silently.", Modifier.padding(top = 10.dp)) } }
    voteSheet?.let { up -> ModalBottomSheet(onDismissRequest = { voteSheet = null }) { Column(Modifier.padding(20.dp).padding(bottom = 24.dp)) {
        Text(if (up) "Recommend ${p.name}" else "Don't recommend ${p.name}", style = MaterialTheme.typography.titleLarge); Muted("One line on why. It's public and tied to your order or booking.")
        BucksField(comment, { comment = it }, placeholder = if (up) "On time, fair price" else "Late, overcharged", modifier = Modifier.padding(top = 14.dp), singleLine = false, minLines = 2)
        PrimaryButton(if (up) "Post recommendation" else "Post review") { if (vm.vote(p.id, up, comment.trim())) { voteSheet = null; comment = "" } } } } }
}

@Composable
private fun UpPill(up: Int, onClick: () -> Unit) = Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Good.copy(alpha = 0.1f)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Text("$up", style = MaterialTheme.typography.titleSmall, color = Good); Icon(Icons.Rounded.ArrowUpward, "recommendations", Modifier.padding(start = 2.dp).size(18.dp), tint = Good) }

@Composable
private fun SyncButton(followed: Boolean, onClick: () -> Unit) = Row(Modifier.clip(RoundedCornerShape(8.dp)).background(if (followed) Brand.copy(alpha = 0.12f) else Brand).clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    val c = if (followed) Brand else Color.White
    Icon(if (followed) Icons.Rounded.HowToReg else Icons.Rounded.PersonAddAlt, null, Modifier.size(18.dp), tint = c); Text(if (followed) "Synced" else "Sync", color = c, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = 6.dp)) }

@Composable
private fun OutlineAction(text: String, icon: ImageVector, onClick: () -> Unit) = Row(Modifier.clip(RoundedCornerShape(8.dp)).border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(18.dp)); Text(text, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(start = 6.dp)) }

@Composable
private fun ProfileStat(n: Int, label: String) = Column { Text("$n", style = MaterialTheme.typography.titleMedium); Muted(label) }

@Composable
private fun ProfileAction(text: String, icon: ImageVector, onClick: () -> Unit) = Row(Modifier.clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(text, style = MaterialTheme.typography.labelLarge); Icon(icon, null, Modifier.padding(start = 6.dp).size(18.dp)) }

@Composable
private fun AboutRow(icon: ImageVector, label: String, value: String) = Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Column(Modifier.padding(start = 12.dp)) { Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(value, style = MaterialTheme.typography.bodyMedium) } }

/** Products: filter pills, a category rail on the left and a two-column grid, as in the business-profile design (all business types share it). */
@Composable
private fun ProductsTab(p: Provider, variant: BusinessVariant, cart: Map<String, Int>, onAdd: (Int, Int) -> Unit) {
    val groups = p.items.map { it.group.ifBlank { p.category } }.distinct()
    var group by remember { mutableStateOf(groups.firstOrNull() ?: "") }
    var veg by remember { mutableStateOf(false) }; var nonVeg by remember { mutableStateOf(false) }; var cheapest by remember { mutableStateOf(false) }
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (variant == BusinessVariant.RESTAURANT) { ToggleChip("Veg", veg, Good) { veg = !veg }; ToggleChip("Non-veg", nonVeg, Bad) { nonVeg = !nonVeg } }
        OutlinePill(if (cheapest) "Price: low to high" else "Sort", Icons.Rounded.SwapVert, cheapest) { cheapest = !cheapest }
    }
    val shown = p.items.withIndex().filter { (it.value.group.ifBlank { p.category }) == group || groups.size <= 1 }
        .filter { !(veg || nonVeg) || (veg && it.value.tag == "Veg") || (nonVeg && it.value.tag == "Non-veg") }
        .let { if (cheapest) it.sortedBy { e -> e.value.price } else it }
    Row(Modifier.fillMaxWidth()) {
        if (groups.size > 1) Column(Modifier.width(84.dp).clip(RoundedCornerShape(topEnd = 18.dp, bottomEnd = 18.dp)).border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(topEnd = 18.dp, bottomEnd = 18.dp)).padding(vertical = 8.dp)) {
            groups.forEach { g -> val on = g == group
                Row(Modifier.fillMaxWidth().background(if (on) Brand.copy(alpha = 0.06f) else Color.Transparent).clickable { group = g }) {
                    Column(Modifier.weight(1f).padding(vertical = 10.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(categoryIcon(p.category), null, Modifier.size(22.dp), tint = if (on) Brand else MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(g, style = MaterialTheme.typography.labelSmall, color = if (on) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp)) }
                    if (on) Box(Modifier.width(4.dp).height(64.dp).align(Alignment.CenterVertically).background(Brand, RoundedCornerShape(topStart = 4.dp, bottomStart = 4.dp)))
                } }
        }
        Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (shown.isEmpty()) Muted("Nothing listed here yet.", Modifier.padding(8.dp))
            shown.chunked(2).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { row.forEach { (i, it) -> ProductCard(it, variant, p.category, cart["${p.id}:$i"] ?: 0, Modifier.weight(1f)) { d -> onAdd(i, d) } }; if (row.size == 1) Spacer(Modifier.weight(1f)) } }
        }
    }
}

@Composable
private fun ToggleChip(label: String, on: Boolean, color: Color, onClick: () -> Unit) = Row(Modifier.height(36.dp).clip(RoundedCornerShape(18.dp)).border(1.dp, if (on) color else MaterialTheme.colorScheme.outline, RoundedCornerShape(18.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
    FoodMark(color); Text(label, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = 8.dp), color = if (on) color else MaterialTheme.colorScheme.onSurfaceVariant) }

@Composable
private fun OutlinePill(label: String, icon: ImageVector, on: Boolean, onClick: () -> Unit) = Row(Modifier.height(36.dp).clip(RoundedCornerShape(8.dp)).border(1.dp, if (on) Brand else MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(18.dp), tint = if (on) Brand else MaterialTheme.colorScheme.onSurfaceVariant); Text(label, style = MaterialTheme.typography.labelLarge, color = if (on) Brand else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 6.dp)) }

/** Indian veg / non-veg mark: a dot inside a square outline. */
@Composable
private fun FoodMark(color: Color) = Box(Modifier.size(14.dp).border(1.5.dp, color, RoundedCornerShape(3.dp)), contentAlignment = Alignment.Center) { Box(Modifier.size(7.dp).background(color, CircleShape)) }

@Composable
private fun ProductCard(item: Item, variant: BusinessVariant, category: String, qty: Int, modifier: Modifier, onAdd: (Int) -> Unit) = Column(modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp)).padding(6.dp)) {
    Box(Modifier.fillMaxWidth().aspectRatio(1.3f).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
        if (item.image.isNotBlank()) AsyncImage(item.image, item.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) else Icon(categoryIcon(category), null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)) }
    if (variant == BusinessVariant.RESTAURANT && item.tag.isNotBlank()) Row(Modifier.padding(top = 6.dp)) { FoodMark(if (item.tag == "Veg") Good else Bad) }
    Text(item.name, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("₹${"%,d".format(item.price)}", style = MaterialTheme.typography.titleSmall)
        if (item.mrp > item.price) Text("₹${"%,d".format(item.mrp)}", style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(if (variant == BusinessVariant.RESTAURANT) "" else item.detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (qty == 0) Box(Modifier.clip(RoundedCornerShape(4.dp)).border(1.dp, Brand, RoundedCornerShape(4.dp)).clickable { onAdd(1) }.padding(horizontal = 14.dp, vertical = 3.dp)) { Text("Add", style = MaterialTheme.typography.labelMedium, color = Brand) }
        else Row(Modifier.clip(RoundedCornerShape(4.dp)).background(Brand), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Remove, "Remove one", Modifier.clickable { onAdd(-1) }.padding(4.dp).size(14.dp), tint = Color.White); Text("$qty", style = MaterialTheme.typography.labelMedium, color = Color.White); Icon(Icons.Rounded.Add, "Add one", Modifier.clickable { onAdd(1) }.padding(4.dp).size(14.dp), tint = Color.White) }
    }
}

@Composable
private fun Stat(label: String, value: String, color: androidx.compose.ui.graphics.Color? = null) = Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { Muted(label, Modifier.weight(1f)); Text(value, style = MaterialTheme.typography.titleMedium, color = color ?: MaterialTheme.colorScheme.onSurface) }

@Composable
fun CartScreen(vm: BucksViewModel, onBack: () -> Unit, onPlaced: (String) -> Unit) {
    val s by vm.state.collectAsState()
    val cl = vm.cartLines(); val p = cl.first; val lines = cl.second; val total = cl.third
    ContentColumn { BucksTopBar("Cart", onBack = onBack)
        if (p == null) Muted("Your cart is empty.", Modifier.fillMaxWidth().padding(top = 80.dp), TextAlign.Center)
        else {
            val fee = if (p.scope == Scope.LOCAL && p.distanceKm <= 3) 0 else 30
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
                ListRow(p.name, "${p.distanceKm} km", leading = { Avatar(icon = p.icon, tinted = false) }, trailing = { TrustBadge(vm.trustFor(p), compact = true) })
                BucksCard(Modifier.padding(top = 10.dp)) {
                    lines.forEach { ln -> Row(Modifier.padding(vertical = 4.dp)) { Text("${ln.first} × ${ln.third}", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium); Text("₹${ln.second * ln.third}", style = MaterialTheme.typography.titleMedium) } }
                    Row(Modifier.padding(vertical = 4.dp)) { Muted("Delivery", Modifier.weight(1f)); Muted(if (fee == 0) "Free (local, under 3 km)" else "₹$fee") }
                    Divider(); Row(Modifier.padding(top = 8.dp)) { Text("Total", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f)); Text("₹$total", style = MaterialTheme.typography.titleLarge) }
                }
                BucksField(s.user?.area ?: "", {}, "Deliver to", modifier = Modifier.padding(top = 16.dp), readOnly = true)
                Label("Pay with"); ChipRow(listOf("Cash on delivery", "UPI"), "Cash on delivery", Modifier.padding(bottom = 20.dp)) {}
                PrimaryButton("Review order · ₹$total") { vm.placeOrder() }
            }
        }
    }
}

@Composable
fun OrderScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onVote: (String) -> Unit, onChatWith: (String, String) -> Unit, onHome: () -> Unit) {
    val s by vm.state.collectAsState(); val o = s.orders.firstOrNull { it.id == id } ?: return
    val i = OrderStatus.entries.indexOf(o.status)
    ContentColumn { BucksTopBar("Order", onBack = onBack)
        Column(Modifier.padding(20.dp)) {
            Text(o.providerName, style = MaterialTheme.typography.headlineSmall); Muted(o.items.joinToString(", ") + " · ₹${o.total}")
            Column(Modifier.padding(vertical = 22.dp)) { OrderStatus.entries.forEachIndexed { k, st -> StatusLine(st.label, if (k == 4) "Leave a review to help the next person." else "The vendor updates this live", done = k < i, now = k == i, last = k == 4) } }
            if (o.status == OrderStatus.DELIVERED) PrimaryButton("Leave a review") { onVote(o.providerId) } else GhostButton("Message vendor") { onChatWith(o.providerName, "Vendor") }
            TextButton(onClick = onHome, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) { Text("Back to home") }
        }
    }
}

@Composable
fun RequestScreen(vm: BucksViewModel, providerId: String, onBack: () -> Unit, onSent: (String) -> Unit) {
    val s by vm.state.collectAsState(); val p = vm.provider(providerId) ?: return
    var text by remember { mutableStateOf("") }; var whenSel by remember { mutableStateOf("Now") }
    ContentColumn { BucksTopBar("Request service", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp)) {
            ListRow(p.name, "${p.category} · ${p.rate ?: ""}", leading = { Avatar(icon = p.icon, tinted = false) })
            BucksField(text, { text = it }, "What do you need?", "e.g. Kitchen tap leaking, need it fixed today", Modifier.padding(top = 12.dp), singleLine = false, minLines = 3)
            Label("When"); ChipRow(listOf("Now", "Today evening", "Tomorrow"), whenSel, Modifier.padding(bottom = 14.dp)) { whenSel = it }
            BucksField(s.user?.area ?: "", {}, "Where", readOnly = true)
            PrimaryButton("Send request") { onSent(vm.sendRequest(p.id, text.trim())) }
            Muted("${p.name} gets a ring. If they don't respond in 5 minutes you can send it to the next most trusted ${p.category.lowercase()}.", Modifier.padding(top = 14.dp).fillMaxWidth(), TextAlign.Center)
        }
    }
}

@Composable
fun RequestStatusScreen(vm: BucksViewModel, id: String, onBack: () -> Unit, onVote: (String) -> Unit, onChatWith: (String, String) -> Unit) {
    val s by vm.state.collectAsState(); val r = s.requests.firstOrNull { it.id == id } ?: return
    val i = RequestStatus.entries.indexOf(r.status)
    ContentColumn { BucksTopBar("Request", onBack = onBack)
        Column(Modifier.padding(20.dp)) {
            Text(r.providerName, style = MaterialTheme.typography.headlineSmall); Muted("${r.category} · \"${r.text}\"")
            Column(Modifier.padding(vertical = 22.dp)) { RequestStatus.entries.forEachIndexed { k, st -> StatusLine(st.label, null, done = k < i, now = k == i, last = k == 3) } }
            when (r.status) {
                RequestStatus.ACCEPTED -> DarkButton("Provider has arrived") { vm.setRequestStatus(r.id, RequestStatus.IN_PROGRESS) }
                RequestStatus.IN_PROGRESS -> GoodButton("Mark as completed") { vm.setRequestStatus(r.id, RequestStatus.COMPLETED) }
                RequestStatus.COMPLETED -> PrimaryButton("Leave a review") { onVote(r.providerId) }
                else -> {}
            }
            GhostButton("Message", Modifier.padding(top = 10.dp)) { onChatWith(r.providerName, r.category) }
        }
    }
}
