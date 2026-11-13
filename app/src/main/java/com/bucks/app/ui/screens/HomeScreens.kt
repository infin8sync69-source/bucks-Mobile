package com.bucks.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.bucks.app.ui.Invite
import com.bucks.app.ui.findActivity
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.LocalIndication
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
import com.bucks.app.data.DriverLocationService
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource

val MeColor = Color(0xFF1D4ED8)

@Composable
fun SearchBar(hint: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(modifier.fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).clickable(onClick = onClick), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.Search, null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(24.dp)); Spacer(Modifier.width(16.dp)); Text(hint, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

/**
 * The home search, typed into right here: after 3 letters the nearest matching places (streets, landmarks, towns) list under the field;
 * tapping one opens it on the map with directions, and the search key (or the last row) searches shops, pros and drivers instead.
 */
@Composable
fun HomeSearch(vm: BucksViewModel, hint: String, onSearchAll: (String) -> Unit, onPlace: () -> Unit) {
    var q by remember { mutableStateOf("") }; var places by remember { mutableStateOf<List<com.bucks.app.data.MapServices.PlaceHit>>(emptyList()) }
    val near = vm.state.collectAsState().value.me ?: vm.mePos
    LaunchedEffect(q) {
        places = emptyList(); val t = q.trim(); if (t.length < 3) return@LaunchedEffect
        kotlinx.coroutines.delay(500); places = com.bucks.app.data.MapServices.search(t, near).take(3)
    }
    // People, by name or Bucks ID, as cards with their quick actions; a tap opens the profile.
    val social = vm.social; val openPerson = com.bucks.app.ui.social.LocalOpenPerson.current
    var people by remember { mutableStateOf<List<com.bucks.app.data.PersonHit>>(emptyList()) }; var allPeople by remember { mutableStateOf(false) }
    val sent = remember { androidx.compose.runtime.mutableStateMapOf<String, Boolean>() }
    LaunchedEffect(social.me?.id) { if (social.me != null) social.refreshSyncs() }
    LaunchedEffect(q) {
        allPeople = false; val t = com.bucks.app.ui.social.peopleQuery(q); if (t.length < 2 || social.me == null) { people = emptyList(); return@LaunchedEffect }
        kotlinx.coroutines.delay(300)
        people = runCatching { com.bucks.app.data.BackendSafety.searchPeople(t) }.getOrDefault(emptyList())
        runCatching { social.namesFor(people.map { it.id }) }
    }
    fun syncState(h: com.bucks.app.data.PersonHit) = when { h.synced || social.synced.any { it.id == h.id } -> "SYNCED"; social.incoming.any { it.id == h.id } -> "INCOMING"; sent[h.id] == true -> "SENT"; else -> "NONE" }
    Column(Modifier.imePadding()) {
        if (people.isNotEmpty()) {
            Text(stringResource(R.string.r1_people), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
            (if (allPeople) people else people.take(3)).forEach { h ->
                com.bucks.app.ui.social.PersonResultCard(vm, h, syncState(h), Modifier.padding(bottom = 8.dp), onOpen = { com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.PEOPLE_RESULT_TAP); openPerson(h.id) },
                    onSync = { if (syncState(h) == "INCOMING") social.acceptSync(h.id) else { sent[h.id] = true; social.syncWith(h.id, h.name) } },
                    onMessage = { social.openDirect(h.id) { vm.open(com.bucks.app.ui.nav.Routes.chat(it)) } })
            }
            if (!allPeople && people.size > 3) TextButton({ allPeople = true }) { Text(pluralStringResource(R.plurals.r1_more_people, people.size - 3, people.size - 3)) }
        }
        if (q.trim().length >= 3) {
            places.forEach { h ->
                ListRow(h.name, h.detail, leading = { Icon(Icons.Rounded.Place, null, tint = MaterialTheme.colorScheme.primary) }, trailing = { Muted(stringResource(R.string.g3_home_directions)) }, onClick = { com.bucks.app.ui.screens.MapsPick.place = h; q = ""; onPlace() })
            }
            ListRow(stringResource(R.string.g3_home_search_all, q.trim()), null, leading = { Icon(Icons.Rounded.Search, null) }, onClick = { onSearchAll(q.trim()); q = "" })
        }
        Surface(Modifier.fillMaxWidth().height(56.dp), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
            Row(Modifier.padding(start = 20.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Search, null, Modifier.size(24.dp)); Spacer(Modifier.width(16.dp))
                androidx.compose.foundation.text.BasicTextField(q, { q = it }, Modifier.weight(1f), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { if (q.isNotBlank()) { onSearchAll(q.trim()); q = "" } }),
                    decorationBox = { inner -> Box { if (q.isEmpty()) Text(hint, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1); inner() } })
                if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, stringResource(R.string.g3_cd_clear), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}

/** Explains the pin colours on the maps: providers are drawn in the theme primary (only where the map shows them), online riders in status good (only where the map shows riders). */
@Composable
private fun MapLegend(modifier: Modifier = Modifier, riders: Boolean = true, shops: Boolean = true) {
    val dots: @Composable () -> Unit = { if (shops) LegendDot(MaterialTheme.colorScheme.primary, stringResource(R.string.g3_legend_shops)); if (riders) LegendDot(MaterialTheme.status.good, stringResource(R.string.g3_legend_riders)) }
    // Large text: one dot per line, so the pill is never wider than the screen and its labels never wrap letter by letter.
    if (largeText()) Surface(modifier, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface, shadowElevation = 2.dp) { Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { dots() } }
    else Surface(modifier, shape = CircleShape, color = MaterialTheme.colorScheme.surface, shadowElevation = 2.dp) { Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { dots() } }
}
@Composable
private fun LegendDot(color: Color, text: String) = Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).clip(CircleShape).background(color)); Spacer(Modifier.width(6.dp)); Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
@Composable
private fun largeText() = LocalDensity.current.fontScale > 1.3f
/** Legend at the start and the OSM attribution at the end, sitting on the map just above the sheet. With large text they stack, so the footer cannot squeeze the sheet off screen. */
@Composable
private fun MapFooter(modifier: Modifier = Modifier, riders: Boolean = true, shops: Boolean = true) {
    if (largeText()) Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) { if (riders || shops) MapLegend(Modifier.align(Alignment.Start), riders = riders, shops = shops); MapAttribution() }
    else Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) { if (riders || shops) MapLegend(riders = riders, shops = shops); Spacer(Modifier.weight(1f)); MapAttribution() }
}

