import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import BucksCore
import BucksUI

@main
struct BucksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let session = AppSession()

    init() {
        // Cloud features need GoogleService-Info.plist (Firebase) and the Supabase values in Config/Secrets.xcconfig; without them the app
        // still launches and shows the sign-in screens, but sign-in and rides are unavailable (same as Android without google-services.json).
        let firebaseReady = AppDelegate.firebaseAvailable
        let info = Bundle.main.infoDictionary ?? [:]
        let config = BackendConfig(url: info["SupabaseURL"] as? String ?? "", anonKey: info["SupabaseAnonKey"] as? String ?? "")
        // Mapbox tiles, search and routes when a token is built in; OpenStreetMap's servers otherwise (same as Android).
        MapServices.token = (info["MapboxToken"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        session.configure(config, auth: firebaseReady ? FirebasePhoneAuth() : nil)
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                // The reCAPTCHA fallback of phone sign-in comes back to the app through its URL scheme (REVERSED_CLIENT_ID).
                .onOpenURL { url in if FirebaseApp.app() != nil { _ = Auth.auth().canHandle(url) } }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var firebaseAvailable: Bool { Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil }
    private let push = FirebasePush()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase has to be configured here, not in the App's init: it hooks the app delegate to receive the verification push for phone
        // sign-in, and in a SwiftUI app the delegate only exists from this point (without it sign-in fails with "notification not forwarded").
        if Self.firebaseAvailable {
            FirebaseApp.configure()
            #if DEBUG && targetEnvironment(simulator)
            // The simulator can't get a real APNs token, so only the console's "Phone numbers for testing" work there.
            Auth.auth().settings?.isAppVerificationDisabledForTesting = true
            #endif
            Messaging.messaging().delegate = push
            Push.shared.provider = push
        }
        UNUserNotificationCenter.current().delegate = self
        // iOS has no channels: a category per kind (and the thread id in each push) groups notifications the way Android's channels do.
        let ids = PushKind.allCases.map(\.categoryId) + [PushKind.quietCategoryId]
        UNUserNotificationCenter.current().setNotificationCategories(Set(ids.map { UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [], options: []) }))
        return true
    }
    // Firebase's automatic delegate hooking is switched off (Info.plist FirebaseAppDelegateProxyEnabled = NO): in a SwiftUI app it can miss the
    // delegate, which breaks phone sign-in ("notification not forwarded"). These three methods are what it would have added.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        Messaging.messaging().apnsToken = deviceToken
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if FirebaseApp.app() != nil, Auth.auth().canHandleNotification(userInfo) { completionHandler(.noData); return }
        completionHandler(.noData)
    }
    /// Shows a push while Bucks is open (quiet hours land silently in the list); a ride request that rings shows as a banner too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Nobody signed in on this phone (or no Firebase in this build): whatever still arrives was meant for the person who signed out.
        guard FirebaseApp.app() != nil, Auth.auth().currentUser != nil else { return [] }
        // A local notification (the ring) has no push payload: show it like any other.
        guard let push = PushPayload(userInfo: notification.request.content.userInfo) else { return [.banner, .list, .sound] }
        var options: UNNotificationPresentationOptions = []
        if push.foreground.banner { options.insert(.banner) }
        if push.foreground.list { options.insert(.list) }
        if push.foreground.sound { options.insert(.sound) }
        return options
    }
    /// A tapped notification opens its screen once the person is signed in (PushRouting).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        await MainActor.run { PushInbox.shared.open(route) }
    }
    func applicationWillTerminate(_ application: UIApplication) {
        // Best effort: take a driver off the map when iOS ends the app (the server also drops presence after 5 minutes).
        // The wait pumps the run loop instead of blocking it: Firebase hands the sign-in token back on the main thread.
        final class Flag: @unchecked Sendable { var done = false }
        let flag = Flag()
        Task { await Presence.shared.offline(); flag.done = true }
        let end = Date().addingTimeInterval(3)
        while !flag.done && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }
}
