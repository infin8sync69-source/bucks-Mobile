package com.bucks.app.ui

import androidx.annotation.StringRes
import com.bucks.app.R
import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.SystemClock
import com.bucks.app.BuildConfig
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.bucks.app.ai.IntentRouter
import com.bucks.app.ai.ParsedIntent
import com.bucks.app.ai.Tools
import com.bucks.app.data.*
import com.bucks.app.ui.nav.Routes
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.random.Random

enum class Role { CUSTOMER, PROVIDER }
enum class SortMode(@StringRes private val labelRes: Int) { TRUST(R.string.g8_sort_trust), NEAR(R.string.g8_sort_near), PRICE(R.string.g8_sort_price); val label: String get() = Str.get(labelRes) }
enum class ScopeFilter(@StringRes private val labelRes: Int) { ALL(R.string.g8_scope_all), LOCAL(R.string.g8_scope_local), GLOBAL(R.string.g8_scope_global); val label: String get() = Str.get(labelRes) }
enum class AskMode { RESULTS, CHAT }
enum class ProKind { VEHICLE, SKILLS, BUSINESS }
data class CallState(val name: String, val phone: String, val startedAt: Long = System.currentTimeMillis(), val muted: Boolean = false, val speaker: Boolean = false)

data class UiState(
    val user: User? = null, val pro: ProProfile? = null, val businesses: List<Business> = emptyList(), val editBiz: Int? = null,
    val role: Role = Role.CUSTOMER, val online: Boolean = false, val earnings: Int = 0,
    val tempPhone: String = "", val tempEmail: String = "",
    val cart: Map<String, Int> = emptyMap(),
    val orders: List<Order> = emptyList(), val requests: List<ServiceRequest> = emptyList(), val rides: List<Ride> = emptyList(),
    val ride: Ride? = null, val driverRide: DriverRide? = null,
    val rideKind: VehicleKind = VehicleKind.AUTO, val rideDest: Place? = null, val ridePickup: Place? = null,
    val query: String = "", val sort: SortMode = SortMode.TRUST, val scope: ScopeFilter = ScopeFilter.ALL, val askMode: AskMode = AskMode.RESULTS, val lens: Lens = Lens.ALL,
    val agent: List<AgentMessage> = listOf(AgentMessage(false, Str.get(R.string.g8_agent_intro))),
    val thinking: Boolean = false, val voiceLang: String = "en-IN",
    val myVotes: Map<String, Int> = emptyMap(), val postVotes: Map<String, Int> = emptyMap(),
    val incoming: List<Incoming> = emptyList(), val followedProviders: Set<String> = emptySet(), val savedPlaces: Set<String> = emptySet(),
    val proKind: ProKind? = null, val proStep: Int = 1, val proMessage: String = "",
    val pendingDest: String? = null, val pending: PendingAction? = null,
    val syncStatus: SyncStatus = SyncStatus.SYNCED, val lastSynced: String = Str.get(R.string.g8_just_now), val devices: List<LinkedDevice> = emptyList(),
    val call: CallState? = null,
    val me: LatLng? = null, val meX: Float = Seed.ME_X, val meY: Float = Seed.ME_Y, val locationGranted: Boolean = false, val mockLocation: Boolean = false,
    /** Street-level name of where I am ("12th Main, Indiranagar"), looked up from the map; null until known or offline. */
    val hereLabel: String? = null,
    /** Cloud builds: whether dispatch presence says I'm online with a checked vehicle ([Dispatch.online]). Null in demo builds, where the local vehicle decides. */
    val dispatchOnline: Boolean? = null,
) {
    val biz: Business? get() = businesses.firstOrNull()
    /** Online with a vehicle: in cloud builds the server's presence (cloud vehicles never reach [pro]), in demo builds the local verified vehicle. */
    val vehicleOnline: Boolean get() = online && (dispatchOnline ?: (pro?.vehicle != null))
    /** Online with anything that can take work: the active vehicle, a business or a skill. Only then do rides, orders and requests reach you. */
    val receiving: Boolean get() = vehicleOnline || businesses.any { it.online } || pro?.skillListings?.any { it.online } == true
}

class BucksViewModel(val repo: BucksRepository) : ViewModel() {
    private val _s = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _s.asStateFlow()
    // Channels, not SharedFlows: events sent while the activity is being recreated wait for the next collector.
    private val _toasts = Channel<String>(Channel.BUFFERED); val toasts = _toasts.receiveAsFlow()
    private val _nav = Channel<String>(Channel.BUFFERED); val nav = _nav.receiveAsFlow()
    private val router = IntentRouter()
    val cloudEnabled get() = router.cloudEnabled
    private var ringJob: Job? = null; private var driveJob: Job? = null; private var drvRingJob: Job? = null; private var autoRingJob: Job? = null; private var drvDriveJob: Job? = null
    /** True when the app was built with google-services.json: real phone sign-in through Firebase. */
    val cloud get() = Cloud.enabled
    /** Cloud social features (Sync, chat, feed, Moments, settings); active when Supabase and Firebase are configured. */
    val social = Social(viewModelScope, repo, ::toast)
    /** Age band, guardian consent and reports (social_safety.sql); the social shell reads it to gate onboarding and offer Report. */
    val safety = Safety(viewModelScope, ::toast)
    /** Cloud rides and deliveries on Supabase tasks (presence, ringing, PIN, payment). In demo builds the simulation below runs instead. */
    val dispatch = Dispatch(viewModelScope, social, ::toast) { msg -> toast(msg); navTo(Routes.HOME) }
    /** Cloud commerce: cart over live items, checkout, my orders, order page and the vendor inbox. */
    val commerce = Commerce(viewModelScope, social, ::toast)
    /** Cloud discovery: search over live listings and the universal listing profile. */
    val discover = Discover(viewModelScope, social, ::toast)
    /** Own listings, vehicles, admins and recommendation QR (cloud only). */
    val myListings = MyListings(viewModelScope, social, ::toast)
    /** Cloud jobs: a business posts jobs, people apply with their skill profiles, managers shortlist / hire. */
    val jobs = Jobs(viewModelScope, social, ::toast)
    /** Which services are open where I stand, and the documents my listings need (services.sql). */
    val services = Services(viewModelScope, social, ::toast)
    /** One-tap updates for test builds from GitHub Releases (never in Play builds). */
    val updates = Updates(viewModelScope, ::toast)
    /** Sample Moments for the demo build (the online build reads real ones from the server). */
    val demoMoments = com.bucks.app.ui.screens.DemoMoments()
    fun unreadCount(demoChats: List<Chat>) = if (social.enabled) social.unread else demoChats.sumOf { it.unread }
    /** Cloud builds: every vehicle I own or drive, from whichever list knows it (Home refreshes [Dispatch.vehicles] each time it opens, so its status wins). */
    val cloudVehicles: List<VehicleRow> get() = if (!dispatch.enabled) emptyList() else (dispatch.vehicles + myListings.vehicles).distinctBy { it.id }
    /** Cloud builds: the checked (ACTIVE) vehicle the online switch uses: the one online now, else the first ACTIVE one I own or drive. Null in demo builds. */
    val cloudVehicle: VehicleRow? get() = if (!dispatch.enabled) null else dispatch.vehicle?.takeIf { dispatch.online } ?: cloudVehicles.firstOrNull { it.status == "ACTIVE" }
    /** Cloud builds: a vehicle of mine that the server hasn't activated (PENDING or SUSPENDED), only while I have no ACTIVE one. Home says so instead of staying silent. */
    val waitingVehicle: VehicleRow? get() = cloudVehicles.takeIf { v -> v.isNotEmpty() && v.none { it.status == "ACTIVE" } }?.firstOrNull()
    /** The simulated parts (fake ring, "Simulate a ride request", the PIN shown on screen, auto-accepting riders) exist only in debug builds without the cloud. */
    val demoTools get() = BuildConfig.DEBUG && !dispatch.enabled
    /** True while I'm online as anything that takes work: my vehicle, or a live shop or pro listing. The Home button shows only then. */
    val providerOnline: Boolean get() = s.vehicleOnline || (!dispatch.enabled && s.receiving) || myListings.listings.any { it.status == "LIVE" && it.online && (it.kind == "BUSINESS" || it.kind == "SKILL") }
    /** Offline but able to go online (a checked vehicle, a live shop or pro listing): Home offers a small "Go online" chip instead of the button. */
    val canGoOnline: Boolean get() = !providerOnline && (cloudVehicle != null || myListings.listings.any { it.status == "LIVE" && (it.kind == "BUSINESS" || it.kind == "SKILL") }
        || (!dispatch.enabled && (s.pro?.vehicle != null || s.businesses.isNotEmpty() || !s.pro?.skillListings.isNullOrEmpty())))
    /** A fresh UiState for sign-out and account deletion; cloud builds keep reading the online state from dispatch. */
    private fun freshState() = UiState(dispatchOnline = if (dispatch.enabled) false else null)