/** Cloud builds: category chips for searching live listings (the categories shops and pros pick from when they list), not the demo seed's. */
private val CLOUD_CATEGORIES = (com.bucks.app.ui.screens.manage.BUSINESS_CATEGORIES + com.bucks.app.ui.screens.manage.SKILL_CATEGORIES).filter { it != "Other" }.distinct()

/**
 * The rider's unfinished ride, always one tap from Home: leaving a ride screen with Back (or the phone's gesture) never cancels it,
 * so this is the way back in until the trip is rated or skipped (the pay and rate screens included).
 */
@Composable
private fun ActiveRideCard(r: Ride, onReturn: () -> Unit) {
    val eta = etaText(r.etaMin)
    val detail = when (r.status) {
        RideStatus.SEARCHING -> stringResource(R.string.g3_ride_searching, r.kind.label.lowercase())
        RideStatus.NO_DRIVER -> stringResource(R.string.g3_ride_no_driver)
        RideStatus.MATCHED -> { val who = r.driver?.name?.substringBefore(' ')
            when { who != null && eta != null -> stringResource(R.string.g3_ride_named_coming_eta, who, eta); who != null -> stringResource(R.string.g3_ride_named_coming, who)
                eta != null -> stringResource(R.string.g3_ride_coming_eta, eta); else -> stringResource(R.string.g3_ride_coming) } }
        RideStatus.ARRIVED -> stringResource(R.string.g3_ride_arrived, r.pin)
        RideStatus.IN_RIDE -> stringResource(R.string.g3_ride_in_ride, r.dest.name)
        RideStatus.COMPLETED -> stringResource(R.string.g3_ride_completed, Money.format(r.fare))
        RideStatus.PAID -> stringResource(R.string.g3_ride_paid)
        RideStatus.CANCELLED -> return }
    BucksCard(Modifier.padding(bottom = 12.dp), tint = true, padding = 14) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 10.dp)) { Text(stringResource(R.string.g3_ride_in_progress), style = MaterialTheme.typography.titleMedium); Muted(detail) }
            SmallButton(stringResource(R.string.g3_return), onClick = onReturn)
        }
    }
}

