package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.foundation.clickable
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Constraints
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
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
        Row(Modifier.padding(start = Gutter, end = Gutter, top = 20.dp).fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(start = 18.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.size(24.dp)); Spacer(Modifier.width(14.dp))
            BasicTextField(input, { input = it }, Modifier.weight(1f), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit(input) }),
                decorationBox = { inner -> Box { if (input.isEmpty()) Text(if (voice.listening) voice.partial.ifBlank { "Listening…" } else "Search", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant); inner() } })
            IconButton(onClick = listen) { Icon(if (voice.listening) Icons.Rounded.GraphicEq else Icons.Rounded.Mic, "Speak", tint = if (voice.listening) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = Gutter, end = Gutter, top = 16.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            // Chip-height (32dp) pill with the same 48dp touch target as the chips, so the row lines up.
            Box(Modifier.minimumInteractiveComponentSize().size(width = 44.dp, height = 32.dp).clip(CircleShape).background(if (advanced) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable { advanced = !advanced }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Tune, "More filters", Modifier.size(18.dp), tint = if (advanced) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface) }
            Chip(ScopeFilter.LOCAL.label, selected = s.scope == ScopeFilter.LOCAL) { vm.setScope(if (s.scope == ScopeFilter.LOCAL) ScopeFilter.ALL else ScopeFilter.LOCAL) }
            DropPill(SortMode.TRUST.label, s.sort.takeIf { it != SortMode.TRUST }?.label, SortMode.entries.map { it.label }) { vm.setSort(SortMode.entries[it]) }
            DropPill("Reviews from", s.lens.takeIf { it != Lens.ALL }?.label, Lens.entries.map { it.label }) { vm.setLens(Lens.entries[it]) }
        }
        if (advanced) Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.horizontalScrollIfNeeded().padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(6.dp)) { ScopeFilter.entries.forEach { f -> Chip(f.label, selected = s.scope == f) { vm.setScope(f) } } }
            Row(Modifier.horizontalScrollIfNeeded().padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(6.dp)) { VOICE_LANGS.forEach { (tag, label) -> Chip(label, selected = s.voiceLang == tag) { vm.setVoiceLang(tag) } }; if (vm.cloudEnabled) Chip("Cloud AI on", selected = true) {} }
        }
        if (s.thinking) LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Gutter), color = MaterialTheme.colorScheme.primary)
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = if (cartCount > 0) 96.dp else 24.dp)) {
            if (chat) items(s.agent) { m -> AgentBubble(m, onAction = { submit(it) }, onCard = { c -> when (val a = c.action) { is AgentAction.OpenProvider -> onProvider(a.id, a.tab ?: ""); is AgentAction.Request -> onRequest(a.providerId) } }) }
            else {
                if (s.query.isBlank()) item { Column(Modifier.padding(Gutter)) { SectionTitle("Try", Modifier.padding(bottom = 10.dp)); FlowChips(TRY_QUERIES.keys.toList()) { val q = TRY_QUERIES.getValue(it); input = q; submit(q) } } }
                itemsIndexed(results, key = { _, p -> p.id }) { i, p ->
                    Box(Modifier.padding(start = Gutter, end = Gutter, top = if (i > 0) 12.dp else 0.dp)) {
                        ResultSection(p, vm.trustFor(p), followed = p.id in s.followedProviders, cart = s.cart, onFollow = { vm.followProvider(p.id) }, onOpen = { tab -> onProvider(p.id, tab) }, onAdd = { idx, d -> vm.cartAdd(p.id, idx, d) }, onRequest = { onRequest(p.id) },
                            onEnquiry = { onChatWith(p.name, p.category) }, onCall = { onCall(p.name, p.phone) },
                            onShare = { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "${p.name} on Bucks · ${p.category}, ${p.distanceKm} km away") }, "Share ${p.name}")) })
                    }
                }
                if (s.query.isNotBlank() && results.isEmpty()) item { Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) { Muted("No one offers \"${s.query}\" yet.", align = TextAlign.Center); TextButton(onClick = { submit("post a request for ${s.query}") }) { Text("Ask people nearby") } } }
            }
        }
    }
        if (cartCount > 0) DarkButton("View cart · $cartCount item${if (cartCount == 1) "" else "s"}", Modifier.align(Alignment.BottomCenter).padding(Gutter), onClick = onCart)
    }
}

/** Empty-state suggestions: sentence-case chip label to the exact query it submits. */
private val TRY_QUERIES = mapOf("Sugar" to "sugar", "Biriyani" to "biriyani", "Plumber" to "plumber", "Doctor" to "doctor", "Bike to Koramangala" to "Bike to Koramangala", "Compare grocery for sugar" to "Compare grocery for sugar", "Show my orders" to "Show my orders")