    init {
        runCatching { Identity.ensureKey() }
        // With Firebase on, a saved profile only counts once the phone number is verified with Firebase too.
        repo.loadSession()?.takeIf { !cloud || Cloud.uid != null }?.let { s -> _s.update { it.copy(user = s.user.copy(id = s.user.id.ifBlank { safeId() }), pro = s.pro, businesses = s.businesses) }; publishOwnListings() }
        _s.update { it.copy(devices = listOf(LinkedDevice(repo.deviceId(), Build.MODEL ?: Str.get(R.string.g8_this_device), Str.get(R.string.g8_now), true))) }
        if (dispatch.enabled) { repo.replaceDrivers(emptyList(), mePos); if (s.user != null) dispatch.startDriversFeed() }
        s.user?.let { u -> if (Backend.enabled) { social.signedIn(u.name, u.phone); dispatch.resume() } }
        // Cloud dispatch is the single writer of ride / driverRide; this mirrors it into UiState and navigates on status changes.
        viewModelScope.launch { dispatch.ride.collect { r -> val prev = s.ride; if (prev == null && r == null) return@collect; _s.update { it.copy(ride = r) }; onCloudRide(prev, r) } }
        viewModelScope.launch { dispatch.driverRide.collect { d -> val prev = s.driverRide; if (prev == null && d == null) return@collect; _s.update { it.copy(driverRide = d) }; onCloudDriverRide(prev, d) } }
        viewModelScope.launch { dispatch.drivers.collect { if (dispatch.enabled) repo.replaceDrivers(it, mePos) } }
        // Cloud builds: the vehicle switch, the OnlineFab and DriverLocationService follow the server presence.
        if (dispatch.enabled) viewModelScope.launch { dispatch.onlineFlow.collect { on -> _s.update { it.copy(dispatchOnline = on) } } }
        // The driver's position comes from the location service, which keeps running with the screen off; collecting it here (not in a
        // composable, which pauses in the background) keeps the ring search and the trip on the real position all the time.
        viewModelScope.launch { combine(DriverLocationService.position, DriverLocationService.mocked) { p, m -> p to m }.collect { (p, m) -> if (p != null) onLocation(p, m) } }
    }
    /** The activity is finishing: leave the map (presence off on the app scope, since viewModelScope is already cancelled) and stop the location service. */
    override fun onCleared() { dispatch.signedOut(); DriverLocationService.stopAll() }
    /** Opens any route from a screen that has no navigation callback for it (e.g. the payment QR from the online sheet). */
    fun open(route: String) = navTo(route)
    /** The repository is re-seeded on every launch; put this user's own skills and businesses back into search. */
    private fun publishOwnListings() { val u = s.user ?: return
        s.pro?.skillListings?.forEach { addSkillProvider(u, it.name, s.pro?.rate.orEmpty()) }
        s.businesses.forEach { addBusinessProvider(it.name, it.category, it.scope, it.items) } }
    private fun addSkillProvider(u: User, n: String, rate: String) { if (repo.providers.value.none { it.id == "me-$n" }) repo.addProvider(Provider("me-$n", ProviderType.SKILL, n, u.name, listOf(n.lowercase()), s.meX, s.meY, 0.0, u.up, u.down, Scope.LOCAL, u.bio.ifBlank { "New on Bucks." }, rate = rate.ifBlank { "On request" })) }
    private fun addBusinessProvider(name: String, cat: String, scope: Scope, items: List<Item>, replace: Boolean = false) { val pid = "biz-me-${name.lowercase()}"
        if (replace || repo.providers.value.none { it.id == pid }) repo.addProvider(Provider(pid, ProviderType.BUSINESS, cat, name, listOf(cat.lowercase()) + items.flatMap { it.name.lowercase().split(" ") }.filter { it.isNotBlank() }, s.meX, s.meY, 0.0, 0, 0, scope, "New business on Bucks.", items)) }
    private fun safeId() = runCatching { Identity.userId() }.getOrDefault("local-" + repo.deviceId())
    private fun sign(payload: String) = runCatching { Identity.sign(payload) }.getOrDefault("")
    val s get() = _s.value
    fun toast(t: String) { _toasts.trySend(t) }
    private fun navTo(route: String) { _nav.trySend(route) }
    private fun persist() { s.user?.let { repo.saveSession(Session(it, s.pro, s.businesses)) } }
    val isLoggedIn get() = s.user != null