@Composable
fun HomeScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit, onServices: () -> Unit, onProCreate: () -> Unit, onEarnings: () -> Unit, onListings: () -> Unit, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit = { _, _ -> }, onPlace: () -> Unit = {}, onReturnToRide: () -> Unit = {}, onListing: (String) -> Unit = {}, onPost: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val drivers by vm.repo.drivers.collectAsState(); val providers by vm.repo.providers.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // Back on Home while on duty or with a trip open puts Bucks in the background instead of closing it (closing would take the driver off the map).
    val hostActivity = LocalContext.current.findActivity()
    BackHandler(enabled = hostActivity != null && (s.vehicleOnline || s.driverRide != null || s.ride != null)) { hostActivity?.moveTaskToBack(true) }
    // The button and the "being checked" note follow the server: reload my vehicles whenever Home comes back on screen.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (vm.dispatch.enabled && s.user != null) vm.dispatch.reloadVehicles() }
    // An accepted ride takes over Home until it's closed.
    if (s.driverRide != null && s.driverRide?.status != DriverRideStatus.RINGING) { DriverTripScreen(vm, onChatWith, onCall); return }
    // Cloud dispatch polls online drivers every 15 s only while a map is on screen.
    DisposableEffect(Unit) { vm.dispatch.mapShown(); onDispose { vm.dispatch.mapHidden() } }
    var showOnline by remember { mutableStateOf(false) }
    var showActivity by remember { mutableStateOf(false) }
    val activity = activityItems(vm)
    // Keep my orders and listings fresh while Home is on screen, so the activity button and the online button follow the server.
    LaunchedEffect(vm.social.me?.id) {
        if (vm.social.me != null) {
            if (!vm.myListings.loaded) vm.myListings.refresh()
            while (true) { vm.commerce.refreshMyOrders(quiet = true); kotlinx.coroutines.delay(20_000) }
        }
    }
    val wide = windowWidth() != Width.COMPACT
    val unread = vm.unreadCount(chats)
    // The map: centred on me once, then mine to move. My location re-centres it; the Recommended layer adds places (RecommendedMap.kt).
    val cmds = remember { MapCommands() }; val rec = rememberRecommendedLayer(); val ctx = LocalContext.current
    val cloud = vm.social.enabled && vm.social.me != null
    if (cloud) RecommendedLoader(rec, cmds, signedIn = true)
    var locating by remember { mutableStateOf(false) }
    fun locate() {
        val ok = androidx.core.content.ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
            androidx.core.content.ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!ok) { cmds.moveTo(vm.mePos, 15.0); vm.toast(Str.get(R.string.g8_allow_location_prompt)); return }
        locating = true
        runCatching {
            com.google.android.gms.location.LocationServices.getFusedLocationProviderClient(ctx).getCurrentLocation(com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY, null)
                .addOnSuccessListener { l -> locating = false; val p = l?.let { com.bucks.app.data.LatLng(it.latitude, it.longitude) }; if (p != null) vm.onLocation(p, false); cmds.moveTo(p ?: vm.mePos, 15.0) }
                .addOnFailureListener { locating = false; cmds.moveTo(vm.mePos, 15.0) }
        }.onFailure { locating = false; cmds.moveTo(vm.mePos, 15.0) }
    }
    val onPinTap: (MapPin) -> Unit = { pin -> rec.places.firstOrNull { it.key == pin.id }?.let { rec.selected = it; cmds.moveTo(it.at) } }
    val onMapMoved: () -> Unit = { if (rec.on && rec.loaded) rec.stale = true }
    // Drivers with a checked vehicle get the button while offline too (it opens the sheet with their vehicle switch), on every layout.
    val showFab = s.receiving || vm.cloudVehicle != null
    run {
        // Provider pins come from the demo seed only (cloud sign-in clears it); cloud listings have no map position here, so the map shows me and the riders online.
        val shopPins = providers.filter { it.scope == Scope.LOCAL }.take(6)
        // Me and online riders at their real positions; the demo's sample shops keep their spots on the Bengaluru grid.
        val pins = listOf(pinAt(vm.mePos, stringResource(R.string.g3_map_you), MeColor, big = true)) + shopPins.map { MapPin(it.x, it.y, it.name, MaterialTheme.colorScheme.primary) } + drivers.filter { it.online }.map { pinAt(it.pos, "", MaterialTheme.status.good) } +
            (if (cloud) rec.pins(MaterialTheme.colorScheme.primary) else emptyList())
        // Same content on phones (in the sheet) and wide screens (in the side panel): an unfinished ride, the vehicle note, the search pill; services live in the Services tab.
        val panel: @Composable ColumnScope.() -> Unit = {
            s.ride?.let { r -> ActiveRideCard(r, onReturnToRide) }
            // A cloud vehicle the server hasn't activated yet: say why there is no online button, and where to look.
            vm.waitingVehicle?.takeIf { !showFab }?.let { v -> Column(Modifier.padding(bottom = 12.dp)) {
                val vName = v.model.ifBlank { stringResource(R.string.g3_vehicle_generic) }
                Notice(if (v.status == "SUSPENDED") stringResource(R.string.g3_vehicle_suspended, vName, v.plate)
                       else stringResource(R.string.g3_vehicle_checking, vName, v.plate))
                SmallButton(stringResource(R.string.g3_menu_manage_listings), Modifier.padding(top = 8.dp), tonal = true, onClick = onListings) } }
            if (cloud) RecommendedSheetContent(vm, rec, s.me, onListing = onListing, onPlace = onPlace, onPost = onPost)
            val hint = stringResource(R.string.g3_home_search_hint)
            if (vm.social.enabled) HomeSearch(vm, hint, onSearchAll = onQuery, onPlace = onPlace) else SearchBar(hint, onClick = onSearch)
        }
        if (wide) Column(Modifier.fillMaxSize()) {
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            Row(Modifier.weight(1f)) {
                Box(Modifier.weight(1.2f).fillMaxHeight()) { BucksMap(Modifier.fillMaxSize(), pins, commands = cmds, recentre = s.me == null, onPinTap = onPinTap, onUserMove = onMapMoved, onMyLocation = ::locate, locating = locating)
                    if (cloud) RecommendedControls(rec, Modifier.align(Alignment.TopCenter).padding(top = 10.dp))
                    MapFooter(Modifier.align(Alignment.BottomStart).padding(8.dp), shops = shopPins.isNotEmpty())
                    if (showFab) OnlineFab(Modifier.align(Alignment.BottomEnd).padding(end = 8.dp, bottom = 32.dp)) { showOnline = true } }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Gutter), content = panel) }
        }
        // Phone: full-bleed map with the wordmark bar laid over it; the sheet holds the search pill, services live in the Services tab.
        else Box(Modifier.fillMaxSize()) {
            BucksMap(Modifier.fillMaxSize(), pins, commands = cmds, recentre = s.me == null, onPinTap = onPinTap, onUserMove = onMapMoved, onMyLocation = ::locate, locating = locating)
            BucksTopBar(onMenu = onMenu, unread = unread, onChat = onMessages)
            if (cloud) RecommendedControls(rec, Modifier.align(Alignment.TopCenter).padding(top = 64.dp))
            // Kept clear of the top bar; a panel taller than the space left (large text, ride card and notes together) scrolls instead of pushing off screen.
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(top = 64.dp)) {
                MapFooter(Modifier.padding(horizontal = Gutter, vertical = 8.dp), shops = shopPins.isNotEmpty())
                Sheet(Modifier.weight(1f, fill = false), scrollable = true) { panel()
                    if (vm.canGoOnline) Box(Modifier.padding(top = 6.dp)) { Chip(stringResource(R.string.g3_home_offline_chip), icon = Icons.Rounded.PowerSettingsNew) { showOnline = true } }
                    Spacer(Modifier.height(24.dp)) }
            }
            // Only while I'm online (a driver switch or a live shop / pro listing); offline, a small chip in the sheet opens the same switches.
            if (vm.providerOnline) OnlineFab(Modifier.align(Alignment.BottomEnd).padding(end = Gutter - 16.dp, bottom = 174.dp)) { showOnline = true }
            // A customer with a ride or an order open: what is happening, one tap away.
            if (activity.isNotEmpty()) ActivityFab(activity, Modifier.align(Alignment.BottomStart).padding(start = Gutter - 4.dp, bottom = 198.dp)) { if (activity.size == 1) vm.open(activity[0].route) else showActivity = true }
        }
    }
    // A ringing request is a card over whichever screen is showing (BucksAppUi), so nothing rings here.
    if (showOnline) OnlineSheet(vm, onDismiss = { showOnline = false }, onListings = onListings, onEarnings = onEarnings)
    if (showActivity) ActivitySheet(activity, onOpen = { showActivity = false; vm.open(it.route) }, onDismiss = { showActivity = false })
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
    val cdQuiet = stringResource(R.string.g3_cd_service_quiet, def.label); val cdSoon = stringResource(R.string.g3_cd_service_soon, def.label); val cdLocked = stringResource(R.string.g3_cd_service_locked, def.label)
    Box(modifier.height(64.dp).enterStagger(index).shakeOn(nope).pressScale(src, 0.93f)) {
        Column(Modifier.fillMaxSize().padding(top = 4.dp, end = 4.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(interactionSource = src, indication = LocalIndication.current) { if (locked) { nope++; haptic.performHapticFeedback(HapticFeedbackType.LongPress) }; onClick() }.padding(horizontal = 2.dp)
            .semantics { contentDescription = when (st?.state) { "OPEN" -> def.label; "QUIET" -> cdQuiet; "SOON" -> cdSoon; else -> cdLocked } },
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
private fun ServiceLockSheet(vm: BucksViewModel, def: ServiceDef, st: ServiceState?, onDismiss: () -> Unit, onList: () -> Unit, onRecommend: () -> Unit) {
    val cloud = vm.social.enabled; val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(def.icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
                Text(if (st?.state == "SOON" || !cloud) stringResource(R.string.g3_service_soon_title, def.label) else stringResource(R.string.g3_service_locked_title, def.label), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 14.dp))
            }
            if (st != null && st.state == "LOCKED") {
                Text(stringResource(R.string.g3_service_locked_body, st.supplyNoun, st.minSupply.toString(), st.radiusKm), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 16.dp))
                val progress = if (st.minSupply == 0) 1f else (st.supply.toFloat() / st.minSupply).coerceIn(0f, 1f)
                val shown by animateFloatAsState(progress, tween(Motion.LONG * 2, easing = Motion.Emphasized), label = "unlock")
                LinearProgressIndicator(progress = { shown }, Modifier.fillMaxWidth().padding(top = 14.dp).height(8.dp).clip(CircleShape))
                Muted(stringResource(R.string.g3_service_progress, st.supply.toString(), st.minSupply.toString()), Modifier.padding(top = 6.dp))
            } else Text(if (cloud) stringResource(R.string.g3_service_building, def.label.lowercase()) else stringResource(R.string.g3_service_online_only),
                style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 16.dp))
            if (st != null && st.interested > 0) Muted(pluralStringResource(R.plurals.g3_service_waiting, st.interested, st.interested), Modifier.padding(top = 10.dp))
            if (cloud) {
                if (st?.mine == true) GhostButton(stringResource(R.string.g3_service_notify_on), Modifier.padding(top = 18.dp)) { vm.services.toggleInterest(def.key) }
                else PrimaryButton(stringResource(R.string.g3_service_notify_me), Modifier.padding(top = 18.dp)) { vm.services.toggleInterest(def.key) }
            }
            // Help it open: bring the people it needs onto Bucks, or vouch for one you know.
            SectionTitle(stringResource(R.string.g3_service_help_open), Modifier.padding(top = 22.dp, bottom = 8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallButton(stringResource(R.string.g3_service_invite), Modifier.weight(1f), tonal = true) { Invite.share(ctx, scope, Invite.forService(def.label, st?.supplyNoun ?: def.label.lowercase())) }
                if (cloud) SmallButton(stringResource(R.string.g3_service_recommend), Modifier.weight(1f), tonal = true, onClick = onRecommend)
            }
            Muted(st?.supplyNoun?.let { stringResource(R.string.g3_service_know_noun, it) } ?: stringResource(R.string.g3_service_know_someone), Modifier.padding(top = 8.dp))
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Muted(def.joinPrompt, Modifier.weight(1f)); TextButton(onClick = onList) { Text(def.joinAction) }
            }
        }
    }
}

