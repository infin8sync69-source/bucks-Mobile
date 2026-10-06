import Foundation
import Observation

/// Wrong PINs a driver may try before the server locks the trip (contract C1).
public let pinTries = 5
/// Trips the server accepts: shorter or longer raise 'that trip is too short / too far' (contract C3).
public let minTripKm = 0.2
public let maxTripKm = 150.0
/// How long a request rings before it is given up when the server's ring_window_seconds can't be read (schema default).
private let ringWindowDefaultS = 180

/// What Dispatch needs from the signed-in session.
@MainActor
public protocol DispatchHost: AnyObject {
    var me: ProfileRow? { get }
    /// My position for the map. Only a real fix when `hereKnown`.
    var here: LatLng { get }
    var hereKnown: Bool { get }
    var names: [String: String] { get set }
    func toast(_ message: String)
}

/// Cloud dispatch: rides and deliveries on Supabase `tasks` (port of Dispatch.kt).
///
/// Rider side: `requestRide` creates the task and follows it (a 5-second poll of `tasks_geo`), publishing the mapped `Ride` through
/// `ride`. Driver side: `setOnline` publishes presence with a heartbeat and rings the nearest open task every 5 s as a `DriverRide`
/// through `driverRide`; accept / pass / advance go through the server functions, which check the PIN.
/// The server is the truth: after a failed or lost call the task row is read again and the screen follows it, and a cancel only
/// changes the screen once the server has cancelled. Every action reports a failure as a toast.
@MainActor @Observable
public final class Dispatch {
    public var enabled: Bool { Backend.shared.enabled }
    /// The rider's current trip (nil when there is none). Only this class writes it.
    public private(set) var ride: Ride?
    /// The driver's ringing request or active trip.
    public private(set) var driverRide: DriverRide?
    /// Online drivers around me, for the map pins and "n riders nearby".
    public private(set) var drivers: [Driver] = []
    /// My UPI payment link (decoded from the QR I uploaded), or nil.
    public private(set) var paymentLink: String?
    public private(set) var paymentLinkLoaded = false
    /// True while presence says I'm online.
    public private(set) var online = false
    /// My vehicles on the server (owned or driven), loaded after sign-in and whenever I go online; the online switch uses the ACTIVE ones.
    public private(set) var vehicles: [VehicleRow] = []
    /// True while a request is being sent or a claim is in flight (buttons show progress).
    public private(set) var busy = false
    /// In-flight guards for the buttons that must not fire twice: the rider's cancel and payment, the driver's hand-back.
    public private(set) var cancelling = false
    public private(set) var paying = false
    public private(set) var handingBack = false
    /// Seconds a request rings before it is given up: the server's ring_window_seconds, read after sign-in.
    public private(set) var ringWindowS = ringWindowDefaultS
    /// The vehicle my presence is published for while online.
    public private(set) var vehicle: VehicleRow?

    @ObservationIgnored private weak var host: DispatchHost?
    @ObservationIgnored private let onRideClosed: (String) -> Void
    @ObservationIgnored private var backend: Backend { Backend.shared }

    public init(host: DispatchHost, onRideClosed: @escaping (String) -> Void = { _ in }) {
        self.host = host; self.onRideClosed = onRideClosed
        // The screen turning off (or Bucks being left) mid-ring turns the buzz into the notification: the request is still open and would expire unseen.
        AppLife.shared.observeForeground { [weak self] fg in
            guard !fg, let self, let r = self.driverRide, r.status == .ringing else { return }
            RingAlert.ring(r)
        }
    }

    private func toast(_ m: String) { host?.toast(m) }
    private var here: LatLng { host?.here ?? Geo.center }
    /// My position for the server, or nil while no real fix has arrived (never the map's default centre).
    private var hereOrNil: LatLng? { (host?.hereKnown ?? false) ? host?.here : nil }
    private var meId: String? { host?.me?.id }