    // ---------- auth & verification ----------
    /** [p]: the full international number (+919876543210) from the phone screen. */
    fun setPhone(p: String) = _s.update { it.copy(tempPhone = p, tempEmail = "") }
    /** Firebase texts a real 6-digit code. Some phones verify on their own, which calls [onSignedIn] with no code typed. */
    fun sendOtp(activity: Activity, resend: Boolean = false, onSignedIn: () -> Unit) {
        if (!cloud) return
        otpStatus.value = Str.get(R.string.g8_otp_sending)
        Cloud.sendCode(activity, s.tempPhone, resend, onSent = { otpStatus.value = "" },
            onSignedIn = { otpStatus.value = ""; onPhoneVerified(); onSignedIn() },
            onError = { otpStatus.value = Str.get(R.string.g8_otp_send_failed, it.toString()) },
            onRetry = { otpStatus.value = Str.get(R.string.g8_otp_sending) })
        // Firebase sometimes never answers (a reCAPTCHA page that didn't open or return): say so instead of waiting silently.
        val asked = otpStatus.value
        viewModelScope.launch { kotlinx.coroutines.delay(30_000); if (otpStatus.value == asked) otpStatus.value = Str.get(R.string.g8_otp_no_code) }
    }
    /** What the phone sign-in is doing right now, shown under the code box so a tester can report it. */
    val otpStatus = kotlinx.coroutines.flow.MutableStateFlow("")
    /** Without Firebase (demo build) the code is 1234, and only in debug builds. */
    fun verifyOtp(code: String, onResult: (Boolean) -> Unit) {
        if (cloud) { otpStatus.value = ""
            Cloud.verifyCode(code, { otpStatus.value = ""; onPhoneVerified(); onResult(true) }, { otpStatus.value = Str.get(R.string.g8_otp_wrong); onResult(false) }); return }
        if (!BuildConfig.DEBUG) { toast("Sign-in isn't set up in this build."); onResult(false); return }
        if (code != "1234") { toast("Wrong code. Try 1234."); onResult(false); return }
        onPhoneVerified(); onResult(true)
    }
    private fun onPhoneVerified() {
        // Same number as the profile saved on this device: restore it instead of starting a new one.
        repo.savedSession()?.takeIf { it.user.phone == s.tempPhone && s.user == null }?.let { se -> _s.update { it.copy(user = se.user.copy(id = se.user.id.ifBlank { safeId() }), pro = se.pro, businesses = se.businesses) }; publishOwnListings() }
        _s.update { it.copy(user = it.user?.copy(phone = it.tempPhone.ifBlank { it.user.phone }, verified = it.user.verified + VerificationLevel.PHONE)) }; persist()
        if (dispatch.enabled) dispatch.startDriversFeed()
        if (Backend.enabled) { social.signedIn(s.user?.name ?: "", s.tempPhone.ifBlank { s.user?.phone ?: "" }); dispatch.resume() } }
    /** Quietly sets where I'm based from my first location fix (onboarding no longer asks for an area). */
    fun setHomeArea(area: String, at: LatLng) { val u = s.user ?: return
        _s.update { it.copy(user = u.copy(area = area)) }; persist(); social.profileSaved(u.name, area, u.bio, at) }
    /** Onboarding's last step: a line about me and my gender. Name, area and home stay as they are. */
    fun saveAbout(bio: String, gender: String) { val u = s.user ?: return
        _s.update { it.copy(user = u.copy(bio = bio, gender = gender)) }; persist(); social.profileSaved(u.name, u.area, bio); if (gender.isNotBlank()) social.genderSaved(gender) }
    /** [home]: the place chosen as where I'm based (null keeps the saved one). */
    fun createProfile(name: String, area: String, bio: String, gender: String = "", interests: List<String> = emptyList(), home: LatLng? = null) {
        val base = s.user ?: User(name, area, bio, s.tempPhone, email = s.tempEmail, id = safeId(), verified = if (s.tempPhone.isNotBlank()) setOf(VerificationLevel.PHONE) else emptySet())
        val dev = deviceLooksGenuine()
        _s.update { it.copy(user = base.copy(name = name, area = area, bio = bio, gender = gender, interests = interests, verified = if (dev) base.verified + VerificationLevel.DEVICE else base.verified)) }; persist(); toast(Str.get(R.string.g8_welcome, name.substringBefore(' '))); social.profileSaved(name, area, bio, home)
    }
    /** Basic genuineness heuristic until Play Integrity is wired (needs a Play Console project). */
    private fun deviceLooksGenuine() = !(Build.TAGS?.contains("test-keys") == true || Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("Emulator"))
    fun grantVerification(level: VerificationLevel) { _s.update { it.copy(user = it.user?.copy(verified = it.user.verified + level)) }; persist(); toast(Str.get(R.string.g8_verification_added, level.label)) }
    fun signUpEmail(email: String, password: String, confirm: String): Boolean {
        val e = email.trim().lowercase()
        if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(e)) { toast(Str.get(R.string.g8_email_invalid)); return false }
        if (password.length < 8) { toast(Str.get(R.string.g8_password_short)); return false }
        if (password != confirm) { toast(Str.get(R.string.g8_password_mismatch)); return false }
        if (repo.hasCredentials(e)) { toast(Str.get(R.string.g8_email_taken)); return false }
        repo.saveCredentials(e, password); _s.update { it.copy(tempEmail = e) }; return true
    }
    fun signInEmail(email: String, password: String): Boolean {
        val e = email.trim().lowercase()
        if (!repo.checkCredentials(e, password)) { toast(Str.get(R.string.g8_signin_wrong)); return false }
        val saved = repo.savedSession()
        if (saved != null && saved.user.email == e) { _s.update { it.copy(user = saved.user.copy(id = saved.user.id.ifBlank { safeId() }), pro = saved.pro, businesses = saved.businesses) }; publishOwnListings(); return true }
        _s.update { it.copy(tempEmail = e) }; return true
    }
    fun logout() { if (s.online) setOnline(false); val off = dispatch.signedOut(); social.signedOut(); safety.signedOut(); jobs.signedOut(); signedOutCloud(); repo.clearSession(); _s.value = freshState()
        // Take presence off and remove this phone from my profile while the Firebase user can still sign those requests, then sign out (each gives up after a few seconds offline).
        viewModelScope.launch { try { withTimeoutOrNull(4_000) { off?.join() }; Push.unregister() } finally { Cloud.signOut() } } }
    fun deleteAccount() {
        // Old session: delete nothing yet; a fresh sign-in lets both the server data and the sign-in go in one step.
        if (Cloud.needsFreshSignIn()) { toast(Str.get(R.string.g8_delete_reauth)); logout(); return }
        val meId = social.me?.id; autoRingJob?.cancel(); if (s.online) setOnline(false); dispatch.signedOut(); social.signedOut(); safety.signedOut(); jobs.signedOut(); signedOutCloud()
        // Server first, while the Firebase user still exists to sign the request: this phone's push token, then presence, open tasks,
        // phone, UPI link and profile (delete_my_account). Only then the Firebase user; if the server part failed, keep it so deleting again works.
        viewModelScope.launch {
            Push.unregister()
            // Private documents (listing and vehicle papers) live only in my storage folder; remove them before the rows go.
            if (Backend.enabled && meId != null) runCatching { Backend.deleteMyDocFiles(meId) }
            val serverOk = !Backend.enabled || runCatching { Backend.deleteMyAccount() }.isSuccess
            if (!serverOk) { Cloud.signOut(); toast(Str.get(R.string.g8_delete_server_failed)); return@launch }
            // Success is only announced once both the server data and the Firebase sign-in are gone.
            Cloud.deleteAccount { ok -> if (ok) toast(Str.get(R.string.g8_delete_done))
                else { Cloud.signOut(); toast(Str.get(R.string.g8_delete_partial)) } }
        }
        repo.deleteAccount(); _s.value = freshState() }
    /** Cart, orders, search results, listing syncs and my listings/vehicles belong to the person who signed out, not the next account on this phone. */
    private fun signedOutCloud() { commerce.signedOut(); discover.signedOut(); myListings.signedOut(); services.signedOut() }
    fun switchRole(role: Role) = _s.update { it.copy(role = role, online = false) }
    /** [plate]: in cloud builds, which of my checked vehicles to go online with (null = the first ACTIVE one). */
    fun setOnline(v: Boolean, plate: String? = null) { if (v && s.mockLocation) { toast(Str.get(R.string.g8_mock_go_online)); return }; _s.update { it.copy(online = v) }
        autoRingJob?.cancel()
        if (dispatch.enabled) {
            // Presence on the server; if it can't be published (no checked cloud vehicle yet, offline) we stay offline.
            dispatch.setOnline(v, plate ?: cloudVehicle?.plate) { ok -> if (ok) toast(if (v) Str.get(R.string.g8_online_requests) else Str.get(R.string.g8_offline)) else if (v) _s.update { it.copy(online = false) } }
            return }
        toast(if (v) Str.get(R.string.g8_online_ride_requests) else Str.get(R.string.g8_offline))
        // Demo dispatch: while a vehicle is online and idle, a nearby customer rings now and then.
        if (v && demoTools) autoRingJob = viewModelScope.launch { delay(8000); while (s.vehicleOnline) { if (s.driverRide == null && s.ride == null) simulateRing(); delay(60000) } } }

    // ---------- location ----------
    private var lastFixAt = 0L
    fun onLocation(p: LatLng, mocked: Boolean) { social.here = p; social.hereKnown = true; lastFixAt = SystemClock.elapsedRealtime(); val wasMocked = s.mockLocation; val (x, y) = Geo.toPercent(p); _s.update { it.copy(me = p, meX = x, meY = y, locationGranted = true, mockLocation = mocked) }; repo.updateDistances(p); if (mocked && !wasMocked) toast(Str.get(R.string.g8_mock_on))
        if (dispatch.enabled) dispatch.driverMoved(p)
        // Name the pick-up point from the map, again only after moving ~250 m (the lookup service is shared and free).
        // The old name is dropped at once: after 250 m it no longer describes where I am.
        if (labelledAt?.let { Geo.distanceKm(it, p) > 0.25 } != false) { labelledAt = p; _s.update { it.copy(hereLabel = null) }
            viewModelScope.launch { MapServices.label(p)?.let { l -> if (labelledAt == p) _s.update { it.copy(hereLabel = l) } } } } }
    /** A fix taken now, for booking. False when there is none (no permission, location switched off, no answer in time); a fix under 90 s old still counts. */
    suspend fun refreshLocation(ctx: Context): Boolean {
        Here.fresh(ctx)?.let { onLocation(it.at, it.mocked); return true }
        return s.me != null && SystemClock.elapsedRealtime() - lastFixAt < 90_000
    }
    private var labelledAt: LatLng? = null
    fun onLocationDenied() = _s.update { it.copy(locationGranted = false) }
    val mePos: LatLng get() = s.me ?: Geo.fromPercent(s.meX, s.meY)

    // ---------- search / ask (intent router) ----------
    fun setQuery(q: String) = _s.update { it.copy(query = q, askMode = AskMode.RESULTS) }
    fun setSort(m: SortMode) = _s.update { it.copy(sort = m) }
    fun setScope(f: ScopeFilter) = _s.update { it.copy(scope = f) }
    fun setLens(l: Lens) = _s.update { it.copy(lens = l) }
    fun setVoiceLang(l: String) = _s.update { it.copy(voiceLang = l) }
    /** Trust as seen through the current lens. ALL uses the aggregate; other lenses count only matching vote records. */
    fun trustFor(p: Provider): Trust = when (s.lens) {
        Lens.ALL -> p.trust
        Lens.FOLLOWING, Lens.VERIFIED -> { val v = reviewsFor(p); Trust(v.count { it.vote > 0 }, v.count { it.vote < 0 }) }
    }
    /** Voter ids of the people I follow; the FOLLOWING lens counts only reviews carrying one of these. */
    private fun followedVoterIds(): Set<String> = repo.people.value.filter { it.following }.map { "u-" + it.name.lowercase().replace(" ", "-") }.toSet()
    /** Reviews as seen through the current lens — the same records trustFor counts, so the badge and the list always agree. */
    fun reviewsFor(p: Provider): List<Comment> = when (s.lens) { Lens.ALL -> p.comments; Lens.FOLLOWING -> followedVoterIds().let { ids -> p.comments.filter { it.voterId in ids } }; Lens.VERIFIED -> p.comments.filter { it.verified } }
    fun sorted(list: List<Provider>): List<Provider> = when (s.sort) {
        SortMode.TRUST -> list.sortedWith(compareByDescending<Provider> { trustFor(it).pct ?: -1 }.thenByDescending { trustFor(it).total })
        SortMode.NEAR -> list.sortedBy { it.distanceKm }
        SortMode.PRICE -> list.sortedBy { it.minPrice }
    }
    fun results(): List<Provider> = sorted(repo.search(s.query)).filter { (s.scope == ScopeFilter.ALL || it.scope.name == s.scope.name) && isOpen(it) }
    /** Your own listings only show up (and take requests) while they're online. */
    private fun isOpen(p: Provider): Boolean = when {
        p.id.startsWith("me-") -> s.pro?.skillListings?.firstOrNull { "me-${it.name}" == p.id }?.online ?: false
        p.id.startsWith("biz-me-") -> s.businesses.firstOrNull { "biz-me-${it.name.lowercase()}" == p.id }?.online ?: false
        else -> true }
    fun toggleSavedPlace(name: String) = _s.update { it.copy(savedPlaces = if (name in it.savedPlaces) it.savedPlaces - name else it.savedPlaces + name) }
    /** A point dropped on the map: named from the map's address data once it answers ("Pinned location" until then). */
    fun chooseDestAt(p: LatLng) { chooseDestPlace(Str.get(R.string.g8_pinned_location), p)
        viewModelScope.launch { MapServices.label(p)?.let { l -> _s.update { u -> if (u.rideDest?.at == p) u.copy(rideDest = u.rideDest.copy(name = l)) else u } } } }
    /** A searched place (MapServices.search) or a pinned point. The distance is straight-line until the road route arrives ([setDestKm]). */
    fun chooseDestPlace(name: String, p: LatLng) { val (x, y) = Geo.toPercent(p); _s.update { it.copy(rideDest = Place(name, x, y, (Geo.distanceKm(mePos, p) * 10).roundToInt() / 10.0, at = p)) } }
    /** The road distance for the chosen destination, so the fare follows the roads rather than a straight line. */
    fun setDestKm(km: Double) { if (km > 0) _s.update { u -> u.rideDest?.let { d -> if (d.km != km) u.copy(rideDest = d.copy(km = km)) else u } ?: u } }
    fun isAgentQuery(q: String): Boolean { val l = q.lowercase(); return Regex("\\b(bike|scooter|taxi|cab|auto|ride|car|compare|cheapest|best|sort|my orders|my rides|history|post a request|go online|become|provider|pro profile|yes|confirm|cancel|show the map|book|take me|drop me)\\b").containsMatchIn(l) }

    /** Every typed or spoken command enters here. */
    fun submitQuery(raw: String) {
        val q = raw.trim(); if (q.isEmpty()) return
        if (!isAgentQuery(q) && s.pending == null) { _s.update { it.copy(query = q, askMode = AskMode.RESULTS) }; return }
        _s.update { it.copy(query = "", askMode = AskMode.CHAT, thinking = true, agent = (it.agent + AgentMessage(true, q)).takeLast(14)) }
        viewModelScope.launch {
            val ctx = "user area=${s.user?.area}; pending=${s.pending?.title ?: "none"}; online riders=${repo.drivers.value.count { it.online }}"
            val intent = router.parse(q, ctx)
            val reply = execute(intent, q)
            _s.update { it.copy(thinking = false, agent = (it.agent + reply.first).takeLast(14)) }
            reply.second?.let { then -> delay(700); then() }
        }
    }
    fun agentSend(text: String) = submitQuery(text)

    private fun execute(i: ParsedIntent, raw: String): Pair<AgentMessage, (() -> Unit)?> {
        val onlineFor = { k: VehicleKind -> Geo.ring(mePos, repo.drivers.value, k).size }
        val via = if (i.source == "gemini") Str.get(R.string.g8_agent_via_cloud) else ""
        return when (i.tool) {
            Tools.CONFIRM -> { val p = s.pending; when { p == null -> AgentMessage(false, Str.get(R.string.g8_agent_nothing_pending)) to null; p.needsBiometric -> AgentMessage(false, Str.get(R.string.g8_agent_needs_biometric)) to null; else -> AgentMessage(false, Str.get(R.string.g8_agent_confirmed, p.title)) to { confirmPending(p) } } }
            Tools.CANCEL -> { cancelPending(); AgentMessage(false, Str.get(R.string.g8_agent_cancelled)) to null }
            Tools.SHOW_MAP -> { s.pendingDest?.let { d -> _s.update { it.copy(pendingDest = null, rideDest = randomPlace(d)) } }; AgentMessage(false, Str.get(R.string.g8_agent_opening_ride)) to { navTo(Routes.CHOOSE_RIDE) } }
            Tools.RIDE -> {
                val k = runCatching { VehicleKind.valueOf(i.args["vehicle"] ?: "AUTO") }.getOrDefault(VehicleKind.AUTO).takeIf { it.carriesPassengers } ?: VehicleKind.AUTO
                val dest = i.args["destination"]?.takeIf { it.isNotBlank() }?.let { d -> Seed.PLACES.firstOrNull { it.equals(d, true) || it.lowercase().contains(d.lowercase().substringBefore(' ')) } }
                _s.update { it.copy(rideKind = k) }
                if (s.mockLocation) return AgentMessage(false, Str.get(R.string.g8_agent_mock_on)) to null
                val n = onlineFor(k)
                if (dest != null) { val place = randomPlace(dest); _s.update { it.copy(rideDest = place) }; proposeRide(place, k)
                    AgentMessage(false, Str.plural(R.plurals.g8_agent_ride_offer, n, n, k.label.lowercase(), k.label, dest, Money.format(fare(k, place.km))) + via, actions = listOf("Yes, ring them", "Show the map first", "Cancel")) to null }
                else AgentMessage(false, Str.plural(R.plurals.g8_agent_where_to, n, n, k.label.lowercase()), actions = Seed.PLACES.take(3).map { "${k.label} to ${it.substringBefore(',')}" }) to null
            }
            Tools.COMPARE -> { val res = sorted(repo.search(i.args["query"] ?: raw)); if (res.isEmpty()) return AgentMessage(false, Str.get(R.string.g8_agent_none_found)) to null
                AgentMessage(false, Str.get(R.string.g8_agent_ranked, s.lens.label.lowercase()) + via, cards = res.take(4).map { p -> AgentCard(p.name, Str.get(R.string.g8_agent_card_compare, (trustFor(p).pct ?: "—").toString(), p.distanceKm.toString(), if (p.items.isNotEmpty()) Str.get(R.string.g8_from_price, Money.format(p.minPrice)) else p.rate.orEmpty()), Str.get(R.string.g8_open), AgentAction.OpenProvider(p.id)) }) to null }
            Tools.SORT -> { val m = runCatching { SortMode.valueOf(i.args["by"] ?: "TRUST") }.getOrDefault(SortMode.TRUST); _s.update { it.copy(sort = m) }; AgentMessage(false, Str.get(R.string.g8_agent_sorted, m.label.lowercase())) to null }
            Tools.ACTIVITY -> AgentMessage(false, Str.get(R.string.g8_agent_activity, s.orders.size, s.requests.size, s.rides.size)) to { navTo(Routes.ACTIVITY) }
            Tools.POST_REQUEST -> { val what = i.args["what"]?.ifBlank { null } ?: raw; repo.addPost(Post("f${System.currentTimeMillis()}", s.user?.name ?: "You", "now", Str.get(R.string.g8_agent_post_looking, what, s.user?.area.orEmpty()), up = 0, down = 0)); AgentMessage(false, Str.get(R.string.g8_agent_posted)) to { navTo(Routes.FEED) } }
            // Cloud: dispatch finds my checked vehicle on the server and says why when there is none.
            Tools.GO_ONLINE -> if (dispatch.enabled) { _s.update { it.copy(role = Role.PROVIDER) }; setOnline(true); AgentMessage(false, Str.get(R.string.g8_agent_going_online)) to { navTo(Routes.HOME) } }
                else if (s.pro?.vehicle != null) { _s.update { it.copy(role = Role.PROVIDER) }; setOnline(true); AgentMessage(false, Str.get(R.string.g8_agent_online)) to { navTo(Routes.HOME) } } else AgentMessage(false, Str.get(R.string.g8_agent_need_vehicle)) to { navTo(Routes.PRO_CREATE) }
            Tools.BECOME_PRO -> AgentMessage(false, Str.get(R.string.g8_agent_become_pro)) to { navTo(Routes.PRO_CREATE) }
            Tools.SEARCH -> { val q = i.args["query"]?.ifBlank { null } ?: raw; val res = sorted(repo.search(q))
                if (res.isEmpty()) AgentMessage(false, Str.get(R.string.g8_agent_no_one_offers, q), actions = listOf("Post a request for $q")) to null
                else AgentMessage(false, Str.get(R.string.g8_agent_recommended) + via, cards = res.take(3).map { p -> AgentCard(p.name, Str.plural(R.plurals.g8_agent_card_search, trustFor(p).total, (trustFor(p).pct ?: "—").toString(), trustFor(p).total, p.distanceKm.toString()), if (p.type == ProviderType.BUSINESS) Str.get(R.string.g8_order) else Str.get(R.string.g8_request), if (p.type == ProviderType.BUSINESS) AgentAction.OpenProvider(p.id, "items") else AgentAction.Request(p.id)) }) to null }
            else -> AgentMessage(false, if (cloudEnabled) Str.get(R.string.g8_agent_not_understood) else Str.get(R.string.g8_agent_not_understood_demo), actions = listOf("Auto to MG Road", "Order sugar", "Find a doctor", "Compare biriyani", "Show my orders")) to null
        }
    }

    // ---------- confirmation gate (every money-moving action passes here) ----------
    private fun propose(p: PendingAction) = _s.update { it.copy(pending = p) }
    fun cancelPending() = _s.update { it.copy(pending = null) }
    /** Called by the UI after the user tapped Confirm and (when required) passed BiometricPrompt. */
    fun confirmPending(expected: PendingAction) { val p = s.pending ?: return; if (p !== expected) return; _s.update { it.copy(pending = null) }; p.run() }
    private fun firstTimeWith(counterparty: String) = s.orders.none { it.providerName == counterparty } && s.requests.none { it.providerName == counterparty }
    private fun proposeRide(place: Place, k: VehicleKind) { val f = fare(k, place.km); propose(PendingAction(Str.get(R.string.g8_book_vehicle, k.label.lowercase()), Str.get(R.string.g8_ride_summary, s.ridePickup?.name ?: s.hereLabel ?: Str.get(R.string.g8_current_location), place.name, place.km.toString(), Money.format(f)), f, Str.get(R.string.g8_nearest_rider), null, needsBiometric = false) { doRequestRide() }) }
    /** Why this trip can't be booked (a fake-location app is on, or - online - the distance is outside what the server takes); null when it can. */
    fun bookingProblem(d: Place): String? = when {
        s.mockLocation -> Str.get(R.string.g8_mock_book)
        dispatch.enabled && d.km < MIN_TRIP_KM -> Str.get(R.string.g8_trip_too_close)
        dispatch.enabled && d.km > MAX_TRIP_KM -> Str.get(R.string.g8_trip_too_far, MAX_TRIP_KM.toInt())
        else -> null }
    fun requestRide() { val d = s.rideDest ?: return; bookingProblem(d)?.let { toast(it); return }; proposeRide(d, s.rideKind) }
    fun placeOrder(): Boolean { val cl = cartLines(); val p = cl.first ?: return false; val total = cl.third
        propose(PendingAction(Str.get(R.string.g8_place_order_with, p.name), Str.get(R.string.g8_order_summary, cl.second.joinToString(", ") { "${it.first} × ${it.third}" }, Money.format(total)), total, p.name, p.trust, needsBiometric = total >= 500 || firstTimeWith(p.name)) { doPlaceOrder() }); return true }

    // ---------- providers, cart, orders, requests ----------
    fun provider(id: String) = repo.providers.value.firstOrNull { it.id == id }
    fun canVote(pid: String) = s.orders.any { it.providerId == pid && it.status == OrderStatus.DELIVERED } || s.requests.any { it.providerId == pid && it.status == RequestStatus.COMPLETED }
    fun vote(pid: String, up: Boolean, comment: String): Boolean {
        if (s.myVotes.containsKey(pid)) { toast(Str.get(R.string.g8_already_reviewed)); return false }
        if (comment.isBlank()) { toast(Str.get(R.string.g8_review_need_reason)); return false }
        val txn = s.orders.firstOrNull { it.providerId == pid && it.status == OrderStatus.DELIVERED }?.id ?: s.requests.firstOrNull { it.providerId == pid && it.status == RequestStatus.COMPLETED }?.id ?: ""
        val u = s.user; val at = System.currentTimeMillis()
        repo.voteProvider(pid, up, u?.name ?: "You", comment, u?.id ?: "", VerificationLevel.DOCUMENT in (u?.verified ?: emptySet()), txn, sign(Identity.txnPayload("vote", txn, u?.id ?: "", pid, if (up) 1 else -1, at)))
        _s.update { it.copy(myVotes = it.myVotes + (pid to if (up) 1 else -1)) }; toast(Str.get(R.string.g8_review_saved)); return true
    }
    fun cartAdd(pid: String, index: Int, delta: Int) = _s.update { st -> val key = "$pid:$index"; val next = max(0, (st.cart[key] ?: 0) + delta); val cleaned = st.cart.filterKeys { it.startsWith("$pid:") }.toMutableMap(); if (next == 0) cleaned.remove(key) else cleaned[key] = next; st.copy(cart = cleaned) }
    fun cartLines(): Triple<Provider?, List<Triple<String, Int, Int>>, Int> {
        val pid = s.cart.keys.firstOrNull()?.substringBefore(':') ?: return Triple(null, emptyList(), 0)
        val p = provider(pid) ?: return Triple(null, emptyList(), 0)
        val lines = s.cart.map { (k, q) -> val it = p.items[k.substringAfter(':').toInt()]; Triple(it.name, it.price, q) }
        val fee = if (p.scope == Scope.LOCAL && p.distanceKm <= 3) 0 else 30
        return Triple(p, lines, lines.sumOf { it.second * it.third } + fee)
    }
    private fun doPlaceOrder() {
        val cl = cartLines(); val p = cl.first ?: return; val lines = cl.second; val total = cl.third
        val id = "o${System.currentTimeMillis()}"; val at = System.currentTimeMillis()
        val o = Order(id, p.id, p.name, total, lines.map { "${it.first} × ${it.third}" }, OrderStatus.REQUESTED, sign(Identity.txnPayload("order", id, s.user?.id ?: "", p.id, total, at)))
        _s.update { it.copy(orders = listOf(o) + it.orders, cart = emptyMap()) }; navTo(Routes.order(id))
        viewModelScope.launch { for (st in OrderStatus.entries.drop(1)) { delay(2600); _s.update { u -> u.copy(orders = u.orders.map { if (it.id == o.id) it.copy(status = st) else it }) } }; toast(Str.get(R.string.g8_delivered_review, p.name)) }
    }
    fun sendRequest(pid: String, text: String): String {
        val p = provider(pid)!!; val id = "r${System.currentTimeMillis()}"
        val r = ServiceRequest(id, p.id, p.name, p.category, text.ifBlank { Str.get(R.string.g8_service_request) }, RequestStatus.SENT, sign(Identity.txnPayload("request", id, s.user?.id ?: "", p.id, 0, System.currentTimeMillis())))
        _s.update { it.copy(requests = listOf(r) + it.requests) }
        viewModelScope.launch { delay(2500); setRequestStatus(r.id, RequestStatus.ACCEPTED); toast(Str.get(R.string.g8_request_accepted, p.name)); val cid = repo.openChat(p.name, p.category); repo.sendMessage(cid, "Got your request: \"${r.text}\". I'll be there.", false) }
        return r.id
    }
    fun setRequestStatus(id: String, st: RequestStatus) { _s.update { u -> u.copy(requests = u.requests.map { if (it.id == id) it.copy(status = st) else it }) }; if (st == RequestStatus.COMPLETED) toast(Str.get(R.string.g8_job_done)) }

    // ---------- ride (customer) ----------
    private fun randomPlace(name: String): Place { val ll = Geo.PLACES[name]; return if (ll != null) { val (x, y) = Geo.toPercent(ll); Place(name, x, y, (Geo.distanceKm(mePos, ll) * 10).roundToInt() / 10.0, at = ll) } else Place(name, 20 + Random.nextFloat() * 60, 15 + Random.nextFloat() * 30, ((1.5 + Random.nextDouble() * 7) * 10).roundToInt() / 10.0) }
    fun startRide() = _s.update { it.copy(rideDest = null, ridePickup = null, pending = null) }
    /** Where the rider will be picked up: the point the customer chose, else where they are. */
    val pickupAt: LatLng get() = s.ridePickup?.at ?: mePos
    fun setPickup(name: String, p: LatLng) { val (x, y) = Geo.toPercent(p); _s.update { it.copy(ridePickup = Place(name, x, y, 0.0, at = p)) } }
    fun resetPickup() = _s.update { it.copy(ridePickup = null) }
    /** Opens the in-app map on a place; [autoStart] begins turn-by-turn as soon as the route is ready (the driver's Navigate button). */
    fun openMapsTo(name: String, at: LatLng, autoStart: Boolean = false) { com.bucks.app.ui.screens.MapsPick.place = MapServices.PlaceHit(name, "", at); com.bucks.app.ui.screens.MapsPick.autoStart = autoStart; navTo(Routes.MAPS) }
    fun chooseDest(name: String) = _s.update { it.copy(rideDest = randomPlace(name)) }
    fun setRideKind(k: VehicleKind) { if (k.carriesPassengers) _s.update { it.copy(rideKind = k) } }
    fun fare(k: VehicleKind, km: Double) = (k.farePerKm * km + 20).roundToInt()
    fun onlineCount(k: VehicleKind) = Geo.ring(pickupAt, repo.drivers.value, k).size
    private fun doRequestRide() {
        val d0 = s.rideDest ?: return; bookingProblem(d0)?.let { toast(it); return }
        if (dispatch.enabled) { val dest = d0
            // A pick-up the rider moved on the map wins; otherwise it is where the phone is now.
            val me = s.ridePickup?.at ?: s.me ?: run { toast(Str.get(R.string.g8_need_location_ride)); return }
            // The real point the rider chose; x/y are clamped to the drawn map, so a pick beyond its edge would move the drop.
            val to = dest.at ?: Geo.PLACES[dest.name] ?: Geo.fromPercent(dest.x, dest.y)
            dispatch.requestRide(s.rideKind, me, s.ridePickup?.name ?: s.hereLabel ?: Str.get(R.string.g8_current_location), dest, to, fare(s.rideKind, dest.km)); return }
        if (!demoTools) { toast(Str.get(R.string.g8_rides_need_online)); return }
        val dest = d0; val k = s.rideKind; val id = "ride${System.currentTimeMillis()}"; val f = fare(k, dest.km)
        val ride = Ride(id, k, dest, f, RideStatus.SEARCHING, (1000 + Random.nextInt(9000)).toString(), signature = sign(Identity.txnPayload("ride", id, s.user?.id ?: "", "", f, System.currentTimeMillis())), pickupLabel = s.ridePickup?.name ?: s.user?.area.orEmpty())
        _s.update { it.copy(ride = ride) }; navTo(Routes.SEARCHING)
        ringJob?.cancel(); ringJob = viewModelScope.launch {
            delay(4500); val cand = Geo.ring(mePos, repo.drivers.value, k).firstOrNull()
            if (cand != null) acceptRide(cand.id) else { delay(15000); _s.update { if (it.ride?.status == RideStatus.SEARCHING) it.copy(ride = it.ride.copy(status = RideStatus.NO_DRIVER)) else it } }
        }
    }
    fun acceptRide(driverId: String) {
        ringJob?.cancel(); val d = repo.drivers.value.first { it.id == driverId }
        _s.update { it.copy(ride = it.ride?.copy(driver = d, driverX = d.x, driverY = d.y, status = RideStatus.MATCHED, etaMin = max(1, (d.distanceKm * 2.5).roundToInt()))) }
        navTo(Routes.DRIVER_FOUND)
        driveJob?.cancel(); driveJob = viewModelScope.launch {
            val steps = 6; val mx = s.meX; val my = s.meY
            for (k in 1..steps) { delay(1200); val r = s.ride ?: return@launch
                _s.update { it.copy(ride = r.copy(driverX = d.x + (mx - d.x) * k / steps, driverY = d.y + (my - d.y) * k / steps - 2, etaMin = max(0, (d.distanceKm * 2.5 * (1 - k.toDouble() / steps)).roundToInt()))) } }
            _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.ARRIVED)) }; toast(Str.get(R.string.g8_rider_here_pin, s.ride?.pin.orEmpty()))
        }
    }
    /**
     * [code] is a CancelReasons.rider code (the server keeps it; demo mode keeps its label). Cloud: the server cancels first and the screen follows
     * its answer; only then "Nothing to pay". A refusal shows the ride's real status instead. [onDone] gets false when it was refused and the ride stays.
     */
    fun cancelRide(code: String?, note: String = "", onDone: (Boolean) -> Unit = {}) { val r = s.ride ?: run { onDone(true); return }
        if (r.status !in setOf(RideStatus.SEARCHING, RideStatus.NO_DRIVER, RideStatus.MATCHED, RideStatus.ARRIVED)) { toast(Str.get(R.string.g8_trip_started_no_cancel)); onDone(false); return }
        val label = CancelReasons.rider.firstOrNull { it.first == code }?.second ?: Str.get(R.string.g8_cancelled_by_rider)
        fun cancelled() { _s.update { it.copy(rides = listOf(r.copy(status = RideStatus.CANCELLED, reason = label)) + it.rides) }; toast(Str.get(R.string.g8_ride_cancelled_free)); navTo(Routes.HOME); onDone(true) }
        if (dispatch.enabled) { dispatch.cancelRide(code, note) { err -> if (err == null) cancelled() else { toast(err); onDone(false) } }; return }
        ringJob?.cancel(); driveJob?.cancel(); _s.update { it.copy(ride = null) }; cancelled() }
    /** Back out of a request nobody took: forget it so the screens and the driver ring are free again. */
    fun dismissEndedRide() { if (dispatch.enabled) dispatch.dismissEndedRide() else _s.update { if (it.ride?.status == RideStatus.NO_DRIVER) it.copy(ride = null) else it } }
    fun startTrip() {
        if (dispatch.enabled) return  // the driver starts the trip after checking the PIN
        _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.IN_RIDE)) }; navTo(Routes.IN_RIDE)
        driveJob?.cancel(); driveJob = viewModelScope.launch { val mx = s.meX; val my = s.meY
            for (k in 1..5) { delay(1300); val r = s.ride ?: return@launch; _s.update { it.copy(ride = r.copy(progress = k / 5f, driverX = mx + (r.dest.x - mx) * k / 5, driverY = my + (r.dest.y - my) * k / 5)) } }
            _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.COMPLETED)) }; navTo(Routes.PAY) }
    }
    /** The rider confirms payment. With cloud dispatch the server records it and the rating screen follows once it's saved. */
    fun payRide(method: String) { if (dispatch.enabled) { dispatch.payRide(method); return }; _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.PAID, paidWith = method)) }; navTo(Routes.RATE_RIDE) }
    fun finishRide(vote: Int?, comment: String, skip: Boolean, reason: String? = null): Boolean {
        val r = s.ride ?: return true
        if (!skip) {
            if (vote == null) { toast(Str.get(R.string.g8_tap_arrow)); return false }
            if (vote < 0 && reason == null) { toast(Str.get(R.string.g8_pick_what_wrong)); return false }
            r.driver?.let { repo.voteDriver(it.id, vote > 0) } }
        _s.update { it.copy(rides = listOf(r.copy(status = RideStatus.COMPLETED)) + it.rides) }
        if (dispatch.enabled) dispatch.finishRide(if (skip) null else vote, comment, reason) else _s.update { it.copy(ride = null) }
        toast(Str.get(R.string.g8_trip_saved)); navTo(Routes.HOME); return true
    }
    /** Cloud ride follow-up: navigate as the task moves along, exactly as the demo simulation does. */
    private fun onCloudRide(prev: Ride?, r: Ride?) {
        if (r == null) return
        if (prev == null || prev.id != r.id) {   // new request, or a trip restored after the app was killed
            // The destination and vehicle come back with a restored ride, so "Ring again" has something to ring.
            _s.update { it.copy(rideDest = r.dest, rideKind = r.kind) }
            rideRoute(r.status)?.let { navTo(it) }; return }
        if (r.status == prev.status) return
        when (r.status) {
            RideStatus.MATCHED -> navTo(Routes.DRIVER_FOUND)
            RideStatus.SEARCHING -> { toast(Str.get(R.string.g8_rider_cancelled_ringing)); navTo(Routes.SEARCHING) }
            RideStatus.ARRIVED -> toast(Str.get(R.string.g8_rider_here_pin, r.pin))
            RideStatus.IN_RIDE -> navTo(Routes.IN_RIDE)
            RideStatus.COMPLETED -> navTo(Routes.PAY)
            RideStatus.PAID -> navTo(Routes.RATE_RIDE)
            RideStatus.NO_DRIVER, RideStatus.CANCELLED -> {}
        }
    }
    private fun onCloudDriverRide(prev: DriverRide?, d: DriverRide?) {
        if (d == null) return
        // Accepting from whichever screen the ring card showed on: the trip lives on Home, so go there (the driver asked for it).
        if (prev != null && prev.id == d.id) { if (prev.status == DriverRideStatus.RINGING && d.status == DriverRideStatus.TO_PICKUP) navTo(Routes.HOME); return }
        // A ringing request is a card over whatever screen is showing (BucksAppUi); it never moves anyone away from a ride in progress.
        if (d.status == DriverRideStatus.RINGING) return
        // A trip restored after the app was killed: back to the trip screen, and back on duty so location keeps flowing.
        navTo(Routes.HOME)
        if (!s.online) setOnline(true)
    }

    // ---------- provider side ----------
    fun simulateRing() {
        if (!demoTools || s.driverRide != null) return
        if (!s.vehicleOnline) { toast(Str.get(R.string.g8_vehicle_online_needed)); return }
        val k = s.pro?.vehicle?.kind ?: VehicleKind.BIKE; val me = mePos
        val pickup = LatLng(me.lat + (Random.nextDouble() - 0.5) * 0.012, me.lng + (Random.nextDouble() - 0.5) * 0.012); val pickupKm = (Geo.distanceKm(me, pickup) * 10).roundToInt().coerceAtLeast(1) / 10.0
        // Prefer a drop within city range of the pick-up; trip distance and fare follow from the real points.
        val dropName = Geo.PLACES.entries.filter { Geo.distanceKm(pickup, it.value) in 1.5..15.0 }.randomOrNull()?.key ?: Seed.PLACES.random()
        val km = ((Geo.PLACES[dropName]?.let { Geo.distanceKm(pickup, it) } ?: 3.0) * 1.3 * 10).roundToInt() / 10.0  // ×1.3: road vs straight line
        val dr = DriverRide("dr${System.currentTimeMillis()}", DriverRideStatus.RINGING, listOf("Deepa N", "Arjun R", "Meera S", "Vikram J").random(), Trust(40 + Random.nextInt(200), Random.nextInt(8)), s.user?.area ?: "Jayanagar", dropName, km, fare(k, km), (1000 + Random.nextInt(9000)).toString(), 15, pickupKm,
            kind = k, driver = me, pickup = pickup, drop = Geo.PLACES[dropName] ?: Geo.fromPercent(20 + Random.nextFloat() * 60, 20 + Random.nextFloat() * 60))
        _s.update { it.copy(driverRide = dr) }; if (s.ride == null && s.pending == null) navTo(Routes.HOME)
        startRingCountdown()
    }
    private fun startRingCountdown() {
        drvRingJob?.cancel(); drvRingJob = viewModelScope.launch { while (true) { delay(1000); val cur = s.driverRide ?: return@launch; if (cur.status != DriverRideStatus.RINGING) return@launch
            if (cur.secondsLeft <= 1) { _s.update { it.copy(driverRide = null) }; toast(Str.get(R.string.g8_too_late)); return@launch }
            _s.update { it.copy(driverRide = cur.copy(secondsLeft = cur.secondsLeft - 1)) } } }
    }
    fun driverDecline() { if (dispatch.enabled) { dispatch.driverDecline(); return }; drvRingJob?.cancel(); _s.update { it.copy(driverRide = null) }; toast(Str.get(R.string.g8_passed)) }
    fun driverAccept() { if (dispatch.enabled) { dispatch.driverAccept(); return }; drvRingJob?.cancel()
        _s.update { it.copy(driverRide = it.driverRide?.copy(status = DriverRideStatus.TO_PICKUP, progress = 0f)) }; toast(Str.get(R.string.g8_its_yours)); navTo(Routes.HOME)
        animateDriver(DriverRideStatus.TO_PICKUP) { _s.update { it.copy(driverRide = it.driverRide?.copy(status = DriverRideStatus.ARRIVED)) }; toast(Str.get(R.string.g8_at_pickup)) } }
    /** Simulated drive for the current leg; replace with real location updates from DriverLocationService. */
    private fun animateDriver(leg: DriverRideStatus, onDone: () -> Unit) { drvDriveJob?.cancel(); drvDriveJob = viewModelScope.launch {
        for (k in 1..8) { delay(900); val cur = s.driverRide ?: return@launch; if (cur.status != leg) return@launch; _s.update { it.copy(driverRide = cur.copy(progress = k / 8f)) } }; onDone() } }
    /** Next step of the driver's trip. With cloud dispatch the server checks the PIN and the screen moves on when the row does. */
    fun driverNext(pin: String = ""): Boolean {
        val d = s.driverRide ?: return true
        if (dispatch.enabled) { dispatch.driverNext(pin); return true }
        when (d.status) {
            DriverRideStatus.TO_PICKUP -> { drvDriveJob?.cancel(); _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.ARRIVED)) } }
            DriverRideStatus.ARRIVED -> { if (pin != d.pin) { toast(Str.get(R.string.g8_pin_mismatch)); return false }
                _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.IN_RIDE, progress = 0f)) }
                animateDriver(DriverRideStatus.IN_RIDE) { toast(Str.get(R.string.g8_arrived_at, d.dropAt)) } }
            DriverRideStatus.IN_RIDE -> { drvDriveJob?.cancel(); _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.DONE, progress = 1f)) } }
            else -> {}
        }; return true
    }
    /** Cash or UPI collected. Counted once, and only from the payment step: a second tap finds the trip already past it. [method] is "CASH", "UPI" or "shop". */
    fun driverPaid(method: String) { val d = s.driverRide ?: return; if (d.status != DriverRideStatus.DONE) return
        if (dispatch.enabled) { if (!dispatch.driverPaid(method)) return } else _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.RATE, paidWith = method)) }
        _s.update { it.copy(earnings = it.earnings + d.fare) }
        toast(if (method == "shop") Str.get(R.string.g8_delivery_paid_by_shop, Money.format(d.fare)) else Str.get(R.string.g8_fare_received, Money.format(d.fare), payWord(method))) }
    fun setUpi(id: String) { val v = id.trim(); if (!Regex("^[\\w.\\-]{2,}@[a-zA-Z]{2,}$").matches(v)) { toast(Str.get(R.string.g8_upi_invalid)); return }; _s.update { it.copy(pro = (it.pro ?: ProProfile()).copy(upiId = v)) }; persist() }
    /** The driver's arrow on the customer. Cloud: saved on the customer's record (rate_rider). Demo: only the local counters. */
    fun driverRateCustomer(stars: Int, comment: String = "", reason: String? = null) { val up = stars >= 3
        if (dispatch.enabled) { dispatch.rateRider(if (up) 1 else -1, comment.trim(), reason); dispatch.closeTrip() }
        else { _s.update { it.copy(user = it.user?.copy(up = it.user.up + if (up) 1 else 0, down = it.user.down + if (up) 0 else 1), driverRide = null) }; persist() }
        toast(Str.get(R.string.g8_trip_closed)) }
    /** Hands the trip back; [code] is a CancelReasons.driver code. Cloud: only once the server has done it (a refusal shows where the trip really is). */
    fun driverCancel(code: String?, note: String = "", onDone: (Boolean) -> Unit = {}) {
        if (dispatch.enabled) { val ringing = s.driverRide?.status == DriverRideStatus.RINGING; dispatch.driverCancel(code, note) { ok -> if (ok && !ringing) toast(Str.get(R.string.g8_handed_back)); onDone(ok) }; return }
        _s.update { it.copy(user = it.user?.copy(down = it.user.down + 1), driverRide = null) }; persist(); toast(Str.get(R.string.g8_driver_cancel_counts)); onDone(true) }
    fun setProKind(k: ProKind) = _s.update { it.copy(proKind = k) }
    fun setProStep(n: Int) = _s.update { it.copy(proStep = n) }
    fun startPro(kind: ProKind?, step: Int) = _s.update { it.copy(proKind = kind, proStep = step, editBiz = null) }
    /** Adds or replaces (by [replacing] plate) a vehicle. It stays "In Progress" until verified; this build simulates community verification after a few seconds. */
    fun saveVehicle(kind: VehicleKind, model: String, plate: String, mode: ListingMode = ListingMode.TAXI, docs: Int = 0, replacing: String? = null) {
        val v = Vehicle(kind, model.ifBlank { kind.label }, plate.ifBlank { "KA 00 XX 0000" }.uppercase(), mode, verified = false, docs = docs)
        _s.update { st -> val p = st.pro ?: ProProfile(); st.copy(pro = p.copy(vehicles = p.vehicles.filter { it.id != replacing && it.id != v.id } + v)) }; persist(); toast(Str.get(R.string.g8_vehicle_submitted, v.model, v.plate))
        viewModelScope.launch { delay(8000); _s.update { st -> st.copy(pro = st.pro?.let { p -> p.copy(vehicles = p.vehicles.map { if (it.id == v.id) it.copy(verified = true) else it }) }) }; persist(); toast(Str.get(R.string.g8_vehicle_verified, v.model, v.plate)) }
    }
    fun setVehicleOnline(id: String, on: Boolean) {
        if (on) { _s.update { it.copy(pro = it.pro?.copy(activeVehicle = id)) }; persist(); setOnline(true) } else if (s.pro?.vehicle?.id == id) setOnline(false)
    }
    fun addSkill(name: String, replacing: String? = null) { val u = s.user ?: return; val n = name.trim(); if (n.isBlank()) return
        addSkillProvider(u, n, s.pro?.rate.orEmpty())
        _s.update { st -> val p = st.pro ?: ProProfile(); val old = p.skillListings.firstOrNull { it.name == replacing }
            st.copy(pro = p.copy(skillListings = p.skillListings.filter { it.name != replacing && it.name != n } + (old?.copy(name = n) ?: SkillListing(n)))) }; persist(); toast(if (replacing != null) Str.get(R.string.g8_skill_updated) else Str.get(R.string.g8_skill_added, n)) }
    fun setSkillOnline(name: String, on: Boolean) { _s.update { st -> st.copy(pro = st.pro?.let { p -> p.copy(skillListings = p.skillListings.map { if (it.name == name) it.copy(online = on) else it }) }) }; persist(); toast(if (on) Str.get(R.string.g8_skill_online, name) else Str.get(R.string.g8_skill_offline, name)) }
    fun setBusinessOnline(i: Int, on: Boolean) { _s.update { st -> st.copy(businesses = st.businesses.mapIndexed { j, b -> if (j == i) b.copy(online = on) else b }) }; persist(); s.businesses.getOrNull(i)?.let { toast(if (on) Str.get(R.string.g8_biz_open, it.name) else Str.get(R.string.g8_biz_closed, it.name)) } }
    fun editBusiness(i: Int?) = _s.update { it.copy(editBiz = i, proKind = ProKind.BUSINESS, proStep = 2) }
    fun saveSkills(skills: List<String>, rate: String) { val u = s.user ?: return
        skills.forEach { addSkillProvider(u, it, rate) }
        _s.update { it.copy(pro = (it.pro ?: ProProfile()).let { p -> p.copy(skillListings = p.skillListings + skills.filter { k -> k !in p.skills }.map { k -> SkillListing(k) }, rate = rate) }, proStep = 3, proMessage = Str.plural(R.plurals.g8_skills_published, skills.size)) }; persist() }
    fun saveBusiness(name: String, cat: String, scope: Scope, items: List<Item>): Boolean { val u = s.user ?: return false
        if (name.isBlank() || cat.isBlank()) { toast(Str.get(R.string.g8_biz_need_name)); return false }
        val edit = s.editBiz?.let { s.businesses.getOrNull(it) }
        val biz = Business(name, cat, scope, items, online = edit?.online ?: true, area = edit?.area?.ifBlank { null } ?: s.user?.area.orEmpty(), followers = edit?.followers ?: 0)
        edit?.takeIf { !it.name.equals(name, true) }?.let { old -> repo.removeProvider("biz-me-${old.name.lowercase()}") }
        addBusinessProvider(name, cat, scope, items, replace = true)
        _s.update { st -> st.copy(businesses = st.editBiz?.let { e -> st.businesses.mapIndexed { j, b -> if (j == e) biz else b } } ?: (st.businesses + biz), editBiz = null, proStep = 3, proMessage = Str.get(R.string.g8_biz_live, name, cat.lowercase())) }; persist(); return true }
    fun simulateIncoming() { if (!demoTools) return; val openBiz = s.businesses.firstOrNull { it.online }; val openSkill = s.pro?.skillListings?.firstOrNull { it.online }
        val inc = when { openBiz != null -> Incoming("Arjun R", "Order: ${openBiz.items.firstOrNull()?.name ?: "1 item"} × 2 for ${openBiz.name} · deliver to Jayanagar"); openSkill != null -> Incoming("Meera S", "Request: ${openSkill.name} needed today evening"); s.businesses.isNotEmpty() || !s.pro?.skills.isNullOrEmpty() -> { toast(Str.get(R.string.g8_go_online_biz)); return }; else -> { toast(Str.get(R.string.g8_add_biz_first)); navTo(Routes.PRO_CREATE); return } }
        _s.update { it.copy(incoming = listOf(inc) + it.incoming) }; toast(Str.get(R.string.g8_new_request)); navTo(Routes.LISTINGS) }
    fun acceptIncoming(i: Incoming) { _s.update { it.copy(incoming = it.incoming - i) }; toast(Str.get(R.string.g8_accepted_customer)) }

    // ---------- feed / chat / social ----------
    fun votePost(id: String, v: Int) { val prev = s.postVotes[id] ?: 0; val next = if (prev == v) 0 else v; repo.votePost(id, next, prev); _s.update { it.copy(postVotes = if (next == 0) it.postVotes - id else it.postVotes + (id to next)) } }
    fun addPost(text: String, image: String? = null, attachment: Attachment? = null) { if (text.isBlank() && image == null && attachment == null) { toast(Str.get(R.string.g8_write_first)); return }; repo.addPost(Post("f${System.currentTimeMillis()}", s.user?.name ?: "You", "now", text, hasImage = image != null, file = attachment?.name, up = 0, down = 0, image = image, attachment = attachment)); toast(Str.get(R.string.g8_posted_feed)) }
    fun addComment(postId: String, text: String) { if (text.isNotBlank()) repo.addPostComment(postId, s.user?.name ?: "You", text) }
    fun openChat(name: String, role: String): String = repo.openChat(name, role).also { repo.markRead(it) }
    fun sendChat(chatId: String, text: String) { if (text.isBlank()) return; repo.sendMessage(chatId, text, true); viewModelScope.launch { delay(1200); repo.sendMessage(chatId, listOf("Sure.", "On it.", "Give me 10 minutes.", "Yes, that works.").random(), false); repo.markRead(chatId) } }
    fun markRead(chatId: String) = repo.markRead(chatId)
    fun sendAttachment(chatId: String, a: Attachment) { repo.sendMessage(chatId, if (a.isImage) Str.get(R.string.g8_photo) else a.name, true, a) }
    fun followProvider(id: String) { val on = id !in s.followedProviders; _s.update { it.copy(followedProviders = if (on) it.followedProviders + id else it.followedProviders - id) }; toast(if (on) Str.get(R.string.g8_following_posts) else Str.get(R.string.g8_unfollowed)) }
    fun follow(id: String, f: Boolean) { repo.follow(id, f); toast(if (f) Str.get(R.string.g8_following_reviews) else Str.get(R.string.g8_unfollowed)) }
    fun join(id: String, j: Boolean) { repo.join(id, j); toast(if (j) Str.get(R.string.g8_joined) else Str.get(R.string.g8_left_community)) }
    fun toggleDriverOnline(id: String) { val d = repo.drivers.value.first { it.id == id }; repo.setDriverOnline(id, !d.online) }

    // ---------- calls ----------
    fun startCall(name: String, phone: String) = _s.update { it.copy(call = CallState(name, phone)) }
    fun toggleMute() = _s.update { it.copy(call = it.call?.copy(muted = !it.call.muted)) }
    fun toggleSpeaker() = _s.update { it.copy(call = it.call?.copy(speaker = !it.call.speaker)) }
    fun endCall() { val c = s.call ?: return; val secs = (System.currentTimeMillis() - c.startedAt) / 1000; _s.update { it.copy(call = null) }; toast(Str.get(R.string.g8_call_ended, c.name, (secs / 60).toString(), (secs % 60).toString())) }

    // ---------- devices & backup ----------
    fun syncNow() { viewModelScope.launch { _s.update { it.copy(syncStatus = SyncStatus.SYNCING) }; delay(1400); _s.update { it.copy(syncStatus = SyncStatus.SYNCED, lastSynced = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault()).format(java.util.Date())) }; toast(Str.plural(R.plurals.g8_synced_devices, s.devices.size)) } }
    fun exportSnapshot(): String = repo.exportSnapshot(s.user?.let { Session(it, s.pro, s.businesses) })
    fun importSnapshot(json: String): Boolean { val se = repo.importSnapshot(json) ?: run { toast(Str.get(R.string.g8_not_backup)); return false }; _s.update { it.copy(user = se.user.copy(id = se.user.id.ifBlank { safeId() }), pro = se.pro, businesses = se.businesses) }; publishOwnListings(); toast(Str.get(R.string.g8_restored_profile, se.user.name)); return true }
    fun linkDevice(code: String): Boolean { if (code.trim().length < 6) { toast(Str.get(R.string.g8_link_code_short)); return false }; _s.update { it.copy(devices = it.devices + LinkedDevice("dev-${code.trim().lowercase()}", Str.get(R.string.g8_device_name, code.trim().uppercase()), Str.get(R.string.g8_linked_just_now), false)) }; toast(Str.get(R.string.g8_device_linked)); return true }
    fun unlinkDevice(id: String) = _s.update { it.copy(devices = it.devices.filterNot { d -> d.id == id && !d.thisDevice }) }

    companion object {
        /** The ride screen for a status (null for a cancelled ride): where a rider goes as it moves along, and what Home's "Return" opens. */
        fun rideRoute(st: RideStatus): String? = when (st) {
            RideStatus.SEARCHING, RideStatus.NO_DRIVER -> Routes.SEARCHING
            RideStatus.MATCHED, RideStatus.ARRIVED -> Routes.DRIVER_FOUND
            RideStatus.IN_RIDE -> Routes.IN_RIDE
            RideStatus.COMPLETED -> Routes.PAY
            RideStatus.PAID -> Routes.RATE_RIDE
            RideStatus.CANCELLED -> null }
    }
    class Factory(private val repo: BucksRepository) : ViewModelProvider.Factory { @Suppress("UNCHECKED_CAST") override fun <T : ViewModel> create(modelClass: Class<T>): T = BucksViewModel(repo) as T }
}
