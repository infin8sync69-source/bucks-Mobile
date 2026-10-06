package com.bucks.app.ui

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.bucks.app.data.*
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

/**
 * Cloud dispatch: rides and deliveries on Supabase `tasks`, replacing the Firestore ride code.
 *
 * Rider side: [requestRide] creates the task and follows it (realtime on `tasks` + a 5-second poll of `tasks_geo`),
 * publishing the mapped [Ride] through [ride]. Driver side: [setOnline] publishes presence with a heartbeat and
 * rings the nearest open task every 5 s (nudged by realtime) as a [DriverRide] through [driverRide]; accept / pass /
 * advance go through the server functions, which check the PIN. [BucksViewModel] mirrors the two flows into
 * UiState and navigates on status changes, so the existing ride screens keep working unchanged in demo mode.
 * Every action reports a failure as a toast.
 */
class Dispatch(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
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

    private val here get() = social.here
    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Throwable): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }
    private fun round1(km: Double) = (km * 10).roundToInt() / 10.0
    private suspend fun waitForMe(): ProfileRow? { var n = 0; while (social.me == null && n++ < 40) delay(500); return social.me }

    // =====================================================================
    // Rider
    // =====================================================================
    private var rideJob: Job? = null; private var noDriverJob: Job? = null
    private var rideDriver: TaskDriverRow? = null; private var ridePhone: String? = null

    /** Books an auto or cab: creates the task, then follows it. Bikes carry goods only. */
    fun requestRide(kind: VehicleKind, from: LatLng, fromLabel: String, dest: Place, to: LatLng, fare: Int) {
        if (!kind.carriesPassengers) { toast("Bikes carry goods only. Choose an auto or a cab."); return }
        if (busy) return
        go { busy = true
            try {
                val t = Backend.requestRide(kind, from, fromLabel, to, dest.name, dest.km, fare)
                rideDriver = null; ridePhone = null
                _ride.value = Ride(t.id, kind, dest, fare, RideStatus.SEARCHING, t.pin)
                startNoDriverTimer(t.id); followRide(t.id)
            } finally { busy = false } }
    }
    private fun followRide(id: String) {
        rideJob?.cancel()
        rideJob = scope.launch {
            val (channel, flow) = Backend.liveTask(id)
            val nudge = launch { runCatching { flow.collect { refreshRide(id) } } }
            try { while (isActive) { refreshRide(id); delay(5_000) } }
            finally { nudge.cancel(); scope.launch { Backend.closeChannel(channel) } }
        }
    }
    private suspend fun refreshRide(id: String) { runCatching { Backend.taskGeo(id) }.getOrNull()?.let { if (_ride.value?.id == id) applyRide(it) } }
    /** Stop ringing after 90 s so the rider can retry or switch vehicle type. */
    private fun startNoDriverTimer(id: String) { noDriverJob?.cancel(); noDriverJob = scope.launch { delay(90_000)
        // advance_task returns the plain tasks row; the rider's Ride is mapped from tasks_geo, so re-read that.
        if (_ride.value?.id == id && _ride.value?.status == RideStatus.SEARCHING) runCatching { Backend.advanceTask(id, "NO_DRIVER") }.onSuccess { refreshRide(id) } } }
    private fun stopFollowingRide() { rideJob?.cancel(); rideJob = null; noDriverJob?.cancel(); noDriverJob = null }

    private fun rideStatus(s: String) = when (s) { "SEARCHING" -> RideStatus.SEARCHING; "MATCHED" -> RideStatus.MATCHED; "ARRIVED" -> RideStatus.ARRIVED; "IN_PROGRESS" -> RideStatus.IN_RIDE
        "COMPLETED" -> RideStatus.COMPLETED; "PAID" -> RideStatus.PAID; "NO_DRIVER" -> RideStatus.NO_DRIVER; else -> RideStatus.CANCELLED }
    private fun placeOf(t: TaskGeoRow): Place { val (x, y) = Geo.toPercent(t.drop); return Place(t.dropLabel.ifBlank { Geo.nearestArea(t.drop) }, x, y, t.km, at = t.drop) }
    private fun kindOf(s: String) = runCatching { VehicleKind.valueOf(s) }.getOrDefault(VehicleKind.AUTO)

    /** Maps a task row onto the rider's [Ride]; fetches the driver's name, vehicle and phone once per driver. */
    private suspend fun applyRide(t: TaskGeoRow) {
        val prev = _ride.value; val st = rideStatus(t.status); val kind = kindOf(t.vehicleKind)
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
        val eta = if (st in setOf(RideStatus.MATCHED, RideStatus.ARRIVED)) pos?.let { max(1, (Geo.distanceKm(it, t.pickup) * 2.5).roundToInt()) } ?: (prev?.etaMin ?: 0) else 0
        val progress = when {
            st == RideStatus.IN_RIDE && pos != null -> (1 - Geo.distanceKm(pos, t.drop) / t.km.coerceAtLeast(0.1)).toFloat().coerceIn(0f, 1f)
            st == RideStatus.COMPLETED || st == RideStatus.PAID -> 1f
            else -> prev?.progress ?: 0f }
        _ride.value = Ride(t.id, kind, placeOf(t), t.fare, st, t.pin, driver, dx, dy, eta, progress, t.paidWith ?: prev?.paidWith, prev?.reason, prev?.signature ?: "", driverAt = drvAt)
        if (st == RideStatus.SEARCHING && prev != null && prev.status != RideStatus.SEARCHING) startNoDriverTimer(t.id)
        if (st in setOf(RideStatus.PAID, RideStatus.CANCELLED, RideStatus.NO_DRIVER)) stopFollowingRide()
    }
    /**
     * Cancel before the trip starts; the server refuses once the driver has entered the PIN. The ride stays on screen until the server agrees,
     * so a refusal never leaves the rider without their trip. [reason] is a CancelReasons.rider code (required once a driver accepted).
     */
    fun cancelRide(reason: String?, note: String = "", onDone: (Boolean) -> Unit = {}) { val r = _ride.value ?: run { onDone(true); return }
        scope.launch {
            try { Backend.cancelTask(r.id, reason, note); stopFollowingRide(); _ride.value = null; onDone(true) }
            catch (e: Exception) {
                val m = friendly(e)
                // Already cancelled elsewhere (the realtime update raced us): same result for the rider.
                if (m.contains("it is cancelled")) { stopFollowingRide(); _ride.value = null; onDone(true) } else { toast(m); onDone(false) }
            }
        } }
    /** The rider confirms they paid (UPI app or cash); the driver's screen picks it up. */
    fun payRide(method: String) { val r = _ride.value ?: return
        go { val t = Backend.advanceTask(r.id, "PAID", paidWith = method); stopFollowingRide(); _ride.value = r.copy(status = RideStatus.PAID, paidWith = t.paidWith ?: method) } }
    /** Posts the review against the driver's DRIVER listing; a driver without one can't be reviewed on the server yet. */
    fun finishRide(vote: Int?, comment: String) { val r = _ride.value ?: return; stopFollowingRide(); _ride.value = null
        if (vote == null) return
        val listing = rideDriver?.takeIf { it.profileId == r.driver?.id }?.listingId
        if (listing == null) { toast("${r.driver?.name?.substringBefore(' ') ?: "Your rider"} has no driver profile on Bucks yet, so this review stays on your phone."); return }
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
    private val nudges = Channel<Unit>(Channel.CONFLATED)
    /** Requests this driver declined, missed or dropped; they don't ring again. */
    private val passed = HashSet<String>()
    private var paidToastFor: String? = null

    /** Publishes presence for my cloud vehicle (matched by [plate], else the first one) and starts ringing. [onResult] false = stay offline. */
    fun setOnline(on: Boolean, plate: String?, onResult: (Boolean) -> Unit = {}) = scope.launch {
        try {
            val me = social.me ?: waitForMe() ?: run { toast("Still signing in. Try again in a moment."); onResult(false); return@launch }
            if (!on) { stopDriverLoops(); markOnline(false); vehicle?.let { v -> runCatching { Backend.setPresence(me.id, v.id, v.kind, false, here) } }; onResult(true); return@launch }
            val mine = Backend.myVehicles(); vehicles = mine; val norm = plate?.uppercase()?.replace(" ", "")
            // Only a checked (ACTIVE) vehicle may go online; the presence policy refuses the others, so say why instead of failing.
            val active = mine.filter { it.status == "ACTIVE" }
            val v = active.firstOrNull { it.plate == norm } ?: active.firstOrNull()
            if (v == null) { toast(if (mine.isEmpty()) "Add your vehicle under My vehicles before going online." else "Bucks is still checking your vehicle. You can go online once it's active."); onResult(false); return@launch }
            Backend.setPresence(me.id, v.id, v.kind, true, here)
            vehicle = v; markOnline(true); startDriverLoops(me.id, v); onResult(true)
        } catch (e: Exception) { toast(friendly(e)); onResult(false) }
    }
    private fun startDriverLoops(me: String, v: VehicleRow) {
        stopDriverLoops()
        // Keeps me visible to riders while standing still (presence unseen for 5 minutes drops off the map).
        heartbeatJob = scope.launch { while (isActive) { delay(60_000); runCatching { Backend.setPresence(me, v.id, v.kind, true, here) } } }
        ringJob = scope.launch {
            val (channel, flow) = Backend.liveOpenTasks()
            val nudge = launch { runCatching { flow.collect { nudges.trySend(Unit) } } }
            try { while (isActive) { runCatching { pollRing() }; withTimeoutOrNull(5_000) { nudges.receive() } } }
            finally { nudge.cancel(); scope.launch { Backend.closeChannel(channel) } }
        }
    }
    private fun stopDriverLoops() { heartbeatJob?.cancel(); ringJob?.cancel(); heartbeatJob = null; ringJob = null; countdownJob?.cancel(); _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING }?.let { _driverRide.value = null } }

    /** Rings the nearest open request I haven't passed on, if I'm free. A ringing request that vanished was taken or cancelled. */
    private suspend fun pollRing() {
        val cur = _driverRide.value
        if (cur != null && cur.status != DriverRideStatus.RINGING) return
        if (_ride.value != null) return
        val list = Backend.openTasksNear(here)
        if (cur != null) { if (list.any { it.id == cur.id }) return
            countdownJob?.cancel(); _driverRide.value = null; toast("That request was taken or cancelled.") }
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
            pickupAt = if (delivery) t.pickupLabel.ifBlank { "the shop" } + (if (items > 0) " · $items item${if (items > 1) "s" else ""}" else "") else t.pickupLabel.ifBlank { Geo.nearestArea(geo.pickup) },
            dropAt = t.dropLabel.ifBlank { Geo.nearestArea(geo.drop) }, km = t.km, fare = t.fare, pin = "", secondsLeft = 15, pickupKm = round1(Geo.distanceKm(me, geo.pickup)),
            kind = vehicle?.kind?.let { kindOf(it) } ?: kindOf(t.vehicleKind), driver = me, pickup = geo.pickup, drop = geo.drop, customerPhone = "")
        _driverRide.value = dr
        startCountdown()
    }
    private fun startCountdown() {
        countdownJob?.cancel(); countdownJob = scope.launch { while (true) { delay(1_000); val cur = _driverRide.value ?: return@launch; if (cur.status != DriverRideStatus.RINGING) return@launch
            if (cur.secondsLeft <= 1) { _driverRide.value = null; passed += cur.id; toast("Missed that one. Stay online for the next request.")
                runCatching { Backend.passTask(cur.id, true) }; nudges.trySend(Unit); return@launch }
            _driverRide.value = cur.copy(secondsLeft = cur.secondsLeft - 1) } }
    }
    fun driverDecline() { val cur = _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING } ?: return
        countdownJob?.cancel(); passed += cur.id; _driverRide.value = null; toast("Passed. We'll send you the next one.")
        go { runCatching { Backend.passTask(cur.id, false) }; nudges.trySend(Unit) } }
    /** First driver to claim wins; otherwise "too late" and the next request rings. */
    fun driverAccept() { val cur = _driverRide.value?.takeIf { it.status == DriverRideStatus.RINGING } ?: return
        if (busy) return; countdownJob?.cancel()
        go { busy = true
            try {
                val ok = runCatching { Backend.claimTask(cur.id) }.getOrElse { toast(friendly(it)); false }
                if (!ok) { passed += cur.id; if (_driverRide.value?.id == cur.id) _driverRide.value = null; toast("Too late. Another rider took it."); nudges.trySend(Unit); return@go }
                _driverRide.value = cur.copy(status = DriverRideStatus.TO_PICKUP, progress = 0f, secondsLeft = 0, driver = here)
                toast(if (cur.kind == VehicleKind.BIKE) "It's yours. Head to the shop to collect the order." else "It's yours. Head to the pick-up.")
                loadCustomerPhone(cur.id); followDriverTask(cur.id)
            } finally { busy = false } }
    }
    private suspend fun loadCustomerPhone(id: String) { runCatching { Backend.contactFor(id)?.phone }.getOrNull()?.let { p -> _driverRide.value?.takeIf { it.id == id }?.let { _driverRide.value = it.copy(customerPhone = p) } } }
    private fun followDriverTask(id: String) {
        tripJob?.cancel()
        tripJob = scope.launch {
            val (channel, flow) = Backend.liveTask(id)
            val nudge = launch { runCatching { flow.collect { refreshDriverTask(id) } } }
            try { while (isActive) { refreshDriverTask(id); delay(5_000) } }
            finally { nudge.cancel(); scope.launch { Backend.closeChannel(channel) } }
        }
    }
    private suspend fun refreshDriverTask(id: String) {
        val t = runCatching { Backend.taskGeo(id) }.getOrNull() ?: return
        val cur = _driverRide.value?.takeIf { it.id == id } ?: return
        when (t.status) {
            "CANCELLED" -> { stopDriverTask(); _driverRide.value = null; toast(if (t.isDelivery) "This delivery was cancelled." else "The customer cancelled this ride."); nudges.trySend(Unit) }
            "PAID" -> if (t.paidWith != null && paidToastFor != id) { paidToastFor = id; toast("The customer says they paid by ${t.paidWith}.") }
            "NO_DRIVER", "SEARCHING" -> if (cur.status != DriverRideStatus.RINGING && t.driverId == null) { stopDriverTask(); _driverRide.value = null; nudges.trySend(Unit) }
        }
        if (cur.customerPhone.isBlank() && t.status in setOf("MATCHED", "ARRIVED", "IN_PROGRESS", "COMPLETED")) loadCustomerPhone(id)
    }
    private fun stopDriverTask() { tripJob?.cancel(); tripJob = null }

    /** Next step of the trip: arrived at pick-up, PIN to start (checked by the server), end of trip. */
    fun driverNext(pin: String = "") { val d = _driverRide.value ?: return; if (busy) return
        go { busy = true
            try { when (d.status) {
                DriverRideStatus.TO_PICKUP -> { Backend.advanceTask(d.id, "ARRIVED"); update(d.id) { it.copy(status = DriverRideStatus.ARRIVED) }
                    toast(if (d.kind == VehicleKind.BIKE) "You're at the shop. Call the customer for the 4-digit pickup PIN." else "You're at the pick-up. Ask the customer for their PIN.") }
                DriverRideStatus.ARRIVED -> { if (pin.length != 4) { toast("Enter the 4-digit PIN."); return@go }
                    Backend.advanceTask(d.id, "IN_PROGRESS", pin = pin); update(d.id) { it.copy(status = DriverRideStatus.IN_RIDE, progress = 0f) }; toast("PIN matched. Off you go.") }
                DriverRideStatus.IN_RIDE -> { Backend.advanceTask(d.id, "COMPLETED"); update(d.id) { it.copy(status = DriverRideStatus.DONE, progress = 1f) } }
                else -> {}
            } } finally { busy = false } }
    }
    private fun update(id: String, f: (DriverRide) -> DriverRide) { _driverRide.value?.takeIf { it.id == id }?.let { _driverRide.value = f(it) } }
    /** Cash or UPI collected; the rider marks the task PAID on their side. */
    fun driverPaid(method: String) { val d = _driverRide.value ?: return; _driverRide.value = d.copy(status = DriverRideStatus.RATE, paidWith = method) }
    /** Trip closed on this phone (after rating the customer); ring the next request. */
    fun closeTrip() { stopDriverTask(); _driverRide.value = null; nudges.trySend(Unit) }
    /** Hands the request back so it rings other drivers. Allowed until the PIN is entered; [reason] is a CancelReasons.driver code. */
    fun driverCancel(reason: String?, note: String = "", onDone: (Boolean) -> Unit = {}) { val d = _driverRide.value ?: run { onDone(true); return }
        if (d.status == DriverRideStatus.RINGING) { driverDecline(); onDone(true); return }
        scope.launch {
            try { Backend.releaseTask(d.id, reason ?: "OTHER", note); stopDriverTask(); passed += d.id; _driverRide.value = null; nudges.trySend(Unit); onDone(true) }
            catch (e: Exception) { toast(friendly(e)); onDone(false) }
        } }
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
        val me = waitForMe() ?: return@go
        refreshVehicles()
        val t = Backend.myOpenTask() ?: return@go
        if (t.driverId == me.id) restoreDriverTrip(t)
        else if (t.requesterId == me.id && t.type == "RIDE") { rideDriver = null; ridePhone = null; _ride.value = Ride(t.id, kindOf(t.vehicleKind), placeOf(t), t.fare, rideStatus(t.status), t.pin); applyRide(t)
            if (t.status == "SEARCHING") startNoDriverTimer(t.id); if (rideJob == null) followRide(t.id) }
        // A buyer's delivery is followed from the order page (DELIVERY_TRACK); nothing to restore here.
    }
    private suspend fun restoreDriverTrip(t: TaskGeoRow) {
        val status = when (t.status) { "MATCHED" -> DriverRideStatus.TO_PICKUP; "ARRIVED" -> DriverRideStatus.ARRIVED; "IN_PROGRESS" -> DriverRideStatus.IN_RIDE; "COMPLETED" -> DriverRideStatus.DONE; else -> return }
        val who = runCatching { Backend.profiles(listOf(t.requesterId)).firstOrNull() }.getOrNull()
        val me = here; val items = t.orderItems ?: 0
        _driverRide.value = DriverRide(t.id, status, who?.name?.ifBlank { null } ?: "Customer", Trust(who?.trustUp ?: 0, who?.trustDown ?: 0),
            pickupAt = if (t.isDelivery) t.pickupLabel.ifBlank { "the shop" } + (if (items > 0) " · $items item${if (items > 1) "s" else ""}" else "") else t.pickupLabel.ifBlank { Geo.nearestArea(t.pickup) },
            dropAt = t.dropLabel.ifBlank { Geo.nearestArea(t.drop) }, km = t.km, fare = t.fare, pin = "", secondsLeft = 0, pickupKm = round1(Geo.distanceKm(me, t.pickup)),
            kind = kindOf(t.vehicleKind), driver = me, pickup = t.pickup, drop = t.drop, progress = if (status == DriverRideStatus.DONE) 1f else 0f, paidWith = if (t.status == "PAID") t.paidWith else null)
        loadCustomerPhone(t.id); followDriverTask(t.id)
    }

    /** Reloads [vehicles] (after sign-in; the manage screens keep their own list). */
    suspend fun refreshVehicles() { runCatching { Backend.myVehicles() }.onSuccess { vehicles = it } }

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

    /** Sign-out or account deletion: presence off, everything cancelled, nothing left on screen. */
    fun signedOut() {
        val me = social.me; val v = vehicle
        stopFollowingRide(); stopDriverTask(); stopDriverLoops(); stopDriversFeed()
        if (online && me != null && v != null) scope.launch { runCatching { Backend.setPresence(me.id, v.id, v.kind, false, here) } }
        markOnline(false); vehicle = null; vehicles = emptyList(); passed.clear(); _ride.value = null; _driverRide.value = null; rideDriver = null; ridePhone = null; paymentLink = null; paymentLinkLoaded = false
    }
}

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