    @discardableResult
    private func go(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { do { try await block() } catch is CancellationError {} catch { toast(friendlyError(error)) } }
    }
    private func waitForMe() async -> ProfileRow? {
        var n = 0
        while host?.me == nil && n < 40 { n += 1; try? await Task.sleep(nanoseconds: 500_000_000) }
        return host?.me
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private func setDriverRide(_ new: DriverRide?) {
        // A ringing request must reach a driver who isn't looking: a buzz in the app, a notification outside it. Any other state takes the alert away again.
        let oldRinging = driverRide.flatMap { $0.status == .ringing ? $0.id : nil }
        let newRinging = new.flatMap { $0.status == .ringing ? $0.id : nil }
        driverRide = new
        if oldRinging != newRinging {
            if oldRinging != nil { RingAlert.cancel() }
            if let n = new, newRinging != nil { RingAlert.ring(n) }
        }
    }

    // =====================================================================
    // Rider
    // =====================================================================
    @ObservationIgnored private var rideTask: Task<Void, Never>?
    @ObservationIgnored private var noDriverTask: Task<Void, Never>?
    @ObservationIgnored private var noDriverRunning = false
    @ObservationIgnored private var rideDriver: TaskDriverRow?
    @ObservationIgnored private var ridePhone: String?

    /// Books an auto or cab: creates the task, then follows it. Bikes carry goods only. The fare and distance shown afterwards are the server's (contract C3).
    public func requestRide(kind: VehicleKind, from: LatLng, fromLabel: String, dest: Place, fare: Int) {
        guard kind.carriesPassengers else { toast("Bikes carry goods only. Choose an auto or a cab."); return }
        guard dest.km >= minTripKm else { toast("That's too close for a ride. Pick a destination at least 200 m away."); return }
        guard dest.km <= maxTripKm else { toast("That trip is too far for Bucks. Rides go up to \(Int(maxTripKm)) km."); return }
        guard !busy else { return }
        go { [self] in
            busy = true; defer { busy = false }
            let t: TaskRow
            do { t = try await backend.requestRide(kind: kind, from: from, fromLabel: fromLabel, to: dest.at, toLabel: dest.name, km: dest.km, fare: fare) }
            catch is CancellationError { throw CancellationError() }
            catch {
                // The request may have reached the server before the answer was lost, or a ride of mine is already open: follow that one.
                guard let open = (try? await backend.myOpenTask()) ?? nil, open.requesterId == meId, open.type == "RIDE" else { throw error }
                toast("You already have a ride in progress."); await restoreRide(open); return
            }
            rideDriver = nil; ridePhone = nil
            ride = Ride(id: t.id, kind: kind, dest: Place(name: dest.name, km: t.km, at: dest.at), fare: t.fare, status: .searching, pin: t.pin, pickupLabel: fromLabel)
            startNoDriverTimer(t.id, ageS: 0); followRide(t.id)
        }
    }

    private func followRide(_ id: String) {
        rideTask?.cancel()
        rideTask = Task { [weak self] in
            // Realtime only makes the next read come sooner; the 5 s poll stays as the safety net.
            let nudge = Task { for await _ in Backend.shared.changes(table: "tasks", filter: "id=eq.\(id)") { await self?.refreshRide(id) } }
            defer { nudge.cancel() }
            while !Task.isCancelled { await self?.refreshRide(id); try? await Task.sleep(nanoseconds: 5_000_000_000) }
        }
    }
    func refreshRide(_ id: String) async {
        guard let t = (try? await backend.taskGeo(id)) ?? nil, ride?.id == id else { return }
        await applyRide(t)
    }

    /// Gives up on a request nobody took once the server's window has passed, so the rider can retry or switch vehicle type
    /// (the server does the same with expire_tasks; this covers a server without it). `ageS` is how long it has been searching:
    /// 0 for a request just made here; for a restored or handed-back one, the server's age, but never less than 20 s of waiting
    /// left, so a phone with a wrong clock can't end a live request at once. A failed call is retried a few times.
    private func startNoDriverTimer(_ id: String, ageS: Int) {
        noDriverTask?.cancel()
        let wait = ringWindowS - min(max(ageS, 0), ringWindowS - 20)
        noDriverRunning = true
        noDriverTask = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.noDriverRunning = false } }
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
            var tries = 0
            while let self, !Task.isCancelled, self.ride?.id == id, self.ride?.status == .searching, tries < 5 {
                tries += 1
                // advance_task returns the plain tasks row; the rider's Ride is mapped from tasks_geo, so re-read that (a driver may have claimed it meanwhile).
                let ok = (try? await self.backend.advanceTask(id, status: "NO_DRIVER")) != nil
                await self.refreshRide(id)
                if ok || self.ride?.status != .searching { break }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
    private func stopFollowingRide() { rideTask?.cancel(); rideTask = nil; noDriverTask?.cancel(); noDriverTask = nil; noDriverRunning = false }

    private func rideStatus(_ s: String) -> RideStatus {
        switch s {
        case "SEARCHING": .searching; case "MATCHED": .matched; case "ARRIVED": .arrived; case "IN_PROGRESS": .inRide
        case "COMPLETED": .completed; case "PAID": .paid; case "NO_DRIVER": .noDriver; default: .cancelled }
    }
    private func placeOf(_ t: TaskGeoRow) -> Place { Place(name: t.dropLabel.isEmpty ? "Drop point" : t.dropLabel, km: t.km, at: t.drop) }

    /// Maps a task row onto the rider's `Ride`; fetches the driver's name, vehicle and phone once per driver.
    private func applyRide(_ t: TaskGeoRow) async {
        let prev = ride, st = rideStatus(t.status), kind = VehicleKind(serverValue: t.vehicleKind)
        // Cancelled somewhere else (another phone, the server): close it here. A cancel from this phone is finished by `cancelRide`.
        if st == .cancelled { if !cancelling { stopFollowingRide(); ride = nil; onRideClosed("This ride was cancelled.") }; return }
        let pos = t.driverAt
        var driver: Driver?
        var drvAt = prev?.driverAt
        if let driverId = t.driverId {
            if rideDriver?.profileId != driverId {
                rideDriver = (try? await backend.taskDriver(t.id)) ?? nil
                ridePhone = ((try? await backend.contactFor(t.id)) ?? nil)?.phone
            } else if ridePhone?.isEmpty ?? true {
                ridePhone = ((try? await backend.contactFor(t.id)) ?? nil)?.phone
            }
            let d = rideDriver
            if let p = pos ?? (prev?.driver == nil ? t.pickup : nil) { drvAt = p }
            let name = (d?.name.isEmpty == false ? d?.name : nil) ?? host?.names[driverId] ?? "Your rider"
            driver = Driver(id: driverId, name: name, vehicle: d.map { VehicleKind(serverValue: $0.kind) } ?? kind, plate: d?.plate ?? "", model: d?.model ?? "",
                            distanceKm: pos.map { Geo.round1(Geo.distanceKm($0, t.pickup)) } ?? 0, up: d?.up ?? 0, down: d?.down ?? 0, online: true, phone: ridePhone ?? "", at: drvAt)
        } else { rideDriver = nil; ridePhone = nil; drvAt = nil }
        // -1 means "no position yet" (the screen says the rider is on the way instead of counting); 0 is "under a minute".
        let eta: Int = (st == .matched || st == .arrived) ? (pos.map { Int((Geo.distanceKm($0, t.pickup) * 2.5).rounded()) } ?? (prev?.etaMin ?? -1)) : 0
        let progress: Double
        if st == .inRide, let pos { progress = min(max(1 - Geo.distanceKm(pos, t.drop) / max(t.km, 0.1), 0), 1) }
        else if st == .completed || st == .paid { progress = 1 }
        else { progress = prev?.progress ?? 0 }
        if ride?.id != t.id { return }   // cleared (cancelled, rated) while this read was fetching the driver: don't bring it back
        ride = Ride(id: t.id, kind: kind, dest: placeOf(t), fare: t.fare, status: st, pin: t.pin, driver: driver, etaMin: eta, progress: progress, paidWith: t.paidWith ?? prev?.paidWith,
                    reason: prev?.reason, driverAt: drvAt, pickupLabel: t.pickupLabel.isEmpty ? (prev?.pickupLabel ?? "") : t.pickupLabel)
        if st == .searching && (!noDriverRunning || prev?.status != .searching) { startNoDriverTimer(t.id, ageS: secondsSince(t.statusAt.isEmpty ? t.createdAt : t.statusAt) ?? 0) }
        if st == .paid || st == .noDriver { stopFollowingRide() }
    }

    /// Cancels before the trip starts through `cancel_task`, server first: the screen changes only once the server has cancelled.
    /// `reason` is a `CancelReasons.rider` code; once a driver has accepted (MATCHED, ARRIVED) one is required and a missing one is
    /// refused here without calling the server. Returns nil on success, otherwise one honest sentence; the ride is then re-read and the
    /// screens show whatever its real status is (the in-ride screen if the driver had already started it). Deals with a lost answer
    /// too: a ride found CANCELLED (or answered "it is cancelled") counts as done.
    public func cancelRide(reason: String? = nil, note: String = "") async -> String? {
        guard let r = ride, !cancelling else { return nil }
        let code = reason.flatMap { $0.isEmpty ? nil : $0 }
        if code == nil, r.status == .matched || r.status == .arrived { return "Choose why you are cancelling." }
        cancelling = true; defer { cancelling = false }
        do { try await backend.cancelTask(r.id, reason: code, note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))); return closedByMe() }
        catch is CancellationError { return nil }
        catch {
            // Already cancelled elsewhere (the update raced this call): the same result for the rider.
            if friendlyError(error).lowercased().contains("it is cancelled") { return closedByMe() }
            guard let t = (try? await backend.taskGeo(r.id)) ?? nil else { return friendlyError(error) }   // can't even read it: nothing has changed
            if t.status == "CANCELLED" { return closedByMe() }
            await applyRide(t)
            switch t.status {
            case "IN_PROGRESS": return "Your trip has already started, so it can't be cancelled here."
            case "COMPLETED", "PAID": return "This trip is already finished."
            default: return friendlyError(error)
            }
        }
    }
    private func closedByMe() -> String? { stopFollowingRide(); ride = nil; return nil }
    /// Clears a ride that has ended on its own (nobody accepted) once the rider leaves its screen.
    public func dismissEndedRide() { if ride?.status == .noDriver { stopFollowingRide(); ride = nil } }

    /// The rider confirms they paid (UPI app or cash); the driver's screen picks it up. Once at a time; a lost answer is checked against the server.
    public func payRide(method: String) {
        guard let r = ride, !paying, r.status == .completed else { return }
        Task { [self] in
            paying = true; defer { paying = false }
            do {
                let paid: String?
                do { paid = try await backend.advanceTask(r.id, status: "PAID", paidWith: method).paidWith }
                catch is CancellationError { return }
                catch {
                    let t = (try? await backend.taskGeo(r.id)) ?? nil
                    if t?.status == "PAID" { paid = t?.paidWith } else { if let t { await applyRide(t) }; throw error }
                }
                stopFollowingRide()
                if var cur = ride ?? Optional(r) { cur.status = .paid; cur.paidWith = paid ?? method; ride = cur }
            } catch is CancellationError {} catch { toast(friendlyError(error)) }
        }
    }

    /// Posts the review against the driver's DRIVER listing; a driver without one can't be reviewed on the server yet.
    public func finishRide(vote: Int?, comment: String) {
        guard let r = ride else { return }
        stopFollowingRide(); ride = nil
        guard let vote else { return }
        guard let listing = (rideDriver.flatMap { $0.profileId == r.driver?.id ? $0.listingId : nil }) else {
            toast("\(r.driver?.name.components(separatedBy: " ")[0] ?? "Your rider") has no driver profile on Bucks yet, so your review wasn't posted."); return
        }
        go { [self] in
            try await backend.review(listingId: listing, taskId: r.id, orderId: nil, up: vote > 0, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
            toast("Thanks. Your review is public.")
        }
    }
    public func contact(taskId: String) async throws -> ContactRow? { try await backend.contactFor(taskId) }
    public func task(_ id: String) async throws -> TaskGeoRow? { try await backend.taskGeo(id) }
    public func driverOf(taskId: String) async throws -> TaskDriverRow? { try await backend.taskDriver(taskId) }

    // =====================================================================
    // Driver
    // =====================================================================
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var ringTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var tripTask: Task<Void, Never>?
    /// The presence-off write of the last time I went offline, so sign-out can wait for it before the login goes.
    @ObservationIgnored private var offTask: Task<Void, Never>?
    @ObservationIgnored private var nudged = false
    /// Requests this driver declined, missed or dropped; they don't ring again.
    @ObservationIgnored private var passed = Set<String>()
    @ObservationIgnored private var paidToastFor: String?
    /// Bumped by every action of mine on the trip, so a read of the task row that began before it can't undo it.
    @ObservationIgnored private var driverGen = 0

    /// Publishes presence for my vehicle (matched by `plate`, else the first ACTIVE one) and starts ringing. Returns false = stay offline.
    @discardableResult
    public func setOnline(_ on: Bool, plate: String? = nil) async -> Bool {
        do {
            let known = host?.me
            let signedIn = known != nil ? known : await waitForMe()
            guard let me = signedIn else { toast("Still signing in. Try again in a moment."); return false }
            if !on {
                stopDriverLoops(); online = false; Presence.shared.meId = nil
                if let v = vehicle { let at = hereOrNil; offTask = Task.detached { _ = await withTimeoutOrNil(4) { try? await Backend.shared.setPresence(me: me.id, vehicleId: v.id, kind: v.kind, online: false, at: at) } } }
                return true
            }
            let mine = try await backend.myVehicles(); vehicles = mine
            let norm = plate?.uppercased().replacingOccurrences(of: " ", with: "")
            // Only a checked (ACTIVE) vehicle may go online; the presence policy refuses the others, so say why instead of failing.
            let active = mine.filter { $0.status == "ACTIVE" }
            guard let v = active.first(where: { $0.plate == norm }) ?? active.first else {
                toast(mine.isEmpty ? "Add your vehicle under My vehicles before going online." : "Bucks is still checking your vehicle. You can go online once it's active.")
                return false
            }
            try await backend.setPresence(me: me.id, vehicleId: v.id, kind: v.kind, online: true, at: hereOrNil)
            Presence.shared.meId = me.id
            vehicle = v; online = true; startDriverLoops(me: me.id, v)
            return true
        } catch is CancellationError { return false } catch { toast(friendlyError(error)); return false }
    }

    private func startDriverLoops(me: String, _ v: VehicleRow) {
        stopDriverLoops()
        // Keeps me visible to riders while standing still (presence unseen for 5 minutes drops off the map).
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                // Going offline cancels this task and wakes the sleep early: it must not publish "online" once more behind the offline write.
                guard let self, !Task.isCancelled else { return }
                _ = try? await self.backend.setPresence(me: me, vehicleId: v.id, kind: v.kind, online: true, at: self.hereOrNil)
            }
        }
        ringTask = Task { [weak self] in
            // A task that becomes SEARCHING nudges the poll below instead of waiting out its 5 s.
            let nudge = Task { for await _ in Backend.shared.changes(table: "tasks", filter: "status=eq.SEARCHING") { self?.nudged = true } }
            defer { nudge.cancel() }
            while !Task.isCancelled {
                guard let self else { return }
                _ = try? await self.pollRing()
                // Waits up to 5 s, or until something here (a decline, a closed trip) asks for the next request sooner.
                var waited = 0.0
                while waited < 5, !self.nudged, !Task.isCancelled { try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25 }
                self.nudged = false
            }
        }
    }
    private func stopDriverLoops() {
        heartbeatTask?.cancel(); ringTask?.cancel(); heartbeatTask = nil; ringTask = nil; countdownTask?.cancel()
        if let r = driverRide, r.status == .ringing { setDriverRide(nil) }
    }

    /// Rings the nearest open request I haven't passed on, if I'm free. A ringing request that vanished was taken or cancelled.
    func pollRing() async throws {
        let cur = driverRide
        if let cur, cur.status != .ringing { return }
        if ride != nil || busy || !(host?.hereKnown ?? false) { return }   // no real position yet: the map's default centre would ring the wrong city's requests
        let list = try await backend.openTasksNear(here)
        if busy { return }   // a claim of mine started while the list was loading; the claim decides
        if let cur {
            if list.contains(where: { $0.id == cur.id }) { return }
            let t: TaskGeoRow?
            do { t = try await backend.taskGeo(cur.id) } catch { return }   // can't tell: keep the ring, the next poll asks again (a nil row is "gone")
            if busy || driverRide?.id != cur.id { return }
            countdownTask?.cancel()
            // A claim of mine can land with both the answer and the retry lost (see claim): the request left the open list because it is mine now.
            if let t, ownedByMe(t) { await adoptTrip(t); return }
            setDriverRide(nil); toast("That request was taken or cancelled.")
        }
        guard let next = list.first(where: { !passed.contains($0.id) }) else { return }
        await ring(next)
    }
    private func ring(_ t: TaskRow) async {
        guard let geo = (try? await backend.taskGeo(t.id)) ?? nil else { return }
        let who = ((try? await backend.profiles([t.requesterId])) ?? []).first
        if let who { host?.names[who.id] = who.name }
        let me = here, delivery = geo.isDelivery, items = geo.orderItems ?? 0
        let pickupAt = delivery ? (t.pickupLabel.isEmpty ? "the shop" : t.pickupLabel) + (items > 0 ? " · \(items) item\(items > 1 ? "s" : "")" : "") : (t.pickupLabel.isEmpty ? "Pick-up point" : t.pickupLabel)
        setDriverRide(DriverRide(id: t.id, status: .ringing, customer: (who?.name.isEmpty == false ? who?.name : nil) ?? "Customer", customerTrust: Trust(up: who?.trustUp ?? 0, down: who?.trustDown ?? 0),
                                 pickupAt: pickupAt, dropAt: t.dropLabel.isEmpty ? "Drop point" : t.dropLabel, km: t.km, fare: t.fare, secondsLeft: 15, pickupKm: Geo.round1(Geo.distanceKm(me, geo.pickup)),
                                 kind: vehicle.map { VehicleKind(serverValue: $0.kind) } ?? VehicleKind(serverValue: t.vehicleKind), driver: me, pickup: geo.pickup, drop: geo.drop))
        startCountdown()
    }
    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, let cur = self.driverRide, cur.status == .ringing else { return }
                if cur.secondsLeft <= 1 {
                    // A trip that is mine (my claim landed, its answer was lost) is not a missed request.
                    let mine = ((try? await self.backend.taskGeo(cur.id)) ?? nil).flatMap { self.ownedByMe($0) ? $0 : nil }
                    if Task.isCancelled { return }   // accepted or declined while the row was being read
                    if let mine { await self.adoptTrip(mine); return }
                    self.setDriverRide(nil); self.passed.insert(cur.id); self.toast("Missed that one. Stay online for the next request.")
                    _ = try? await self.backend.passTask(cur.id, missed: true); self.nudged = true
                    return
                }
                var next = cur; next.secondsLeft -= 1; self.setDriverRide(next)
            }
        }
    }
    public func driverDecline() {
        guard let cur = driverRide, cur.status == .ringing else { return }
        countdownTask?.cancel(); passed.insert(cur.id); setDriverRide(nil); toast("Passed. We'll send you the next one.")
        Task { [self] in _ = try? await backend.passTask(cur.id, missed: false); nudged = true }
    }

    private enum Claim { case won, taken, unreachable, refused(String) }
    private func ownedByMe(_ t: TaskGeoRow) -> Bool { t.driverId == meId && ["MATCHED", "ARRIVED", "IN_PROGRESS"].contains(t.status) }
    private func adoptTrip(_ t: TaskGeoRow) async { toast("It's yours. Your accept had gone through."); await restoreDriverTrip(t) }
    private func isMine(_ id: String) async -> Bool { ((try? await backend.taskGeo(id)) ?? nil).map(ownedByMe) ?? false }
    /// claim_task answers false only for "not claimable" (taken, too far, stale). A call that throws says nothing about the task:
    /// a lost connection is retried once, and a lost *answer* is caught by reading the row (it may already be mine). The server
    /// refusing with a sentence ('go online first', 'vehicle not verified', 'finish your current trip') is `.refused`.
    private func claim(_ id: String) async -> Claim {
        for attempt in 0..<2 {
            do { let ok = try await backend.claimTask(id); if ok { return .won }; return await isMine(id) ? .won : .taken }
            catch is CancellationError { return .unreachable }
            catch {
                if isServerRefusal(error) { return await isMine(id) ? .won : .refused(friendlyError(error)) }
                if attempt == 0 { await pause(0.6) }
            }
        }
        return await isMine(id) ? .won : .unreachable
    }
    /// First driver to claim wins; otherwise "too late" and the next request rings. A lost connection keeps the ring so the driver can tap again.
    public func driverAccept() {
        guard let cur = driverRide, cur.status == .ringing, !busy else { return }
        countdownTask?.cancel(); driverGen += 1
        go { [self] in
            busy = true; defer { busy = false }
            switch await claim(cur.id) {
            case .won:
                var d = cur; d.status = .toPickup; d.progress = 0; d.secondsLeft = 0; d.driver = hereOrNil ?? cur.driver; setDriverRide(d)
                toast(cur.kind == .bike ? "It's yours. Head to the shop to collect the order." : "It's yours. Head to the pick-up.")
                await loadCustomerPhone(cur.id); followDriverTask(cur.id)
            case .taken:
                passed.insert(cur.id); if driverRide?.id == cur.id { setDriverRide(nil) }; toast("Too late. Another rider took it, or it's no longer available."); nudged = true
            case .unreachable:
                if driverRide?.id == cur.id { var d = cur; d.secondsLeft = max(cur.secondsLeft, 8); setDriverRide(d); startCountdown() }
                toast("Couldn't reach Bucks. Try again.")
            case .refused(let message):
                passed.insert(cur.id); if driverRide?.id == cur.id { setDriverRide(nil) }; toast(message); try? await restoreFromServer(); nudged = true
            }
        }
    }
    private func loadCustomerPhone(_ id: String) async {
        guard let p = ((try? await backend.contactFor(id)) ?? nil)?.phone, var d = driverRide, d.id == id else { return }
        d.customerPhone = p; setDriverRide(d)
    }
    private func followDriverTask(_ id: String) {
        tripTask?.cancel()
        tripTask = Task { [weak self] in
            let nudge = Task { for await _ in Backend.shared.changes(table: "tasks", filter: "id=eq.\(id)") { await self?.refreshDriverTask(id) } }
            defer { nudge.cancel() }
            while !Task.isCancelled { await self?.refreshDriverTask(id); try? await Task.sleep(nanoseconds: 5_000_000_000) }
        }
    }
    private func driverStatusOf(_ server: String, _ local: DriverRideStatus) -> DriverRideStatus? {
        switch server {
        case "MATCHED": .toPickup; case "ARRIVED": .arrived; case "IN_PROGRESS": .inRide
        case "COMPLETED", "PAID": local == .rate ? .rate : .done
        default: nil }
    }
    /// Reads the task and follows it, unless an action of mine is in flight (its own answer, or the next read, decides).
    func refreshDriverTask(_ id: String) async {
        let g = driverGen
        guard let t = (try? await backend.taskGeo(id)) ?? nil else { return }
        if g != driverGen || busy || handingBack { return }
        _ = await applyDriverTruth(id, t)
    }
    /// Puts the driver's screen where the server row says the trip is (forward or back). Returns true when the trip is gone from this driver.
    private func applyDriverTruth(_ id: String, _ t: TaskGeoRow) async -> Bool {
        guard let cur = driverRide, cur.id == id else { return false }
        if t.status == "CANCELLED" { stopDriverTask(); setDriverRide(nil); toast(t.isDelivery ? "This delivery was cancelled." : "The customer cancelled this ride."); nudged = true; return true }
        if t.driverId != meId { stopDriverTask(); passed.insert(id); setDriverRide(nil); toast("This trip is no longer yours. It went back to other riders."); nudged = true; return true }
        guard let st = driverStatusOf(t.status, cur.status) else { return false }
        var next = cur
        if st != cur.status { next.status = st; next.progress = (st == .done || st == .rate) ? 1 : (st == .inRide ? 0 : cur.progress) }
        // What the customer says they paid with (they mark it on their phone); the server doesn't verify it.
        if t.status == "PAID", let paid = t.paidWith {
            next.paidWith = paid
            if paidToastFor != id { paidToastFor = id; toast("The customer says they paid by \(payWord(paid)). Check \(isCash(paid) ? "you have the cash" : "your UPI app") before you continue.") }
        }
        if t.pinAttempts > cur.pinAttempts { next.pinAttempts = t.pinAttempts; next.pinLocked = t.pinAttempts >= pinTries }
        if next != cur { setDriverRide(next) }
        if cur.customerPhone.isEmpty && ["MATCHED", "ARRIVED", "IN_PROGRESS", "COMPLETED"].contains(t.status) { await loadCustomerPhone(id) }
        return false
    }
    private func stopDriverTask() { tripTask?.cancel(); tripTask = nil }
    /// An action of mine failed or its answer was lost: read the trip again and show the truth, then say what went wrong.
    private func failedDriverAction(_ id: String, _ e: Error) async {
        var msg = friendlyError(e)
        let before = driverRide?.status
        if let t = (try? await backend.taskGeo(id)) ?? nil {
            if msg.lowercased().hasPrefix("cannot go from") { msg = "This trip had already moved on. Your screen now shows where it really is." }
            if msg.lowercased().contains("too many wrong pin") { update(id) { $0.pinAttempts = pinTries; $0.pinLocked = true } }
            if await applyDriverTruth(id, t) { return }
            // The call itself failed but the server has the change (a lost answer): say so instead of an error.
            if driverRide?.status != before && !msg.hasPrefix("This trip had already") { toast("That had already gone through. Your screen is up to date."); return }
        }
        toast(msg)
    }

    /// Next step of the trip: arrived at pick-up, PIN to start (checked by the server), end of trip.
    public func driverNext(pin: String = "") {
        guard let d = driverRide, !busy else { return }
        driverGen += 1
        go { [self] in
            busy = true; defer { busy = false }
            do {
                switch d.status {
                case .toPickup:
                    _ = try await backend.advanceTask(d.id, status: "ARRIVED"); update(d.id) { $0.status = .arrived }
                    toast(d.kind == .bike ? "You're at the shop. Call the customer for the 4-digit pickup PIN." : "You're at the pick-up. Ask the customer for their PIN.")
                case .arrived:
                    guard pin.count == 4 else { toast("Enter the 4-digit PIN."); return }
                    if d.pinLocked { toast("Too many wrong PINs. Hand this trip back."); return }
                    // A wrong PIN doesn't raise (contract C1): the row comes back still ARRIVED with the attempts counted. Only IN_PROGRESS means it matched.
                    let t = try await backend.advanceTask(d.id, status: "IN_PROGRESS", pin: pin)
                    if t.status == "IN_PROGRESS" { update(d.id) { $0.status = .inRide; $0.progress = 0 }; toast("PIN matched. Off you go.") }
                    else {
                        let left = max(pinTries - t.pinAttempts, 0)
                        update(d.id) { $0.pinAttempts = t.pinAttempts; $0.pinLocked = left == 0 }
                        toast(left == 0 ? "That PIN doesn't match, and you have no tries left. Hand this trip back." : "That PIN doesn't match. \(left) \(left == 1 ? "try" : "tries") left.")
                    }
                case .inRide:
                    _ = try await backend.advanceTask(d.id, status: "COMPLETED"); update(d.id) { $0.status = .done; $0.progress = 1 }
                default: break
                }
            } catch is CancellationError {} catch { await failedDriverAction(d.id, error) }
        }
    }
    private func update(_ id: String, _ f: (inout DriverRide) -> Void) {
        driverGen += 1
        guard var d = driverRide, d.id == id else { return }
        f(&d); setDriverRide(d)
    }
    /// Cash or UPI collected, once and only from the payment step; false when there was nothing to move (a second tap). The customer marks PAID on their phone.
    @discardableResult
    public func driverPaid(method: String) -> Bool {
        guard var d = driverRide, d.status == .done else { return false }
        driverGen += 1; d.status = .rate; d.paidWith = method; setDriverRide(d); return true
    }
    /// Trip closed on this phone (after rating the customer); ring the next request.
    public func closeTrip() { stopDriverTask(); setDriverRide(nil); nudged = true }
    /// Hands the request back so it rings other drivers, through `release_task`. Allowed from the way to the pick-up and at the pick-up,
    /// not once the PIN is in. `reason` is a `CancelReasons.driver` code and is required: without one nothing is sent and a toast says why.
    /// A refusal from the server is shown as a toast and leaves the trip where it is. Returns whether it happened.
    @discardableResult
    public func driverCancel(reason: String?, note: String = "") async -> Bool {
        guard let d = driverRide else { return false }
        if d.status == .ringing { driverDecline(); return true }
        guard d.status == .toPickup || d.status == .arrived else { toast("A trip that has started can't be handed back."); return false }
        guard let code = reason, !code.isEmpty else { toast("Choose why you are handing it back."); return false }
        if handingBack || busy { return false }
        driverGen += 1
        handingBack = true; defer { handingBack = false }
        do { try await backend.releaseTask(d.id, reason: code, note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))); stopDriverTask(); passed.insert(d.id); setDriverRide(nil); nudged = true; return true }
        catch is CancellationError { return false }
        catch { await failedDriverAction(d.id, error); return false }
    }
    /// Real position: moves me on the map and updates distance left; the server gets it from the location tracker.
    public func driverMoved(_ p: LatLng) {
        guard var dr = driverRide, [.toPickup, .arrived, .inRide].contains(dr.status), let pickup = dr.pickup, let drop = dr.drop else { return }
        let progress = dr.status == .inRide ? min(max(1 - Geo.distanceKm(p, drop) / max(Geo.distanceKm(pickup, drop), 0.1), 0), 1) : 0
        dr.driver = p; dr.pickupKm = Geo.round1(Geo.distanceKm(p, pickup)); dr.progress = progress
        setDriverRide(dr)
    }

    // =====================================================================
    // Resume, map feed, payment link, lifecycle
    // =====================================================================
    /// After sign-in: pick up the trip a killed app was on, as rider or driver.
    public func resume() {
        go { [self] in
            guard await waitForMe() != nil else { return }
            await refreshVehicles()
            if let v = (try? await backend.settingValue("ring_window_seconds")) ?? nil, v >= 30 { ringWindowS = Int(v) }
            try await restoreFromServer()
        }
    }
    /// Follows my open trip on the server, as rider or driver, unless this phone already has it.
    private func restoreFromServer() async throws {
        guard let me = host?.me, let t = try await backend.myOpenTask() else { return }
        if ride?.id == t.id || driverRide?.id == t.id { return }
        if t.driverId == me.id { await restoreDriverTrip(t) }
        else if t.requesterId == me.id && t.type == "RIDE" { await restoreRide(t) }
        // A buyer's delivery is followed from the order page; nothing to restore here.
    }
    private func restoreRide(_ t: TaskGeoRow) async {
        rideDriver = nil; ridePhone = nil
        ride = Ride(id: t.id, kind: VehicleKind(serverValue: t.vehicleKind), dest: placeOf(t), fare: t.fare, status: rideStatus(t.status), pin: t.pin, pickupLabel: t.pickupLabel)
        await applyRide(t)
        if rideTask == nil && ride != nil { followRide(t.id) }
    }
    private func restoreDriverTrip(_ t: TaskGeoRow) async {
        let status: DriverRideStatus
        switch t.status { case "MATCHED": status = .toPickup; case "ARRIVED": status = .arrived; case "IN_PROGRESS": status = .inRide; case "COMPLETED": status = .done; default: return }
        let who = ((try? await backend.profiles([t.requesterId])) ?? []).first
        let me = here, items = t.orderItems ?? 0
        let pickupAt = t.isDelivery ? (t.pickupLabel.isEmpty ? "the shop" : t.pickupLabel) + (items > 0 ? " · \(items) item\(items > 1 ? "s" : "")" : "") : (t.pickupLabel.isEmpty ? "Pick-up point" : t.pickupLabel)
        setDriverRide(DriverRide(id: t.id, status: status, customer: (who?.name.isEmpty == false ? who?.name : nil) ?? "Customer", customerTrust: Trust(up: who?.trustUp ?? 0, down: who?.trustDown ?? 0),
                                 pickupAt: pickupAt, dropAt: t.dropLabel.isEmpty ? "Drop point" : t.dropLabel, km: t.km, fare: t.fare, secondsLeft: 0, pickupKm: Geo.round1(Geo.distanceKm(me, t.pickup)),
                                 kind: VehicleKind(serverValue: t.vehicleKind), driver: me, pickup: t.pickup, drop: t.drop, progress: status == .done ? 1 : 0, paidWith: t.status == "PAID" ? t.paidWith : nil,
                                 pinAttempts: t.pinAttempts, pinLocked: t.pinAttempts >= pinTries))
        await loadCustomerPhone(t.id); followDriverTask(t.id)
    }

    /// Reloads `vehicles` (after sign-in and when Home opens; the manage screens keep their own list).
    public func refreshVehicles() async { if let v = try? await backend.myVehicles() { vehicles = v } }

    @ObservationIgnored private var driversTask: Task<Void, Never>?
    @ObservationIgnored private var mapViewers = 0
    /// Polls `online_drivers_near` every 15 s while a map is showing (45 s otherwise) so pins and "n riders nearby" stay fresh.
    public func startDriversFeed() {
        guard driversTask == nil else { return }
        driversTask = Task { [weak self] in
            while !Task.isCancelled { guard let self else { return }; await self.refreshDrivers(); try? await Task.sleep(nanoseconds: self.mapViewers > 0 ? 15_000_000_000 : 45_000_000_000) }
        }
    }
    public func stopDriversFeed() { driversTask?.cancel(); driversTask = nil; drivers = [] }
    public func refreshDrivers() async {
        guard let rows = try? await backend.onlineDriversNear(here, radiusM: 10_000) else { return }
        let me = here
        drivers = rows.compactMap { r in
            guard let kind = VehicleKind(rawValue: r.kind) else { return nil }
            let at = LatLng(r.lat, r.lng)
            return Driver(id: r.profileId, name: r.name.isEmpty ? "Rider" : r.name, vehicle: kind, plate: r.plate, model: r.model, distanceKm: Geo.round1(Geo.distanceKm(me, at)), up: r.up, down: r.down, online: true, at: at)
        }
    }
    /// Call from a screen that shows the map (onAppear/onDisappear) to poll faster while it is visible.
    public func mapShown() { mapViewers += 1 }
    public func mapHidden() { mapViewers = max(0, mapViewers - 1) }

    /// Online drivers of `kind` inside the ring radius, nearest first: the published rule, not a model.
    public func ring(from: LatLng, kind: VehicleKind, radiusKm: Double = 5) -> [Driver] {
        drivers.filter { $0.online && $0.vehicle == kind && Geo.distanceKm(from, $0.at ?? from) <= radiusKm }.sorted { Geo.distanceKm(from, $0.at ?? from) < Geo.distanceKm(from, $1.at ?? from) }
    }

    public func refreshPaymentLink() {
        go { [self] in
            let known = host?.me
            let signedIn = known != nil ? known : await waitForMe()
            guard let me = signedIn else { return }
            paymentLink = try await backend.myPaymentLink(me: me.id); paymentLinkLoaded = true
        }
    }
    /// Saves a decoded `upi://pay?...` link as my payment QR.
    public func savePaymentLink(_ uri: String, then: @escaping () -> Void = {}) {
        go { [self] in
            guard let me = host?.me else { return }
            guard uri.lowercased().hasPrefix("upi://pay") else { toast("That QR isn't a UPI payment code."); return }
            busy = true; defer { busy = false }
            try await backend.setPaymentLink(profileId: me.id, upiUri: uri); paymentLink = uri; paymentLinkLoaded = true
            toast("Saved. Customers can now pay you by UPI."); then()
        }
    }
    public func removePaymentLink() {
        go { [self] in
            guard let me = host?.me else { return }
            try await backend.clearPaymentLink(me: me.id); paymentLink = nil
            toast("Payment QR removed. Customers can't pay you by UPI until you add one again.")
        }
    }

    /// Sign-out, account deletion or a cleared session: presence off, everything cancelled, nothing left on screen. Sign-out waits for the
    /// returned task before it drops the login.
    @discardableResult
    public func signedOut() -> Task<Void, Never>? {
        stopFollowingRide(); stopDriverTask(); stopDriverLoops(); stopDriversFeed()
        let off: Task<Void, Never>? = online ? Task.detached { await Presence.shared.offline() } : (offTask)
        online = false; vehicle = nil; vehicles = []; passed.removeAll(); ride = nil; setDriverRide(nil); rideDriver = nil; ridePhone = nil; paymentLink = nil; paymentLinkLoaded = false
        cancelling = false; paying = false; handingBack = false
        return off
    }
}

