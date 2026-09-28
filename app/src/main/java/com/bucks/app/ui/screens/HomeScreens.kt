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
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.ServiceDef
import com.bucks.app.ui.SERVICE_CATALOG
import com.bucks.app.ui.serviceDef
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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

/** Explains the pin colours on the maps: providers are drawn in the theme primary (only where the map shows them), online riders in status good (only where the map shows riders). */
@Composable
private fun MapLegend(modifier: Modifier = Modifier, riders: Boolean = true, shops: Boolean = true) = Surface(modifier, shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 2.dp) {
    Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { if (shops) LegendDot(MaterialTheme.colorScheme.primary, "Shops & services"); if (riders) LegendDot(MaterialTheme.status.good, "Riders online") }
}
@Composable
private fun LegendDot(color: Color, text: String) = Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(color)); Spacer(Modifier.width(6.dp)); Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
/** Legend at the start and the OSM attribution at the end, sitting on the map just above the sheet. */
@Composable
private fun MapFooter(modifier: Modifier = Modifier, riders: Boolean = true, shops: Boolean = true) = Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) { if (riders || shops) MapLegend(riders = riders, shops = shops); Spacer(Modifier.weight(1f)); MapAttribution() }

/** Cloud builds: category chips for searching live listings (the categories shops and pros pick from when they list), not the demo seed's. */
private val CLOUD_CATEGORIES = (com.bucks.app.ui.screens.manage.BUSINESS_CATEGORIES + com.bucks.app.ui.screens.manage.SKILL_CATEGORIES).filter { it != "Other" }.distinct()

@Composable
fun HomeScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit, onServices: () -> Unit, onProCreate: () -> Unit, onEarnings: () -> Unit, onListings: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit = { _, _ -> }) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // An accepted ride takes over Home until it's closed.
    if (s.driverRide != null && s.driverRide?.status != DriverRideStatus.RINGING) { DriverTripScreen(vm, onChatWith, onCall); return }
    // Cloud dispatch polls online drivers every 15 s only while a map is on screen.
    DisposableEffect(Unit) { vm.dispatch.mapShown(); onDispose { vm.dispatch.mapHidden() } }
    var showOnline by remember { mutableStateOf(false) }
    val wide = windowWidth() != Width.COMPACT
    val unread = vm.unreadCount(chats)
    run {
        // Provider pins come from the demo seed only (cloud sign-in clears it); cloud listings have no map position here, so the map shows me and the riders online.
        val shopPins = providers.filter { it.scope == Scope.LOCAL }.take(6)
        // Me and online riders at their real positions; the demo's sample shops keep their spots on the Bengaluru grid.
        val pins = listOf(pinAt(vm.mePos, "You", MeColor, big = true)) + shopPins.map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) } + drivers.filter { it.online }.map { pinAt(it.pos, "", MaterialTheme.status.good) }
        // Same content on phones (in the sheet) and wide screens (in the side panel): the search pill; services live in the Services tab.
        val panel: @Composable ColumnScope.() -> Unit = {
            SearchBar("Where to, or what do you need?", onClick = onSearch)
        }
        if (wide) Column(Modifier.fillMaxSize()) {
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Row(Modifier.weight(1f)) { Box(Modifier.weight(1.2f).fillMaxHeight()) { BucksMap(Modifier.fillMaxSize(), pins); MapFooter(Modifier.align(Alignment.BottomStart).padding(8.dp), shops = shopPins.isNotEmpty()) }; Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Gutter), content = panel) }
        }
        // Phone: full-bleed map with the wordmark bar laid over it; the sheet holds the search pill, services live in the Services tab.
        else Box(Modifier.fillMaxSize()) {
            BucksMap(Modifier.fillMaxSize(), pins)
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                MapFooter(Modifier.padding(horizontal = Gutter, vertical = 8.dp), shops = shopPins.isNotEmpty())
                Sheet { panel(); Spacer(Modifier.height(24.dp)) }
            }
            // Cloud drivers with a checked vehicle get the button while offline too: it opens the sheet with their vehicle switch.
            if (s.receiving || vm.cloudVehicle != null) OnlineFab(Modifier.align(Alignment.BottomEnd).padding(end = Gutter - 16.dp, bottom = 174.dp)) { showOnline = true }
            s.driverRide?.takeIf { it.status == DriverRideStatus.RINGING }?.let { dr -> RideRequestCard(dr, onAccept = { vm.driverAccept() }, onDecline = { vm.driverDecline() }, modifier = Modifier.align(Alignment.Center)) }
        }
    }
    if (showOnline) OnlineSheet(vm, onDismiss = { showOnline = false }, onListings = onListings, onEarnings = onEarnings)
}

