import SwiftUI
import BucksCore

/// The whole app: splash and sign-in while signed out, profile setup, then the main stack with the ride and driver overlays.
public struct RootView: View {
    @State private var session: AppSession
    @State private var router: Router
    @StateObject private var toasts = ToastCenter()
    @Environment(\.scenePhase) private var scenePhase

    /// `router` is only passed by the macOS preview harness, which drives the screens from a script.
    @MainActor public init(session: AppSession, router: Router? = nil) {
        _session = State(initialValue: session); _router = State(initialValue: router ?? Router())
        // Cold start for someone already signed in: the wordmark intro, once per launch.
        IntroState.pending = IntroState.pending && session.auth?.uid != nil && PushInbox.shared.pending == nil
    }
    /// Preview harness only: how far into the signed-out flow to start (0 splash, 1 phone number, 2 code).
    nonisolated(unsafe) public static var previewAuthStep = 0
    /// Preview harness only: skip the location and notification prompts (they are system alerts that would cover the screenshots).
    nonisolated(unsafe) public static var previewSkipPrompts = false

    public var body: some View {
        Group {
            switch session.phase {
            case .launching: LaunchingView()
            case .signedOut: AuthFlow()
            case .needsProfile: CreateProfileScreen()
            case .ready: MainStack()
            }
        }
        .environment(session)
        .environment(router)
        .bucksToasts(toasts)
        .preferredColorScheme(Prefs.shared.colorScheme)
        .dynamicTypeSize(Prefs.shared.dynamicTypeSize)
        .task {
            BucksFonts.register()
            session.toastHandler = { [toasts] in toasts.show($0) }
            session.start()
        }
        .onChange(of: scenePhase) { _, p in AppLife.shared.setForeground(p == .active) }
        .onChange(of: session.phase) { old, _ in
            // Signing in or out starts the next person on Home with nothing left open; a tapped notification meant for the last account is dropped.
            router.reset()
            if old == .ready { _ = PushInbox.shared.take() }
        }
    }
}

struct LaunchingView: View {
    var body: some View { ZStack { BucksColor.purple.ignoresSafeArea(); BucksWordmark(color: .white, height: 48) } }
}

/// Signed out: splash → phone number → code.
struct AuthFlow: View {
    enum Step: Hashable { case login, otp }
    @State private var path: [Step] = [[], [.login], [.login, .otp]][min(RootView.previewAuthStep, 2)]
    var body: some View {
        NavigationStack(path: $path) {
            SplashScreen { path.append(.login) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .login: LoginScreen { path.append(.otp) }
                    case .otp: OtpScreen()
                    }
                }
        }
    }
}

