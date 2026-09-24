package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.*
import com.bucks.app.ui.AskMode
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.ScopeFilter
import com.bucks.app.ui.SortMode
import com.bucks.app.ui.components.*
import com.bucks.app.ui.VOICE_LANGS
import com.bucks.app.ui.rememberVoiceInput
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import android.content.Intent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import coil.compose.AsyncImage
import com.bucks.app.ui.theme.Brand
import com.bucks.app.ui.theme.Good
import kotlin.math.ceil

@Composable
fun ProviderRow(p: Provider, trust: Trust = p.trust, onClick: () -> Unit) {
    ListRow(p.name, "${p.category} · ${p.distanceKm} km" + (p.rate?.let { " · $it" } ?: "") + (if (p.items.isNotEmpty()) " · from ₹${p.minPrice}" else ""), leading = { Avatar(icon = p.icon, tinted = false) },
        trailing = { Column(horizontalAlignment = Alignment.End) { TrustBadge(trust, compact = true); Spacer(Modifier.height(4.dp)); if (p.scope == Scope.LOCAL) PillPurple("Local") else PillGrey("Global") } }, onClick = onClick)
    Divider()
}

@Composable
fun SearchScreen(vm: BucksViewModel, onBack: () -> Unit, onProvider: (String, String) -> Unit, onRequest: (String) -> Unit, onMessages: () -> Unit, onChatWith: (String, String) -> Unit = { _, _ -> }, onCall: (String, String) -> Unit = { _, _ -> }, onCart: () -> Unit = {}, showToast: (String) -> Unit = {}) {
    val s by vm.state.collectAsState(); val ctx = LocalContext.current
    var input by remember { mutableStateOf(s.query) }; var advanced by remember { mutableStateOf(false) }
    val chat = s.askMode == AskMode.CHAT
    val results = if (chat) emptyList() else vm.results()
    fun submit(q: String) { vm.submitQuery(q); input = if (vm.isAgentQuery(q) || s.pending != null) "" else q }
    val (voice, listen) = rememberVoiceInput(s.voiceLang, onResult = { heard -> input = heard; submit(heard) }, onError = { msg -> showToast(msg) })
    val cartCount = s.cart.values.sum()
    Box(Modifier.fillMaxSize()) { ContentColumn(Modifier.fillMaxHeight()) {
        Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp).fillMaxWidth().height(56.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(start = 18.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.size(24.dp)); Spacer(Modifier.width(14.dp))
            BasicTextField(input, { input = it }, Modifier.weight(1f), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(Brand),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit(input) }),
                decorationBox = { inner -> Box { if (input.isEmpty()) Text(if (voice.listening) voice.partial.ifBlank { "Listening…" } else "Search", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant); inner() } })
            IconButton(onClick = listen) { Icon(if (voice.listening) Icons.Rounded.GraphicEq else Icons.Rounded.Mic, "Speak", tint = if (voice.listening) Brand else MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)).background(if (advanced) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.surfaceContainer).clickable { advanced = !advanced }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Tune, "More filters", tint = if (advanced) MaterialTheme.colorScheme.onSecondary else MaterialTheme.colorScheme.onSurface) }
            FilterPill("Available Now", s.scope == ScopeFilter.LOCAL) { vm.setScope(if (s.scope == ScopeFilter.LOCAL) ScopeFilter.ALL else ScopeFilter.LOCAL) }
            FilterPill("Most Recommend", s.sort == SortMode.TRUST) { vm.setSort(SortMode.TRUST) }
            DropPill("Ratings", s.lens.takeIf { it != Lens.ALL }?.label, Lens.entries.map { it.label }) { vm.setLens(Lens.entries[it]) }
            DropPill("Sort", s.sort.takeIf { it != SortMode.TRUST }?.label, SortMode.entries.map { it.label }) { vm.setSort(SortMode.entries[it]) }
        }
        if (advanced) Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { ScopeFilter.entries.forEach { f -> Chip(f.label, purple = s.scope == f) { vm.setScope(f) } } }
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { VOICE_LANGS.forEach { (tag, label) -> Chip(label, purple = s.voiceLang == tag) { vm.setVoiceLang(tag) } }; if (vm.cloudEnabled) Chip("Cloud AI on", selected = true) {} }
        }
        if (s.thinking) LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = 20.dp), color = Brand)
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = if (cartCount > 0) 96.dp else 24.dp)) {
            if (chat) items(s.agent) { m -> AgentBubble(m, onAction = { submit(it) }, onCard = { c -> when (val a = c.action) { is AgentAction.OpenProvider -> onProvider(a.id, a.tab); is AgentAction.Request -> onRequest(a.providerId) } }) }
            else {
                if (s.query.isBlank()) item { Column(Modifier.padding(20.dp)) { SectionTitle("Try", Modifier.padding(bottom = 10.dp)); FlowChips(listOf("sugar", "biriyani", "plumber", "doctor", "Bike to Koramangala", "Compare grocery for sugar", "Show my orders")) { input = it; submit(it) } } }
                itemsIndexed(results, key = { _, p -> p.id }) { i, p ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceContainer))
                    ResultSection(p, vm.trustFor(p), followed = p.id in s.followedProviders, cart = s.cart, onFollow = { vm.followProvider(p.id) }, onOpen = { tab -> onProvider(p.id, tab) }, onAdd = { idx, d -> vm.cartAdd(p.id, idx, d) }, onRequest = { onRequest(p.id) },
                        onEnquiry = { onChatWith(p.name, p.category) }, onCall = { onCall(p.name, p.phone) },
                        onShare = { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "${p.name} on Bucks · ${p.category}, ${p.distanceKm} km away") }, "Share ${p.name}")) })
                }
                if (s.query.isNotBlank() && results.isEmpty()) item { Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) { Muted("No one offers \"${s.query}\" yet.", align = TextAlign.Center); TextButton(onClick = { submit("post a request for ${s.query}") }) { Text("Ask people nearby") } } }
            }
        }
    }
        if (cartCount > 0) DarkButton("View cart · $cartCount item${if (cartCount == 1) "" else "s"}", Modifier.align(Alignment.BottomCenter).padding(20.dp), onClick = onCart)
    }
}

