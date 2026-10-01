import Foundation
import Observation

/// Phone sign-in. The iOS app implements this on FirebaseAuth (ios/App/FirebasePhoneAuth.swift); the rest of the app only sees this.
public enum PhoneSendResult: Sendable { case codeSent, signedIn }
public protocol PhoneSignIn: IdentityProvider {
    /// Sends an SMS code to `phone` (10 digits, India). Some devices verify instantly, which returns `.signedIn` without a code.
    func sendCode(phone: String, resend: Bool) async throws -> PhoneSendResult
    func verify(code: String) async throws
    func signOut() throws
    /// Removes the Firebase account. Firebase may ask for a fresh sign-in first. Nothing on Supabase goes with it: call
    /// `Backend.deleteMyAccount()` first, while this user can still sign the request.
    func deleteAccount() async throws
    /// Firebase project this build talks to (shown on the code screen of test builds).
    var projectName: String? { get }
}

/// The person on this phone, saved locally (the server profile is the source of truth; this lets a relaunch sign in without asking again).
public struct StoredUser: Codable, Hashable, Sendable {
    public var name: String
    public var area: String
    public var bio: String
    public var phone: String
    public var gender: String
    public var interests: [String]
    public init(name: String = "", area: String = "", bio: String = "", phone: String = "", gender: String = "", interests: [String] = []) {
        self.name = name; self.area = area; self.bio = bio; self.phone = phone; self.gender = gender; self.interests = interests
    }
}

/// A money-moving step the person confirms before it runs (Confirm.kt's PendingAction): the ride booking sheet.
public struct PendingBooking: Identifiable {
    public let id = UUID()
    public var title: String
    public var summary: String
    public var amount: Int
    public var run: @MainActor () -> Void
}

/// App-wide state: sign-in, the profile, where I am, the ride being planned, and the dispatch engine (the BucksViewModel + Social of Android).
@MainActor @Observable
public final class AppSession: DispatchHost {
    public enum Phase: Equatable { case launching, signedOut, needsProfile, ready }

    // MARK: sign-in and profile
    public private(set) var phase: Phase = .launching
    public var me: ProfileRow?
    public private(set) var user: StoredUser?
    /// The number being verified (10 digits).
    public var tempPhone = ""
    /// What the phone sign-in is doing right now, shown under the code box so a tester can report it.
    public var otpStatus = ""
    public var names: [String: String] = [:]
    /// Cloud features need Supabase and Firebase configured.
    public var cloud: Bool { Backend.shared.enabled }
    public var firebaseProject: String? { auth?.projectName }

    // MARK: where I am
    public private(set) var here: LatLng = Geo.center
    /// True once a real fix has set `here`; until then it is only the map's default centre and must not be sent as my position.
    public private(set) var hereKnown = false
    public private(set) var hereLabel: String?
    public private(set) var mockLocation = false
    public private(set) var locationGranted = false
    public var mePos: LatLng { here }

    // MARK: ride planning
    public var rideDest: Place?
    public var rideKind: VehicleKind = .auto
    public private(set) var savedPlaces: [String] = []
    public var pending: PendingBooking?
    /// Taken today by this phone's driver (fares collected); in memory only, like Android.
    public private(set) var earningsToday = 0

    // MARK: engines
    @ObservationIgnored public private(set) lazy var dispatch: Dispatch = Dispatch(host: self, onRideClosed: { [weak self] msg in self?.toast(msg) })
    // One state holder per area, like the Android ViewModel's social / discover / commerce / myListings / jobs / services.
    @ObservationIgnored public private(set) lazy var social: SocialStore = SocialStore(session: self)
    @ObservationIgnored public private(set) lazy var feed: FeedStore = FeedStore(session: self)
    @ObservationIgnored public private(set) lazy var chat: ChatStore = ChatStore(session: self)
    @ObservationIgnored public private(set) lazy var discover: DiscoverStore = DiscoverStore(session: self)
    @ObservationIgnored public private(set) lazy var services: ServicesStore = ServicesStore(session: self)
    @ObservationIgnored public private(set) lazy var commerce: CommerceStore = CommerceStore(session: self)
    @ObservationIgnored public private(set) lazy var listings: ListingsStore = ListingsStore(session: self)
    @ObservationIgnored public private(set) lazy var jobs: JobsStore = JobsStore(session: self)
    @ObservationIgnored public let location = LocationService()
    @ObservationIgnored public private(set) var auth: PhoneSignIn?
    @ObservationIgnored public var toastHandler: (String) -> Void = { _ in }
    @ObservationIgnored private var lastFixAt: Date?
    @ObservationIgnored private var labelledAt: LatLng?
    @ObservationIgnored private var lastPush = Date.distantPast
    @ObservationIgnored private let defaults = UserDefaults.standard