/**
 * One tile of the Services menu. Its state comes from the server (services_near, docs/SERVICES_UNLOCK.md): LOCKED and SOON
 * show a padlock and dim; QUIET (unlocked, nobody online right now) gets an amber dot; OPEN is plain.
 */
@Composable
private fun ServiceTile(def: ServiceDef, st: ServiceState?, index: Int, modifier: Modifier, onClick: () -> Unit) {
    val locked = st == null || !st.usable
    val fg = if (!locked) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    val src = remember { MutableInteractionSource() }; var nope by remember { mutableIntStateOf(0) }; val haptic = LocalHapticFeedback.current
    // Tiles assemble in reading order; a locked tile shakes and its padlock wiggles before its sheet opens.
    Box(modifier.height(64.dp).enterStagger(index).shakeOn(nope).pressScale(src, 0.93f)) {
        Column(Modifier.fillMaxSize().padding(top = 4.dp, end = 4.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(interactionSource = src, indication = LocalIndication.current) { if (locked) { nope++; haptic.performHapticFeedback(HapticFeedbackType.LongPress) }; onClick() }.padding(horizontal = 2.dp)
            .semantics { contentDescription = def.label + when (st?.state) { "OPEN" -> ""; "QUIET" -> ", nobody online right now"; "SOON" -> ", coming soon"; else -> ", locked near you" } },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(def.icon, null, tint = fg)
            Text(def.label, style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp), color = fg, modifier = Modifier.padding(top = 4.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (locked) Box(Modifier.align(Alignment.TopEnd).size(18.dp).clip(MaterialTheme.shapes.extraSmall).background(MaterialTheme.colorScheme.surface), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Lock, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        } else if (st?.state == "QUIET") Box(Modifier.align(Alignment.TopEnd).padding(top = 8.dp, end = 8.dp).size(8.dp).clip(CircleShape).background(MaterialTheme.status.warn))
    }
}

/**
 * What a locked or coming-soon tile explains: what unlocks it here, how far along it is, "notify me", and the way in for
 * providers ("Run a restaurant? List it").
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ServiceLockSheet(vm: BucksViewModel, def: ServiceDef, st: ServiceState?, onDismiss: () -> Unit, onList: () -> Unit) {
    val cloud = vm.social.enabled
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(def.icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
                Text(if (st?.state == "SOON" || !cloud) "${def.label} is coming soon" else "${def.label} isn't open near you yet", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 14.dp))
            }
            if (st != null && st.state == "LOCKED") {
                Text("It opens here once ${st.minSupply} ${st.supplyNoun} within ${st.radiusKm} of you are on Bucks and checked.", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 16.dp))
                val progress = if (st.minSupply == 0) 1f else (st.supply.toFloat() / st.minSupply).coerceIn(0f, 1f)
                val shown by animateFloatAsState(progress, tween(Motion.LONG * 2, easing = Motion.Emphasized), label = "unlock")
                LinearProgressIndicator(progress = { shown }, Modifier.fillMaxWidth().padding(top = 14.dp).height(8.dp).clip(CircleShape))
                Muted("${st.supply} of ${st.minSupply} so far", Modifier.padding(top = 6.dp))
            } else Text(if (cloud) "Bucks is still building ${def.label.lowercase()}. Tell us you want it and we'll let you know when it opens." else "It opens in the online version of Bucks.",
                style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 16.dp))
            if (st != null && st.interested > 0) Muted("${st.interested} ${if (st.interested == 1) "person" else "people"} near you ${if (st.interested == 1) "is" else "are"} waiting for it.", Modifier.padding(top = 10.dp))
            if (cloud) {
                if (st?.mine == true) GhostButton("You'll be told when it opens · Stop", Modifier.padding(top = 18.dp)) { vm.services.toggleInterest(def.key) }
                else PrimaryButton("Notify me when it opens", Modifier.padding(top = 18.dp)) { vm.services.toggleInterest(def.key) }
            }
            Row(Modifier.fillMaxWidth().padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Muted(def.joinPrompt, Modifier.weight(1f)); TextButton(onClick = onList) { Text(def.joinAction) }
            }
        }
    }
}

@Composable
fun ServicesScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit,
                   onOpenService: (String) -> Unit = {}, onListService: (String) -> Unit = {}) {
    val s by vm.state.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // Which services are open here: read when the screen opens and whenever I move a real distance (the counts are per place).
    // Without a real fix the map's default centre would stand in for "here", so nothing is checked until one arrives.
    LaunchedEffect(s.me?.let { (it.lat * 200).toInt() to (it.lng * 200).toInt() }) { if (s.me != null) vm.services.refresh() }
    var sheetFor by remember { mutableStateOf<String?>(null) }
    DisposableEffect(Unit) { vm.dispatch.mapShown(); onDispose { vm.dispatch.mapHidden() } }
    val cats = if (vm.social.enabled) CLOUD_CATEGORIES else providers.map { it.category }.distinct()
    val shopPins = providers.filter { it.scope == Scope.LOCAL }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // Natural height up to ~60% of the screen, and never tall enough (with the footer) to reach the top bar on short screens.
        val sheetMax = (maxHeight * 0.6f).coerceAtMost(maxHeight - 120.dp).coerceAtLeast(0.dp)
        BucksMap(Modifier.fillMaxSize(), listOf(pinAt(vm.mePos, "You", MeColor, big = true)) + shopPins.map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) })
        BucksTopBar(onMenu = onMenu, unread = vm.unreadCount(chats), onChat = onMessages)
        // Same footer as Home (legend + OSM attribution) sitting on the map just above the sheet; this map has no rider pins.
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            MapFooter(Modifier.padding(horizontal = Gutter, vertical = 8.dp), riders = false, shops = shopPins.isNotEmpty())
            Sheet(Modifier.heightIn(max = sheetMax)) { Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                Text("Services near you", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 14.dp))
                // Every service gets a tile, 5 per row (the last row padded so tiles keep their width). Locked ones open a sheet saying
                // what unlocks them here; open ones go straight in; quiet ones go in with a word about nobody being online.
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { SERVICE_CATALOG.chunked(5).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        row.forEach { def -> val st = vm.services.state(def.key)
                            ServiceTile(def, st, SERVICE_CATALOG.indexOf(def), Modifier.weight(1f)) {
                                when {
                                    st == null || !st.usable -> sheetFor = def.key
                                    st.state == "QUIET" && st.minOnline > 0 -> { vm.toast(if (st.delivery) "Most ${st.supplyNoun} near you are closed right now." else "No ${st.supplyNoun} online near you right now. Try again in a few minutes."); onOpenService(def.key) }
                                    else -> onOpenService(def.key)
                                }
                            }
                        }
                        repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                } }
                vm.services.error?.let { Muted("Couldn't check which services are open here. $it", Modifier.padding(top = 8.dp)) }
                if (vm.social.enabled && s.me == null) Muted("Turn on location to see which services are open where you are.", Modifier.padding(top = 8.dp))
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
    sheetFor?.let { key -> serviceDef(key)?.let { def -> ServiceLockSheet(vm, def, vm.services.state(key), onDismiss = { sheetFor = null }, onList = { sheetFor = null; onListService(key) }) } }
}
