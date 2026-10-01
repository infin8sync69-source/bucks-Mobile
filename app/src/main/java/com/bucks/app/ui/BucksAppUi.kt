package com.bucks.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.*
import com.bucks.app.ui.screens.commerce.*
import com.bucks.app.ui.screens.discover.CloudSearchScreen
import com.bucks.app.ui.screens.discover.ListingProfileScreen
import com.bucks.app.ui.screens.dispatch.DeliveryTrackScreen
import com.bucks.app.ui.screens.dispatch.PaymentQrScreen
import com.bucks.app.ui.screens.jobs.*
import com.bucks.app.ui.screens.manage.*
import com.bucks.app.ui.theme.BucksTheme
import kotlinx.coroutines.launch
import android.Manifest
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.bucks.app.data.DriverRideStatus
import com.bucks.app.data.Here
import com.bucks.app.data.Prefs
import com.bucks.app.data.RingAlert
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

private val RIDE_STAGES = setOf(Routes.SEARCHING, Routes.DRIVER_FOUND, Routes.IN_RIDE, Routes.PAY, Routes.RATE_RIDE)
private val TAB_ROUTES = mapOf(BottomTab.HOME to Routes.HOME, BottomTab.FEED to Routes.FEED, BottomTab.SERVICES to Routes.SERVICES, BottomTab.RECOMMENDED to Routes.RECOMMENDED, BottomTab.ACCOUNT to "account")