@Composable
private fun FilterPill(text: String, selected: Boolean, trailing: ImageVector? = null, onClick: () -> Unit) =
    Row(Modifier.height(40.dp).clip(RoundedCornerShape(6.dp)).then(if (selected) Modifier.background(MaterialTheme.colorScheme.secondary) else Modifier.border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(6.dp))).clickable(onClick = onClick).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        val c = if (selected) MaterialTheme.colorScheme.onSecondary else MaterialTheme.colorScheme.onSurfaceVariant
        Text(text, style = MaterialTheme.typography.bodyLarge, color = c); trailing?.let { Icon(it, null, Modifier.padding(start = 4.dp).size(18.dp), tint = c) } }

@Composable
private fun DropPill(label: String, chosen: String?, options: List<String>, onPick: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box { FilterPill(chosen ?: label, chosen != null, Icons.Rounded.KeyboardArrowDown) { open = true }
        DropdownMenu(open, { open = false }) { options.forEachIndexed { i, o -> DropdownMenuItem(text = { Text(o) }, onClick = { open = false; onPick(i) }) } } }
}

/** One provider in the results: header with Follow, item carousel (or rate + Request for skills), vote stats and actions. */
@Composable
fun ResultSection(p: Provider, trust: Trust, followed: Boolean, cart: Map<String, Int>, onFollow: () -> Unit, onOpen: (String) -> Unit, onAdd: (Int, Int) -> Unit, onRequest: () -> Unit, onEnquiry: () -> Unit, onCall: () -> Unit, onShare: () -> Unit) {
    val mins = ceil(p.distanceKm * 3).toInt().coerceAtLeast(1)  // ~20 km/h city travel
    Column(Modifier.fillMaxWidth().padding(vertical = 20.dp)) {
        Row(Modifier.padding(horizontal = 20.dp).clickable { onOpen("about") }, verticalAlignment = Alignment.CenterVertically) {
            Avatar(icon = p.icon, size = 56, tinted = false)
            Column(Modifier.weight(1f).padding(horizontal = 14.dp)) { Text(p.name, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted("~$mins min · ${p.distanceKm} km away · ${Geo.nearestArea(p.pos)}", maxLines = 1) }
            Row(Modifier.clip(RoundedCornerShape(10.dp)).background(Brand.copy(alpha = 0.1f)).clickable(onClick = onFollow).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (followed) Icons.Rounded.Check else Icons.Rounded.Add, null, Modifier.size(18.dp), tint = Brand); Text(if (followed) "Following" else "Follow", style = MaterialTheme.typography.labelLarge, color = Brand, modifier = Modifier.padding(start = 6.dp)) }
        }
        if (p.items.isNotEmpty()) LazyRow(Modifier.padding(top = 16.dp), contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            itemsIndexed(p.items) { i, it -> ItemCard(it, p.icon, cart["${p.id}:$i"] ?: 0, onOpen = { onOpen("items") }) { d -> onAdd(i, d) } }
        } else Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text(p.rate ?: "Rate on request", style = MaterialTheme.typography.titleMedium); Muted(p.bio, maxLines = 2) }
            OutlinedButton(onRequest, shape = RoundedCornerShape(6.dp), border = BorderStroke(1.dp, Brand)) { Text("Request", color = Brand) }
        }
        Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.clip(RoundedCornerShape(12.dp)).background(Good.copy(alpha = 0.1f)).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { Text("${trust.up}", style = MaterialTheme.typography.titleSmall, color = Good); Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(16.dp), tint = Good) }
            Text("${p.comments.count { it.vote > 0 }} People Recommended", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("${p.comments.size} Reviews", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.clickable { onOpen("votes") })
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionPill("Enquiry", Icons.Rounded.Sms, onEnquiry); ActionPill("Call", Icons.Rounded.Call, onCall); ActionPill("Recommend", Icons.Rounded.Leaderboard) { onOpen("votes") }; ActionPill("Share", Icons.Rounded.Share, onShare)
        }
    }
}