    public init() {
        location.onFix = { [weak self] f in self?.onLocation(f.at, mocked: f.mocked) }
        location.onAuthorizationChange = { [weak self] in self?.locationGranted = self?.location.hasPermission ?? false }
        locationGranted = location.hasPermission
        savedPlaces = defaults.stringArray(forKey: "savedPlaces") ?? []
        if let d = defaults.data(forKey: "storedUser"), let u = try? JSONDecoder().decode(StoredUser.self, from: d) { user = u }
    }

    public func toast(_ message: String) { toastHandler(message) }

    /// Wire the real services in. Call once at launch, then `start()`.
    public func configure(_ config: BackendConfig, auth: PhoneSignIn?) {
        self.auth = auth
        Backend.shared.configure(config, identity: auth)
    }

    /// Decides the first screen: signed in on a previous launch → restore; otherwise the welcome/login flow.
    public func start() {
        location.startUpdates()   // the permission prompt comes after sign-in, with an explanation (MainStack)
        guard cloud, auth?.uid != nil else { phase = .signedOut; return }
        Task { await signedIn(name: user?.name ?? "", phone: user?.phone ?? "") }
    }

    // MARK: phone sign-in

    public func sendOtp(resend: Bool = false) async {
        guard let auth else { otpStatus = "Sign-in isn't set up in this build."; return }
        otpStatus = "Asking Firebase to send the code…"
        do {
            switch try await auth.sendCode(phone: tempPhone, resend: resend) {
            case .codeSent: otpStatus = "Code sent. Enter it below."; toast("Code sent to +91 \(tempPhone)")
            case .signedIn: otpStatus = "Signed in"; await phoneVerified()
            }
        } catch { otpStatus = "Couldn't send the code: \(error.localizedDescription)"; toast(error.localizedDescription) }
    }
    /// Returns whether the code was accepted.
    public func verifyOtp(_ code: String) async -> Bool {
        guard let auth else { toast("Sign-in isn't set up in this build."); return false }
        otpStatus = "Checking the code…"
        do { try await auth.verify(code: code); otpStatus = "Signed in"; await phoneVerified(); return true }
        catch { otpStatus = "Code not accepted: \(error.localizedDescription)"; toast(error.localizedDescription); return false }
    }
    private func phoneVerified() async {
        var u = user ?? StoredUser(); u.phone = tempPhone.isEmpty ? u.phone : tempPhone; save(u)
        dispatch.startDriversFeed()
        await signedIn(name: u.name, phone: u.phone)
    }

