import Foundation
#if os(iOS)
import AudioToolbox
#endif
import UserNotifications

/// Whether the app is on screen (the ring only needs a notification when it is not). The app's scene phase feeds `setForeground`.
@MainActor
public final class AppLife {
    public static let shared = AppLife()
    public private(set) var isForeground = true
    private var observers: [(Bool) -> Void] = []

    public func setForeground(_ on: Bool) {
        guard on != isForeground else { return }
        isForeground = on
        if on { RingAlert.cancel() }
        observers.forEach { $0(on) }
    }
    public func observeForeground(_ f: @escaping (Bool) -> Void) { observers.append(f) }
}

/// Who is online from this phone, for the paths that outlive the UI: a ViewModel that is already gone, sign-out, and the app being
/// terminated. Set when going online, cleared when going offline.
public final class Presence: @unchecked Sendable {
    public static let shared = Presence()
    private let lock = NSLock()
    private var _meId: String?
    public var meId: String? { get { lock.lock(); defer { lock.unlock() }; return _meId } set { lock.lock(); _meId = newValue; lock.unlock() } }

    /// Presence off, best effort: never throws, gives up after 4 s, and is safe to call twice.
    public func offline() async {
        guard let me = meId else { return }
        meId = nil
        _ = await withTimeoutOrNil(4) { try? await Backend.shared.setOffline(me: me) }
    }
}

/// Runs `op` and returns its result, or nil when it hasn't finished within `seconds` (the work is cancelled).
public func withTimeoutOrNil<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await op() }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Tells an online driver about a ringing request. In the app: a short buzz (the card is on screen). Otherwise a time-sensitive
/// local notification, which carries the sound. It is replaced by the next ring and cleared when the request is accepted, passed,
/// expired or cancelled, and times out on its own.
public enum RingAlert {
    private static let identifier = "bucks.ring"
    /// False in unit tests, where there is no app bundle for the notification centre to attach to.
    nonisolated(unsafe) public static var enabled = true

    public enum Problem: String {
        case off = "Notifications are off for Bucks, so a ride request can't ring you while the app isn't open."
        case quiet = "The Bucks notifications are set to silent, so a request may not pop up or ring while the app isn't open."
        public var message: String { rawValue }
    }

    @MainActor public static func ring(_ dr: DriverRide) {
        if AppLife.shared.isForeground { buzz() } else { post(dr) }
    }
    public static func cancel() {
        guard enabled else { return }
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [identifier]); c.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Why a request could not alert the driver in the background (nil when it can).
    public static func problem() async -> Problem? {
        guard enabled else { return nil }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .denied, .notDetermined: return .off
        default: return s.soundSetting == .disabled ? .quiet : nil
        }
    }
    public static func requestPermission() async -> Bool {
        guard enabled else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func buzz() {
        #if os(iOS)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        #endif
    }

    @MainActor private static func post(_ dr: DriverRide) {
        guard enabled else { return }
        let delivery = dr.isDelivery
        let away = dr.pickupKm < 1 ? "\(Int(dr.pickupKm * 1000)) m" : "\(dr.pickupKm) km"
        let content = UNMutableNotificationContent()
        content.title = "\(delivery ? "New delivery" : "New ride request") · ₹\(dr.fare)"
        content.body = "\(dr.pickupAt.components(separatedBy: " · ")[0]) · \(away) away · tap to accept"
        content.sound = .default   // a critical-alert sound needs Apple's Critical Alerts entitlement, which this app does not have
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["route": "home"]
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: [identifier])
        c.add(req)
        // Android's notification times out with the request; a local one cannot, so take it away when the ring is over (unless a newer ring replaced it).
        generation += 1
        let mine = generation, secs = max(dr.secondsLeft, 5)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            if generation == mine { cancel() }
        }
    }
    @MainActor private static var generation = 0
}