@Composable
private fun ActionPill(text: String, icon: ImageVector, onClick: () -> Unit) = Row(Modifier.clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(text, style = MaterialTheme.typography.bodyMedium); Icon(icon, null, Modifier.padding(start = 8.dp).size(18.dp)) }

@Composable
private fun ItemCard(item: Item, fallback: ImageVector, qty: Int, onOpen: () -> Unit, onAdd: (Int) -> Unit) = Column(Modifier.width(160.dp)) {
    Box(Modifier.size(160.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onOpen), contentAlignment = Alignment.Center) {
        if (item.image.isNotBlank()) AsyncImage(item.image, item.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) else Icon(fallback, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)) }
    Text(item.name + (item.detail.takeIf { it.isNotBlank() }?.let { " ($it)" } ?: ""), style = MaterialTheme.typography.bodyMedium, maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("₹${item.price}", style = MaterialTheme.typography.titleSmall)
        if (item.mrp > item.price) { Text("₹${item.mrp}", style = MaterialTheme.typography.bodySmall.copy(textDecoration = TextDecoration.LineThrough), color = MaterialTheme.colorScheme.onSurfaceVariant); Text("${(item.mrp - item.price) * 100 / item.mrp}% Off", style = MaterialTheme.typography.bodySmall, color = Good) }
    }
    if (qty == 0) OutlinedButton({ onAdd(1) }, Modifier.fillMaxWidth().padding(top = 8.dp).height(40.dp), shape = RoundedCornerShape(6.dp), border = BorderStroke(1.dp, Brand), contentPadding = PaddingValues(0.dp)) { Text("Add to Cart", color = Brand) }
    else Row(Modifier.fillMaxWidth().padding(top = 8.dp).height(40.dp).clip(RoundedCornerShape(6.dp)).background(Brand), verticalAlignment = Alignment.CenterVertically) {
        IconButton({ onAdd(-1) }) { Icon(Icons.Rounded.Remove, "Remove one", tint = Color.White) }; Text("$qty", Modifier.weight(1f), color = Color.White, textAlign = TextAlign.Center, style = MaterialTheme.typography.titleSmall); IconButton({ onAdd(1) }) { Icon(Icons.Rounded.Add, "Add one", tint = Color.White) } }
}

@Composable
fun AgentBubble(m: AgentMessage, onAction: (String) -> Unit, onCard: (AgentCard) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
        Column(Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(18.dp)).background(if (m.mine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer).padding(14.dp)) {
            Text(m.text, style = MaterialTheme.typography.bodyMedium, color = if (m.mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
            m.cards.forEach { c -> Surface(modifier = Modifier.padding(top = 8.dp).fillMaxWidth(), shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surface, onClick = { onCard(c) }) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(c.title, style = MaterialTheme.typography.titleMedium); Muted(c.detail) }; PillPurple(c.cta) } } }
            if (m.actions.isNotEmpty()) Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { m.actions.chunked(2).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { row.forEach { a -> Chip(a, purple = true) { onAction(a) } } } } }
        }
    }
}