@Composable
fun ServicesScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onSearch: () -> Unit, onRide: () -> Unit, onQuery: (String) -> Unit,
                   onOpenService: (String) -> Unit = {}, onListService: (String) -> Unit = {}, onRecommend: () -> Unit = {}) {
    val s by vm.state.collectAsState(); val chats by vm.repo.chats.collectAsState()
    // Which services are open here: read when the screen opens and whenever I move a real distance (the counts are per place).
    LaunchedEffect(s.me?.let { (it.lat * 200).toInt() to (it.lng * 200).toInt() }) { if (s.me != null) vm.services.refresh() }
    var sheetFor by remember { mutableStateOf<String?>(null) }
    // Services is for booking and buying: one small icon per service, each opening its own flow. Finding anything else is Home's search.
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g3_services_title), onMenu = onMenu, unread = vm.unreadCount(chats), onChat = onMessages)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            if (vm.social.enabled) {
                val open = SERVICE_CATALOG.count { vm.services.state(it.key)?.usable == true }
                Muted(if (s.me == null) stringResource(R.string.g3_services_need_location) else stringResource(R.string.g3_services_open_count, open, SERVICE_CATALOG.size), Modifier.padding(top = 4.dp, bottom = 12.dp))
            }
            // Locked tiles open a sheet saying what unlocks them here; open ones go straight in; quiet ones go in with a word about nobody online.
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { SERVICE_CATALOG.chunked(4).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { def -> val st = vm.services.state(def.key)
                        ServiceTile(def, st, SERVICE_CATALOG.indexOf(def), Modifier.weight(1f)) {
                            when {
                                st == null || !st.usable -> sheetFor = def.key
                                st.state == "QUIET" && st.minOnline > 0 -> { vm.toast(if (st.delivery) Str.get(R.string.g3_services_quiet_delivery, st.supplyNoun) else Str.get(R.string.g3_services_quiet_online, st.supplyNoun)); onOpenService(def.key) }
                                else -> onOpenService(def.key)
                            }
                        }
                    }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            } }
            vm.services.error?.let { Muted(stringResource(R.string.g3_services_error, it), Modifier.padding(top = 8.dp)) }
        }
    }
    sheetFor?.let { key -> serviceDef(key)?.let { def -> ServiceLockSheet(vm, def, vm.services.state(key), onDismiss = { sheetFor = null }, onList = { sheetFor = null; onListService(key) }, onRecommend = { sheetFor = null; onRecommend() }) } }
}