    /// Right after the first sign-in the Supabase role claim may still be on its way: try again before giving up.
    private func signedIn(name: String, phone: String) async {
        var tries = 0
        while true {
            do {
                let p = try await Backend.shared.ensureProfile(name: name, phone: phone.isEmpty ? nil : phone)
                me = p; names[p.id] = p.name
                // A returning person on a new phone already has a name and area on the server.
                if user == nil || (user?.name.isEmpty ?? true), !p.name.isEmpty { var u = user ?? StoredUser(phone: phone); u.name = p.name; u.area = p.area; u.bio = p.bio; save(u) }
                phase = (p.name.isEmpty && (user?.name.isEmpty ?? true)) ? .needsProfile : .ready
                dispatch.startDriversFeed(); dispatch.resume(); social.signedIn(); registerPushIfSignedIn()
                return
            } catch is CancellationError { return } catch {
                tries += 1
                if tries >= 3 { toast(friendlyError(error)); if phase == .launching { phase = .signedOut }; return }
                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * tries))
            }
        }
    }
    /// After the three-step profile setup (or an edit). `home` null leaves the saved home point alone; it is never guessed from the map's default centre.
    public func createProfile(name: String, area: String, bio: String, gender: String = "", interests: [String] = [], home: LatLng? = nil) async {
        var u = user ?? StoredUser(phone: tempPhone); u.name = name; u.area = area; u.bio = bio; u.gender = gender; u.interests = interests; save(u)
        do {
            let p: ProfileRow
            if let m = me { p = m } else { p = try await Backend.shared.ensureProfile(name: name, phone: u.phone.isEmpty ? nil : u.phone) }
            try await Backend.shared.updateProfile(id: p.id, name: name, bio: bio, area: area, home: home)
            var q = p; q.name = name; q.area = area; q.bio = bio; me = q; names[q.id] = name
            toast("Welcome to Bucks, \(name.components(separatedBy: " ")[0])")
            phase = .ready
        } catch { toast(friendlyError(error)) }
    }
    /// Stores this phone's push token against my profile (no-op without Firebase Messaging or when signed out). Runs once the profile is loaded, which covers launch and a fresh sign-in.
    public func registerPushIfSignedIn() { Push.shared.registerIfSignedIn() }
    private func save(_ u: StoredUser) { user = u; if let d = try? JSONEncoder().encode(u) { defaults.set(d, forKey: "storedUser") } }

    /// Takes presence off and drops the login while the Firebase user can still sign those requests.
    public func logout() async {
        if dispatch.online { await setOnline(false) }
        await Push.shared.unregister()
        let off = dispatch.signedOut()
        clearLocalState()
        if let off { _ = await withTimeoutOrNil(4) { await off.value } }
        try? auth?.signOut()
        phase = .signedOut
    }
    /// Server first, while the Firebase user still exists to sign the request: presence, open tasks, phone, UPI link and profile
    /// (delete_my_account). Only then the Firebase user; if the server part failed, keep it so deleting again works.
    public func deleteAccount() async {
        if dispatch.online { await setOnline(false) }
        dispatch.signedOut()
        // Private documents (listing and vehicle papers) live only in my storage folder; remove them before the rows go.
        if cloud, let meId = me?.id { _ = try? await Backend.shared.deleteMyDocFiles(me: meId) }
        do { try await Backend.shared.deleteMyAccount() } catch {
            toast("Couldn't remove your account from the server. Sign in again and delete it once more."); try? auth?.signOut(); clearLocalState(); phase = .signedOut; return
        }
        clearLocalState(); Identity.deleteKey()
        do { try await auth?.deleteAccount(); toast("Your account and data were deleted.") }
        catch { try? auth?.signOut(); toast("Your profile, listings, posts and messages were removed, but your sign-in couldn't be. Sign in again and delete the account once more.") }
        phase = .signedOut
    }
    private func clearLocalState() {
        // Cart, orders, search results, listings, jobs, chats and the feed belong to the person who signed out, not the next account on this phone.
        commerce.signedOut(); discover.signedOut(); listings.signedOut(); services.signedOut(); jobs.signedOut(); social.signedOut(); chat.signedOut(); feed.clear()
        me = nil; user = nil; names = [:]; tempPhone = ""; otpStatus = ""; rideDest = nil; pending = nil; earningsToday = 0
        defaults.removeObject(forKey: "storedUser")
    }

    // MARK: location

    public func onLocation(_ p: LatLng, mocked: Bool) {
        let wasMocked = mockLocation
        here = p; hereKnown = true; lastFixAt = Date(); mockLocation = mocked; locationGranted = true
        if mocked && !wasMocked { toast("A fake-location app is on. Turn it off to book or take rides.") }
        dispatch.driverMoved(p)
        // A driver on duty streams the position to the server at most every 5 s (it moves the car on the rider's screen and keeps presence fresh).
        if dispatch.online, Date().timeIntervalSince(lastPush) >= 5 { lastPush = Date(); Task { try? await Backend.shared.updateLocation(p) } }
        // Name the pick-up point from the map, again only after moving ~250 m (the lookup service is shared and free).
        // The old name is dropped at once: after 250 m it no longer describes where I am.
        if labelledAt.map({ Geo.distanceKm($0, p) > 0.25 }) ?? true {
            labelledAt = p; hereLabel = nil
            Task { if let l = await MapServices.label(at: p), labelledAt == p { hereLabel = l } }
        }
    }
    /// A fix taken now, for booking. False when there is none (no permission, location switched off, no answer in time); a fix under 90 s old still counts.
    public func refreshLocation() async -> Bool {
        if let f = await location.fresh() { onLocation(f.at, mocked: f.mocked); return true }
        return hereKnown && (lastFixAt.map { Date().timeIntervalSince($0) < 90 } ?? false)
    }

    // MARK: going online

    /// Goes online with one of my checked vehicles (matched by `plate`, else the first ACTIVE one).
    @discardableResult
    public func setOnline(_ on: Bool, plate: String? = nil) async -> Bool {
        if on && mockLocation { toast("Turn off the fake-location app to go online."); return false }
        if on { location.requestPermission(); _ = await RingAlert.requestPermission() }
        let ok = await dispatch.setOnline(on, plate: plate)
        location.setDriverMode(ok ? on : false)
        if ok && on { toast("Online. Nearby requests will ring you.") } else if ok { toast("Offline") }
        return ok
    }

    // MARK: ride planning

    /// Same fare formula as Android: per-km rate plus a ₹20 base.
    public func fare(_ k: VehicleKind, km: Double) -> Int { Int((Double(k.farePerKm) * km + 20).rounded()) }
    public func onlineCount(_ k: VehicleKind) -> Int { dispatch.ring(from: mePos, kind: k).count }

    public func startRide() { rideDest = nil; pending = nil }
    /// One of the built-in places.
    public func chooseDest(_ name: String) { if let at = Geo.place(named: name) { chooseDestPlace(name, at: at) } }
    public func chooseDestPlace(_ name: String, at: LatLng) { rideDest = Place(name: name, km: Geo.round1(Geo.distanceKm(mePos, at)), at: at) }
    /// A point dropped on the map: named from the map's address data once it answers ("Pinned location" until then).
    public func chooseDestAt(_ p: LatLng) {
        chooseDestPlace("Pinned location", at: p)
        Task { if let l = await MapServices.label(at: p), var d = rideDest, d.at == p { d.name = l; rideDest = d } }
    }
    /// The road distance replaces the straight-line one once the route arrives.
    public func setDestKm(_ km: Double) { if km > 0, var d = rideDest, d.km != km { d.km = km; rideDest = d } }
    public func setRideKind(_ k: VehicleKind) { if k.carriesPassengers { rideKind = k } }
    public func toggleSavedPlace(_ name: String) {
        if let i = savedPlaces.firstIndex(of: name) { savedPlaces.remove(at: i) } else { savedPlaces.append(name) }
        defaults.set(savedPlaces, forKey: "savedPlaces")
    }

    /// Why this trip can't be booked (a fake-location app is on, or the distance is outside what the server takes); nil when it can.
    public func bookingProblem(_ d: Place) -> String? {
        if mockLocation { return "A fake-location app is on. Turn it off to book a ride." }
        if d.km < minTripKm { return "That's too close for a ride. Pick a destination at least 200 m away." }
        if d.km > maxTripKm { return "That trip is too far for Bucks. Rides go up to \(Int(maxTripKm)) km." }
        return nil
    }
    /// Shows the booking confirmation; the person confirms, then `doRequestRide` runs.
    public func requestRide() {
        guard let d = rideDest else { return }
        if let p = bookingProblem(d) { toast(p); return }
        let f = fare(rideKind, km: d.km), kind = rideKind
        pending = PendingBooking(title: "Book a \(kind.label.lowercased())", summary: "\(hereLabel ?? "Current location") → \(d.name) · \(d.km) km · about ₹\(f), pay after the trip", amount: f) { [weak self] in self?.doRequestRide() }
    }
    public func confirmPending(_ p: PendingBooking) { guard pending?.id == p.id else { return }; pending = nil; p.run() }
    public func cancelPending() { pending = nil }
    private func doRequestRide() {
        guard let d = rideDest else { return }
        if let p = bookingProblem(d) { toast(p); return }
        guard hereKnown else { toast("Turn on location so your rider can find your pick-up point."); return }
        dispatch.requestRide(kind: rideKind, from: here, fromLabel: hereLabel ?? "Current location", dest: d, fare: fare(rideKind, km: d.km))
    }

    /// Rider: cancel before the trip starts. Shows the server's answer; success returns home.
    public func cancelRide() async -> Bool {
        guard let r = dispatch.ride else { return true }
        if dispatch.cancelling { return false }   // a cancel is already on its way; its own call reports the outcome
        guard [.searching, .noDriver, .matched, .arrived].contains(r.status) else { toast("This trip has already started, so it can't be cancelled here."); return false }
        if let err = await dispatch.cancelRide() { toast(err); return false }
        toast("Ride cancelled. Nothing to pay."); return true
    }
    /// Rider: review the driver (or skip) and clear the ride.
    public func finishRide(vote: Int?, comment: String, skip: Bool) -> Bool {
        if !skip, vote == nil || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { toast("Choose Recommend or Not recommended, and add a line on why."); return false }
        dispatch.finishRide(vote: skip ? nil : vote, comment: comment)
        toast("Trip saved. Find it under Activity."); return true
    }

    // MARK: driver trip

    /// Cash or UPI collected. Counted once, and only from the payment step. `method` is "CASH", "UPI" or "shop".
    public func driverPaid(method: String) {
        guard let d = dispatch.driverRide, dispatch.driverPaid(method: method) else { return }
        earningsToday += d.fare
        toast(method == "shop" ? "Delivery done. ₹\(d.fare) comes from the shop." : "₹\(d.fare) received by \(payWord(method)). Added to today's earnings.")
    }
    /// The driver rates the customer; the server only counts the rider's review of the driver, so this just closes the trip.
    public func driverRateCustomer(stars: Int) { dispatch.closeTrip(); toast("Trip closed. Fare added to today's earnings.") }
}
