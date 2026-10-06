import Foundation

/// The push service on the phone. The iOS app implements it with Firebase Messaging (ios/App/FirebasePush.swift), which turns the APNs
/// token into an FCM token, so the server's existing FCM sender (supabase/functions/notify) reaches iPhones too.
public protocol PushTokenProvider: AnyObject, Sendable {
    /// Asks for notification permission (the first time), registers with APNs, and returns this phone's FCM token (nil when it has none yet).
    func token() async throws -> String?
    /// Retires the token at FCM so nothing addressed to the previous person reaches the next one who signs in here.
    func deleteToken() async throws
}

public extension Backend {
    /// Stores (or takes over) this phone's token for the signed-in person (push.sql). Platform is "ios".
    func registerDeviceToken(_ token: String, platform: String = "ios") async throws {
        try await rpcVoid("register_device_token", ["p_token": token, "p_platform": platform])
    }
    /// Forgets this phone before sign-out.
    func unregisterDeviceToken(_ token: String) async throws {
        try await rpcVoid("unregister_device_token", ["p_token": token])
    }
}

/// What kind of notification a push is. iOS has no channels: the kind becomes the thread (grouping), the category and the interruption level.
public enum PushKind: String, CaseIterable, Sendable {
    /// `tasks`: updates on my own trips and deliveries; `ride`: a new request ringing this driver (the Bucks ride-request tune).
    case messages, orders, tasks, ride, social
    public init(type: String?) { self = PushKind(rawValue: type ?? "") ?? .social }
    /// Android's channel ids, kept as category identifiers so settings and logs read the same on both phones.
    public var categoryId: String {
        switch self { case .messages: "bucks_messages"; case .orders: "bucks_orders"; case .tasks: "bucks_trips"; case .ride: "bucks_ride_request"; case .social: "bucks_social" }
    }
    public static let quietCategoryId = "bucks_quiet"
}

/// One push as the server sends it (data keys type, title, body, route, quiet), read from the notification's userInfo.
public struct PushPayload: Equatable, Sendable {
    public var kind: PushKind
    public var title: String
    public var body: String
    /// Already vetted by `Push.safeRoute`.
    public var route: String?
    public var quiet: Bool

    public init(kind: PushKind, title: String, body: String, route: String?, quiet: Bool) { self.kind = kind; self.title = title; self.body = body; self.route = route; self.quiet = quiet }

    /// nil when there is no title (nothing to show), like BucksMessagingService.onMessageReceived.
    public init?(userInfo: [AnyHashable: Any]) {
        func s(_ k: String) -> String? { userInfo[k] as? String }
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"]
        let apsTitle = (alert as? [String: Any])?["title"] as? String
        let apsBody = (alert as? [String: Any])?["body"] as? String ?? (alert as? String)
        guard let title = s("title") ?? apsTitle else { return nil }
        self.init(kind: PushKind(type: s("type")), title: title, body: s("body") ?? apsBody ?? "", route: Push.safeRoute(s("route")), quiet: s("quiet") == "true")
    }

    /// How to present it while Bucks is open: quiet hours land silently in the notification list, a ride request is not shown at all (the
    /// request card rings inside the app, as on Android), everything else banners with sound.
    public var foreground: Presentation {
        if kind == .ride { return Presentation(banner: false, list: false, sound: false) }
        return quiet ? Presentation(banner: false, list: true, sound: false) : Presentation(banner: true, list: true, sound: true)
    }
    /// `time-sensitive` for rides and deliveries (the one you must not miss), `passive` in quiet hours.
    public var interruptionLevel: String { quiet ? "passive" : ((kind == .tasks || kind == .ride) ? "timeSensitive" : "active") }

    public struct Presentation: Equatable, Sendable { public var banner: Bool; public var list: Bool; public var sound: Bool }
}

/// Token registration with the server. Call `registerIfSignedIn()` once the person is signed in and `unregister()` before signing out.
@MainActor
public final class Push {
    public static let shared = Push()
    /// Set by the app at launch; nil in builds without Firebase (registration then does nothing).
    public var provider: PushTokenProvider?
    private var registered: String?
    /// Set while (and after) signing out, so a token FCM hands out in the meantime is not stored against the leaving person.
    private var signingOut = false
    /// How long sign-out waits on each network step (server, then FCM) before going ahead without it.
    static let signOutStepSeconds = 5.0

    /// After sign-in: fetch this phone's token and store it against my profile.
    public func registerIfSignedIn() {
        guard Backend.shared.enabled, Backend.shared.uid != nil, let provider else { return }
        signingOut = false
        Task { if let t = try? await provider.token() { await register(t) } }
    }

    /// FCM rotated the token (or handed out the first one): store it.
    public func register(_ token: String) async {
        guard !token.isEmpty, !signingOut, Backend.shared.enabled, Backend.shared.uid != nil else { return }
        if (try? await Backend.shared.registerDeviceToken(token)) != nil { registered = token }
    }

    /// Before sign-out: remove this phone from my profile and retire the token at FCM. Await it and only then sign out: the request is signed
    /// with the Firebase user. Never fails and gives up on each step after a few seconds, so signing out offline still works.
    public func unregister() async {
        guard Backend.shared.enabled else { return }
        signingOut = true
        let known = registered; registered = nil
        let provider = provider
        let step = Push.signOutStepSeconds
        _ = await withTimeoutOrNil(step) {
            let token: String?
            if let known { token = known } else { token = (try? await provider?.token()) ?? nil }
            if let token, Backend.shared.uid != nil { try? await Backend.shared.unregisterDeviceToken(token) }
        }
        _ = await withTimeoutOrNil(step) { try? await provider?.deleteToken() }
    }

    /// Only routes the app knows how to open; anything else opens the app on its usual first screen. Same list as Push.kt.
    public nonisolated static func safeRoute(_ route: String?) -> String? {
        guard let r = route?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty, r.count <= 200, !r.contains("\n") else { return nil }
        if exactRoutes.contains(r) { return r }
        return routePrefixes.contains { r.hasPrefix($0) && r.count > $0.count } ? r : nil
    }
    public nonisolated static let exactRoutes: Set<String> = ["home", "feed", "sync", "messages", "invites", "my/orders", "my/applications", "my/listings", "jobs-near", "bucks-id"]
    public nonisolated static let routePrefixes = ["chat/", "cloud-order/", "orders-for/", "delivery/", "moments/", "l/", "job/", "jobs-of/", "members/", "studio/", "listing-docs/", "doc-requests/", "post/"]
}

/// A tapped notification's route, waiting for the person to be signed in. The app delegate fills it; the shell opens it once and clears it.
@MainActor @Observable
public final class PushInbox {
    public static let shared = PushInbox()
    public private(set) var pending: String?
    public func open(_ route: String?) { if let r = Push.safeRoute(route) { pending = r } }
    /// The waiting route, once.
    public func take() -> String? { defer { pending = nil }; return pending }
}
