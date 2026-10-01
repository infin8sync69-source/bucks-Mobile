package com.bucks.app.ui

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.bucks.app.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.max
import kotlin.math.roundToInt

/** Wrong PINs a driver may try before the server locks the trip (contract C1). */
const val PIN_TRIES = 5
/** Trips the server accepts: shorter or longer raise 'that trip is too short / too far' (contract C3). */
const val MIN_TRIP_KM = 0.2
const val MAX_TRIP_KM = 150.0
/** How long a request rings before it is given up when the server's ring_window_seconds can't be read (schema default). */
private const val RING_WINDOW_DEFAULT_S = 180L

/** Whole seconds since an ISO timestamp from PostgREST (with offset); null when it can't be read. */
fun secondsSince(iso: String): Long? = runCatching { java.time.Duration.between(java.time.OffsetDateTime.parse(iso.replace(" ", "T")).toInstant(), java.time.Instant.now()).seconds }.getOrNull()

/**
 * Cloud dispatch: rides and deliveries on Supabase `tasks`, replacing the Firestore ride code.
 *
 * Rider side: [requestRide] creates the task and follows it (realtime on `tasks` + a 5-second poll of `tasks_geo`),
 * publishing the mapped [Ride] through [ride]. Driver side: [setOnline] publishes presence with a heartbeat and
 * rings the nearest open task every 5 s (nudged by realtime) as a [DriverRide] through [driverRide]; accept / pass /
 * advance go through the server functions, which check the PIN. [BucksViewModel] mirrors the two flows into
 * UiState and navigates on status changes, so the existing ride screens keep working unchanged in demo mode.
 * The server is the truth: after a failed or lost call the task row is read again and the screen follows it, and a
 * cancel only changes the screen once the server has cancelled. Every action reports a failure as a toast.
 */
class Dispatch(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit, private val onRideClosed: (String) -> Unit = {}) {
    val enabled get() = Backend.enabled
    /** The rider's current trip (null when there is none). Only this class writes it in cloud mode. */
    private val _ride = MutableStateFlow<Ride?>(null); val ride: StateFlow<Ride?> = _ride.asStateFlow()
    /** The driver's ringing request or active trip. */
    private val _driverRide = MutableStateFlow<DriverRide?>(null); val driverRide: StateFlow<DriverRide?> = _driverRide.asStateFlow()
    /** Online drivers around me, for the map pins and "n riders nearby"; refreshed every 15 s while a map is showing. */
    private val _drivers = MutableStateFlow<List<Driver>>(emptyList()); val drivers: StateFlow<List<Driver>> = _drivers.asStateFlow()
    /** My UPI payment link (decoded from the QR I uploaded), or null. */
    var paymentLink by mutableStateOf<String?>(null); private set
    var paymentLinkLoaded by mutableStateOf(false); private set
    /** True while presence says I'm online. [onlineFlow] carries the same value for [BucksViewModel]'s UiState. */
    var online by mutableStateOf(false); private set
    private val _online = MutableStateFlow(false); val onlineFlow: StateFlow<Boolean> = _online.asStateFlow()
    private fun markOnline(v: Boolean) { online = v; _online.value = v }
    /** My vehicles on the server (owned or driven), loaded after sign-in and whenever I go online; the online switch uses the ACTIVE ones. */
    var vehicles by mutableStateOf<List<VehicleRow>>(emptyList()); private set
    /** True while a request is being sent or a claim is in flight (buttons show progress). */
    var busy by mutableStateOf(false); private set
    /** In-flight guards for the buttons that must not fire twice: the rider's cancel and payment, the driver's hand-back. */
    var cancelling by mutableStateOf(false); private set
    var paying by mutableStateOf(false); private set
    var handingBack by mutableStateOf(false); private set
    /** Seconds a request rings before it is given up: the server's ring_window_seconds, read after sign-in. */
    var ringWindowS by mutableLongStateOf(RING_WINDOW_DEFAULT_S); private set

