import SwiftUI
import BucksCore
import UserNotifications

/// What Bucks tells me about, quiet hours, and whether this phone lets Bucks show notifications at all.
struct NotificationSettingsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var edited: SettingsRow?
    @State private var qOn = false
    @State private var from = "22:00"
    @State private var to = "07:00"

    // Keys the notify Edge Function checks (supabase/functions/notify/index.ts, NotifyKey); a missing key means on, except offers.
    private static let keys: [(String, String)] = [
        ("messages", "Messages"), ("sync_requests", "Sync requests"), ("moments", "Moments from synced people"), ("comments", "Comments on my posts"),
        ("my_orders", "Updates on orders I place"), ("my_trips", "Updates on rides and deliveries I book"), ("orders", "New orders for my businesses"),
        ("tasks", "Trips I drive (cancellations, payments)"), ("offers", "Offers and deals nearby"),
    ]

    private var saved: SettingsRow { session.social.settings ?? SettingsRow(profileId: session.me?.id ?? "") }
    private var row: SettingsRow { edited ?? saved }

    private func on(_ k: String) -> Bool { row.notify[k]?.bool ?? (k != "offers") }
    private func binding(_ k: String) -> Binding<Bool> {
        Binding(get: { on(k) }, set: { v in
            var r = row; var o = r.notify.object ?? [:]; o[k] = .bool(v); r.notify = .object(o); edited = r
        })
    }
    private func load() {
        let q = saved.quietHours
        qOn = q != nil; from = q?["from"]?.string ?? "22:00"; to = q?["to"]?.string ?? "07:00"
    }
    private func validTime(_ s: String) -> Bool { s.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Notifications", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PhoneNotificationStatus()
                        ForEach(Self.keys, id: \.0) { k, l in SettingsToggleRow(l, on: binding(k)) }
                        SettingsToggleRow("Quiet hours", detail: "No sounds or banners between these times. Ride requests still ring while you're online.", on: $qOn)
                        if qOn {
                            HStack(alignment: .top, spacing: 10) {
                                BucksField(Binding(get: { from }, set: { from = String($0.prefix(5)) }), label: "From", placeholder: "22:00")
                                BucksField(Binding(get: { to }, set: { to = String($0.prefix(5)) }), label: "To", placeholder: "07:00")
                            }.padding(.top, 8)
                        }
                        PrimaryButton("Save") {
                            var r = row
                            r.quietHours = qOn && validTime(from) && validTime(to) ? .object(["from": .string(from), "to": .string(to)]) : nil
                            session.social.saveSettings(r)
                        }.padding(.top, 20)
                        Muted("Notifications reach this phone even when Bucks is closed. Quiet hours make them silent; ride, delivery and new-order alerts still ring, because someone is waiting.").padding(.top, 12)
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .onChange(of: session.social.settings, initial: true) { _, _ in edited = nil; load() }
    }
}

/// Whether this phone lets Bucks show notifications, with the fix and a test. The server can send a notification perfectly and the phone
/// still show nothing when notifications are switched off for the app in the phone's settings (or permission was never granted).
private struct PhoneNotificationStatus: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = true
    @State private var asked = true

    var body: some View {
        BucksCard(tint: !enabled) {
            Text(enabled ? "This phone shows Bucks notifications" : "Notifications are off for Bucks on this phone").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
            Muted(enabled ? "If a comment, like or message still doesn't appear, tap Send a test. Also check that the phone isn't in Do Not Disturb or Low Power Mode."
                          : "Comments, likes, messages and orders reach this phone but iOS hides them. Turn notifications on for Bucks.").padding(.top, 4)
            HStack(spacing: 8) {
                if !enabled { SmallButton("Turn on") { turnOn() } }
                SmallButton("Open phone settings", tonal: true) { openSettings() }
                if enabled { SmallButton("Send a test", tonal: true) { sendTest() } }
            }.padding(.top, 10)
        }
        .padding(.bottom, 16)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        #if os(iOS)
        let s = await UNUserNotificationCenter.current().notificationSettings()
        enabled = [.authorized, .provisional, .ephemeral].contains(s.authorizationStatus)
        asked = s.authorizationStatus != .notDetermined
        #endif
    }

    private func turnOn() {
        if asked { openSettings(); return }
        #if os(iOS)
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await refresh() }
        #endif
    }
    private func openSettings() {
        #if os(iOS)
        openSystemURL(UIApplication.openNotificationSettingsURLString)
        #endif
    }
    private func sendTest() {
        #if os(iOS)
        let c = UNMutableNotificationContent()
        c.title = "Test from Bucks"; c.body = "If you can read this, notifications work on this phone."; c.sound = .default
        let req = UNNotificationRequest(identifier: "bucks-test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req) { e in if e != nil { Task { @MainActor in session.toast("Couldn't send the test.") } } }
        #endif
    }
}
