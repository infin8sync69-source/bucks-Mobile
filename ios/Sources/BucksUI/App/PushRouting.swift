import SwiftUI
import BucksCore

/// Push route strings (the server's `route` data key, vetted by `Push.safeRoute`) mapped to screens. Same list as Android's allow-list.
public enum PushRouting {
    /// The screen a safe route opens, or nil when it opens the app on its usual first screen ("home", "feed" and anything unknown).
    public static func route(forPush raw: String?) -> Route? {
        guard let r = Push.safeRoute(raw) else { return nil }
        switch r {
        case "sync": return .sync
        case "messages": return .messages
        case "invites": return .invites
        case "my/orders": return .myOrders
        case "my/applications": return .myApplications
        case "my/listings": return .myListings
        case "jobs-near": return .jobsNear
        case "bucks-id": return .bucksId
        default: break
        }
        let table: [(String, (String) -> Route)] = [
            ("chat/", { .chat($0) }), ("cloud-order/", { .order($0) }), ("orders-for/", { .vendorOrders($0) }), ("delivery/", { .deliveryTrack($0) }),
            ("moments/", { .moments($0) }), ("l/", { .listing($0) }), ("job/", { .job($0) }), ("jobs-of/", { .listingJobs($0) }),
            ("members/", { .members($0) }), ("studio/", { .studio($0) }), ("listing-docs/", { .listingDocs($0) }), ("doc-requests/", { .showcaseDocs($0) }), ("post/", { .post($0) }),
        ]
        for (prefix, make) in table where r.hasPrefix(prefix) { return make(String(r.dropFirst(prefix.count))) }
        return nil
    }
}

public extension PushRouting {
    /// The tab a route opens ("home" and "feed" are tabs, not pushed screens), like Android's navigate(HOME / FEED).
    static func tab(forPush raw: String?) -> BottomTab? {
        switch Push.safeRoute(raw) { case "home": .home; case "feed": .feed; default: nil }
    }
}

public func route(forPush raw: String?) -> Route? { PushRouting.route(forPush: raw) }

public extension View {
    /// Opens the screen of a tapped notification once the person is signed in and has a profile, then forgets it. Apply inside the
    /// view that provides the session and router (RootView).
    func bucksPushRouting() -> some View { modifier(PushRoutingModifier()) }
}

private struct PushRoutingModifier: ViewModifier {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    private struct Trigger: Equatable { var pending: String?; var ready: Bool }

    func body(content: Content) -> some View {
        content.onChange(of: Trigger(pending: PushInbox.shared.pending, ready: session.phase == .ready), initial: true) { _, t in
            guard t.ready, t.pending != nil, let raw = PushInbox.shared.take() else { return }
            // Android: "home" pops back to Home, anything else is pushed on top of where the person is (a ride in progress stays under it).
            if let tab = PushRouting.tab(forPush: raw) { router.select(tab) }
            else if let r = PushRouting.route(forPush: raw), router.path.last != r { router.push(r) }
        }
    }
}
