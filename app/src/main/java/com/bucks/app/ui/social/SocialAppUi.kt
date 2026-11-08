package com.bucks.app.ui.social

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.bucks.app.data.Here
import com.bucks.app.data.Prefs
import com.bucks.app.data.Push
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.UpdatePrompt
import com.bucks.app.ui.components.BrandIntro
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.*
import com.bucks.app.ui.theme.BucksTheme
import com.bucks.app.ui.theme.Purple
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.launch

/** The five places of the social app. Create is an action (opens the composer), not a screen. */
enum class SocialTab(val label: String, val icon: ImageVector, val selectedIcon: ImageVector, val route: String?) {
    HOME("Home", Icons.Rounded.Home, Icons.Rounded.Home, Routes.HOME),
    DISCOVER("Discover", Icons.Rounded.Search, Icons.Rounded.Search, Routes.DISCOVER),
    CREATE("Create", Icons.Rounded.Add, Icons.Rounded.Add, null),
    CHATS("Chats", Icons.Rounded.ChatBubbleOutline, Icons.Rounded.ChatBubble, Routes.CHATS),
    PROFILE("Profile", Icons.Rounded.PersonOutline, Icons.Rounded.Person, Routes.ME),
}

private val SIGNED_OUT = setOf(Routes.SPLASH, Routes.LOGIN, Routes.OTP, Routes.SIGNUP_EMAIL)
private val ONBOARDING = setOf(Routes.AGE, Routes.GUARDIAN, Routes.PROFILE)

/**
 * The Bucks 1.0 app shell (social only; see docs/PLAY_RELEASE_PLAN.md). Reuses the existing social logic (vm.social) and screens where
 * they fit, and adds the onboarding gates (date of birth, guardian consent), Discover, profiles of other people, Help and reporting.
 */
