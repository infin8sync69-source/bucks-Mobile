import UIKit
import UserNotifications
import FirebaseMessaging
import BucksCore

/// Firebase Cloud Messaging on iPhone: registers with APNs and hands out the FCM token the server sends to. It does not ask for notification
/// permission: the app does that after the intro (MainStack), and a token is valid before and after the person answers.
final class FirebasePush: NSObject, PushTokenProvider, MessagingDelegate, @unchecked Sendable {
    func token() async throws -> String? {
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        // FCM can only mint a token once iOS has handed over the APNs token, a moment after registering. Try again for a while;
        // `didReceiveRegistrationToken` below stores it as soon as it exists in any case. (No APNs token at all on the Simulator.)
        var last: Error?
        for _ in 0..<8 {
            do { return try await Messaging.messaging().token() } catch {
                last = error
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        throw last ?? CancellationError()
    }

    func deleteToken() async throws { try await Messaging.messaging().deleteToken() }

    /// FCM hands out a token on first start and now and then afterwards; the server needs the current one.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await Push.shared.register(fcmToken) }
    }
}
