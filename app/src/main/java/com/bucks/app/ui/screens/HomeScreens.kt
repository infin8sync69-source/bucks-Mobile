package com.bucks.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Role
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Good
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.data.DriverLocationService

val MeColor = Color(0xFF1D4ED8)

@Composable
fun SearchBar(hint: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick), shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Search, null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(24.dp)); Spacer(Modifier.width(16.dp)); Text(hint, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

data class ServiceTile(val name: String, val icon: ImageVector, val query: String)
val HOME_SERVICES = listOf(ServiceTile("Ride", Icons.Rounded.LocalTaxi, "ride"), ServiceTile("Food", Icons.Rounded.Restaurant, "biriyani"), ServiceTile("Grocery", Icons.Rounded.ShoppingBasket, "sugar"), ServiceTile("Plumber", Icons.Rounded.Plumbing, "plumber"),
    ServiceTile("Doctor", Icons.Rounded.MedicalServices, "doctor"), ServiceTile("Electric", Icons.Rounded.ElectricalServices, "electrician"), ServiceTile("Fitness", Icons.Rounded.FitnessCenter, "gym trainer"), ServiceTile("All", Icons.Rounded.GridView, "services"))

@Composable
fun HomeScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit, onServices: () -> Unit, onProCreate: () -> Unit, onEarnings: () -> Unit, onListings: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit = { _, _ -> }) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // An accepted ride takes over Home until it's closed.
    if (s.driverRide != null && s.driverRide?.status != DriverRideStatus.RINGING) { DriverTripScreen(vm, onChatWith, onCall); return }
    var showOnline by remember { mutableStateOf(false) }
    val wide = windowWidth() != Width.COMPACT
    val unread = chats.sumOf { it.unread }
    run {
        val pins = listOf(MapPin(s.meX, s.meY, "You", MeColor, big = true)) + providers.filter { it.scope == Scope.LOCAL }.take(6).map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) } + drivers.filter { it.online }.map { MapPin(it.x, it.y, "", Good) }
        val panel: @Composable ColumnScope.() -> Unit = {
            SearchBar("Search or ask · sugar, doctor, bike to MG Road", onClick = onSearch)
            Row(Modifier.padding(top = 18.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) { SectionTitle("Near you", Modifier.weight(1f)); Muted("${drivers.count { it.online }} riders online") }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { HOME_SERVICES.take(4).forEach { ServiceCell(it, Modifier.weight(1f)) { when (it.query) { "ride" -> onRide(); "services" -> onServices(); else -> onQuery(it.query) } } } }
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { HOME_SERVICES.drop(4).forEach { ServiceCell(it, Modifier.weight(1f)) { when (it.query) { "ride" -> onRide(); "services" -> onServices(); else -> onQuery(it.query) } } } }
        }
        if (wide) Column(Modifier.fillMaxSize()) {
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Row(Modifier.weight(1f)) { Box(Modifier.weight(1.2f).fillMaxHeight()) { BucksMap(Modifier.fillMaxSize(), pins); MapAttribution(Modifier.align(Alignment.BottomStart).padding(8.dp)) }; Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), content = panel) }
        }
        // Phone: full-bleed map with a floating top card and a search-only sheet; services live in the Services tab.
        else Box(Modifier.fillMaxSize()) {
            BucksMap(Modifier.fillMaxSize(), pins)
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                MapAttribution(Modifier.padding(start = 12.dp, bottom = 4.dp))
                Sheet { SearchBar("Search", onClick = onSearch); Spacer(Modifier.height(24.dp)) }
            }
            // Pulled up past the top edge so the card's shadow only shows along its rounded bottom.
            if (s.receiving) OnlineFab(Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 150.dp)) { showOnline = true }
            s.driverRide?.takeIf { it.status == DriverRideStatus.RINGING }?.let { dr -> RideRequestCard(dr, onAccept = { vm.driverAccept() }, onDecline = { vm.driverDecline() }, modifier = Modifier.align(Alignment.Center)) }
            Surface(Modifier.fillMaxWidth().offset(y = (-24).dp), shape = RoundedCornerShape(bottomStart = 24.dp, bottomEnd = 24.dp), color = MaterialTheme.colorScheme.surface, shadowElevation = 6.dp) {
                Box(Modifier.padding(start = 8.dp, end = 8.dp, top = 38.dp, bottom = 14.dp)) { BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages) }
            }
        }
    }
    if (showOnline) OnlineSheet(vm, onDismiss = { showOnline = false }, onListings = onListings, onEarnings = onEarnings)
}

@Composable
fun ServiceCell(t: ServiceTile, modifier: Modifier = Modifier, onClick: () -> Unit) = Column(modifier.clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Box(Modifier.size(54.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(t.icon, t.name, tint = MaterialTheme.colorScheme.onSurface) }
    Text(t.name, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
}

private data class Offer(val name: String, val icon: ImageVector, val live: Boolean)
private val OFFERS = listOf(Offer("Taxi", Icons.Rounded.LocalTaxi, true), Offer("Jobs", Icons.Rounded.Work, true), Offer("Tools", Icons.Rounded.Handyman, true), Offer("Shopping", Icons.Rounded.ShoppingBag, true), Offer("Pay", Icons.Rounded.Payments, false),
    Offer("Book Tickets", Icons.Rounded.ConfirmationNumber, false), Offer("Delivery", Icons.Rounded.LocalShipping, false), Offer("Community", Icons.Rounded.Groups, false), Offer("Services", Icons.Rounded.DesignServices, false), Offer("Banking", Icons.Rounded.AccountBalance, false))

@Composable
fun ServicesScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState()
    val cats = providers.map { it.category }.distinct()
    Box(Modifier.fillMaxSize()) {
        BucksMap(Modifier.fillMaxSize(), listOf(MapPin(s.meX, s.meY, "You", MeColor, big = true)) + providers.filter { it.scope == Scope.LOCAL }.map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) })
        Sheet(Modifier.align(Alignment.BottomCenter)) { Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) {
            Text("Services we Offer", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 14.dp))
            OFFERS.chunked(5).forEach { row -> Row(Modifier.padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { o ->
                Column(Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).clickable { when (o.name) { "Taxi" -> onRide(); "Jobs" -> onQuery("jobs"); "Tools" -> onQuery("hardware"); "Shopping" -> onQuery("grocery"); else -> vm.toast("${o.name} is coming soon") } }.padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(52.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceContainer), contentAlignment = Alignment.Center) {
                        Icon(o.icon, null, tint = if (o.live) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                        if (!o.live) Icon(Icons.Rounded.Lock, "Coming soon", Modifier.align(Alignment.TopEnd).padding(4.dp).size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text(o.name, style = MaterialTheme.typography.labelSmall, color = if (o.live) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp), maxLines = 1)
                } } } }
            SearchBar("Search or ask anything", Modifier.padding(top = 6.dp), onClick = onSearch)
            SectionTitle("Categories", Modifier.padding(top = 18.dp, bottom = 10.dp))
            FlowChips(cats) { onQuery(it.lowercase()) }
            SectionTitle("Skills A to Z", Modifier.padding(top = 18.dp, bottom = 10.dp))
            FlowChips(Seed.SKILLS.take(18)) { onQuery(it.lowercase()) }
        } }
    }
}