@Composable
fun BucksAppUi(vm: BucksViewModel, startRoute: String? = null, onStartRouteHandled: () -> Unit = {}) {
    val sysDark = isSystemInDarkTheme()
    val dark = when (Prefs.theme) { Prefs.Theme.LIGHT -> false; Prefs.Theme.DARK -> true; else -> sysDark }
    BucksTheme(dark = dark, textScale = Prefs.textSize.scale) {
        val startDest = remember { if (vm.isLoggedIn) Routes.HOME else Routes.SPLASH }
        val nav = rememberNavController(); val snack = remember { SnackbarHostState() }; val scope = rememberCoroutineScope()
        val drawer = rememberDrawerState(DrawerValue.Closed)
        val s by vm.state.collectAsState()
        CompositionLocalProvider(LocalCartAction provides (if (vm.social.enabled) CartAction(vm.commerce.count) { nav.navigate(Routes.CLOUD_CART) { launchSingleTop = true } } else null)) {
        val width = windowWidth()
        // Cold start for someone already signed in: the purple system splash hands over to the wordmark intro, which fades up
        // into Home. Skipped when a notification tap opened the app (get them to the screen straight away) and after a rotation.
        // Permission prompts wait until it has finished.
        var showIntro by rememberSaveable { mutableStateOf(vm.isLoggedIn && startRoute == null) }
        val toast: (String) -> Unit = { msg -> scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar(msg, duration = SnackbarDuration.Short) } }
        LaunchedEffect(Unit) { vm.toasts.collect { toast(it) } }
        // Real position for the customer side: one fix on start and whenever the app returns to the foreground.
        val ctx = LocalContext.current
        fun fetchLocation() { if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) return; runCatching { LocationServices.getFusedLocationProviderClient(ctx).getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null).addOnSuccessListener { l -> if (l != null) Here.fixOf(l).let { vm.onLocation(it.at, it.mocked) } } } }
        fun hasLocation() = Here.hasPermission(ctx)
        val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
        // Asked twice and still refused, Android stops showing the prompt: the only way left is the app's own settings page.
        val locPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { g -> if (g.values.any { it }) fetchLocation() else { vm.onLocationDenied()
            val a = ctx.findActivity(); if (a != null && !androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale(a, Manifest.permission.ACCESS_FINE_LOCATION)) { toast("Location is blocked for Bucks. Allow it in the app's settings."); runCatching { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", ctx.packageName, null))) } } } }
        // Play policy: explain what location is used for before the system prompt appears.
        var locDisclosure by rememberSaveable { mutableStateOf(false) }
        LaunchedEffect(s.user != null, showIntro) { if (s.user != null && !showIntro) { if (hasLocation()) fetchLocation() else locDisclosure = true } }
        // Going online as a driver: make sure requests can reach a phone that is locked or in another app (notifications allowed, no battery restriction).
        var reachSheet by remember { mutableStateOf(false) }
        fun notifOk() = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        fun batteryOk() = (ctx.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isIgnoringBatteryOptimizations(ctx.packageName)
        LaunchedEffect(s.vehicleOnline) { if (s.vehicleOnline && (!notifOk() || !batteryOk())) reachSheet = true }
        if (reachSheet) AlertDialog(onDismissRequest = { reachSheet = false },
            title = { Text("Stay reachable while online") },
            text = { Text("To ring you when a customer needs a ride, Bucks must be allowed to run in the background and send notifications.\n\n" +
                (if (notifOk()) "\u2713 Notifications are on.\n" else "\u2717 Notifications are off.\n") + (if (batteryOk()) "\u2713 Battery: unrestricted." else "\u2717 Battery: the phone may put Bucks to sleep. Choose \"Allow\" or \"Unrestricted\".")) },
            confirmButton = { TextButton({ reachSheet = false
                if (!notifOk()) { if (Build.VERSION.SDK_INT >= 33) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS) else ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName)) }
                else if (!batteryOk()) runCatching { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:${ctx.packageName}"))) }
                    .onFailure { runCatching { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } } }) { Text("Fix now") } },
            dismissButton = { TextButton({ reachSheet = false }) { Text("Later") } })
        // Back in the foreground: where the phone is now, not where it was when Bucks was last opened.
        LifecycleEventEffect(Lifecycle.Event.ON_START) { if (s.user != null && !showIntro && hasLocation()) fetchLocation() }
        // "Turn on location" from a booking screen: ask for the permission, open the phone's location switch, or look again.
        val enableLocation: () -> Unit = { when { !hasLocation() -> locDisclosure = true; !Here.switchedOn(ctx) -> runCatching { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)) }; else -> fetchLocation() } }
        if (locDisclosure) AlertDialog(onDismissRequest = { locDisclosure = false; vm.onLocationDenied() },
            title = { Text("Use your location") },
            text = { Text("Bucks uses your location to find riders, shops and services near you and to set your pick-up point. If you go online as a driver, Bucks keeps sharing your location while you're online, even when the app is closed, so nearby customers can ring you. It stops when you go offline.") },
            confirmButton = { TextButton({ locDisclosure = false; locPermission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) }) { Text("Continue") } },
            dismissButton = { TextButton({ locDisclosure = false; vm.onLocationDenied() }) { Text("Not now") } })
        // Foreground location service runs whenever a vehicle is online, whichever screen is showing. Without permission it can't start (Android 14 would crash), so go back offline.
        LaunchedEffect(s.vehicleOnline) { when { !s.vehicleOnline -> com.bucks.app.data.DriverLocationService.stop(ctx); hasLocation() -> com.bucks.app.data.DriverLocationService.start(ctx); else -> { vm.setOnline(false); toast("Allow location to go online, so customers can find you."); locDisclosure = true } } }
        // A request can only ring a driver outside the app through a notification: when those are blocked, say so as they go online (never blocks going online).
        var notifHelp by remember { mutableStateOf<RingAlert.Problem?>(null) }
        LaunchedEffect(s.vehicleOnline) { if (s.vehicleOnline) notifHelp = RingAlert.problem(ctx) }
        notifHelp?.let { p -> AlertDialog(onDismissRequest = { notifHelp = null }, title = { Text("Turn on notifications") },
            text = { Text("${p.message} Turn them on so requests reach you when Bucks is closed or the screen is off. You're online either way.") },
            confirmButton = { TextButton({ notifHelp = null; runCatching { ctx.startActivity(RingAlert.settingsIntent(ctx, p)) } }) { Text("Open settings") } },
            dismissButton = { TextButton({ notifHelp = null }) { Text("Not now") } }) }
        LaunchedEffect(s.user != null, showIntro) { if (!showIntro && s.user != null && Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }
        LaunchedEffect(Unit) { vm.nav.collect { route -> when {
            route == Routes.HOME || route == Routes.FEED || route == Routes.ACTIVITY -> nav.navigate(route) { popUpTo(Routes.HOME) { inclusive = route == Routes.HOME } }
            route in RIDE_STAGES -> nav.navigate(route) { popUpTo(Routes.HOME); launchSingleTop = true }
            route.startsWith("order/") -> nav.navigate(route) { popUpTo(Routes.CART) { inclusive = true } }
            else -> nav.navigate(route) } } }
        // A tapped notification asked for a screen: open it once the person is signed in, then forget it (Push.safeRoute already vetted it).
        LaunchedEffect(startRoute, s.user != null) { val r = startRoute ?: return@LaunchedEffect; if (s.user == null) return@LaunchedEffect
            runCatching { nav.navigate(r) { launchSingleTop = true; if (r == Routes.HOME) popUpTo(Routes.HOME) } }; onStartRouteHandled() }
        val backEntry by nav.currentBackStackEntryAsState(); val current = backEntry?.destination?.route ?: Routes.SPLASH
        val currentTab = when { current.startsWith("feed") -> BottomTab.FEED; current.startsWith("services") || current == Routes.SEARCH || current.startsWith("provider/") || current.startsWith("l/") -> BottomTab.SERVICES; current.startsWith("recommended") -> BottomTab.RECOMMENDED; current.startsWith("account") -> BottomTab.ACCOUNT; else -> BottomTab.HOME }
        val loggedIn = s.user != null && current !in listOf(Routes.SPLASH, Routes.LOGIN, Routes.OTP, Routes.SIGNUP_EMAIL, Routes.PROFILE) || (s.user != null && current == Routes.PROFILE)
        // A driver trip in progress is full-screen, like the design (no bottom navigation).
        val onTrip = s.driverRide != null && s.driverRide?.status != com.bucks.app.data.DriverRideStatus.RINGING && current == Routes.HOME
        val showBottomBar = !onTrip && width == Width.COMPACT && (current in listOf(Routes.HOME, Routes.FEED, Routes.SERVICES, Routes.RECOMMENDED, Routes.SEARCH) || current.startsWith("provider/") || current.startsWith("account"))
        val showRail = width != Width.COMPACT && loggedIn
        fun tab(t: BottomTab) { nav.navigate(TAB_ROUTES[t]!!) { popUpTo(Routes.HOME) { inclusive = t == BottomTab.HOME }; launchSingleTop = true } }
        // A request ringing for me (I'm online as a driver): play the driver tune and bring Home, where the accept card is, to the front.
        val ringing = s.driverRide?.status == com.bucks.app.data.DriverRideStatus.RINGING
        RideRingEffect(ringing)
        LaunchedEffect(ringing) { if (ringing && current != Routes.HOME) tab(BottomTab.HOME) }
        val openMenu: () -> Unit = { scope.launch { drawer.open() } }
        val closeMenu: () -> Unit = { scope.launch { drawer.close() } }
        val messages: () -> Unit = { nav.navigate(Routes.MESSAGES) }
        val chatWith: (String, String) -> Unit = { n, r -> nav.navigate(Routes.chat(vm.openChat(n, r))) }
        val call: (String, String) -> Unit = { n, p -> vm.startCall(n, p) }
        val home: () -> Unit = { nav.navigate(Routes.HOME) { popUpTo(Routes.HOME) { inclusive = true } } }
        val query: (String) -> Unit = { q -> vm.discover.useService(null); if (q == "jobs" && vm.social.enabled) nav.navigate(Routes.JOBS_NEAR) else { vm.setQuery(q); nav.navigate(Routes.SEARCH) } }
        val ride: () -> Unit = { vm.startRide(); nav.navigate(Routes.DESTINATION) }
        // Home's "Return": the screen for where the rider's unfinished trip is now.
        val returnToRide: () -> Unit = { s.ride?.status?.let { BucksViewModel.rideRoute(it) }?.let { r -> nav.navigate(r) { popUpTo(Routes.HOME); launchSingleTop = true } } }
        val logout: () -> Unit = { vm.logout(); nav.navigate(Routes.LOGIN) { popUpTo(0) } }

        Box(Modifier.fillMaxSize()) {
        ModalNavigationDrawer(drawerState = drawer, gesturesEnabled = loggedIn, drawerContent = {
            ModalDrawerSheet(drawerContainerColor = MaterialTheme.colorScheme.surface, drawerShape = RoundedCornerShape(topEnd = 20.dp, bottomEnd = 20.dp), modifier = Modifier.width(300.dp)) { s.user?.let { u ->
                // Demo builds keep the local vehicle; cloud builds use my checked vehicle on the server (never in s.pro).
                val v = if (vm.dispatch.enabled) null else s.pro?.vehicle; val cv = vm.cloudVehicle
                val studio = vm.social.enabled; val m = vm.myListings
                // The menu is the professional side (Studio); the personal profile lives in the bottom bar. Fresh numbers each time it opens.
                LaunchedEffect(drawer.isOpen) { if (drawer.isOpen && studio && vm.social.me != null) m.refresh() }
                Column(Modifier.fillMaxHeight()) { Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Bucks Pro", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                        IconButton(onClick = closeMenu) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Close menu", tint = MaterialTheme.colorScheme.primary) }
                    }
                    // Bucks ID: a mini card that opens the full card with QR and barcode.
                    vm.social.me?.takeIf { studio }?.let { me ->
                        val info = BucksIdCardInfo.of(me.idIssuedAt)
                        Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp))
                            .background(androidx.compose.ui.graphics.Brush.linearGradient(listOf(androidx.compose.ui.graphics.Color(0xFF811FF0), androidx.compose.ui.graphics.Color(0xFF4A0AA6))))
                            .clickable { closeMenu(); nav.navigate(Routes.BUCKS_ID) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.QrCode2, null, tint = androidx.compose.ui.graphics.Color.White)
                            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                                Text("Bucks ID  ${pretty(me.shortCode)}", color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.titleSmall)
                                Text(when { info == null -> "Tap to show your card"; info.expired -> "Expired · tap to renew"; info.renewable -> "Renew soon · valid till ${info.validTill}"; else -> "Valid till ${info.validTill}" },
                                    color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.bodySmall)
                            }
                            Icon(Icons.Rounded.ChevronRight, "Show card", tint = androidx.compose.ui.graphics.Color.White)
                        }
                    }
                    Column(Modifier.padding(12.dp)) {
                        DrawerItem(Icons.Rounded.GridView, if (studio) "Bucks Pro home" else "Manage listings", current == Routes.MY_LISTINGS || current.startsWith("studio/") || current.startsWith(Routes.LISTINGS) || current.startsWith(Routes.VEHICLE_FORM) || current.startsWith(Routes.ADD_SKILL) || current == Routes.MY_VEHICLES) { closeMenu(); nav.navigate(if (studio) Routes.MY_LISTINGS else Routes.LISTINGS) }
                        // Quick access: every listing I run, one tap to its dashboard, and the switch right here when it's live.
                        if (studio) m.listings.sortedWith(compareBy({ it.status != "LIVE" }, { it.title.lowercase() })).forEach { l ->
                            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { closeMenu(); nav.navigate(Routes.studioListing(l.id)) }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                PhotoOrIcon(l.photoUrl ?: l.gallery.firstOrNull()?.url, studioIcon(l), size = 40)
                                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                                    Text(l.title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(when (l.status) { "LIVE" -> onlineLabel(l.kind, l.online); "SUSPENDED" -> "Suspended"; else -> "${kindLabel(l.kind)} · not live yet" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                                }
                                if (l.status == "LIVE" && m.canManage(l.id)) ListingSwitch(l.online) { on -> m.setOnline(l.id, on) }
                            }
                        }
                        // Quick switch for the active vehicle, so a driver can go online from anywhere.
                        if (v != null) ListingCard({ ListingThumb(v.kind.icon, size = 44) }, v.model, pill = v.mode.label, online = s.online, onToggle = { on -> vm.setVehicleOnline(v.id, on); if (on) { closeMenu(); home() } }, onEdit = { closeMenu(); nav.navigate("${Routes.VEHICLE_FORM}?id=${Uri.encode(v.id)}") }) { Muted(v.plate) }
                        if (cv != null) ListingCard({ ListingThumb(vehicleIcon(cv.kind), size = 44) }, cv.model.ifBlank { vehicleKindLabel(cv.kind) }, pill = vehicleKindLabel(cv.kind), online = s.vehicleOnline, onToggle = { on -> vm.setOnline(on, cv.plate); if (on) { closeMenu(); home() } }, onEdit = { closeMenu(); nav.navigate(Routes.vehicleEdit(cv.id)) }) { Muted(cv.plate) }
                        if (studio) DrawerItem(Icons.Rounded.Add, "Create a listing", false) { closeMenu(); nav.navigate(Routes.MY_LISTINGS) }
                    }
                    if (studio) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                        Column(Modifier.padding(12.dp)) {
                            DrawerItem(Icons.Rounded.MailOutline, if (m.pendingCount > 0) "Invites (${m.pendingCount})" else "Invites", current == Routes.INVITES) { closeMenu(); nav.navigate(Routes.INVITES) }
                            DrawerItem(Icons.Rounded.ShoppingBag, "My orders", current == Routes.MY_ORDERS) { closeMenu(); nav.navigate(Routes.MY_ORDERS) }
                            DrawerItem(Icons.Rounded.Work, "Jobs and applications", current == Routes.MY_APPLICATIONS) { closeMenu(); nav.navigate(Routes.MY_APPLICATIONS) }
                            DrawerItem(Icons.Rounded.QrCodeScanner, "Recommend a local", current == Routes.RECOMMEND_SCAN) { closeMenu(); nav.navigate(Routes.RECOMMEND_SCAN) }
                        }
                    }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                    Column(Modifier.padding(12.dp)) {
                        DrawerItem(Icons.Rounded.Settings, "Account settings", false) { closeMenu(); nav.navigate("account?tab=settings") }
                        DrawerItem(Icons.AutoMirrored.Rounded.Logout, "Logout", false) { closeMenu(); logout() }
                    }
                }
            } }
        }) {
            // The welcome screen is purple edge to edge, including behind the status and navigation bars.
            Scaffold(containerColor = if (current == Routes.SPLASH) com.bucks.app.ui.theme.Purple else MaterialTheme.colorScheme.surface, snackbarHost = { SnackbarHost(snack) { d -> Snackbar(d, shape = MaterialTheme.shapes.medium, containerColor = MaterialTheme.colorScheme.inverseSurface, contentColor = MaterialTheme.colorScheme.inverseOnSurface, modifier = Modifier.padding(horizontal = 4.dp)) } }, bottomBar = { if (showBottomBar) BucksBottomBar(currentTab) { tab(it) } }) { pad ->
                Row(Modifier.padding(pad).consumeWindowInsets(pad).fillMaxSize()) {
                    if (showRail) BucksRail(currentTab) { tab(it) }
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        // The trip screen is Home; from any other screen a driver on a trip gets a way back to it (above the content, so no button is covered).
                        if (loggedIn && current != Routes.HOME && s.driverRide?.let { it.status != DriverRideStatus.RINGING } == true)
                            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary).clickable(onClickLabel = "Return to the trip") { home() }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("Trip in progress", Modifier.weight(1f), color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleSmall)
                                Text("Return", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge) }
                        Box(Modifier.weight(1f).fillMaxWidth()) {
                        NavHost(nav, startDestination = startDest,
                            enterTransition = { fadeIn(tween(220)) + slideInVertically(tween(260, easing = FastOutSlowInEasing)) { it / 20 } }, exitTransition = { fadeOut(tween(140)) },
                            popEnterTransition = { fadeIn(tween(200)) }, popExitTransition = { fadeOut(tween(160)) + slideOutVertically(tween(220, easing = FastOutSlowInEasing)) { it / 20 } }) {
                            composable(Routes.SPLASH) { SplashScreen { nav.navigate(Routes.LOGIN) } }
                            composable(Routes.LOGIN) { LoginScreen(vm, onSent = { val st = vm.state.value; if (st.tempEmail.isNotBlank() && st.tempPhone.isBlank()) nav.navigate(Routes.PROFILE) else nav.navigate(Routes.OTP) }, onSignedIn = { nav.navigate(Routes.HOME) { popUpTo(0) } }, onSignUp = { nav.navigate(Routes.SIGNUP_EMAIL) }, showToast = toast) }
                            composable(Routes.SIGNUP_EMAIL) { SignUpEmailScreen(vm, onBack = { nav.popBackStack() }, onCreated = { nav.navigate(Routes.PROFILE) }, onUseMobile = { nav.popBackStack() }) }
                            composable(Routes.OTP) { OtpScreen(vm, s.tempPhone, onBack = { nav.popBackStack() }, onVerified = { if (vm.isLoggedIn) nav.navigate(Routes.HOME) { popUpTo(0) } else nav.navigate(Routes.PROFILE) }, showToast = toast) }
                            composable(Routes.PROFILE) { CreateProfileScreen(vm, onDone = { nav.navigate(Routes.HOME) { popUpTo(0) } }, showToast = toast) }
                            composable(Routes.HOME) { HomeScreen(vm, openMenu, messages, onSearch = { nav.navigate(Routes.SEARCH) }, onRide = ride, onQuery = query, onServices = { tab(BottomTab.SERVICES) }, onProCreate = { nav.navigate(Routes.VEHICLE_FORM) }, onEarnings = { nav.navigate(Routes.EARNINGS) }, onListings = { nav.navigate(Routes.LISTINGS) }, onChatWith = chatWith, onCall = call, onPlace = { nav.navigate(Routes.MAPS) }, onReturnToRide = returnToRide) }
                            composable(Routes.SERVICES) { ServicesScreen(vm, openMenu, messages, onSearch = { vm.discover.useService(null); nav.navigate(Routes.SEARCH) }, onRide = ride, onQuery = query, onRecommend = { nav.navigate(Routes.RECOMMEND_SCAN) },
                                // An open (or quiet) tile: taxi and auto book a ride of that kind, jobs open jobs near me, the rest search that service.
                                onOpenService = { key -> when (key) {
                                    "TAXI" -> { vm.setRideKind(com.bucks.app.data.VehicleKind.CAB); ride() }
                                    "AUTO" -> { vm.setRideKind(com.bucks.app.data.VehicleKind.AUTO); ride() }
                                    "JOBS" -> query("jobs")
                                    else -> { vm.discover.useService(key, vm.services.state(key)?.radiusM); nav.navigate(Routes.SEARCH) } } },
                                // "List it" on a locked tile: the supply side of that service signs up.
                                onListService = { key -> when {
                                    !vm.social.enabled -> nav.navigate(Routes.LISTINGS)
                                    key in setOf("TAXI", "AUTO", "PARCEL") -> nav.navigate(Routes.MY_VEHICLES)
                                    key == "GIGS" -> nav.navigate(Routes.listingEdit(null, "SKILL"))
                                    key == "JOBS" -> nav.navigate(Routes.MY_LISTINGS)
                                    else -> nav.navigate(Routes.listingEdit(null, "BUSINESS", key)) } }) }
                            composable(Routes.FEED) { if (vm.social.enabled) CloudFeedScreen(vm, openMenu, messages, onOpenMoments = { nav.navigate(Routes.moments(it)) }, onNewMoment = { nav.navigate(Routes.MOMENT_NEW) }) else FeedScreen(vm, openMenu, messages, toast) }
                            composable(Routes.RECOMMENDED) { RecommendedScreen(vm, openMenu, messages, onProvider = { nav.navigate(Routes.provider(it)) }, onRide = { k -> vm.setRideKind(k); ride() }, onChatWith = chatWith, onListing = { nav.navigate(Routes.listing(it)) }) }
                            composable("account?tab={tab}", arguments = listOf(navArgument("tab") { type = NavType.StringType; defaultValue = "profile" })) { e ->
                                AccountScreen(vm, e.arguments?.getString("tab") ?: "profile", openMenu, messages, onProCreate = { vm.startPro(null, 1); nav.navigate(Routes.PRO_CREATE) }, onOrder = { nav.navigate(Routes.order(it)) }, onRequest = { nav.navigate(Routes.requestStatus(it)) }, onEditProfile = { nav.navigate(Routes.PROFILE) }, onToggleTheme = { nav.navigate(Routes.SETTINGS_APPEARANCE) }, onOpen = { nav.navigate(it) }, onLogout = logout, onDeleted = { nav.navigate(Routes.LOGIN) { popUpTo(0) } }, onCreatePost = { nav.navigate(Routes.CREATE_POST) }, showToast = toast) }
                            composable(Routes.SEARCH) { if (vm.social.enabled) CloudSearchScreen(vm, onBack = { nav.popBackStack() }, onOpenListing = { nav.navigate(Routes.listing(it)) }, onRide = { k -> vm.setRideKind(k); ride() }, onPlace = { nav.navigate(Routes.MAPS) }) else SearchScreen(vm, onBack = { nav.popBackStack() }, onProvider = { id, t -> nav.navigate(Routes.provider(id, t)) }, onRequest = { nav.navigate(Routes.request(it)) }, onMessages = messages, onChatWith = chatWith, onCall = call, onCart = { nav.navigate(Routes.CART) }, showToast = toast) }
                            composable("provider/{id}?tab={tab}", arguments = listOf(navArgument("id") { type = NavType.StringType }, navArgument("tab") { type = NavType.StringType; defaultValue = "" })) { e ->
                                val id = e.arguments!!.getString("id")!!
                                ProviderScreen(vm, id, e.arguments?.getString("tab") ?: "", onBack = { nav.popBackStack() }, onRequest = { nav.navigate(Routes.request(id)) }, onChatWith = chatWith, onCall = call, onCart = { nav.navigate(Routes.CART) }, onMessages = messages) }
                            composable(Routes.CART) { if (vm.social.enabled) CloudCartScreen(vm, onBack = { nav.popBackStack() }, onPlaced = { ids -> if (ids.size == 1) nav.navigate(Routes.cloudOrder(ids.first())) { popUpTo(Routes.CART) { inclusive = true } } else nav.navigate(Routes.MY_ORDERS) { popUpTo(Routes.CART) { inclusive = true } } }) else CartScreen(vm, onBack = { nav.popBackStack() }, onPlaced = { }) }
                            composable(Routes.ORDER, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> val id = e.arguments!!.getString("id")!!; if (vm.social.enabled) CloudOrderScreen(vm, id, onBack = { nav.popBackStack() }, onTrack = { nav.navigate(Routes.deliveryTrack(it)) }, onOpenListing = { nav.navigate(Routes.listing(it)) }) else OrderScreen(vm, id, onBack = { nav.popBackStack() }, onVote = { nav.navigate(Routes.provider(it, "votes")) }, onChatWith = chatWith, onHome = home) }
                            composable(Routes.REQUEST, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> RequestScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onSent = { nav.navigate(Routes.requestStatus(it)) { popUpTo(Routes.HOME) } }) }
                            composable(Routes.REQUEST_STATUS, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> RequestStatusScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onVote = { nav.navigate(Routes.provider(it, "votes")) }, onChatWith = chatWith) }
                            composable(Routes.DESTINATION) { DestinationScreen(vm, onBack = { nav.popBackStack() }, onChosen = { nav.navigate(Routes.CHOOSE_RIDE) }, onEnableLocation = enableLocation) }
                            composable(Routes.CHOOSE_RIDE) { ChooseRideScreen(vm, onBack = { nav.popBackStack() }, onConfirm = { nav.navigate(Routes.CONFIRM_PICKUP) }) }
                            composable(Routes.CONFIRM_PICKUP) { ConfirmPickupScreen(vm, onBack = { nav.popBackStack() }, onEnableLocation = enableLocation) }
                            composable(Routes.SEARCHING) { SearchingScreen(vm, onChangeType = { nav.navigate(Routes.CHOOSE_RIDE) { popUpTo(Routes.HOME) } }, onBack = { nav.popBackStack() }) }
                            composable(Routes.DRIVER_FOUND) { DriverFoundScreen(vm, chatWith, call, toast) }
                            composable(Routes.IN_RIDE) { InRideScreen(vm, toast) }
                            composable(Routes.PAY) { PayScreen(vm) }
                            composable(Routes.RATE_RIDE) { RateRideScreen(vm) }
                            // Manage (cloud): the demo "listings" entry points open the cloud hub / edit screens when Supabase is configured.
                            composable(Routes.PRO_CREATE) {
                                if (vm.social.enabled) MyListingsScreen(vm, onBack = { nav.popBackStack() }, onEdit = { kind, id -> nav.navigate(Routes.listingEdit(id, kind)) }, onItems = { nav.navigate(Routes.itemEdit(it, null)) }, onMembers = { nav.navigate(Routes.members(it)) }, onRecommend = { nav.navigate(Routes.recommendShow(it)) }, onOrders = { nav.navigate(Routes.vendorOrders(it)) }, onJobs = { nav.navigate(Routes.listingJobs(it)) }, onVehicles = { nav.navigate(Routes.MY_VEHICLES) }, onInvites = { nav.navigate(Routes.INVITES) }, onOpenProfile = { nav.navigate(Routes.listing(it)) }, onScan = { nav.navigate(Routes.RECOMMEND_SCAN) })
                                else ProCreateScreen(vm, onBack = { nav.popBackStack() }, onHome = home, onListings = { t -> nav.navigate("${Routes.LISTINGS}?tab=$t") { popUpTo(Routes.HOME) } }, onVehicleForm = { nav.navigate(Routes.VEHICLE_FORM) }) }
                            composable("${Routes.LISTINGS}?tab={tab}", arguments = listOf(navArgument("tab") { type = NavType.StringType; defaultValue = "vehicles" })) { e ->
                                if (vm.social.enabled) MyListingsScreen(vm, onBack = { nav.popBackStack() }, onEdit = { kind, id -> nav.navigate(Routes.listingEdit(id, kind)) }, onItems = { nav.navigate(Routes.itemEdit(it, null)) }, onMembers = { nav.navigate(Routes.members(it)) }, onRecommend = { nav.navigate(Routes.recommendShow(it)) }, onOrders = { nav.navigate(Routes.vendorOrders(it)) }, onJobs = { nav.navigate(Routes.listingJobs(it)) }, onVehicles = { nav.navigate(Routes.MY_VEHICLES) }, onInvites = { nav.navigate(Routes.INVITES) }, onOpenProfile = { nav.navigate(Routes.listing(it)) }, onScan = { nav.navigate(Routes.RECOMMEND_SCAN) })
                                else ManageListingsScreen(vm, e.arguments?.getString("tab") ?: "vehicles", onBack = { nav.popBackStack() },
                                    onVehicle = { id -> nav.navigate(if (id == null) Routes.VEHICLE_FORM else "${Routes.VEHICLE_FORM}?id=${Uri.encode(id)}") },
                                    onBusiness = { i -> vm.editBusiness(i); nav.navigate(Routes.PRO_CREATE) },
                                    onSkill = { n -> nav.navigate(if (n == null) Routes.ADD_SKILL else "${Routes.ADD_SKILL}?name=${Uri.encode(n)}") }) }
                            composable("${Routes.VEHICLE_FORM}?id={id}", arguments = listOf(navArgument("id") { type = NavType.StringType; nullable = true; defaultValue = null })) { e ->
                                if (vm.social.enabled) VehicleEditScreen(vm, e.arguments?.getString("id"), onBack = { nav.popBackStack() })
                                else VehicleFormScreen(vm, e.arguments?.getString("id"), onBack = { nav.popBackStack() }, onDone = { nav.navigate("${Routes.LISTINGS}?tab=vehicles") { popUpTo(Routes.HOME) } }) }
                            composable("${Routes.ADD_SKILL}?name={name}", arguments = listOf(navArgument("name") { type = NavType.StringType; nullable = true; defaultValue = null })) { e ->
                                if (vm.social.enabled) ListingEditScreen(vm, kind = "SKILL", id = null, onBack = { nav.popBackStack() }, onDone = { nav.popBackStack() })
                                else AddSkillScreen(vm, e.arguments?.getString("name"), onBack = { nav.popBackStack() }) }
                            composable(Routes.EARNINGS) { EarningsScreen(vm, onBack = { nav.popBackStack() }) }
                            // Cloud builds post through social.post (the real feed); the demo screen writes to the local demo store.
                            composable(Routes.CREATE_POST) { if (vm.social.enabled) { Box(Modifier.fillMaxSize()); NewPostSheet(vm) { nav.popBackStack() } } else CreatePostScreen(vm, onClose = { nav.popBackStack() }) }
                            composable(Routes.MESSAGES) { if (vm.social.enabled) CloudMessagesScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.chat(it)) }, onSync = { nav.navigate(Routes.SYNC) }, onNewGroup = { nav.navigate(Routes.GROUP_NEW) }, onRoute = { r -> com.bucks.app.data.Push.safeRoute(r)?.let { nav.navigate(if (it == "bucks-id") Routes.BUCKS_ID else if (it.startsWith("studio/")) Routes.studioListing(it.removePrefix("studio/")) else it) } }) else MessagesScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.chat(it)) }, onCall = call) }
                            composable(Routes.GROUP_NEW) { if (vm.social.enabled) NewGroupScreen(vm, onBack = { nav.popBackStack() }, onCreated = { id -> nav.navigate(Routes.chat(id)) { popUpTo(Routes.MESSAGES) } }) else LaunchedEffect(Unit) { nav.popBackStack() } }
                            composable(Routes.CHAT, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> val id = e.arguments!!.getString("id")!!; if (vm.social.enabled) CloudChatScreen(vm, id, onBack = { nav.popBackStack() }, onOpenListing = { nav.navigate(Routes.listing(it)) }) else ChatScreen(vm, id, onBack = { nav.popBackStack() }, onCall = call) }
                            composable(Routes.SYNC) { SyncScreen(vm, onBack = { nav.popBackStack() }, onOpenChat = { nav.navigate(Routes.chat(it)) }) }
                            composable(Routes.MOMENTS, arguments = listOf(navArgument("author") { type = NavType.StringType })) { e -> MomentViewerScreen(vm, e.arguments!!.getString("author")!!, onClose = { nav.popBackStack() }, onOpenChat = { nav.navigate(Routes.chat(it)) { popUpTo(Routes.FEED) } }) }
                            composable(Routes.MOMENT_NEW) { NewMomentScreen(vm, onClose = { nav.popBackStack() }) }
                            composable(Routes.SETTINGS_PRIVACY) { PrivacyScreen(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.SETTINGS_NOTIFS) { NotificationsScreen(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.SETTINGS_APPEARANCE) { AppearanceScreen(onBack = { nav.popBackStack() }) }
                            composable(Routes.SETTINGS_BLOCKED) { BlockedScreen(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.SETTINGS_CLOSE) { CloseFriendsScreen(vm, onBack = { nav.popBackStack() }) }
                            // Dispatch (cloud-only): a buyer following a delivery, and the driver's UPI payment QR (opened through vm.open(Routes.PAYMENT_QR)).
                            composable(Routes.DELIVERY_TRACK, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> DeliveryTrackScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }) }
                            composable(Routes.PAYMENT_QR) { PaymentQrScreen(vm, onBack = { nav.popBackStack() }) }
                            // Discover (cloud-only): the universal listing profile for a business, skill or driver.
                            composable(Routes.LISTING, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> val id = e.arguments!!.getString("id")!!
                                ListingProfileScreen(vm, id, onBack = { nav.popBackStack() }, onOpenChat = { nav.navigate(Routes.chat(it)) }, onCart = { nav.navigate(Routes.CLOUD_CART) }, onJobs = { nav.navigate(Routes.listingJobs(it)) }, onBook = { k -> vm.setRideKind(k); ride() }, onOpenListing = { nav.navigate(Routes.listing(it)) }, onMap = { nav.navigate(Routes.MAPS) }) }
                            // Commerce (cloud-only): cart + checkout, order page, my orders and the vendor order inbox.
                            composable(Routes.CLOUD_CART) { CloudCartScreen(vm, onBack = { nav.popBackStack() }, onPlaced = { ids -> if (ids.size == 1) nav.navigate(Routes.cloudOrder(ids.first())) { popUpTo(Routes.CLOUD_CART) { inclusive = true } } else nav.navigate(Routes.MY_ORDERS) { popUpTo(Routes.CLOUD_CART) { inclusive = true } } }) }
                            composable(Routes.CLOUD_ORDER, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> CloudOrderScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onTrack = { nav.navigate(Routes.deliveryTrack(it)) }, onOpenListing = { nav.navigate(Routes.listing(it)) }) }
                            composable(Routes.MY_ORDERS) { MyOrdersScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.cloudOrder(it)) }) }
                            composable(Routes.VENDOR_ORDERS, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> VendorOrdersScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.cloudOrder(it)) }) }
                            // Manage (cloud-only): own listings, products, vehicles, admins, invites and the recommendation QR.
                            // Studio (cloud-only): the professional space. The hub lists everything I run; each listing has a dashboard.
                            composable(Routes.MY_LISTINGS) { StudioScreen(vm, onBack = { nav.popBackStack() },
                                onOpen = { nav.navigate(Routes.studioListing(it)) },
                                onCreate = { kind -> when (kind) { "VEHICLE" -> nav.navigate(Routes.vehicleEdit(null)); else -> nav.navigate(Routes.listingEdit(null, kind)) } },
                                onVehicle = { nav.navigate(Routes.vehicleEdit(it)) },
                                onVehicles = { nav.navigate(Routes.MY_VEHICLES) },
                                onInvites = { nav.navigate(Routes.INVITES) },
                                onScan = { nav.navigate(Routes.RECOMMEND_SCAN) },
                                onBucksId = { nav.navigate(Routes.BUCKS_ID) }) }
                            composable(Routes.STUDIO_LISTING, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> ListingDashboardScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() },
                                onEdit = { kind, id -> nav.navigate(Routes.listingEdit(id, kind)) },
                                onItem = { l, i -> nav.navigate(Routes.itemEdit(l, i ?: "new")) },
                                onDocs = { nav.navigate(Routes.listingDocs(it)) },
                                onMembers = { nav.navigate(Routes.members(it)) },
                                onRecommend = { nav.navigate(Routes.recommendShow(it)) },
                                onOrders = { nav.navigate(Routes.vendorOrders(it)) },
                                onJobs = { nav.navigate(Routes.listingJobs(it)) },
                                onOpenProfile = { nav.navigate(Routes.listing(it)) },
                                onPaymentQr = { nav.navigate(Routes.PAYMENT_QR) },
                                onVehicles = { nav.navigate(Routes.MY_VEHICLES) }) }
                            composable(Routes.POST, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> PostDetailScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }) }
                            composable(Routes.MAPS) { MapsScreen(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.CONTACTS) { ContactsScreen(vm, onBack = { nav.popBackStack() }, onSync = { nav.navigate(Routes.SYNC) }, onOpenChat = { nav.navigate(Routes.chat(it)) }, onMap = { nav.navigate(Routes.MAPS) }) }
                            composable(Routes.BUCKS_ID) { BucksIdScreen(vm, onBack = { nav.popBackStack() }, onSync = { nav.navigate(Routes.SYNC) }) }
                            composable(Routes.MY_VEHICLES) { VehiclesScreen(vm, onBack = { nav.popBackStack() }, onEdit = { nav.navigate(Routes.vehicleEdit(it)) }, onStats = { nav.navigate(Routes.VEHICLE_STATS) }, onMembers = { nav.navigate(Routes.members("v:$it")) }) }
                            composable(Routes.VEHICLE_STATS) { VehicleStatsScreen(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.LISTING_EDIT, arguments = listOf(navArgument("id") { type = NavType.StringType; nullable = true; defaultValue = null }, navArgument("kind") { type = NavType.StringType; defaultValue = "BUSINESS" },
                                    navArgument("service") { type = NavType.StringType; nullable = true; defaultValue = null })) { e ->
                                val editingId = e.arguments?.getString("id")
                                ListingEditScreen(vm, kind = e.arguments?.getString("kind") ?: "BUSINESS", id = editingId, onBack = { nav.popBackStack() }, onDone = { nav.popBackStack() },
                                    service = e.arguments?.getString("service"),
                                    onDocs = { id -> nav.navigate(Routes.listingDocs(id)) },
                                    // A just-created listing opens its dashboard (with the go-live checklist) in place of the empty "Add" form.
                                    onCreated = { id -> nav.navigate(Routes.studioListing(id)) { popUpTo(Routes.LISTING_EDIT) { inclusive = true } } }) }
                            composable(Routes.LISTING_DOCS, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> ListingDocsScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }) }
                            composable(Routes.STAFF_REVIEW) { StaffReviewScreen(vm, onBack = { nav.popBackStack() }) }
                            // ITEM_EDIT convention (there is no separate items-list route): item == null -> the list (ItemsScreen); item == "new" -> add; any other id -> edit that item.
                            composable(Routes.ITEM_EDIT, arguments = listOf(navArgument("listing") { type = NavType.StringType }, navArgument("item") { type = NavType.StringType; nullable = true; defaultValue = null })) { e ->
                                val listing = e.arguments!!.getString("listing")!!; val item = e.arguments?.getString("item")
                                if (item == null) ItemsScreen(vm, listing, onBack = { nav.popBackStack() }, onEdit = { l, i -> nav.navigate(Routes.itemEdit(l, i ?: "new")) })
                                else ItemEditScreen(vm, listing, item.takeUnless { it == "new" }, onBack = { nav.popBackStack() }) }
                            composable(Routes.VEHICLE_EDIT, arguments = listOf(navArgument("id") { type = NavType.StringType; nullable = true; defaultValue = null })) { e -> VehicleEditScreen(vm, e.arguments?.getString("id"), onBack = { nav.popBackStack() }) }
                            composable(Routes.RECOMMEND_SHOW, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> RecommendShowScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }) }
                            composable(Routes.RECOMMEND_SCAN) { RecommendScanScreen(vm, onBack = { nav.popBackStack() }) }
                            // MEMBERS convention: a plain id is a listing; "v:<vehicleId>" (built with Routes.members("v:$vehicleId")) is a vehicle.
                            composable(Routes.MEMBERS, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> val raw = e.arguments!!.getString("id")!!
                                if (raw.startsWith("v:")) MembersScreen(vm, vehicleId = raw.removePrefix("v:"), onBack = { nav.popBackStack() }) else MembersScreen(vm, listingId = raw, onBack = { nav.popBackStack() }) }
                            composable(Routes.INVITES) { InvitesScreen(vm, onBack = { nav.popBackStack() }) }
                            // Jobs (cloud-only): a listing's jobs, post a job, the job page (apply / manage applications), my applications and jobs near me.
                            composable(Routes.LISTING_JOBS, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> val id = e.arguments!!.getString("id")!!
                                if (vm.social.enabled) ListingJobsScreen(vm, id, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.job(it)) }, onNew = { nav.navigate(Routes.jobNew(id)) }) else JobsNeedCloud(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.JOB_NEW, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
                                if (vm.social.enabled) JobNewScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onDone = { nav.popBackStack() }) else JobsNeedCloud(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.JOB, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e ->
                                if (vm.social.enabled) JobScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onOpenListing = { nav.navigate(Routes.listing(it)) }, onOpenChat = { nav.navigate(Routes.chat(it)) }) else JobsNeedCloud(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.MY_APPLICATIONS) { if (vm.social.enabled) MyApplicationsScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.job(it)) }, onNear = { nav.navigate(Routes.JOBS_NEAR) }) else JobsNeedCloud(vm, onBack = { nav.popBackStack() }) }
                            composable(Routes.JOBS_NEAR) { if (vm.social.enabled) JobsNearScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(Routes.job(it)) }, onMyApplications = { nav.navigate(Routes.MY_APPLICATIONS) }) else JobsNeedCloud(vm, onBack = { nav.popBackStack() }) }
                        }
                        // A driver's ringing request shows over whichever screen they're on; it never moves them away from what they're doing.
                        // imePadding: with a keyboard up (chat, search) the card sits in the space above it, so Accept is never behind the keys.
                        if (loggedIn) s.driverRide?.takeIf { it.status == DriverRideStatus.RINGING }?.let { dr ->
                            RideRequestCard(dr, onAccept = { vm.driverAccept() }, onDecline = { vm.driverDecline() }, busy = vm.dispatch.busy, modifier = Modifier.align(Alignment.Center).imePadding()) }
                        if (s.call != null) CallOverlay(vm)
                        ConfirmationSheet(vm, toast)
                        }
                    }
                }
            }
        }
        if (showIntro) com.bucks.app.ui.components.BrandIntro { showIntro = false }
        // Test builds: a newer build on GitHub shows a one-tap update once the intro is out of the way.
        LaunchedEffect(showIntro) { if (!showIntro) vm.updates.check(ctx, manual = false) }
        if (!showIntro) UpdatePrompt(vm.updates)
        }
        }
    }
}

/** Demo-mode fallback for the cloud-only jobs routes: say why and go back. */
@Composable
private fun JobsNeedCloud(vm: BucksViewModel, onBack: () -> Unit) { LaunchedEffect(Unit) { vm.toast("Jobs need the cloud build."); onBack() } }

@Composable
private fun DrawerItem(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) = NavigationDrawerItem(icon = { Icon(icon, null) }, label = { Text(label, style = MaterialTheme.typography.bodyLarge) }, selected = selected, onClick = onClick, shape = MaterialTheme.shapes.small, modifier = Modifier.padding(vertical = 1.dp),
    colors = NavigationDrawerItemDefaults.colors(selectedContainerColor = MaterialTheme.colorScheme.primaryContainer, selectedIconColor = MaterialTheme.colorScheme.onPrimaryContainer, selectedTextColor = MaterialTheme.colorScheme.onPrimaryContainer, unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant, unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant, unselectedContainerColor = Color.Transparent))
