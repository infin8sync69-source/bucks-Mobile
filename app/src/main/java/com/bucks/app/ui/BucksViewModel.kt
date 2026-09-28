package com.bucks.app.ui

import android.app.Activity
import android.os.Build
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
enum class SortMode(val label: String) { TRUST("Most recommended"), NEAR("Nearest"), PRICE("Lowest price") }
enum class ScopeFilter(val label: String) { ALL("All"), LOCAL("Local"), GLOBAL("Global") }
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
    val rideKind: VehicleKind = VehicleKind.AUTO, val rideDest: Place? = null,
    val query: String = "", val sort: SortMode = SortMode.TRUST, val scope: ScopeFilter = ScopeFilter.ALL, val askMode: AskMode = AskMode.RESULTS, val lens: Lens = Lens.ALL,
    val agent: List<AgentMessage> = listOf(AgentMessage(false, "Tell me what you need — a ride, food, a plumber, a comparison — by typing or speaking.")),
    val thinking: Boolean = false, val voiceLang: String = "en-IN",
    val myVotes: Map<String, Int> = emptyMap(), val postVotes: Map<String, Int> = emptyMap(),
    val incoming: List<Incoming> = emptyList(), val followedProviders: Set<String> = emptySet(), val savedPlaces: Set<String> = emptySet(),
    val proKind: ProKind? = null, val proStep: Int = 1, val proMessage: String = "",
    val pendingDest: String? = null, val pending: PendingAction? = null,
    val syncStatus: SyncStatus = SyncStatus.SYNCED, val lastSynced: String = "Just now", val devices: List<LinkedDevice> = emptyList(),
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
    /** Cloud rides and deliveries on Supabase tasks (presence, ringing, PIN, payment). In demo builds the simulation below runs instead. */
    val dispatch = Dispatch(viewModelScope, social, ::toast)
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
    /** Cloud builds: the checked (ACTIVE) vehicle the online switch uses: the one online now, else the first ACTIVE one I own or drive. Null in demo builds. */
    val cloudVehicle: VehicleRow? get() = if (!dispatch.enabled) null
        else dispatch.vehicle?.takeIf { dispatch.online } ?: (if (myListings.loaded) myListings.vehicles else dispatch.vehicles).firstOrNull { it.status == "ACTIVE" }
    /** A fresh UiState for sign-out and account deletion; cloud builds keep reading the online state from dispatch. */
    private fun freshState() = UiState(dispatchOnline = if (dispatch.enabled) false else null)

    init {
        runCatching { Identity.ensureKey() }
        // With Firebase on, a saved profile only counts once the phone number is verified with Firebase too.
        repo.loadSession()?.takeIf { !cloud || Cloud.uid != null }?.let { s -> _s.update { it.copy(user = s.user.copy(id = s.user.id.ifBlank { safeId() }), pro = s.pro, businesses = s.businesses) }; publishOwnListings() }
        _s.update { it.copy(devices = listOf(LinkedDevice(repo.deviceId(), Build.MODEL ?: "This device", "Now", true))) }
        if (dispatch.enabled) { repo.replaceDrivers(emptyList(), mePos); if (s.user != null) dispatch.startDriversFeed() }
        s.user?.let { u -> if (Backend.enabled) { social.signedIn(u.name, u.phone); dispatch.resume() } }
        // Cloud dispatch is the single writer of ride / driverRide; this mirrors it into UiState and navigates on status changes.
        viewModelScope.launch { dispatch.ride.collect { r -> val prev = s.ride; if (prev == null && r == null) return@collect; _s.update { it.copy(ride = r) }; onCloudRide(prev, r) } }
        viewModelScope.launch { dispatch.driverRide.collect { d -> val prev = s.driverRide; if (prev == null && d == null) return@collect; _s.update { it.copy(driverRide = d) }; onCloudDriverRide(prev, d) } }
        viewModelScope.launch { dispatch.drivers.collect { if (dispatch.enabled) repo.replaceDrivers(it, mePos) } }
        // Cloud builds: the vehicle switch, the OnlineFab and DriverLocationService follow the server presence.
        if (dispatch.enabled) viewModelScope.launch { dispatch.onlineFlow.collect { on -> _s.update { it.copy(dispatchOnline = on) } } }
    }
    override fun onCleared() { dispatch.signedOut() }
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
    fun setPhone(p: String) = _s.update { it.copy(tempPhone = p, tempEmail = "") }
    /** Firebase texts a real 6-digit code. Some phones verify on their own, which calls [onSignedIn] with no code typed. */
    fun sendOtp(activity: Activity, resend: Boolean = false, onSignedIn: () -> Unit) {
        if (!cloud) return
        otpStatus.value = "Asking Firebase to send the code…"
        Cloud.sendCode(activity, s.tempPhone, resend, onSent = { otpStatus.value = "Code sent. Enter it below."; toast("Code sent to +91 ${s.tempPhone}") },
            onSignedIn = { otpStatus.value = "Signed in"; onPhoneVerified(); onSignedIn() },
            onError = { otpStatus.value = "Couldn't send the code: $it"; toast(it) },
            onRetry = { otpStatus.value = "App check failed; trying again as a test number…" })
        // Firebase sometimes never answers (a reCAPTCHA page that didn't open or return): say so instead of waiting silently.
        val asked = otpStatus.value
        viewModelScope.launch { kotlinx.coroutines.delay(30_000); if (otpStatus.value == asked || otpStatus.value.startsWith("App check failed"))
            otpStatus.value = "No reply from Firebase after 30 seconds. Tap Resend code, and send a screenshot of this screen." }
    }
    /** What the phone sign-in is doing right now, shown under the code box so a tester can report it. */
    val otpStatus = kotlinx.coroutines.flow.MutableStateFlow("")
    /** Without Firebase (demo build) the code is 1234, and only in debug builds. */
    fun verifyOtp(code: String, onResult: (Boolean) -> Unit) {
        if (cloud) { otpStatus.value = "Checking the code…"
            Cloud.verifyCode(code, { otpStatus.value = "Signed in"; onPhoneVerified(); onResult(true) }, { otpStatus.value = "Code not accepted: $it"; toast(it); onResult(false) }); return }
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
    fun createProfile(name: String, area: String, bio: String, gender: String = "", interests: List<String> = emptyList()) {
        val base = s.user ?: User(name, area, bio, s.tempPhone, email = s.tempEmail, id = safeId(), verified = if (s.tempPhone.isNotBlank()) setOf(VerificationLevel.PHONE) else emptySet())
        val dev = deviceLooksGenuine()
        _s.update { it.copy(user = base.copy(name = name, area = area, bio = bio, gender = gender, interests = interests, verified = if (dev) base.verified + VerificationLevel.DEVICE else base.verified)) }; persist(); toast("Welcome to Bucks, ${name.substringBefore(' ')}"); social.profileSaved(name, area, bio)
    }
    /** Basic genuineness heuristic until Play Integrity is wired (needs a Play Console project). */
    private fun deviceLooksGenuine() = !(Build.TAGS?.contains("test-keys") == true || Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("Emulator"))
    fun grantVerification(level: VerificationLevel) { _s.update { it.copy(user = it.user?.copy(verified = it.user.verified + level)) }; persist(); toast("${level.label} added to your identity") }
    fun signUpEmail(email: String, password: String, confirm: String): Boolean {
        val e = email.trim().lowercase()
        if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(e)) { toast("Enter an email like name@example.com."); return false }
        if (password.length < 8) { toast("Use at least 8 characters for your password."); return false }
        if (password != confirm) { toast("The two passwords don't match."); return false }
        if (repo.hasCredentials(e)) { toast("That email already has an account. Sign in instead."); return false }
        repo.saveCredentials(e, password); _s.update { it.copy(tempEmail = e) }; return true
    }
    fun signInEmail(email: String, password: String): Boolean {
        val e = email.trim().lowercase()
        if (!repo.checkCredentials(e, password)) { toast("That email and password don't match. Check both and try again."); return false }
        val saved = repo.savedSession()
        if (saved != null && saved.user.email == e) { _s.update { it.copy(user = saved.user.copy(id = saved.user.id.ifBlank { safeId() }), pro = saved.pro, businesses = saved.businesses) }; publishOwnListings(); return true }
        _s.update { it.copy(tempEmail = e) }; return true
    }
    fun logout() { if (s.online) setOnline(false); dispatch.signedOut(); social.signedOut(); jobs.signedOut(); signedOutCloud(); repo.clearSession(); _s.value = freshState()
        // Remove this phone from my profile while the Firebase user can still sign that request, then sign out (Push.unregister never throws and gives up after a few seconds offline).
        viewModelScope.launch { try { Push.unregister() } finally { Cloud.signOut() } } }
    fun deleteAccount() { val meId = social.me?.id; autoRingJob?.cancel(); if (s.online) setOnline(false); dispatch.signedOut(); social.signedOut(); jobs.signedOut(); signedOutCloud()
        // Server first, while the Firebase user still exists to sign the request: this phone's push token, then presence, open tasks,
        // phone, UPI link and profile (delete_my_account). Only then the Firebase user; if the server part failed, keep it so deleting again works.
        viewModelScope.launch {
            Push.unregister()
            // Private documents (listing and vehicle papers) live only in my storage folder; remove them before the rows go.
            if (Backend.enabled && meId != null) runCatching { Backend.deleteMyDocFiles(meId) }
            val serverOk = !Backend.enabled || runCatching { Backend.deleteMyAccount() }.isSuccess
            if (!serverOk) { Cloud.signOut(); toast("Couldn't remove your account from the server. Sign in again and delete it once more."); return@launch }
            // Success is only announced once both the server data and the Firebase sign-in are gone.
            Cloud.deleteAccount { ok -> if (ok) toast("Your account and data were deleted.")
                else { Cloud.signOut(); toast("Your profile, listings, posts and messages were removed, but your sign-in couldn't be. Sign in again and delete the account once more.") } }
        }
        repo.deleteAccount(); _s.value = freshState() }
    /** Cart, orders, search results, listing syncs and my listings/vehicles belong to the person who signed out, not the next account on this phone. */
    private fun signedOutCloud() { commerce.signedOut(); discover.signedOut(); myListings.signedOut(); services.signedOut() }
    fun switchRole(role: Role) = _s.update { it.copy(role = role, online = false) }
    /** [plate]: in cloud builds, which of my checked vehicles to go online with (null = the first ACTIVE one). */
    fun setOnline(v: Boolean, plate: String? = null) { if (v && s.mockLocation) { toast("Turn off the fake-location app to go online."); return }; _s.update { it.copy(online = v) }
        autoRingJob?.cancel()
        if (dispatch.enabled) {
            // Presence on the server; if it can't be published (no checked cloud vehicle yet, offline) we stay offline.
            dispatch.setOnline(v, plate ?: cloudVehicle?.plate) { ok -> if (ok) toast(if (v) "Online. Nearby requests will ring you." else "Offline") else if (v) _s.update { it.copy(online = false) } }
            return }
        toast(if (v) "Online. Nearby ride requests will ring you." else "Offline")
        // Demo dispatch: while a vehicle is online and idle, a nearby customer rings now and then.
        if (v) autoRingJob = viewModelScope.launch { delay(8000); while (s.vehicleOnline) { if (s.driverRide == null && s.ride == null) simulateRing(); delay(60000) } } }

    // ---------- location ----------
    fun onLocation(p: LatLng, mocked: Boolean) { social.here = p; val wasMocked = s.mockLocation; val (x, y) = Geo.toPercent(p); _s.update { it.copy(me = p, meX = x, meY = y, locationGranted = true, mockLocation = mocked) }; repo.updateDistances(p); if (mocked && !wasMocked) toast("A fake-location app is on. Turn it off to book or take rides.")
        if (dispatch.enabled) dispatch.driverMoved(p)
        // Name the pick-up point from the map, again only after moving ~250 m (the lookup service is shared and free).
        if (labelledAt?.let { Geo.distanceKm(it, p) > 0.25 } != false) { labelledAt = p
            viewModelScope.launch { MapServices.label(p)?.let { l -> if (s.me == p) _s.update { it.copy(hereLabel = l) } } } } }
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
    fun chooseDestAt(p: LatLng) { chooseDestPlace("Pinned location", p)
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
        val via = if (i.source == "gemini") " (understood by cloud AI)" else ""
        return when (i.tool) {
            Tools.CONFIRM -> { val p = s.pending; when { p == null -> AgentMessage(false, "Nothing is waiting for confirmation.") to null; p.needsBiometric -> AgentMessage(false, "This one needs your fingerprint or PIN — tap Confirm on the card.") to null; else -> AgentMessage(false, "Confirmed. ${p.title}.") to { confirmPending(p) } } }
            Tools.CANCEL -> { cancelPending(); AgentMessage(false, "Cancelled.") to null }
            Tools.SHOW_MAP -> { s.pendingDest?.let { d -> _s.update { it.copy(pendingDest = null, rideDest = randomPlace(d)) } }; AgentMessage(false, "Opening the ride screen.") to { navTo(Routes.CHOOSE_RIDE) } }
            Tools.RIDE -> {
                val k = runCatching { VehicleKind.valueOf(i.args["vehicle"] ?: "AUTO") }.getOrDefault(VehicleKind.AUTO).takeIf { it.carriesPassengers } ?: VehicleKind.AUTO
                val dest = i.args["destination"]?.takeIf { it.isNotBlank() }?.let { d -> Seed.PLACES.firstOrNull { it.equals(d, true) || it.lowercase().contains(d.lowercase().substringBefore(' ')) } }
                _s.update { it.copy(rideKind = k) }
                if (s.mockLocation) return AgentMessage(false, "Mock location is on, so I can't book a ride. Turn it off in developer settings.") to null
                val n = onlineFor(k)
                if (dest != null) { val place = randomPlace(dest); _s.update { it.copy(rideDest = place) }; proposeRide(place, k)
                    AgentMessage(false, "$n ${k.label.lowercase()} rider${if (n == 1) "" else "s"} within 5 km. ${k.label} to $dest, about ₹${fare(k, place.km)}, cash or UPI after the trip. Confirm?$via", actions = listOf("Yes, ring them", "Show the map first", "Cancel")) to null }
                else AgentMessage(false, "Where to? $n ${k.label.lowercase()} riders are online near you.", actions = Seed.PLACES.take(3).map { "${k.label} to ${it.substringBefore(',')}" }) to null
            }
            Tools.COMPARE -> { val res = sorted(repo.search(i.args["query"] ?: raw)); if (res.isEmpty()) return AgentMessage(false, "I couldn't find anyone for that.") to null
                AgentMessage(false, "Ranked by community trust (${s.lens.label.lowercase()}), then price:$via", cards = res.take(4).map { p -> AgentCard(p.name, "${trustFor(p).pct ?: "—"}% recommend · ${p.distanceKm} km · ${if (p.items.isNotEmpty()) "from ₹${p.minPrice}" else p.rate}", "Open", AgentAction.OpenProvider(p.id)) }) to null }
            Tools.SORT -> { val m = runCatching { SortMode.valueOf(i.args["by"] ?: "TRUST") }.getOrDefault(SortMode.TRUST); _s.update { it.copy(sort = m) }; AgentMessage(false, "Sorted by ${m.label.lowercase()}. Type a search term and I'll show results that way.") to null }
            Tools.ACTIVITY -> AgentMessage(false, "You have ${s.orders.size} orders, ${s.requests.size} service requests and ${s.rides.size} rides.") to { navTo(Routes.ACTIVITY) }
            Tools.POST_REQUEST -> { val what = i.args["what"]?.ifBlank { null } ?: raw; repo.addPost(Post("f${System.currentTimeMillis()}", s.user?.name ?: "You", "now", "Looking for $what near ${s.user?.area}. Any recommendations?", up = 0, down = 0)); AgentMessage(false, "Posted to your neighbourhood feed.") to { navTo(Routes.FEED) } }
            // Cloud: dispatch finds my checked vehicle on the server and says why when there is none.
            Tools.GO_ONLINE -> if (dispatch.enabled) { _s.update { it.copy(role = Role.PROVIDER) }; setOnline(true); AgentMessage(false, "Putting you online with your checked vehicle.") to { navTo(Routes.HOME) } }
                else if (s.pro?.vehicle != null) { _s.update { it.copy(role = Role.PROVIDER) }; setOnline(true); AgentMessage(false, "You're online.") to { navTo(Routes.HOME) } } else AgentMessage(false, "Attach a vehicle first and I'll put you online.") to { navTo(Routes.PRO_CREATE) }
            Tools.BECOME_PRO -> AgentMessage(false, "Let's set up your pro profile.") to { navTo(Routes.PRO_CREATE) }
            Tools.SEARCH -> { val q = i.args["query"]?.ifBlank { null } ?: raw; val res = sorted(repo.search(q))
                if (res.isEmpty()) AgentMessage(false, "No one offers \"$q\" yet. Want me to ask the community?", actions = listOf("Post a request for $q")) to null
                else AgentMessage(false, "Here's who people nearby recommend for that:$via", cards = res.take(3).map { p -> AgentCard(p.name, "${trustFor(p).pct ?: "—"}% recommend · ${trustFor(p).total} reviews · ${p.distanceKm} km", if (p.type == ProviderType.BUSINESS) "Order" else "Request", if (p.type == ProviderType.BUSINESS) AgentAction.OpenProvider(p.id, "items") else AgentAction.Request(p.id)) }) to null }
            else -> AgentMessage(false, if (cloudEnabled) "I didn't get that. Try 'auto to MG Road', 'order sugar' or 'compare biriyani'." else "I didn't get that. Try one of these (add a Gemini key to understand free-form commands):", actions = listOf("Auto to MG Road", "Order sugar", "Find a doctor", "Compare biriyani", "Show my orders")) to null
        }
    }

    // ---------- confirmation gate (every money-moving action passes here) ----------
    private fun propose(p: PendingAction) = _s.update { it.copy(pending = p) }
    fun cancelPending() = _s.update { it.copy(pending = null) }
    /** Called by the UI after the user tapped Confirm and (when required) passed BiometricPrompt. */
    fun confirmPending(expected: PendingAction) { val p = s.pending ?: return; if (p !== expected) return; _s.update { it.copy(pending = null) }; p.run() }
    private fun firstTimeWith(counterparty: String) = s.orders.none { it.providerName == counterparty } && s.requests.none { it.providerName == counterparty }
    private fun proposeRide(place: Place, k: VehicleKind) { val f = fare(k, place.km); propose(PendingAction("Book a ${k.label.lowercase()}", "${s.user?.area} → ${place.name} · ${place.km} km · about ₹$f, pay after the trip", f, "Nearest online rider", null, needsBiometric = false) { doRequestRide() }) }
    fun requestRide() { val d = s.rideDest ?: return; proposeRide(d, s.rideKind) }
    fun placeOrder(): Boolean { val cl = cartLines(); val p = cl.first ?: return false; val total = cl.third
        propose(PendingAction("Place order with ${p.name}", cl.second.joinToString(", ") { "${it.first} × ${it.third}" } + " · ₹$total", total, p.name, p.trust, needsBiometric = total >= 500 || firstTimeWith(p.name)) { doPlaceOrder() }); return true }

    // ---------- providers, cart, orders, requests ----------
    fun provider(id: String) = repo.providers.value.firstOrNull { it.id == id }
    fun canVote(pid: String) = s.orders.any { it.providerId == pid && it.status == OrderStatus.DELIVERED } || s.requests.any { it.providerId == pid && it.status == RequestStatus.COMPLETED }
    fun vote(pid: String, up: Boolean, comment: String): Boolean {
        if (s.myVotes.containsKey(pid)) { toast("You've already reviewed them."); return false }
        if (comment.isBlank()) { toast("Add a line on why. Reviews without a reason aren't counted."); return false }
        val txn = s.orders.firstOrNull { it.providerId == pid && it.status == OrderStatus.DELIVERED }?.id ?: s.requests.firstOrNull { it.providerId == pid && it.status == RequestStatus.COMPLETED }?.id ?: ""
        val u = s.user; val at = System.currentTimeMillis()
        repo.voteProvider(pid, up, u?.name ?: "You", comment, u?.id ?: "", VerificationLevel.DOCUMENT in (u?.verified ?: emptySet()), txn, sign(Identity.txnPayload("vote", txn, u?.id ?: "", pid, if (up) 1 else -1, at)))
        _s.update { it.copy(myVotes = it.myVotes + (pid to if (up) 1 else -1)) }; toast("Thanks. Your review is public and signed."); return true
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
        viewModelScope.launch { for (st in OrderStatus.entries.drop(1)) { delay(2600); _s.update { u -> u.copy(orders = u.orders.map { if (it.id == o.id) it.copy(status = st) else it }) } }; toast("Delivered. Tell others how ${p.name} did.") }
    }
    fun sendRequest(pid: String, text: String): String {
        val p = provider(pid)!!; val id = "r${System.currentTimeMillis()}"
        val r = ServiceRequest(id, p.id, p.name, p.category, text.ifBlank { "Service request" }, RequestStatus.SENT, sign(Identity.txnPayload("request", id, s.user?.id ?: "", p.id, 0, System.currentTimeMillis())))
        _s.update { it.copy(requests = listOf(r) + it.requests) }
        viewModelScope.launch { delay(2500); setRequestStatus(r.id, RequestStatus.ACCEPTED); toast("${p.name} accepted. They'll message you."); val cid = repo.openChat(p.name, p.category); repo.sendMessage(cid, "Got your request: \"${r.text}\". I'll be there.", false) }
        return r.id
    }
    fun setRequestStatus(id: String, st: RequestStatus) { _s.update { u -> u.copy(requests = u.requests.map { if (it.id == id) it.copy(status = st) else it }) }; if (st == RequestStatus.COMPLETED) toast("Job done. Tell others how it went.") }

    // ---------- ride (customer) ----------
    private fun randomPlace(name: String): Place { val ll = Geo.PLACES[name]; return if (ll != null) { val (x, y) = Geo.toPercent(ll); Place(name, x, y, (Geo.distanceKm(mePos, ll) * 10).roundToInt() / 10.0, at = ll) } else Place(name, 20 + Random.nextFloat() * 60, 15 + Random.nextFloat() * 30, ((1.5 + Random.nextDouble() * 7) * 10).roundToInt() / 10.0) }
    fun startRide() = _s.update { it.copy(rideDest = null, pending = null) }
    fun chooseDest(name: String) = _s.update { it.copy(rideDest = randomPlace(name)) }
    fun setRideKind(k: VehicleKind) { if (k.carriesPassengers) _s.update { it.copy(rideKind = k) } }
    fun fare(k: VehicleKind, km: Double) = (k.farePerKm * km + 20).roundToInt()
    fun onlineCount(k: VehicleKind) = Geo.ring(mePos, repo.drivers.value, k).size
    private fun doRequestRide() {
        if (dispatch.enabled) { val dest = s.rideDest ?: return
            val me = s.me ?: run { toast("Turn on location so your rider can find your pick-up point."); return }
            // The real point the rider chose; x/y are clamped to the drawn map, so a pick beyond its edge would move the drop.
            val to = dest.at ?: Geo.PLACES[dest.name] ?: Geo.fromPercent(dest.x, dest.y)
            dispatch.requestRide(s.rideKind, me, s.hereLabel ?: s.user?.area?.ifBlank { null } ?: Geo.nearestArea(me), dest, to, fare(s.rideKind, dest.km)); return }
        val dest = s.rideDest ?: return; val k = s.rideKind; val id = "ride${System.currentTimeMillis()}"; val f = fare(k, dest.km)
        val ride = Ride(id, k, dest, f, RideStatus.SEARCHING, (1000 + Random.nextInt(9000)).toString(), signature = sign(Identity.txnPayload("ride", id, s.user?.id ?: "", "", f, System.currentTimeMillis())))
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
            _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.ARRIVED)) }; toast("Your rider is here. Share PIN ${s.ride?.pin} to start.")
        }
    }
    fun cancelRide(reason: String) { if (s.ride?.status !in setOf(RideStatus.SEARCHING, RideStatus.NO_DRIVER, RideStatus.MATCHED, RideStatus.ARRIVED)) return; ringJob?.cancel(); driveJob?.cancel()
        s.ride?.let { r -> _s.update { it.copy(rides = listOf(r.copy(status = RideStatus.CANCELLED, reason = reason)) + it.rides) } }
        if (dispatch.enabled) dispatch.cancelRide() else _s.update { it.copy(ride = null) }
        toast("Ride cancelled. Nothing to pay."); navTo(Routes.HOME) }
    fun startTrip() {
        if (dispatch.enabled) return  // the driver starts the trip after checking the PIN
        _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.IN_RIDE)) }; navTo(Routes.IN_RIDE)
        driveJob?.cancel(); driveJob = viewModelScope.launch { val mx = s.meX; val my = s.meY
            for (k in 1..5) { delay(1300); val r = s.ride ?: return@launch; _s.update { it.copy(ride = r.copy(progress = k / 5f, driverX = mx + (r.dest.x - mx) * k / 5, driverY = my + (r.dest.y - my) * k / 5)) } }
            _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.COMPLETED)) }; navTo(Routes.PAY) }
    }
    /** The rider confirms payment. With cloud dispatch the server records it and the rating screen follows once it's saved. */
    fun payRide(method: String) { if (dispatch.enabled) { dispatch.payRide(method); return }; _s.update { it.copy(ride = it.ride?.copy(status = RideStatus.PAID, paidWith = method)) }; navTo(Routes.RATE_RIDE) }
    fun finishRide(vote: Int?, comment: String, skip: Boolean): Boolean {
        val r = s.ride ?: return true
        if (!skip) { if (vote == null || comment.isBlank()) { toast("Choose Recommend or Not recommended, and add a line on why."); return false }; r.driver?.let { repo.voteDriver(it.id, vote > 0) } }
        _s.update { it.copy(rides = listOf(r.copy(status = RideStatus.COMPLETED)) + it.rides) }
        if (dispatch.enabled) dispatch.finishRide(if (skip) null else vote, comment) else _s.update { it.copy(ride = null) }
        toast("Trip saved. Find it under Activity."); navTo(Routes.HOME); return true
    }
    /** Cloud ride follow-up: navigate as the task moves along, exactly as the demo simulation does. */
    private fun onCloudRide(prev: Ride?, r: Ride?) {
        if (r == null) return
        if (prev == null || prev.id != r.id) { when (r.status) {   // new request, or a trip restored after the app was killed
            RideStatus.SEARCHING, RideStatus.NO_DRIVER -> navTo(Routes.SEARCHING)
            RideStatus.MATCHED, RideStatus.ARRIVED -> navTo(Routes.DRIVER_FOUND)
            RideStatus.IN_RIDE -> navTo(Routes.IN_RIDE)
            RideStatus.COMPLETED -> navTo(Routes.PAY)
            RideStatus.PAID -> navTo(Routes.RATE_RIDE)
            RideStatus.CANCELLED -> {} }; return }
        if (r.status == prev.status) return
        when (r.status) {
            RideStatus.MATCHED -> navTo(Routes.DRIVER_FOUND)
            RideStatus.SEARCHING -> { toast("Your rider cancelled. Ringing others nearby."); navTo(Routes.SEARCHING) }
            RideStatus.ARRIVED -> toast("Your rider is here. Share PIN ${r.pin} to start.")
            RideStatus.IN_RIDE -> navTo(Routes.IN_RIDE)
            RideStatus.COMPLETED -> navTo(Routes.PAY)
            RideStatus.PAID -> navTo(Routes.RATE_RIDE)
            RideStatus.NO_DRIVER, RideStatus.CANCELLED -> {}
        }
    }
    private fun onCloudDriverRide(prev: DriverRide?, d: DriverRide?) {
        if (d == null || (prev != null && prev.id == d.id)) return
        if (d.status == DriverRideStatus.RINGING) { if (s.ride == null && s.pending == null) navTo(Routes.HOME); return }
        // A trip restored after the app was killed: back to the trip screen, and back on duty so location keeps flowing.
        navTo(Routes.HOME)
        if (!s.online) setOnline(true)
    }

    // ---------- provider side ----------
    fun simulateRing() {
        if (s.driverRide != null) return
        if (!s.vehicleOnline) { toast("Turn your vehicle online to receive ride requests."); return }
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
            if (cur.secondsLeft <= 1) { _s.update { it.copy(driverRide = null) }; toast("Too late. Another rider took it."); return@launch }
            _s.update { it.copy(driverRide = cur.copy(secondsLeft = cur.secondsLeft - 1)) } } }
    }
    fun driverDecline() { if (dispatch.enabled) { dispatch.driverDecline(); return }; drvRingJob?.cancel(); _s.update { it.copy(driverRide = null) }; toast("Passed. We'll send you the next one.") }
    fun driverAccept() { if (dispatch.enabled) { dispatch.driverAccept(); return }; drvRingJob?.cancel()
        _s.update { it.copy(driverRide = it.driverRide?.copy(status = DriverRideStatus.TO_PICKUP, progress = 0f)) }; toast("It's yours. Head to the pick-up.")
        animateDriver(DriverRideStatus.TO_PICKUP) { _s.update { it.copy(driverRide = it.driverRide?.copy(status = DriverRideStatus.ARRIVED)) }; toast("You're at the pick-up. Ask the customer for their PIN.") } }
    /** Simulated drive for the current leg; replace with real location updates from DriverLocationService. */
    private fun animateDriver(leg: DriverRideStatus, onDone: () -> Unit) { drvDriveJob?.cancel(); drvDriveJob = viewModelScope.launch {
        for (k in 1..8) { delay(900); val cur = s.driverRide ?: return@launch; if (cur.status != leg) return@launch; _s.update { it.copy(driverRide = cur.copy(progress = k / 8f)) } }; onDone() } }
    /** Next step of the driver's trip. With cloud dispatch the server checks the PIN and the screen moves on when the row does. */
    fun driverNext(pin: String = ""): Boolean {
        val d = s.driverRide ?: return true
        if (dispatch.enabled) { dispatch.driverNext(pin); return true }
        when (d.status) {
            DriverRideStatus.TO_PICKUP -> { drvDriveJob?.cancel(); _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.ARRIVED)) } }
            DriverRideStatus.ARRIVED -> { if (pin != d.pin) { toast("That PIN doesn't match. Ask the customer to read it again."); return false }
                _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.IN_RIDE, progress = 0f)) }
                animateDriver(DriverRideStatus.IN_RIDE) { toast("Arrived at ${d.dropAt}") } }
            DriverRideStatus.IN_RIDE -> { drvDriveJob?.cancel(); _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.DONE, progress = 1f)) } }
            else -> {}
        }; return true
    }
    fun driverPaid(method: String) { val d = s.driverRide ?: return
        if (dispatch.enabled) dispatch.driverPaid(method) else _s.update { it.copy(driverRide = d.copy(status = DriverRideStatus.RATE, paidWith = method)) }
        _s.update { it.copy(earnings = it.earnings + d.fare) }; toast("₹${d.fare} received by $method. Added to today's earnings.") }
    fun setUpi(id: String) { val v = id.trim(); if (!Regex("^[\\w.\\-]{2,}@[a-zA-Z]{2,}$").matches(v)) { toast("A UPI ID looks like name@bank. Check it and try again."); return }; _s.update { it.copy(pro = (it.pro ?: ProProfile()).copy(upiId = v)) }; persist() }
    fun driverRateCustomer(stars: Int) { val up = stars >= 3; _s.update { it.copy(user = it.user?.copy(up = it.user.up + if (up) 1 else 0, down = it.user.down + if (up) 0 else 1)) }; persist()
        if (dispatch.enabled) dispatch.closeTrip() else _s.update { it.copy(driverRide = null) }; toast("Trip closed. Fare added to today's earnings.") }
    fun driverCancel() { _s.update { it.copy(user = it.user?.copy(down = it.user.down + 1)) }; persist()
        if (dispatch.enabled) dispatch.driverCancel() else _s.update { it.copy(driverRide = null) }; toast("Ride cancelled. This counts against your recommendations.") }
    fun setProKind(k: ProKind) = _s.update { it.copy(proKind = k) }
    fun setProStep(n: Int) = _s.update { it.copy(proStep = n) }
    fun startPro(kind: ProKind?, step: Int) = _s.update { it.copy(proKind = kind, proStep = step, editBiz = null) }
    /** Adds or replaces (by [replacing] plate) a vehicle. It stays "In Progress" until verified; this build simulates community verification after a few seconds. */
    fun saveVehicle(kind: VehicleKind, model: String, plate: String, mode: ListingMode = ListingMode.TAXI, docs: Int = 0, replacing: String? = null) {
        val v = Vehicle(kind, model.ifBlank { kind.label }, plate.ifBlank { "KA 00 XX 0000" }.uppercase(), mode, verified = false, docs = docs)
        _s.update { st -> val p = st.pro ?: ProProfile(); st.copy(pro = p.copy(vehicles = p.vehicles.filter { it.id != replacing && it.id != v.id } + v)) }; persist(); toast("${v.model} (${v.plate}) submitted. Documents are being verified.")
        viewModelScope.launch { delay(8000); _s.update { st -> st.copy(pro = st.pro?.let { p -> p.copy(vehicles = p.vehicles.map { if (it.id == v.id) it.copy(verified = true) else it }) }) }; persist(); toast("${v.model} (${v.plate}) is verified. You can go online with it.") }
    }
    fun setVehicleOnline(id: String, on: Boolean) {
        if (on) { _s.update { it.copy(pro = it.pro?.copy(activeVehicle = id)) }; persist(); setOnline(true) } else if (s.pro?.vehicle?.id == id) setOnline(false)
    }
    fun addSkill(name: String, replacing: String? = null) { val u = s.user ?: return; val n = name.trim(); if (n.isBlank()) return
        addSkillProvider(u, n, s.pro?.rate.orEmpty())
        _s.update { st -> val p = st.pro ?: ProProfile(); val old = p.skillListings.firstOrNull { it.name == replacing }
            st.copy(pro = p.copy(skillListings = p.skillListings.filter { it.name != replacing && it.name != n } + (old?.copy(name = n) ?: SkillListing(n)))) }; persist(); toast(if (replacing != null) "Skill updated" else "$n added to your skillset") }
    fun setSkillOnline(name: String, on: Boolean) { _s.update { st -> st.copy(pro = st.pro?.let { p -> p.copy(skillListings = p.skillListings.map { if (it.name == name) it.copy(online = on) else it }) }) }; persist(); toast(if (on) "$name is online. Service requests will reach you." else "$name is offline. You won't get requests for it.") }
    fun setBusinessOnline(i: Int, on: Boolean) { _s.update { st -> st.copy(businesses = st.businesses.mapIndexed { j, b -> if (j == i) b.copy(online = on) else b }) }; persist(); s.businesses.getOrNull(i)?.let { toast(if (on) "${it.name} is open for orders" else "${it.name} is closed. It won't get orders.") } }
    fun editBusiness(i: Int?) = _s.update { it.copy(editBiz = i, proKind = ProKind.BUSINESS, proStep = 2) }
    fun saveSkills(skills: List<String>, rate: String) { val u = s.user ?: return
        skills.forEach { addSkillProvider(u, it, rate) }
        _s.update { it.copy(pro = (it.pro ?: ProProfile()).let { p -> p.copy(skillListings = p.skillListings + skills.filter { k -> k !in p.skills }.map { k -> SkillListing(k) }, rate = rate) }, proStep = 3, proMessage = "${skills.size} skills published. You'll appear in searches, ranked by votes you earn.") }; persist() }
    fun saveBusiness(name: String, cat: String, scope: Scope, items: List<Item>): Boolean { val u = s.user ?: return false
        if (name.isBlank() || cat.isBlank()) { toast("Add a business name and pick a category."); return false }
        val edit = s.editBiz?.let { s.businesses.getOrNull(it) }
        val biz = Business(name, cat, scope, items, online = edit?.online ?: true, area = edit?.area?.ifBlank { null } ?: s.user?.area.orEmpty(), followers = edit?.followers ?: 0)
        edit?.takeIf { !it.name.equals(name, true) }?.let { old -> repo.removeProvider("biz-me-${old.name.lowercase()}") }
        addBusinessProvider(name, cat, scope, items, replace = true)
        _s.update { st -> st.copy(businesses = st.editBiz?.let { e -> st.businesses.mapIndexed { j, b -> if (j == e) biz else b } } ?: (st.businesses + biz), editBiz = null, proStep = 3, proMessage = "$name is live. Customers searching \"${cat.lowercase()}\" will find you.") }; persist(); return true }
    fun simulateIncoming() { val openBiz = s.businesses.firstOrNull { it.online }; val openSkill = s.pro?.skillListings?.firstOrNull { it.online }
        val inc = when { openBiz != null -> Incoming("Arjun R", "Order: ${openBiz.items.firstOrNull()?.name ?: "1 item"} × 2 for ${openBiz.name} · deliver to Jayanagar"); openSkill != null -> Incoming("Meera S", "Request: ${openSkill.name} needed today evening"); s.businesses.isNotEmpty() || !s.pro?.skills.isNullOrEmpty() -> { toast("Go online with a business or skill to receive orders and requests"); return }; else -> { toast("Add a business or a skill first, then switch it online."); navTo(Routes.PRO_CREATE); return } }
        _s.update { it.copy(incoming = listOf(inc) + it.incoming) }; toast("New request. Open Incoming to accept it."); navTo(Routes.LISTINGS) }
    fun acceptIncoming(i: Incoming) { _s.update { it.copy(incoming = it.incoming - i) }; toast("Accepted. The customer knows you're on it.") }

    // ---------- feed / chat / social ----------
    fun votePost(id: String, v: Int) { val prev = s.postVotes[id] ?: 0; val next = if (prev == v) 0 else v; repo.votePost(id, next, prev); _s.update { it.copy(postVotes = if (next == 0) it.postVotes - id else it.postVotes + (id to next)) } }
    fun addPost(text: String, image: String? = null, attachment: Attachment? = null) { if (text.isBlank() && image == null && attachment == null) { toast("Write something first"); return }; repo.addPost(Post("f${System.currentTimeMillis()}", s.user?.name ?: "You", "now", text, hasImage = image != null, file = attachment?.name, up = 0, down = 0, image = image, attachment = attachment)); toast("Posted to your feed.") }
    fun addComment(postId: String, text: String) { if (text.isNotBlank()) repo.addPostComment(postId, s.user?.name ?: "You", text) }
    fun openChat(name: String, role: String): String = repo.openChat(name, role).also { repo.markRead(it) }
    fun sendChat(chatId: String, text: String) { if (text.isBlank()) return; repo.sendMessage(chatId, text, true); viewModelScope.launch { delay(1200); repo.sendMessage(chatId, listOf("Sure.", "On it.", "Give me 10 minutes.", "Yes, that works.").random(), false); repo.markRead(chatId) } }
    fun markRead(chatId: String) = repo.markRead(chatId)
    fun sendAttachment(chatId: String, a: Attachment) { repo.sendMessage(chatId, if (a.isImage) "Photo" else a.name, true, a) }
    fun followProvider(id: String) { val on = id !in s.followedProviders; _s.update { it.copy(followedProviders = if (on) it.followedProviders + id else it.followedProviders - id) }; toast(if (on) "Following. Their posts show up in your feed." else "Unfollowed") }
    fun follow(id: String, f: Boolean) { repo.follow(id, f); toast(if (f) "Following. Their reviews now count under 'People I follow'." else "Unfollowed.") }
    fun join(id: String, j: Boolean) { repo.join(id, j); toast(if (j) "Joined" else "Left community") }
    fun toggleDriverOnline(id: String) { val d = repo.drivers.value.first { it.id == id }; repo.setDriverOnline(id, !d.online) }

    // ---------- calls ----------
    fun startCall(name: String, phone: String) = _s.update { it.copy(call = CallState(name, phone)) }
    fun toggleMute() = _s.update { it.copy(call = it.call?.copy(muted = !it.call.muted)) }
    fun toggleSpeaker() = _s.update { it.copy(call = it.call?.copy(speaker = !it.call.speaker)) }
    fun endCall() { val c = s.call ?: return; val secs = (System.currentTimeMillis() - c.startedAt) / 1000; _s.update { it.copy(call = null) }; toast("Call with ${c.name} ended · ${secs / 60}m ${secs % 60}s") }

    // ---------- devices & backup ----------
    fun syncNow() { viewModelScope.launch { _s.update { it.copy(syncStatus = SyncStatus.SYNCING) }; delay(1400); _s.update { it.copy(syncStatus = SyncStatus.SYNCED, lastSynced = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault()).format(java.util.Date())) }; toast("Up to date on ${s.devices.size} device${if (s.devices.size > 1) "s" else ""}") } }
    fun exportSnapshot(): String = repo.exportSnapshot(s.user?.let { Session(it, s.pro, s.businesses) })
    fun importSnapshot(json: String): Boolean { val se = repo.importSnapshot(json) ?: run { toast("That file isn't a Bucks backup"); return false }; _s.update { it.copy(user = se.user.copy(id = se.user.id.ifBlank { safeId() }), pro = se.pro, businesses = se.businesses) }; publishOwnListings(); toast("Restored ${se.user.name}'s profile on this device"); return true }
    fun linkDevice(code: String): Boolean { if (code.trim().length < 6) { toast("Enter the 6-character code shown on the other device"); return false }; _s.update { it.copy(devices = it.devices + LinkedDevice("dev-${code.trim().lowercase()}", "Device ${code.trim().uppercase()}", "Linked just now", false)) }; toast("Device linked. Your profile will sync there."); return true }
    fun unlinkDevice(id: String) = _s.update { it.copy(devices = it.devices.filterNot { d -> d.id == id && !d.thisDevice }) }

    class Factory(private val repo: BucksRepository) : ViewModelProvider.Factory { @Suppress("UNCHECKED_CAST") override fun <T : ViewModel> create(modelClass: Class<T>): T = BucksViewModel(repo) as T }
}