@Composable
fun SocialAppUi(vm: BucksViewModel, startRoute: String? = null, onStartRouteHandled: () -> Unit = {}) {
    val sysDark = isSystemInDarkTheme()
    val dark = when (Prefs.theme) { Prefs.Theme.LIGHT -> false; Prefs.Theme.DARK -> true; else -> sysDark }
    BucksTheme(dark = dark, textScale = Prefs.textSize.scale) {
        val nav = rememberNavController(); val snack = remember { SnackbarHostState() }; val scope = rememberCoroutineScope()
        val s by vm.state.collectAsState(); val social = vm.social; val safety = vm.safety; val ctx = LocalContext.current
        val startDest = remember { if (vm.isLoggedIn) Routes.HOME else Routes.SPLASH }
        var showIntro by rememberSaveable { mutableStateOf(vm.isLoggedIn && startRoute == null) }
        val toast: (String) -> Unit = { msg -> scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar(msg, duration = SnackbarDuration.Short) } }
        LaunchedEffect(Unit) { vm.toasts.collect { toast(it) } }

        // ---- onboarding gate: the server says what it still needs (date of birth, a guardian's consent) before the app opens up ----
        val backEntry by nav.currentBackStackEntryAsState(); val current = backEntry?.destination?.route ?: Routes.SPLASH
        LaunchedEffect(social.me?.id) { if (social.me != null) safety.refresh() }
        // Analytics only for adults who haven't opted out; screen names are route patterns (no ids).
        LaunchedEffect(Prefs.shareUsage, safety.band) { safety.applyAnalytics() }
        LaunchedEffect(current) { com.bucks.app.data.Analytics.screen(current.substringBefore('/').substringBefore('?')) }
        LaunchedEffect(safety.pendingStep, current) {
            val step = safety.pendingStep ?: return@LaunchedEffect
            if (current in SIGNED_OUT) return@LaunchedEffect
            val target = if (step == com.bucks.app.ui.Safety.STEP_BIRTH) Routes.AGE else Routes.GUARDIAN
            if (current != target) nav.navigate(target) { popUpTo(0); launchSingleTop = true }
        }
        /** Where onboarding goes once the server is satisfied: profile setup for a new person, else Home. */
        val afterGate: () -> Unit = { if (!vm.isLoggedIn) nav.navigate(Routes.PROFILE) { popUpTo(0) } else nav.navigate(Routes.HOME) { popUpTo(0) } }

        // ---- permissions: notifications once signed in; approximate location for Nearby, explained first (Play policy) ----
        val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
        fun fetchLocation() { if (!Here.hasPermission(ctx)) return; runCatching { LocationServices.getFusedLocationProviderClient(ctx).getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null).addOnSuccessListener { l -> if (l != null) Here.fixOf(l).let { vm.onLocation(it.at, it.mocked) } } } }
        val locPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> if (ok) fetchLocation() else vm.onLocationDenied() }
        var locDisclosure by rememberSaveable { mutableStateOf(false) }
        val ready = s.user != null && !showIntro && current !in SIGNED_OUT && current !in ONBOARDING
        LaunchedEffect(ready) { if (ready) { if (Here.hasPermission(ctx)) fetchLocation() else if (!safety.isChild && !Prefs.askedLocation) locDisclosure = true } }
        LaunchedEffect(ready) { if (ready && Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }
        LifecycleEventEffect(Lifecycle.Event.ON_START) { if (ready && Here.hasPermission(ctx)) fetchLocation() }
        if (locDisclosure) AlertDialog(onDismissRequest = { locDisclosure = false; Prefs.askedLocation = true; vm.onLocationDenied() },
            icon = { Icon(Icons.Rounded.NearMe, null) },
            title = { Text("See what's happening near you") },
            text = { Text("Bucks uses your approximate location (about 2 km) to show posts and Moments from people nearby. Your exact location is never shown to anyone. You can change this any time in your phone's settings.") },
            confirmButton = { TextButton({ locDisclosure = false; Prefs.askedLocation = true; locPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION) }) { Text("Continue") } },
            dismissButton = { TextButton({ locDisclosure = false; Prefs.askedLocation = true; vm.onLocationDenied() }) { Text("Not now") } })

        // A tapped notification asked for a screen: open it once signed in (Push.safeRoute vetted it). Routes this shell doesn't have are ignored.
        LaunchedEffect(startRoute, s.user != null) { val r = startRoute ?: return@LaunchedEffect; if (s.user == null) return@LaunchedEffect
            runCatching { nav.navigate(r) { launchSingleTop = true } }; onStartRouteHandled() }
        LaunchedEffect(Unit) { vm.nav.collect { route -> runCatching { nav.navigate(route) { launchSingleTop = true } } } }

        var composer by remember { mutableStateOf<String?>(null) }   // "post" while the post composer is open
        var createMenu by remember { mutableStateOf(false) }
        var reporting by remember { mutableStateOf<ReportTarget?>(null) }
        val currentTab = when { current == Routes.HOME -> SocialTab.HOME; current == Routes.DISCOVER -> SocialTab.DISCOVER; current == Routes.CHATS -> SocialTab.CHATS; current == Routes.ME -> SocialTab.PROFILE; else -> null }
        fun tab(t: SocialTab) {
            if (t == SocialTab.CREATE) { createMenu = true; return }
            nav.navigate(t.route!!) { popUpTo(Routes.HOME) { inclusive = t == SocialTab.HOME; saveState = t != SocialTab.HOME }; launchSingleTop = true; restoreState = true }
        }
        val logout: () -> Unit = { vm.logout(); nav.navigate(Routes.LOGIN) { popUpTo(0) } }
        val openChat: (String) -> Unit = { nav.navigate(Routes.chat(it)) }
        val openPerson: (String) -> Unit = { id -> if (id == social.me?.id) tab(SocialTab.PROFILE) else nav.navigate(Routes.person(id)) }

        CompositionLocalProvider(LocalReporter provides { t -> reporting = t }, LocalOpenPerson provides openPerson) {
        Scaffold(containerColor = if (current == Routes.SPLASH) Purple else MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snack) { d -> Snackbar(d, shape = MaterialTheme.shapes.medium, containerColor = MaterialTheme.colorScheme.inverseSurface, contentColor = MaterialTheme.colorScheme.inverseOnSurface) } },
            bottomBar = { if (currentTab != null) SocialBottomBar(currentTab, unreadChats = social.inbox.sumOf { it.unread } + social.incoming.size) { tab(it) } }) { pad ->
            NavHost(nav, startDestination = startDest, modifier = Modifier.padding(pad).consumeWindowInsets(pad),
                enterTransition = { fadeIn(tween(200)) + slideInHorizontally(tween(240, easing = FastOutSlowInEasing)) { it / 12 } }, exitTransition = { fadeOut(tween(120)) },
                popEnterTransition = { fadeIn(tween(200)) }, popExitTransition = { fadeOut(tween(140)) + slideOutHorizontally(tween(200, easing = FastOutSlowInEasing)) { it / 12 } }) {
                // ---- signed out and onboarding ----
                composable(Routes.SPLASH) { WelcomeScreen(onStart = { nav.navigate(Routes.LOGIN) }) }
                composable(Routes.LOGIN) { LoginScreen(vm, onSent = { nav.navigate(Routes.OTP) }, onSignedIn = { nav.navigate(Routes.HOME) { popUpTo(0) } }, onSignUp = { nav.navigate(Routes.SIGNUP_EMAIL) }, showToast = toast) }
                composable(Routes.SIGNUP_EMAIL) { SignUpEmailScreen(vm, onBack = { nav.popBackStack() }, onCreated = { nav.navigate(Routes.AGE) }, onUseMobile = { nav.popBackStack() }) }
                composable(Routes.OTP) { OtpScreen(vm, s.tempPhone, onBack = { nav.popBackStack() }, onVerified = { nav.navigate(Routes.AGE) { popUpTo(0) } }, showToast = toast) }
                composable(Routes.AGE) { AgeScreen(vm, onDone = { band -> if (band == "ADULT") afterGate() else nav.navigate(Routes.GUARDIAN) { popUpTo(0); launchSingleTop = true } }, onSignOut = logout) }
                composable(Routes.GUARDIAN) { GuardianScreen(vm, onDone = afterGate, onSignOut = logout) }
                composable(Routes.PROFILE) { CreateProfileScreen(vm, onDone = { nav.navigate(Routes.HOME) { popUpTo(0) } }, showToast = toast) }
                // ---- tabs ----
                composable(Routes.HOME) { HomeFeedScreen(vm, onNotifications = { nav.navigate(Routes.NOTIFICATIONS) }, onOpenMoments = { nav.navigate(Routes.moments(it)) }, onNewMoment = { nav.navigate(Routes.MOMENT_NEW) }, onNewPost = { composer = "post" }, onDiscover = { tab(SocialTab.DISCOVER) }) }
                composable(Routes.DISCOVER) { DiscoverScreen(vm, onOpenPerson = openPerson, onContacts = { nav.navigate(Routes.CONTACTS) }, onBucksId = { nav.navigate(Routes.SYNC) }) }
                composable(Routes.CHATS) { CloudMessagesScreen(vm, onBack = null, onOpen = openChat, onSync = { tab(SocialTab.DISCOVER) }, onNewGroup = { nav.navigate(Routes.GROUP_NEW) }, onRoute = { r -> Push.safeRoute(r)?.let { runCatching { nav.navigate(it) } } }) }
                composable(Routes.ME) { MeScreen(vm, onEditProfile = { nav.navigate(Routes.PROFILE) }, onSettings = { nav.navigate(Routes.SETTINGS) }, onSynced = { nav.navigate(Routes.SYNC) }, onNewPost = { composer = "post" }, onBucksId = { nav.navigate(Routes.BUCKS_ID) }) }
                // ---- people, posts, chat, moments ----
                composable(Routes.PERSON, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> PersonScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onOpenChat = openChat) }
                composable(Routes.POST, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> PostDetailScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }) }
                composable(Routes.NOTIFICATIONS) { CloudMessagesScreen(vm, onBack = { nav.popBackStack() }, onOpen = openChat, onSync = { tab(SocialTab.DISCOVER) }, onNewGroup = { nav.navigate(Routes.GROUP_NEW) }, initialTab = 1, onRoute = { r -> Push.safeRoute(r)?.let { runCatching { nav.navigate(it) } } }) }
                composable(Routes.MESSAGES) { CloudMessagesScreen(vm, onBack = { nav.popBackStack() }, onOpen = openChat, onSync = { tab(SocialTab.DISCOVER) }, onNewGroup = { nav.navigate(Routes.GROUP_NEW) }) }
                composable(Routes.GROUP_NEW) { NewGroupScreen(vm, onBack = { nav.popBackStack() }, onCreated = { id -> nav.navigate(Routes.chat(id)) { popUpTo(Routes.CHATS) } }) }
                composable(Routes.CHAT, arguments = listOf(navArgument("id") { type = NavType.StringType })) { e -> CloudChatScreen(vm, e.arguments!!.getString("id")!!, onBack = { nav.popBackStack() }, onOpenListing = { }) }
                composable(Routes.MOMENTS, arguments = listOf(navArgument("author") { type = NavType.StringType })) { e -> MomentViewerScreen(vm, e.arguments!!.getString("author")!!, onClose = { nav.popBackStack() }, onOpenChat = { nav.navigate(Routes.chat(it)) { popUpTo(Routes.HOME) } }) }
                composable(Routes.MOMENT_NEW) { NewMomentScreen(vm, onClose = { nav.popBackStack() }) }
                composable(Routes.SYNC) { SyncScreen(vm, onBack = { nav.popBackStack() }, onOpenChat = openChat) }
                composable(Routes.CONTACTS) { ContactsScreen(vm, onBack = { nav.popBackStack() }, onSync = { nav.navigate(Routes.SYNC) }, onOpenChat = openChat, onMap = { }) }
                composable(Routes.BUCKS_ID) { BucksIdScreen(vm, onBack = { nav.popBackStack() }, onSync = { nav.navigate(Routes.SYNC) }) }
                // ---- settings, safety, help ----
                composable(Routes.SETTINGS) { SocialSettingsScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(it) }, onEditProfile = { nav.navigate(Routes.PROFILE) }, onLogout = logout, onDeleted = { nav.navigate(Routes.LOGIN) { popUpTo(0) } }) }
                composable(Routes.SAFETY_CENTER) { SafetyCenterScreen(vm, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(it) }) }
                composable(Routes.HELP) { HelpScreen(vm, onBack = { nav.popBackStack() }, onFeedback = { nav.navigate(Routes.FEEDBACK) }) }
                composable(Routes.FEEDBACK) { FeedbackBoardScreen(vm, onBack = { nav.popBackStack() }) }
                composable(Routes.STAFF_REPORTS) { StaffReportsScreen(vm, onBack = { nav.popBackStack() }, onOpenPerson = openPerson) }
                composable(Routes.SETTINGS_PRIVACY) { PrivacyScreen(vm, onBack = { nav.popBackStack() }) }
                composable(Routes.SETTINGS_NOTIFS) { NotificationsScreen(vm, onBack = { nav.popBackStack() }) }
                composable(Routes.SETTINGS_APPEARANCE) { AppearanceScreen(onBack = { nav.popBackStack() }) }
                composable(Routes.SETTINGS_BLOCKED) { BlockedScreen(vm, onBack = { nav.popBackStack() }) }
                composable(Routes.SETTINGS_CLOSE) { CloseFriendsScreen(vm, onBack = { nav.popBackStack() }) }
            }
        }
        if (createMenu) CreateSheet(onPost = { createMenu = false; composer = "post" }, onMoment = { createMenu = false; nav.navigate(Routes.MOMENT_NEW) }, onDismiss = { createMenu = false })
        if (composer == "post") NewPostSheet(vm) { composer = null }
        reporting?.let { t -> ReportSheet(vm, t) { reporting = null } }
        }
        if (showIntro) BrandIntro { showIntro = false }
        // Test builds only: a newer GitHub build offers a one-tap update. Play builds never self-update (SELF_UPDATE=false).
        LaunchedEffect(showIntro) { if (!showIntro) vm.updates.check(ctx, manual = false) }
        if (!showIntro) UpdatePrompt(vm.updates)
    }
}