/// "cash" for the customer-facing words; anything else the server holds is a UPI payment.
public func isCash(_ paidWith: String?) -> Bool { paidWith?.lowercased().contains("cash") == true }
public func payWord(_ paidWith: String?) -> String {
    guard let p = paidWith, !p.isEmpty else { return "cash or UPI" }
    return isCash(p) ? "cash" : p
}

/// The query of a UPI link as Android's Uri reads it: first value of each name, `+` meaning a space, percent escapes decoded.
private func upiQuery(_ link: String) -> [(name: String, value: String)] {
    // Split by hand: QR codes in the wild carry raw spaces and non-ASCII letters, which URLComponents refuses (Uri.parse does not).
    let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let q = text.firstIndex(of: "?") else { return [] }
    let raw = text[text.index(after: q)...].prefix { $0 != "#" }
    var seen = Set<String>(), out: [(name: String, value: String)] = []
    for part in raw.split(separator: "&", omittingEmptySubsequences: true) {
        let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        func decode(_ s: Substring) -> String { let t = s.replacingOccurrences(of: "+", with: " "); return t.removingPercentEncoding ?? t }
        let name = decode(kv[0])
        if seen.insert(name).inserted { out.append((name, kv.count > 1 ? decode(kv[1]) : "")) }
    }
    return out
}
/// Percent-encodes like Android's Uri.encode: letters, digits and `_-!.~'()*` stay, everything else (space, @, &, +, /) is escaped.
private func upiEncode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-!.~'()*")) ?? s
}

/// A UPI deep link with the amount and note filled in: any UPI app opens it with the driver's details from their QR.
public func upiPayLink(base: String, amountRupees: Int, note: String) -> String {
    let kept = upiQuery(base).filter { !["am", "tn", "cu"].contains($0.name) }
    let items = kept + [("am", "\(amountRupees).00"), ("cu", "INR"), ("tn", note)]
    return "upi://pay?" + items.map { "\(upiEncode($0.name))=\(upiEncode($0.value))" }.joined(separator: "&")
}
/// "Payments go to <pn> (<pa>)" from a UPI link; nil when it has no payee address.
public func upiPayee(_ link: String) -> (name: String, address: String)? {
    let items = upiQuery(link)
    guard let pa = items.first(where: { $0.name == "pa" })?.value, !pa.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    var pn = pa.components(separatedBy: "@")[0]
    if let given = items.first(where: { $0.name == "pn" })?.value, !given.trimmingCharacters(in: .whitespaces).isEmpty { pn = given }
    return (pn, pa)
}
