package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Role
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.data.DriverLocationService

val MeColor = Color(0xFF1D4ED8)

@Composable
fun SearchBar(hint: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(modifier.fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).clickable(onClick = onClick), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Search, null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(24.dp)); Spacer(Modifier.width(16.dp)); Text(hint, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

/** Explains the pin colours on the maps: providers are drawn in the theme primary, online riders in status good (only where the map shows riders). */
@Composable
private fun MapLegend(modifier: Modifier = Modifier, riders: Boolean = true) = Surface(modifier, shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 2.dp) {
    Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { LegendDot(MaterialTheme.colorScheme.primary, "Shops & services"); if (riders) LegendDot(MaterialTheme.status.good, "Riders online") }
}
@Composable
private fun LegendDot(color: Color, text: String) = Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(color)); Spacer(Modifier.width(6.dp)); Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
/** Legend at the start and the OSM attribution at the end, sitting on the map just above the sheet. */
@Composable
private fun MapFooter(modifier: Modifier = Modifier, riders: Boolean = true) = Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) { MapLegend(riders = riders); Spacer(Modifier.weight(1f)); MapAttribution() }

@Composable
fun HomeScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit, onServices: () -> Unit, onProCreate: () -> Unit, onEarnings: () -> Unit, onListings: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit = { _, _ -> }) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // An accepted ride takes over Home until it's closed.
    if (s.driverRide != null && s.driverRide?.status != DriverRideStatus.RINGING) { DriverTripScreen(vm, onChatWith, onCall); return }
    var showOnline by remember { mutableStateOf(false) }
    val wide = windowWidth() != Width.COMPACT
    val unread = chats.sumOf { it.unread }
    run {
        val pins = listOf(MapPin(s.meX, s.meY, "You", MeColor, big = true)) + providers.filter { it.scope == Scope.LOCAL }.take(6).map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) } + drivers.filter { it.online }.map { MapPin(it.x, it.y, "", MaterialTheme.status.good) }
        // Same content on phones (in the sheet) and wide screens (in the side panel): the search pill; services live in the Services tab.
        val panel: @Composable ColumnScope.() -> Unit = {
            SearchBar("Where to, or what do you need?", onClick = onSearch)
        }
        if (wide) Column(Modifier.fillMaxSize()) {
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Row(Modifier.weight(1f)) { Box(Modifier.weight(1.2f).fillMaxHeight()) { BucksMap(Modifier.fillMaxSize(), pins); MapFooter(Modifier.align(Alignment.BottomStart).padding(8.dp)) }; Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Gutter), content = panel) }
        }
        // Phone: full-bleed map with the wordmark bar laid over it; the sheet holds the search pill, services live in the Services tab.
        else Box(Modifier.fillMaxSize()) {
            BucksMap(Modifier.fillMaxSize(), pins)
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                MapFooter(Modifier.padding(horizontal = Gutter, vertical = 8.dp))
                Sheet { panel(); Spacer(Modifier.height(24.dp)) }
            }
            if (s.receiving) OnlineFab(Modifier.align(Alignment.BottomEnd).padding(end = Gutter, bottom = 190.dp)) { showOnline = true }
            s.driverRide?.takeIf { it.status == DriverRideStatus.RINGING }?.let { dr -> RideRequestCard(dr, onAccept = { vm.driverAccept() }, onDecline = { vm.driverDecline() }, modifier = Modifier.align(Alignment.Center)) }
        }
    }
    if (showOnline) OnlineSheet(vm, onDismiss = { showOnline = false }, onListings = onListings, onEarnings = onEarnings)
}

/** Services that open for the pilot. Add a name here to unlock its tile; everything else shows a padlock and "coming soon". */
private val LIVE_SERVICES = setOf("Taxi")
private data class Offer(val name: String, val icon: ImageVector) { val live get() = name in LIVE_SERVICES }
private val OFFERS = listOf(Offer("Taxi", Icons.Rounded.LocalTaxi), Offer("Jobs", Icons.Rounded.Work), Offer("Foods", Icons.Rounded.Restaurant), Offer("Shopping", Icons.Rounded.ShoppingBag), Offer("Pay", Icons.Rounded.Payments),
    Offer("Book Tickets", Icons.Rounded.ConfirmationNumber), Offer("Delivery", Icons.Rounded.LocalShipping), Offer("Community", Icons.Rounded.Groups), Offer("Networks", Icons.Rounded.People), Offer("Banking", Icons.Rounded.AccountBalance))

@Composable
private fun OfferTile(o: Offer, modifier: Modifier, onClick: () -> Unit) {
    val fg = if (o.live) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    Box(modifier.height(64.dp)) {
        Column(Modifier.fillMaxSize().padding(top = 4.dp, end = 4.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(horizontal = 2.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(o.icon, null, tint = fg)
            Text(o.name, style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp), color = fg, modifier = Modifier.padding(top = 4.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        // Padlock badge on the top-right corner, like the design.
        if (!o.live) Box(Modifier.align(Alignment.TopEnd).size(18.dp).clip(MaterialTheme.shapes.extraSmall).background(MaterialTheme.colorScheme.surface), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Lock, "Locked", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun ServicesScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    val cats = providers.map { it.category }.distinct()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // Natural height up to ~60% of the screen, and never tall enough (with the footer) to reach the top bar on short screens.
        val sheetMax = (maxHeight * 0.6f).coerceAtMost(maxHeight - 120.dp).coerceAtLeast(0.dp)
        BucksMap(Modifier.fillMaxSize(), listOf(MapPin(s.meX, s.meY, "You", MeColor, big = true)) + providers.filter { it.scope == Scope.LOCAL }.map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) })
        BucksTopBar(onMenu = onMenu, unread = chats.sumOf { it.unread }, onChat = onMessages)
        // Same footer as Home (legend + OSM attribution) sitting on the map just above the sheet; this map has no rider pins.
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            MapFooter(Modifier.padding(horizontal = Gutter, vertical = 8.dp), riders = false)
            Sheet(Modifier.heightIn(max = sheetMax)) { Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Text("Services we offer", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 14.dp))
                // Every service gets a tile, 5 per row; locked ones are dimmed with a padlock and only say "coming soon".
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { OFFERS.chunked(5).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { row.forEach { o ->
                        OfferTile(o, Modifier.weight(1f)) {
                            if (!o.live) vm.toast("${o.name} is coming soon")
                            else when (o.name) { "Taxi" -> onRide(); "Jobs" -> onQuery("jobs"); "Foods" -> onQuery("food"); "Shopping" -> onQuery("grocery"); else -> vm.toast("${o.name} is coming soon") }
                        }
                    } }
                } }
                SearchBar("Search or ask anything", Modifier.padding(top = 14.dp), onClick = onSearch)
                SectionTitle("Categories", Modifier.padding(top = 18.dp, bottom = 10.dp))
                FlowChips(cats) { onQuery(it.lowercase()) }
                SectionTitle("Skills A to Z", Modifier.padding(top = 18.dp, bottom = 10.dp))
                FlowChips(Seed.SKILLS.take(18)) { onQuery(it.lowercase()) }
                // Room under the last chip row so scrolling to the end never leaves it sliced by the sheet edge.
                Spacer(Modifier.height(24.dp))
            } }
        }
    }
}