/** Open someone's profile from anywhere (post author, comment, search result). */
val LocalOpenPerson = staticCompositionLocalOf<(String) -> Unit> { {} }

/**
 * Bottom navigation: four places and a raised Create button in the middle. Words under every icon (not icons alone), 48 dp+
 * targets, and the selected tab is announced to TalkBack.
 */
@Composable
fun SocialBottomBar(current: SocialTab, unreadChats: Int, onSelect: (SocialTab) -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 0.dp, shadowElevation = 8.dp) {
        Row(Modifier.fillMaxWidth().navigationBarsPadding().height(68.dp), verticalAlignment = Alignment.CenterVertically) {
            SocialTab.entries.forEach { t ->
                val sel = t == current
                if (t == SocialTab.CREATE) {
                    Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(52.dp).clip(CircleShape).background(androidx.compose.ui.graphics.Brush.linearGradient(listOf(Purple, com.bucks.app.ui.theme.PurpleDeep)))
                            .clickable(role = Role.Button, onClickLabel = "Create a post or moment") { onSelect(t) }.semantics { contentDescription = "Create" }, contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.Add, null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(30.dp))
                        }
                    }
                } else {
                    val c by animateColorAsState(if (sel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, tween(180), label = "tab")
                    Column(Modifier.weight(1f).fillMaxHeight().clickable(role = Role.Tab) { onSelect(t) }.semantics { selected = sel }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        BadgedBox(badge = { if (t == SocialTab.CHATS && unreadChats > 0) Badge { Text(if (unreadChats > 99) "99+" else "$unreadChats") } }) {
                            Box(Modifier.clip(CircleShape).background(if (sel) MaterialTheme.colorScheme.primaryContainer else androidx.compose.ui.graphics.Color.Transparent).padding(horizontal = 16.dp, vertical = 4.dp)) {
                                Icon(if (sel) t.selectedIcon else t.icon, null, tint = if (sel) MaterialTheme.colorScheme.onPrimaryContainer else c, modifier = Modifier.size(24.dp))
                            }
                        }
                        Text(t.label, style = MaterialTheme.typography.labelSmall.copy(fontSize = 12.sp), color = c, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
        }
    }
}

/** What Create offers: a post (stays on your profile) or a Moment (24 hours). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateSheet(onPost: () -> Unit, onMoment: () -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Text("Create", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 12.dp))
            CreateOption(Icons.Rounded.EditNote, "Post", "Words, photos or a video. Stays on your profile.", onPost)
            Spacer(Modifier.height(10.dp))
            CreateOption(Icons.Rounded.AutoAwesome, "Moment", "A photo or video that disappears after 24 hours.", onMoment)
        }
    }
}

@Composable
private fun CreateOption(icon: ImageVector, title: String, detail: String, onClick: () -> Unit) =
    Surface(onClick = onClick, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
            Column(Modifier.padding(start = 14.dp).weight(1f)) { Text(title, style = MaterialTheme.typography.titleMedium); Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