    private val here get() = social.here
    /** My position for the server, or null while no real fix has arrived (never the map's default centre). */
    private val hereOrNull get() = social.here.takeIf { social.hereKnown }
    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { toast(friendlyError(e)) } }
    private fun round1(km: Double) = (km * 10).roundToInt() / 10.0
    private suspend fun waitForMe(): ProfileRow? { var n = 0; while (social.me == null && n++ < 40) delay(500); return social.me }

    init {
        // A ringing request must reach a driver who isn't looking: a buzz in the app, a heads-up notification outside it.
        // Any other state (accepted, passed, missed, cancelled, offline) takes the alert away again.
        scope.launch { var ringing: String? = null
            _driverRide.collect { d -> val r = d?.takeIf { it.status == DriverRideStatus.RINGING }
                if (r?.id != ringing) { if (ringing != null) RingAlert.cancel(); if (r != null) RingAlert.ring(r); ringing = r?.id } } }
        // The screen turning off (or Bucks being left) mid-ring turns the buzz into the heads-up: the request is still open and would expire unseen.
        scope.launch { AppLife.foreground.collect { fg -> if (!fg) _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING }?.let { RingAlert.ring(it) } } }
    }

    // =====================================================================
    // Rider
    // =====================================================================
    private var rideJob: Job? = null; private var noDriverJob: Job? = null
    private var rideDriver: TaskDriverRow? = null; private var ridePhone: String? = null

    /** Books an auto or cab: creates the task, then follows it. Bikes carry goods only. The fare and distance shown afterwards are the server's (contract C3). */
    fun requestRide(kind: VehicleKind, from: LatLng, fromLabel: String, dest: Place, to: LatLng, fare: Int) {
        if (!kind.carriesPassengers) { toast("Bikes carry goods only. Choose an auto or a cab."); return }
        if (dest.km < MIN_TRIP_KM) { toast("That's too close for a ride. Pick a destination at least 200 m away."); return }
        if (dest.km > MAX_TRIP_KM) { toast("That trip is too far for Bucks. Rides go up to ${MAX_TRIP_KM.toInt()} km."); return }
        if (busy) return
        go { busy = true
            try {
                val t = try { Backend.requestRide(kind, from, fromLabel, to, dest.name, dest.km, fare) } catch (e: CancellationException) { throw e } catch (e: Exception) {
                    // The request may have reached the server before the answer was lost, or a ride of mine is already open: follow that one.
                    val open = runCatching { Backend.myOpenTask() }.getOrNull()?.takeIf { it.requesterId == social.me?.id && it.type == "RIDE" }
                    if (open == null) throw e
                    toast("You already have a ride in progress."); restoreRide(open); return@go }
                rideDriver = null; ridePhone = null
                _ride.value = Ride(t.id, kind, dest.copy(km = t.km), t.fare, RideStatus.SEARCHING, t.pin, pickupLabel = fromLabel)
                startNoDriverTimer(t.id, 0); followRide(t.id)
            } finally { busy = false } }
    }
    private fun followRide(id: String) {
        rideJob?.cancel()
        rideJob = scope.launch {
            val (channel, flow) = Backend.liveTask(id)
            val nudge = launch { runCatching { flow.collect { refreshRide(id) } } }
            try { while (isActive) { refreshRide(id); delay(5_000) } }
            finally { nudge.cancel(); Backend.releaseChannel(channel) }
        }
    }
    private suspend fun refreshRide(id: String) { runCatching { Backend.taskGeo(id) }.getOrNull()?.let { if (_ride.value?.id == id) applyRide(it) } }
    /**
     * Gives up on a request nobody took once the server's window has passed, so the rider can retry or switch vehicle type
     * (the server does the same with expire_tasks; this covers a server without it). [ageS] is how long it has been searching:
     * 0 for a request just made here; for a restored or handed-back one, the server's age, but never less than 20 s of waiting
     * left, so a phone with a wrong clock can't end a live request at once. A failed call is retried a few times.
     */
    private fun startNoDriverTimer(id: String, ageS: Long) { noDriverJob?.cancel(); noDriverJob = scope.launch { delay((ringWindowS - ageS.coerceIn(0, ringWindowS - 20)) * 1000)
        var tries = 0
        while (isActive && _ride.value?.id == id && _ride.value?.status == RideStatus.SEARCHING && tries++ < 5) {
            // advance_task returns the plain tasks row; the rider's Ride is mapped from tasks_geo, so re-read that (a driver may have claimed it meanwhile).
            val ok = runCatching { Backend.advanceTask(id, "NO_DRIVER") }.isSuccess
            refreshRide(id)
            if (ok || _ride.value?.status != RideStatus.SEARCHING) break
            delay(10_000)
        } } }
    private fun stopFollowingRide() { rideJob?.cancel(); rideJob = null; noDriverJob?.cancel(); noDriverJob = null }

    private fun rideStatus(s: String) = when (s) { "SEARCHING" -> RideStatus.SEARCHING; "MATCHED" -> RideStatus.MATCHED; "ARRIVED" -> RideStatus.ARRIVED; "IN_PROGRESS" -> RideStatus.IN_RIDE
        "COMPLETED" -> RideStatus.COMPLETED; "PAID" -> RideStatus.PAID; "NO_DRIVER" -> RideStatus.NO_DRIVER; else -> RideStatus.CANCELLED }
    private fun placeOf(t: TaskGeoRow): Place { val (x, y) = Geo.toPercent(t.drop); return Place(t.dropLabel.ifBlank { "Drop point" }, x, y, t.km, at = t.drop) }
    private fun kindOf(s: String) = runCatching { VehicleKind.valueOf(s) }.getOrDefault(VehicleKind.AUTO)

    /** Maps a task row onto the rider's [Ride]; fetches the driver's name, vehicle and phone once per driver. */
    private suspend fun applyRide(t: TaskGeoRow) {
        val prev = _ride.value; val st = rideStatus(t.status); val kind = kindOf(t.vehicleKind)
        // Cancelled somewhere else (another phone, the server): close it here. A cancel from this phone is finished by [cancelRide].
        if (st == RideStatus.CANCELLED) { if (!cancelling) { stopFollowingRide(); _ride.value = null; onRideClosed("This ride was cancelled.") }; return }
        val pos = t.driverAt
        var driver: Driver? = null; var dx = prev?.driverX ?: 0f; var dy = prev?.driverY ?: 0f; var drvAt = prev?.driverAt
        if (t.driverId != null) {
            if (rideDriver?.profileId != t.driverId) { rideDriver = runCatching { Backend.taskDriver(t.id) }.getOrNull(); ridePhone = runCatching { Backend.contactFor(t.id)?.phone }.getOrNull() }
            else if (ridePhone.isNullOrBlank()) ridePhone = runCatching { Backend.contactFor(t.id)?.phone }.getOrNull()
            val d = rideDriver
            (pos ?: if (prev?.driver == null) t.pickup else null)?.let { p -> drvAt = p; Geo.toPercent(p).let { dx = it.first; dy = it.second } }
            driver = Driver(t.driverId, d?.name?.ifBlank { null } ?: social.names[t.driverId] ?: "Your rider", d?.kind?.let(::kindOf) ?: kind, d?.plate.orEmpty(), d?.model.orEmpty(), dx, dy,
                pos?.let { round1(Geo.distanceKm(it, t.pickup)) } ?: 0.0, d?.up ?: 0, d?.down ?: 0, true, ridePhone.orEmpty(), at = drvAt)
        } else { rideDriver = null; ridePhone = null; drvAt = null }
        // -1 means "no position yet" (the screen says the rider is on the way instead of counting); 0 is "under a minute".
        val eta = if (st in setOf(RideStatus.MATCHED, RideStatus.ARRIVED)) pos?.let { (Geo.distanceKm(it, t.pickup) * 2.5).roundToInt() } ?: (prev?.etaMin ?: -1) else 0
        val progress = when {
            st == RideStatus.IN_RIDE && pos != null -> (1 - Geo.distanceKm(pos, t.drop) / t.km.coerceAtLeast(0.1)).toFloat().coerceIn(0f, 1f)
            st == RideStatus.COMPLETED || st == RideStatus.PAID -> 1f
            else -> prev?.progress ?: 0f }
        if (_ride.value?.id != t.id) return   // cleared (cancelled, rated) while this read was fetching the driver: don't bring it back
        _ride.value = Ride(t.id, kind, placeOf(t), t.fare, st, t.pin, driver, dx, dy, eta, progress, t.paidWith ?: prev?.paidWith, prev?.reason, prev?.signature ?: "", driverAt = drvAt, pickupLabel = t.pickupLabel.ifBlank { prev?.pickupLabel.orEmpty() })
        if (st == RideStatus.SEARCHING && (noDriverJob?.isActive != true || prev?.status != RideStatus.SEARCHING)) startNoDriverTimer(t.id, secondsSince(t.statusAt.ifBlank { t.createdAt }) ?: 0)
        if (st in setOf(RideStatus.PAID, RideStatus.NO_DRIVER)) stopFollowingRide()
    }
    /**
     * Cancels before the trip starts, server first: the screen changes only once the server has cancelled. [done] gets null on
     * success, otherwise one honest sentence; the ride is then re-read and the screens show whatever its real status is
     * (the in-ride screen if the driver had already started it). Deals with a lost answer too: a ride found CANCELLED counts as done.
     */
    fun cancelRide(done: (String?) -> Unit) { val r = _ride.value ?: return; if (cancelling) return
        scope.launch { cancelling = true
            val msg = try { cancelNow(r) } finally { cancelling = false }
            done(msg) } }
    private suspend fun cancelNow(r: Ride): String? {
        try { Backend.advanceTask(r.id, "CANCELLED"); return closedByMe() }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            val t = runCatching { Backend.taskGeo(r.id) }.getOrNull() ?: return friendlyError(e)   // can't even read it: nothing has changed
            if (t.status == "CANCELLED") return closedByMe()
            applyRide(t)
            return when (t.status) { "IN_PROGRESS" -> "Your trip has already started, so it can't be cancelled here."; "COMPLETED", "PAID" -> "This trip is already finished."
                "NO_DRIVER" -> "Nobody took this request in time. You can ring again."; else -> friendlyError(e) }
        }
    }
    private fun closedByMe(): String? { stopFollowingRide(); _ride.value = null; return null }
    /** Clears a ride that has ended on its own (nobody accepted) once the rider leaves its screen. */
    fun dismissEndedRide() { if (_ride.value?.status == RideStatus.NO_DRIVER) { stopFollowingRide(); _ride.value = null } }
    /** The rider confirms they paid (UPI app or cash); the driver's screen picks it up. Once at a time; a lost answer is checked against the server. */
    fun payRide(method: String) { val r = _ride.value ?: return; if (paying || r.status != RideStatus.COMPLETED) return
        scope.launch { paying = true
            try {
                val paid = try { Backend.advanceTask(r.id, "PAID", paidWith = method).paidWith } catch (e: CancellationException) { throw e } catch (e: Exception) {
                    val t = runCatching { Backend.taskGeo(r.id) }.getOrNull()
                    if (t?.status == "PAID") t.paidWith else { t?.let { applyRide(it) }; throw e } }
                stopFollowingRide(); _ride.value = (_ride.value ?: r).copy(status = RideStatus.PAID, paidWith = paid ?: method)
            } catch (e: CancellationException) { throw e } catch (e: Exception) { toast(friendlyError(e)) } finally { paying = false } } }
    /** Posts the review against the driver's DRIVER listing; a driver without one can't be reviewed on the server yet. */
    fun finishRide(vote: Int?, comment: String) { val r = _ride.value ?: return; stopFollowingRide(); _ride.value = null
        if (vote == null) return
        val listing = rideDriver?.takeIf { it.profileId == r.driver?.id }?.listingId
        if (listing == null) { toast("${r.driver?.name?.substringBefore(' ') ?: "Your rider"} has no driver profile on Bucks yet, so your review wasn't posted."); return }
        go { Backend.review(listing, r.id, null, vote > 0, comment.trim()); toast("Thanks. Your review is public.") }
    }
    suspend fun contact(taskId: String): ContactRow? = Backend.contactFor(taskId)
    suspend fun task(taskId: String): TaskGeoRow? = Backend.taskGeo(taskId)
    suspend fun driverOf(taskId: String): TaskDriverRow? = Backend.taskDriver(taskId)

    // =====================================================================
    // Driver
    // =====================================================================
    /** The vehicle my presence is published for while online. */
    var vehicle by mutableStateOf<VehicleRow?>(null); private set
    private var heartbeatJob: Job? = null; private var ringJob: Job? = null; private var countdownJob: Job? = null; private var tripJob: Job? = null
    /** The presence-off write of the last time I went offline, so sign-out can wait for it before the login goes. */
    private var offJob: Job? = null
    private val nudges = Channel<Unit>(Channel.CONFLATED)
    /** Requests this driver declined, missed or dropped; they don't ring again. */
    private val passed = HashSet<String>()
    private var paidToastFor: String? = null
    /** Bumped by every action of mine on the trip, so a read of the task row that began before it can't undo it. */
    private var driverGen = 0

    /** Publishes presence for my cloud vehicle (matched by [plate], else the first one) and starts ringing. [onResult] false = stay offline. */
    fun setOnline(on: Boolean, plate: String?, onResult: (Boolean) -> Unit = {}) = scope.launch {
        try {
            val me = social.me ?: waitForMe() ?: run { toast("Still signing in. Try again in a moment."); onResult(false); return@launch }
            if (!on) { stopDriverLoops(); markOnline(false); Presence.meId = null
                offJob = vehicle?.let { v -> AppLife.scope.launch { withTimeoutOrNull(4_000) { runCatching { Backend.setPresence(me.id, v.id, v.kind, false, hereOrNull) } } } }
                onResult(true); return@launch }
            val mine = Backend.myVehicles(); vehicles = mine; val norm = plate?.uppercase()?.replace(" ", "")
            // Only a checked (ACTIVE) vehicle may go online; the presence policy refuses the others, so say why instead of failing.
            val active = mine.filter { it.status == "ACTIVE" }
            val v = active.firstOrNull { it.plate == norm } ?: active.firstOrNull()
            if (v == null) { toast(if (mine.isEmpty()) "Add your vehicle under My vehicles before going online." else "Bucks is still checking your vehicle. You can go online once it's active."); onResult(false); return@launch }
            Backend.setPresence(me.id, v.id, v.kind, true, hereOrNull)
            Presence.meId = me.id
            vehicle = v; markOnline(true); startDriverLoops(me.id, v); onResult(true)
        } catch (e: CancellationException) { throw e } catch (e: Exception) { toast(friendlyError(e)); onResult(false) }
    }
    private fun startDriverLoops(me: String, v: VehicleRow) {
        stopDriverLoops()
        // Keeps me visible to riders while standing still (presence unseen for 5 minutes drops off the map).
        heartbeatJob = scope.launch { while (isActive) { delay(60_000); runCatching { Backend.setPresence(me, v.id, v.kind, true, hereOrNull) } } }
        ringJob = scope.launch {
            val (channel, flow) = Backend.liveOpenTasks()
            val nudge = launch { runCatching { flow.collect { nudges.trySend(Unit) } } }
            try { while (isActive) { runCatching { pollRing() }; withTimeoutOrNull(5_000) { nudges.receive() } } }
            finally { nudge.cancel(); Backend.releaseChannel(channel) }
        }
    }
    private fun stopDriverLoops() { heartbeatJob?.cancel(); ringJob?.cancel(); heartbeatJob = null; ringJob = null; countdownJob?.cancel(); _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING }?.let { _driverRide.value = null } }

    /** Rings the nearest open request I haven't passed on, if I'm free. A ringing request that vanished was taken or cancelled. */
    private suspend fun pollRing() {
        val cur = _driverRide.value
        if (cur != null && cur.status != DriverRideStatus.RINGING) return
        if (_ride.value != null || busy || !social.hereKnown) return   // no real position yet: the map's default centre would ring the wrong city's requests
        val list = Backend.openTasksNear(here)
        if (busy) return   // a claim of mine started while the list was loading; the claim decides
        if (cur != null) { if (list.any { it.id == cur.id }) return
            val t = runCatching { Backend.taskGeo(cur.id) }.getOrElse { return }   // can't tell: keep the ring, the next poll asks again
            if (busy || _driverRide.value?.id != cur.id) return
            countdownJob?.cancel()
            // A claim of mine can land with both the answer and the retry lost (see claim): the request left the open list because it is mine now.
            t?.takeIf { ownedByMe(it) }?.let { adoptTrip(it); return }
            _driverRide.value = null; toast("That request was taken or cancelled.") }
        val next = list.firstOrNull { it.id !in passed } ?: return
        ringTask(next)
    }
    private suspend fun ringTask(t: TaskRow) {
        val geo = Backend.taskGeo(t.id) ?: return
        val who = runCatching { Backend.profiles(listOf(t.requesterId)).firstOrNull() }.getOrNull()
        who?.let { social.names[it.id] = it.name }
        val me = here; val delivery = geo.isDelivery
        val items = geo.orderItems ?: 0
        val dr = DriverRide(t.id, DriverRideStatus.RINGING, who?.name?.ifBlank { null } ?: "Customer", Trust(who?.trustUp ?: 0, who?.trustDown ?: 0),
            pickupAt = if (delivery) t.pickupLabel.ifBlank { "the shop" } + (if (items > 0) " · $items item${if (items > 1) "s" else ""}" else "") else t.pickupLabel.ifBlank { "Pick-up point" },
            dropAt = t.dropLabel.ifBlank { "Drop point" }, km = t.km, fare = t.fare, pin = "", secondsLeft = 15, pickupKm = round1(Geo.distanceKm(me, geo.pickup)),
            kind = vehicle?.kind?.let { kindOf(it) } ?: kindOf(t.vehicleKind), driver = me, pickup = geo.pickup, drop = geo.drop, customerPhone = "")
        _driverRide.value = dr
        startCountdown()
    }
    private fun startCountdown() {
        countdownJob?.cancel(); countdownJob = scope.launch { while (true) { delay(1_000); val cur = _driverRide.value ?: return@launch; if (cur.status != DriverRideStatus.RINGING) return@launch
            if (cur.secondsLeft <= 1) {
                // A trip that is mine (my claim landed, its answer was lost) is not a missed request.
                val mine = runCatching { Backend.taskGeo(cur.id) }.getOrNull()?.takeIf { ownedByMe(it) }
                if (!isActive) return@launch   // accepted or declined while the row was being read
                if (mine != null) { adoptTrip(mine); return@launch }
                _driverRide.value = null; passed += cur.id; toast("Missed that one. Stay online for the next request.")
                runCatching { Backend.passTask(cur.id, true) }; nudges.trySend(Unit); return@launch }
            _driverRide.value = cur.copy(secondsLeft = cur.secondsLeft - 1) } }
    }
    fun driverDecline() { val cur = _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING } ?: return
        countdownJob?.cancel(); passed += cur.id; _driverRide.value = null; toast("Passed. We'll send you the next one.")
        go { runCatching { Backend.passTask(cur.id, false) }; nudges.trySend(Unit) } }

    private sealed interface Claim { data object Won : Claim; data object Taken : Claim; data object Unreachable : Claim; class Refused(val message: String) : Claim }
    private fun ownedByMe(t: TaskGeoRow) = t.driverId == social.me?.id && t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS")
    private suspend fun adoptTrip(t: TaskGeoRow) { toast("It's yours. Your accept had gone through."); restoreDriverTrip(t) }
    private suspend fun isMine(id: String): Boolean = runCatching { Backend.taskGeo(id) }.getOrNull()?.let { ownedByMe(it) } == true
    /**
     * claim_task answers false only for "not claimable" (taken, too far, stale). A call that throws says nothing about the task:
     * a lost connection is retried once, and a lost *answer* is caught by reading the row (it may already be mine). The server
     * refusing with a sentence ('go online first', 'vehicle not verified', 'finish your current trip') is [Claim.Refused].
     */
    private suspend fun claim(id: String): Claim {
        repeat(2) { attempt ->
            try { return if (Backend.claimTask(id) || isMine(id)) Claim.Won else Claim.Taken }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (isServerRefusal(e)) return if (isMine(id)) Claim.Won else Claim.Refused(friendlyError(e)); if (attempt == 0) delay(600) }
        }
        return if (isMine(id)) Claim.Won else Claim.Unreachable
    }
    /** First driver to claim wins; otherwise "too late" and the next request rings. A lost connection keeps the ring so the driver can tap again. */
    fun driverAccept() { val cur = _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING } ?: return
        if (busy) return; countdownJob?.cancel(); driverGen++
        go { busy = true
            try {
                when (val res = claim(cur.id)) {
                    Claim.Won -> {
                        _driverRide.value = cur.copy(status = DriverRideStatus.TO_PICKUP, progress = 0f, secondsLeft = 0, driver = hereOrNull ?: cur.driver)
                        toast(if (cur.kind == VehicleKind.BIKE) "It's yours. Head to the shop to collect the order." else "It's yours. Head to the pick-up.")
                        loadCustomerPhone(cur.id); followDriverTask(cur.id) }
                    Claim.Taken -> { passed += cur.id; if (_driverRide.value?.id == cur.id) _driverRide.value = null; toast("Too late. Another rider took it, or it's no longer available."); nudges.trySend(Unit) }
                    Claim.Unreachable -> { if (_driverRide.value?.id == cur.id) { _driverRide.value = cur.copy(secondsLeft = max(cur.secondsLeft, 8)); startCountdown() }
                        toast("Couldn't reach Bucks. Try again.") }
                    is Claim.Refused -> { passed += cur.id; if (_driverRide.value?.id == cur.id) _driverRide.value = null; toast(res.message); runCatching { restoreFromServer() }; nudges.trySend(Unit) }
                }
            } finally { busy = false } }
    }
    private suspend fun loadCustomerPhone(id: String) { runCatching { Backend.contactFor(id)?.phone }.getOrNull()?.let { p -> _driverRide.value?.takeIf { it.id == id }?.let { _driverRide.value = it.copy(customerPhone = p) } } }
    private fun followDriverTask(id: String) {
        tripJob?.cancel()
        tripJob = scope.launch {
            val (channel, flow) = Backend.liveTask(id)
            val nudge = launch { runCatching { flow.collect { refreshDriverTask(id) } } }
            try { while (isActive) { refreshDriverTask(id); delay(5_000) } }
            finally { nudge.cancel(); Backend.releaseChannel(channel) }
        }
    }
    private fun driverStatusOf(server: String, local: DriverRideStatus): DriverRideStatus? = when (server) {
        "MATCHED" -> DriverRideStatus.TO_PICKUP; "ARRIVED" -> DriverRideStatus.ARRIVED; "IN_PROGRESS" -> DriverRideStatus.IN_RIDE
        "COMPLETED", "PAID" -> if (local == DriverRideStatus.RATE) DriverRideStatus.RATE else DriverRideStatus.DONE
        else -> null }
    /** Reads the task and follows it, unless an action of mine is in flight (its own answer, or the next read, decides). */
    private suspend fun refreshDriverTask(id: String) {
        val g = driverGen
        val t = runCatching { Backend.taskGeo(id) }.getOrNull() ?: return
        if (g != driverGen || busy || handingBack) return
        applyDriverTruth(id, t)
    }
    /** Puts the driver's screen where the server row says the trip is (forward or back). Returns true when the trip is gone from this driver. */
    private suspend fun applyDriverTruth(id: String, t: TaskGeoRow): Boolean {
        val cur = _driverRide.value?.takeIf { it.id == id } ?: return false
        if (t.status == "CANCELLED") { stopDriverTask(); _driverRide.value = null; toast(if (t.isDelivery) "This delivery was cancelled." else "The customer cancelled this ride."); nudges.trySend(Unit); return true }
        if (t.driverId != social.me?.id) { stopDriverTask(); passed += id; _driverRide.value = null; toast("This trip is no longer yours. It went back to other riders."); nudges.trySend(Unit); return true }
        val st = driverStatusOf(t.status, cur.status) ?: return false
        var next = cur
        if (st != cur.status) next = next.copy(status = st, progress = when { st == DriverRideStatus.DONE || st == DriverRideStatus.RATE -> 1f; st == DriverRideStatus.IN_RIDE -> 0f; else -> cur.progress })
        // What the customer says they paid with (they mark it on their phone); the server doesn't verify it.
        if (t.status == "PAID" && t.paidWith != null) { next = next.copy(paidWith = t.paidWith)
            if (paidToastFor != id) { paidToastFor = id; toast("The customer says they paid by ${payWord(t.paidWith)}. Check ${if (isCash(t.paidWith)) "you have the cash" else "your UPI app"} before you continue.") } }
        if (t.pinAttempts > cur.pinAttempts) next = next.copy(pinAttempts = t.pinAttempts, pinLocked = t.pinAttempts >= PIN_TRIES)
        if (next != cur) _driverRide.value = next
        if (cur.customerPhone.isBlank() && t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS", "COMPLETED")) loadCustomerPhone(id)
        return false
    }
    private fun stopDriverTask() { tripJob?.cancel(); tripJob = null }
    /** An action of mine failed or its answer was lost: read the trip again and show the truth, then say what went wrong. */
    private suspend fun failedDriverAction(id: String, e: Exception) {
        var msg = friendlyError(e)
        val before = _driverRide.value?.status
        val t = runCatching { Backend.taskGeo(id) }.getOrNull()
        if (t != null) {
            if (msg.startsWith("Cannot go from", true)) msg = "This trip had already moved on. Your screen now shows where it really is."
            if (msg.contains("too many wrong PIN", true)) update(id) { it.copy(pinAttempts = PIN_TRIES, pinLocked = true) }
            if (applyDriverTruth(id, t)) return
            // The call itself failed but the server has the change (a lost answer): say so instead of an error.
            if (_driverRide.value?.status != before && !msg.startsWith("This trip had already")) { toast("That had already gone through. Your screen is up to date."); return }
        }
        toast(msg)
    }

    /** Next step of the trip: arrived at pick-up, PIN to start (checked by the server), end of trip. */
    fun driverNext(pin: String = "") { val d = _driverRide.value ?: return; if (busy) return
        driverGen++
        go { busy = true
            try { when (d.status) {
                DriverRideStatus.TO_PICKUP -> { Backend.advanceTask(d.id, "ARRIVED"); update(d.id) { it.copy(status = DriverRideStatus.ARRIVED) }
                    toast(if (d.kind == VehicleKind.BIKE) "You're at the shop. Call the customer for the 4-digit pickup PIN." else "You're at the pick-up. Ask the customer for their PIN.") }
                DriverRideStatus.ARRIVED -> { if (pin.length != 4) { toast("Enter the 4-digit PIN."); return@go }
                    if (d.pinLocked) { toast("Too many wrong PINs. Hand this trip back."); return@go }
                    // A wrong PIN doesn't raise (contract C1): the row comes back still ARRIVED with the attempts counted. Only IN_PROGRESS means it matched.
                    val t = Backend.advanceTask(d.id, "IN_PROGRESS", pin = pin)
                    if (t.status == "IN_PROGRESS") { update(d.id) { it.copy(status = DriverRideStatus.IN_RIDE, progress = 0f) }; toast("PIN matched. Off you go.") }
                    else { val left = (PIN_TRIES - t.pinAttempts).coerceAtLeast(0); update(d.id) { it.copy(pinAttempts = t.pinAttempts, pinLocked = left == 0) }
                        toast(if (left == 0) "That PIN doesn't match, and you have no tries left. Hand this trip back." else "That PIN doesn't match. $left ${if (left == 1) "try" else "tries"} left.") } }
                DriverRideStatus.IN_RIDE -> { Backend.advanceTask(d.id, "COMPLETED"); update(d.id) { it.copy(status = DriverRideStatus.DONE, progress = 1f) } }
                else -> {}
            } } catch (e: CancellationException) { throw e } catch (e: Exception) { failedDriverAction(d.id, e) } finally { busy = false } }
    }
    private fun update(id: String, f: (DriverRide) -> DriverRide) { driverGen++; _driverRide.value?.takeIf { it.id == id }?.let { _driverRide.value = f(it) } }
    /** Cash or UPI collected, once and only from the payment step; false when there was nothing to move (a second tap). The customer marks PAID on their phone. */
    fun driverPaid(method: String): Boolean { val d = _driverRide.value ?: return false; if (d.status != DriverRideStatus.DONE) return false
        driverGen++; _driverRide.value = d.copy(status = DriverRideStatus.RATE, paidWith = method); return true }
    /** Trip closed on this phone (after rating the customer); ring the next request. */
    fun closeTrip() { stopDriverTask(); _driverRide.value = null; nudges.trySend(Unit) }
    /** Hands the request back so it rings other drivers. Allowed from the way to the pick-up and at the pick-up, not once the PIN is in. [done] says whether it happened. */
    fun driverCancel(done: (Boolean) -> Unit = {}) { val d = _driverRide.value ?: return
        if (d.status == DriverRideStatus.RINGING) { driverDecline(); done(true); return }
        if (d.status != DriverRideStatus.TO_PICKUP && d.status != DriverRideStatus.ARRIVED) { toast("A trip that has started can't be handed back."); done(false); return }
        if (handingBack || busy) return
        driverGen++
        scope.launch { handingBack = true
            try { Backend.advanceTask(d.id, "SEARCHING"); stopDriverTask(); passed += d.id; _driverRide.value = null; nudges.trySend(Unit); done(true) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { failedDriverAction(d.id, e); done(false) }
            finally { handingBack = false } } }
    /** Real position: moves me on the map and updates distance left; the server gets it from DriverLocationService. */
    fun driverMoved(p: LatLng) {
        val dr = _driverRide.value?.takeIf { it.status in setOf(DriverRideStatus.TO_PICKUP, DriverRideStatus.ARRIVED, DriverRideStatus.IN_RIDE) } ?: return
        val pickup = dr.pickup ?: return; val drop = dr.drop ?: return
        val progress = if (dr.status == DriverRideStatus.IN_RIDE) (1 - Geo.distanceKm(p, drop) / Geo.distanceKm(pickup, drop).coerceAtLeast(0.1)).toFloat().coerceIn(0f, 1f) else 0f
        _driverRide.value = dr.copy(driver = p, pickupKm = round1(Geo.distanceKm(p, pickup)), progress = progress)
    }

    // =====================================================================
    // Resume, map feed, payment link, lifecycle
    // =====================================================================
    /** After sign-in: pick up the trip a killed app was on, as rider or driver. */
    fun resume() = go {
        waitForMe() ?: return@go
        refreshVehicles()
        runCatching { Backend.settingValue("ring_window_seconds") }.getOrNull()?.takeIf { it >= 30 }?.let { ringWindowS = it.toLong() }
        restoreFromServer()
    }
    /** Follows my open trip on the server, as rider or driver, unless this phone already has it. */
    private suspend fun restoreFromServer() {
        val me = social.me ?: return
        val t = Backend.myOpenTask() ?: return
        if (_ride.value?.id == t.id || _driverRide.value?.id == t.id) return
        if (t.driverId == me.id) restoreDriverTrip(t)
        else if (t.requesterId == me.id && t.type == "RIDE") restoreRide(t)
        // A buyer's delivery is followed from the order page (DELIVERY_TRACK); nothing to restore here.
    }
    private suspend fun restoreRide(t: TaskGeoRow) {
        rideDriver = null; ridePhone = null
        _ride.value = Ride(t.id, kindOf(t.vehicleKind), placeOf(t), t.fare, rideStatus(t.status), t.pin, pickupLabel = t.pickupLabel)
        applyRide(t); if (rideJob == null && _ride.value != null) followRide(t.id)
    }
    private suspend fun restoreDriverTrip(t: TaskGeoRow) {
        val status = when (t.status) { "MATCHED" -> DriverRideStatus.TO_PICKUP; "ARRIVED" -> DriverRideStatus.ARRIVED; "IN_PROGRESS" -> DriverRideStatus.IN_RIDE; "COMPLETED" -> DriverRideStatus.DONE; else -> return }
        val who = runCatching { Backend.profiles(listOf(t.requesterId)).firstOrNull() }.getOrNull()
        val me = here; val items = t.orderItems ?: 0
        _driverRide.value = DriverRide(t.id, status, who?.name?.ifBlank { null } ?: "Customer", Trust(who?.trustUp ?: 0, who?.trustDown ?: 0),
            pickupAt = if (t.isDelivery) t.pickupLabel.ifBlank { "the shop" } + (if (items > 0) " · $items item${if (items > 1) "s" else ""}" else "") else t.pickupLabel.ifBlank { "Pick-up point" },
            dropAt = t.dropLabel.ifBlank { "Drop point" }, km = t.km, fare = t.fare, pin = "", secondsLeft = 0, pickupKm = round1(Geo.distanceKm(me, t.pickup)),
            kind = kindOf(t.vehicleKind), driver = me, pickup = t.pickup, drop = t.drop, progress = if (status == DriverRideStatus.DONE) 1f else 0f, paidWith = if (t.status == "PAID") t.paidWith else null,
            pinAttempts = t.pinAttempts, pinLocked = t.pinAttempts >= PIN_TRIES)
        loadCustomerPhone(t.id); followDriverTask(t.id)
    }

    /** Reloads [vehicles] (after sign-in and when Home opens; the manage screens keep their own list). */
    suspend fun refreshVehicles() { runCatching { Backend.myVehicles() }.onSuccess { vehicles = it } }
    fun reloadVehicles() { scope.launch { refreshVehicles() } }

    private var driversJob: Job? = null; private var mapViewers = 0
    /** Polls `online_drivers_near` every 15 s while a map is showing (45 s otherwise) so pins and "n riders nearby" stay fresh. */
    fun startDriversFeed() { if (driversJob?.isActive == true) return
        driversJob = scope.launch { while (isActive) { refreshDrivers(); delay(if (mapViewers > 0) 15_000 else 45_000) } } }
    fun stopDriversFeed() { driversJob?.cancel(); driversJob = null; _drivers.value = emptyList() }
    suspend fun refreshDrivers() { runCatching { Backend.onlineDriversNear(here, 10_000) }.onSuccess { rows -> _drivers.value = rows.mapNotNull { r ->
        val kind = runCatching { VehicleKind.valueOf(r.kind) }.getOrNull() ?: return@mapNotNull null
        val (x, y) = Geo.toPercent(LatLng(r.lat, r.lng))
        Driver(r.profileId, r.name.ifBlank { "Rider" }, kind, r.plate, r.model, x, y, round1(Geo.distanceKm(here, LatLng(r.lat, r.lng))), r.up, r.down, true, at = LatLng(r.lat, r.lng)) } } }
    /** Call from a screen that shows the map (DisposableEffect) to poll faster while it is visible. */
    fun mapShown() { mapViewers++ }
    fun mapHidden() { mapViewers = max(0, mapViewers - 1) }

    fun refreshPaymentLink() = go { val me = social.me ?: waitForMe() ?: return@go; paymentLink = Backend.myPaymentLink(me.id); paymentLinkLoaded = true }
    /** Saves a decoded `upi://pay?...` link as my payment QR. */
    fun savePaymentLink(uri: String, then: () -> Unit = {}) = go { val me = social.me ?: return@go
        if (!uri.startsWith("upi://pay", ignoreCase = true)) { toast("That QR isn't a UPI payment code."); return@go }
        busy = true
        try { Backend.setPaymentLink(me.id, uri); paymentLink = uri; paymentLinkLoaded = true; toast("Saved. Customers can now pay you by UPI."); then() } finally { busy = false } }
    fun removePaymentLink() = go { val me = social.me ?: return@go; Backend.clearPaymentLink(me.id); paymentLink = null; toast("Payment QR removed. Customers can't pay you by UPI until you add one again.") }

    /**
     * Sign-out, account deletion or a cleared ViewModel: presence off, everything cancelled, nothing left on screen. The presence call
     * runs on the app scope (this class's own scope is gone by then); sign-out waits for the returned job before it drops the login.
     */
    fun signedOut(): Job? {
        stopFollowingRide(); stopDriverTask(); stopDriverLoops(); stopDriversFeed()
        val off = if (online) AppLife.scope.launch { Presence.offline() } else offJob?.takeIf { it.isActive }
        markOnline(false); vehicle = null; vehicles = emptyList(); passed.clear(); _ride.value = null; _driverRide.value = null; rideDriver = null; ridePhone = null; paymentLink = null; paymentLinkLoaded = false
        cancelling = false; paying = false; handingBack = false
        return off
    }
}

/** "cash" for the customer-facing words; anything else the server holds is a UPI payment. */
fun isCash(paidWith: String?) = paidWith?.contains("cash", ignoreCase = true) == true
fun payWord(paidWith: String?) = when { paidWith.isNullOrBlank() -> "cash or UPI"; isCash(paidWith) -> "cash"; else -> paidWith }

/** A UPI deep link with the amount and note filled in: any UPI app opens it with the driver's details from their QR. */
fun upiPayLink(base: String, amountRupees: Int, note: String): String {
    val u = Uri.parse(base.trim())
    val b = Uri.Builder().scheme("upi").authority("pay")
    runCatching { u.queryParameterNames }.getOrDefault(emptySet()).filter { it !in setOf("am", "tn", "cu") }.forEach { k -> u.getQueryParameter(k)?.let { b.appendQueryParameter(k, it) } }
    b.appendQueryParameter("am", "$amountRupees.00").appendQueryParameter("cu", "INR").appendQueryParameter("tn", note)
    return b.build().toString()
}
/** "Payments go to <pn> (<pa>)" from a UPI link; null when it has no payee address. */
fun upiPayee(link: String): Pair<String, String>? {
    val u = runCatching { Uri.parse(link.trim()) }.getOrNull() ?: return null
    val pa = runCatching { u.getQueryParameter("pa") }.getOrNull()?.takeIf { it.isNotBlank() } ?: return null
    val pn = runCatching { u.getQueryParameter("pn") }.getOrNull()?.takeIf { it.isNotBlank() } ?: pa.substringBefore('@')
    return pn to pa
}