/// Signed in: the five tab roots with everything pushed on top, the bottom bar, the "Bucks Pro" side menu, the ringing-request card for
/// drivers, the ride navigation and the permission prompts (Android's BucksAppUi).
struct MainStack: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var showIntro = IntroState.pending
    @State private var locDisclosure = false
    @State private var notifHelp: RingAlert.Problem?

    private struct RideKey: Equatable { var id: String?; var status: RideStatus? }

    /// A driver trip in progress is full-screen, like the design (no bottom navigation).
    private var onTrip: Bool {
        guard let d = session.dispatch.driverRide, d.status != .ringing else { return false }
        return router.tab == .home && router.path.isEmpty
    }
    private var tripElsewhere: Bool {
        guard let d = session.dispatch.driverRide, d.status != .ringing else { return false }
        return !(router.tab == .home && router.path.isEmpty)
    }
    /// Android: Home, Feed, Services, For you, search and account show it; every other screen (listing profiles included) does not.
    private var showBottomBar: Bool {
        if onTrip { return false }
        guard let last = router.path.last else { return true }
        switch last { case .search, .account: return true; default: return false }
    }
    /// The highlighted item: search belongs to Services, the pushed account screen to Profile, otherwise the tab at the root.
    private var currentTab: BottomTab {
        guard let last = router.path.last else { return router.tab }
        switch last { case .search: return .services; case .account: return .account; default: return router.tab }
    }

    var body: some View {
        @Bindable var router = router
        ZStack {
            // The bar is laid out explicitly under the stack (a safeAreaInset on a NavigationStack does not reach the screens inside it on every iOS version).
            VStack(spacing: 0) {
                if tripElsewhere { tripBar }
                NavigationStack(path: $router.path) {
                    tabRoot.navigationDestination(for: Route.self) { destination($0) }
                }
                if showBottomBar { BucksBottomBar(current: router.tab) { router.select($0) } }
            }
            // A ringing request is a card over whatever screen is showing; it never moves anyone away from a ride in progress.
            if let dr = session.dispatch.driverRide, dr.status == .ringing {
                RideRequestCard(dr: dr, busy: session.dispatch.busy, onAccept: { session.dispatch.driverAccept() }, onDecline: { session.dispatch.driverDecline() })
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            if router.menuOpen { SideMenu(isOpen: $router.menuOpen) }
            if showIntro { BrandIntro { showIntro = false; IntroState.pending = false }.transition(.opacity) }
        }
        .environment(\.openBucksMenu, { withAnimation(.easeOut(duration: 0.25)) { router.menuOpen = true } })
        // The cart next to Messages in every top bar (cloud builds), with the piece count across every shop in it.
        .environment(\.bucksCartAction, session.cloud ? CartAction(count: session.commerce.count) { if router.path.last != .cart { router.push(.cart) } } : nil)
        .animation(.easeOut(duration: 0.25), value: session.dispatch.driverRide?.id)
        .confirmationGate()
        .rideRing(session.dispatch.driverRide?.status == .ringing)
        .bucksPushRouting()
        .onChange(of: RideKey(id: session.dispatch.ride?.id, status: session.dispatch.ride?.status)) { old, new in rideChanged(from: old, to: new) }
        .onChange(of: session.dispatch.driverRide?.id) { _, _ in tripRestored() }
        .onChange(of: session.dispatch.driverRide?.status) { old, new in
            if old == .ringing, new == .toPickup { router.select(.home) }
            // A request ringing for me brings Home, where the accept card and the map are, to the front (Android does the same).
            if new == .ringing, old != .ringing, session.dispatch.ride == nil, !(router.tab == .home && router.path.isEmpty) { router.select(.home) }
        }
        // Going online (or arriving already online): say so when a request could not ring the phone outside the app. Waits for the intro.
        .task(id: [session.dispatch.online, showIntro]) {
            guard session.dispatch.online, !showIntro, !RootView.previewSkipPrompts else { return }
            _ = await RingAlert.requestPermission()
            notifHelp = await RingAlert.problem()
        }
        .task { if let r = session.dispatch.ride, let route = Route.ride(for: r.status) { router.showRide(route) } }
        // Play policy (and App Review): explain what location is used for before the system prompt appears. Prompts wait for the intro.
        .task(id: showIntro) {
            guard !showIntro, !RootView.previewSkipPrompts else { return }
            if session.location.notDetermined { locDisclosure = true }
            _ = await RingAlert.requestPermission()
        }
        .alert("Use your location", isPresented: $locDisclosure) {
            Button("Continue") { session.location.requestPermission() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Bucks uses your location to find riders, shops and services near you and to set your pick-up point. If you go online as a driver, Bucks keeps sharing your location while you're online, even when the app is closed, so nearby customers can ring you. It stops when you go offline.")
        }
        .alert("Turn on notifications", isPresented: Binding(get: { notifHelp != nil }, set: { if !$0 { notifHelp = nil } })) {
            Button("Open settings") { notifHelp = nil; openSettings() }
            Button("Not now", role: .cancel) { notifHelp = nil }
        } message: {
            Text("\(notifHelp?.message ?? "") Turn them on so requests reach you when Bucks is closed or the screen is off. You're online either way.")
        }
    }

    @ViewBuilder private var tabRoot: some View {
        switch router.tab {
        case .home: HomeScreen()
        case .feed: FeedScreen()
        case .services: ServicesScreen()
        case .recommended: RecommendedScreen()
        case .account: AccountScreen()
        }
    }

    /// A driver on a trip who is on another screen gets a way back to it (above the content, so no button is covered).
    private var tripBar: some View {
        Button { router.select(.home) } label: {
            HStack {
                Text("Trip in progress").font(.bucks(.titleSmall)).foregroundStyle(BucksColor.onPrimary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Return").font(.bucks(.labelLarge)).foregroundStyle(BucksColor.onPrimary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(BucksColor.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain).accessibilityLabel("Trip in progress. Return to the trip")
    }

    private func openSettings() {
        #if os(iOS)
        if let u = URL(string: UIApplication.openNotificationSettingsURLString) ?? URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        #endif
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .destination: DestinationScreen()
        case .chooseRide: ChooseRideScreen()
        case .confirmPickup: ConfirmPickupScreen()
        case .searching: SearchingScreen()
        case .driverFound: DriverFoundScreen()
        case .inRide: InRideScreen()
        case .pay: PayScreen()
        case .rateRide: RateRideScreen()
        case .vehicles: VehiclesScreen()
        case .vehicleEdit(let id): VehicleEditScreen(id: id)
        case .vehicleStats: VehicleStatsScreen()
        case .paymentQr: PaymentQrScreen()
        case .invites: InvitesScreen()
        case .search: CloudSearchScreen()
        case .listing(let id): ListingProfileScreen(id: id)
        case .cart: CloudCartScreen()
        case .order(let id): CloudOrderScreen(id: id)
        case .myOrders: MyOrdersScreen()
        case .vendorOrders(let id): VendorOrdersScreen(listingId: id)
        case .deliveryTrack(let id): DeliveryTrackScreen(id: id)
        case .myListings: StudioScreen()
        case .studio(let id): ListingDashboardScreen(id: id)
        case .listingEdit(let id, let kind, let service): ListingEditScreen(id: id, kind: kind, service: service)
        case .listingDocs(let id): ListingDocsScreen(id: id)
        case .showcaseDocs(let id): ShowcaseDocsManageScreen(id: id)
        case .staffReview: StaffReviewScreen()
        case .itemEdit(let listing, let item): ItemEditScreen(listing: listing, item: item)
        case .members(let id): MembersScreen(id: id)
        case .recommendShow(let id): RecommendShowScreen(id: id)
        case .recommendScan: RecommendScanScreen()
        case .listingJobs(let id): ListingJobsScreen(id: id)
        case .job(let id): JobScreen(id: id)
        case .jobNew(let id): NewJobScreen(listingId: id)
        case .myApplications: MyApplicationsScreen()
        case .jobsNear: JobsNearScreen()
        case .messages: MessagesScreen()
        case .chat(let id): ChatScreen(id: id)
        case .newGroup: NewGroupScreen()
        case .sync: SyncScreen()
        case .moments(let author): MomentViewerScreen(author: author)
        case .momentNew: NewMomentScreen()
        case .post(let id): PostDetailScreen(id: id)
        case .createPost: CreatePostScreen()
        case .contacts: ContactsScreen()
        case .bucksId: BucksIdScreen()
        case .settingsPrivacy: PrivacyScreen()
        case .settingsNotifications: NotificationSettingsScreen()
        case .settingsAppearance: AppearanceScreen()
        case .settingsBlocked: BlockedScreen()
        case .settingsCloseFriends: CloseFriendsScreen()
        case .maps: MapsScreen()
        case .editProfile: CreateProfileScreen(editing: true)
        case .account: AccountScreen()
        }
    }

    /// Cloud ride follow-up: navigate as the task moves along (port of onCloudRide).
    private func rideChanged(from old: RideKey, to new: RideKey) {
        guard let id = new.id, let status = new.status, let ride = session.dispatch.ride else {
            if old.id != nil { router.popToRoot() }   // finished, cancelled or closed
            return
        }
        if old.id != id {   // a new request, or a trip restored after the app was killed
            // The destination and vehicle come back with a restored ride, so "Ring again" has something to ring.
            session.rideDest = ride.dest; session.rideKind = ride.kind
            if let r = Route.ride(for: status) { router.showRide(r) }
            return
        }
        guard old.status != status else { return }
        switch status {
        case .matched: router.showRide(.driverFound)
        case .searching: session.toast("Your rider cancelled. Ringing others nearby."); router.showRide(.searching)
        case .arrived: session.toast("Your rider is here. Share PIN \(ride.pin) to start.")
        case .inRide: router.showRide(.inRide)
        case .completed: router.showRide(.pay)
        case .paid: router.showRide(.rateRide)
        case .noDriver, .cancelled: break
        }
    }
    /// A trip restored after the app was killed: back on duty so location keeps flowing; Home shows the trip.
    private func tripRestored() {
        guard let d = session.dispatch.driverRide, d.status != .ringing else { return }
        router.select(.home)
        if !session.dispatch.online { Task { await session.setOnline(true) } }
    }
}

/// Whether the wordmark intro still has to play this launch.
enum IntroState { nonisolated(unsafe) static var pending = true }

/// The wordmark intro for a signed-in cold start (BrandIntro): purple, the wordmark settles in, then it fades into Home.
struct BrandIntro: View {
    var onDone: () -> Void
    @State private var shown = false
    var body: some View {
        ZStack {
            BucksColor.purple.ignoresSafeArea()
            BucksWordmark(color: .white, height: 56).scaleEffect(shown ? 1 : 0.9).opacity(shown ? 1 : 0)
        }
        .task {
            withAnimation(.easeOut(duration: 0.45)) { shown = true }
            try? await Task.sleep(nanoseconds: (bucksReduceMotion ? 400 : 1_100) * 1_000_000)
            onDone()
        }
        .accessibilityHidden(true)
    }
}