/** Same look as the shared Chip, plus a trailing icon for dropdowns. */
@Composable
private fun FilterPill(text: String, selected: Boolean, trailing: ImageVector? = null, onClick: () -> Unit) =
    Row(Modifier.minimumInteractiveComponentSize().clip(CircleShape).background(if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(horizontal = 13.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        val c = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface
        Text(text, style = MaterialTheme.typography.labelMedium, color = c); trailing?.let { Icon(it, null, Modifier.padding(start = 2.dp).size(16.dp), tint = c) } }

@Composable
private fun DropPill(label: String, chosen: String?, options: List<String>, onPick: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box { FilterPill(chosen ?: label, chosen != null, Icons.Rounded.KeyboardArrowDown) { open = true }
        DropdownMenu(open, { open = false }) { options.forEachIndexed { i, o -> DropdownMenuItem(text = { Text(o) }, onClick = { open = false; onPick(i) }) } } }
}

/** One provider in the results: a card with header + Follow, up to three items (or rate + Request for skills, or Message for a business with no products), the trust badge with Share, and three actions. */
@Composable
fun ResultSection(p: Provider, trust: Trust, followed: Boolean, cart: Map<String, Int>, onFollow: () -> Unit, onOpen: (String) -> Unit, onAdd: (Int, Int) -> Unit, onRequest: () -> Unit, onEnquiry: () -> Unit, onCall: () -> Unit, onShare: () -> Unit) {
    val mins = ceil(p.distanceKm * 3).toInt().coerceAtLeast(1)  // ~20 km/h city travel
    BucksCard(padding = 12) {
        Row(Modifier.clickable { onOpen("") }, verticalAlignment = Alignment.CenterVertically) {
            Avatar(icon = p.icon, size = 56, tinted = false)
            // Area on its own line, distance and ETA below, so the Follow pill never pushes the ETA off.
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(p.name, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(Geo.nearestArea(p.pos), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted("${p.distanceKm} km · ~$mins min", maxLines = 1) }
            Row(Modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primaryContainer).clickable(onClick = onFollow).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                val c = MaterialTheme.colorScheme.onPrimaryContainer
                Icon(if (followed) Icons.Rounded.Check else Icons.Rounded.Add, null, Modifier.size(18.dp), tint = c); Text(if (followed) "Following" else "Follow", style = MaterialTheme.typography.labelLarge, color = c, modifier = Modifier.padding(start = 6.dp)) }
        }
        if (p.items.isNotEmpty()) Column(Modifier.padding(top = 8.dp)) {
            p.items.take(3).forEachIndexed { i, it -> ItemLine(it, cart["${p.id}:$i"] ?: 0, onOpen = { onOpen("items") }) { d -> onAdd(i, d) } }
            // 32dp tall (touch target is still extended to 48dp) so no dead band opens between it and the trust badge.
            if (p.items.size > 3) TextButton(onClick = { onOpen("items") }, modifier = Modifier.height(32.dp), contentPadding = PaddingValues(0.dp)) { Text("See all ${p.items.size} items", style = MaterialTheme.typography.labelMedium) }
        } else if (p.type == ProviderType.BUSINESS) Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Muted("No products listed yet", Modifier.weight(1f).padding(end = 12.dp)); SmallButton("Message", tonal = true, onClick = onEnquiry)
        } else Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(p.rate ?: "Rate on request", style = MaterialTheme.typography.titleMedium); Muted(p.bio, maxLines = 2) }
            OutlinedButton(onRequest, shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary)) { Text("Request", color = MaterialTheme.colorScheme.primary) }
        }
        // Share lives here (the header has no room for it at 360dp next to Follow); its 48dp touch height gives the badge its ~12dp spacing above and below.
        Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.weight(1f)) { TrustBadge(trust) }; IconButton(onClick = onShare) { Icon(Icons.Rounded.Share, "Share ${p.name}", Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionPill("Message", Icons.Rounded.Sms, Modifier.weight(1f), onEnquiry); ActionPill("Call", Icons.Rounded.Call, Modifier.weight(1f), onCall); ActionPill("Recommend", Icons.Rounded.Leaderboard, Modifier.weight(1f)) { onOpen("votes") }
        }
    }
}

/** Equal-width action pill: icon + label, centred. When the label can't fit the slot (360dp phones, large fonts) the pill shows the icon alone, still announced by its label, so nothing is ever clipped. */
@Composable
private fun ActionPill(text: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) = Box(modifier.minimumInteractiveComponentSize().clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onClick).clearAndSetSemantics { contentDescription = text }.padding(horizontal = 8.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
    Layout({ Icon(icon, null, Modifier.size(18.dp)); Text(text, style = MaterialTheme.typography.labelMedium, maxLines = 1, softWrap = false) }) { ms, c ->
        val gap = 6.dp.roundToPx(); val ip = ms[0].measure(Constraints()); val tp = ms[1].measure(Constraints())
        val label = ip.width + gap + tp.width <= c.maxWidth
        val w = if (label) ip.width + gap + tp.width else ip.width; val h = if (label) maxOf(ip.height, tp.height) else ip.height
        layout(w, h) { ip.placeRelative(0, (h - ip.height) / 2); if (label) tp.placeRelative(ip.width + gap, (h - tp.height) / 2) }
    }
}

/** One product line in a result card; tapping the row opens the items tab, Add puts one in the cart, then a -/qty/+ stepper adjusts it. */
@Composable
private fun ItemLine(item: Item, qty: Int, onOpen: () -> Unit, onAdd: (Int) -> Unit) = Row(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(item.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis); if (item.detail.isNotBlank()) Muted(item.detail, maxLines = 1) }
    Text("₹${item.price}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(end = 10.dp))
    AddStepper(qty, onAdd)
}

@Composable
fun AgentBubble(m: AgentMessage, onAction: (String) -> Unit, onCard: (AgentCard) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 4.dp), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
        Column(Modifier.widthIn(max = 420.dp).clip(MaterialTheme.shapes.large).background(if (m.mine) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer).padding(12.dp)) {
            Text(m.text, style = MaterialTheme.typography.bodyMedium, color = if (m.mine) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
            m.cards.forEach { c -> Surface(modifier = Modifier.padding(top = 8.dp).fillMaxWidth(), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surface, onClick = { onCard(c) }) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(c.title, style = MaterialTheme.typography.titleMedium); Muted(c.detail) }; PillPurple(c.cta) } } }
            if (m.actions.isNotEmpty()) Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { m.actions.chunked(2).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { row.forEach { a -> Chip(a, selected = true) { onAction(a) } } } } }
        }
    }
}
