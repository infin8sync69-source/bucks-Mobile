import Foundation
import Testing
@testable import BucksCore

/// One code request at a time: a second tap while Firebase is still checking the app would text a second code and void the first.
/// Part of DispatchTests so it runs serialized with every suite that configures the shared Backend.
extension DispatchTests {
    final class CountingSignIn: PhoneSignIn, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var sends: Int { lock.lock(); defer { lock.unlock() }; return count }
        var uid: String? { nil }
        var projectName: String? { nil }
        func idToken(forceRefresh: Bool) async throws -> String? { nil }
        func sendCode(phone: String, resend: Bool) async throws -> PhoneSendResult {
            lock.lock(); count += 1; lock.unlock()
            try? await Task.sleep(nanoseconds: 300_000_000)
            return .codeSent
        }
        func verify(code: String) async throws {}
        func signOut() throws {}
        func deleteAccount() async throws {}
    }

    @Test func aSecondRequestWhileSendingIsIgnored() async {
        RingAlert.enabled = false
        let s = AppSession(), fake = CountingSignIn()
        s.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), auth: fake)
        s.tempPhone = "9000000001"
        async let first: Void = s.sendOtp()
        async let second: Void = s.sendOtp(resend: true)
        _ = await (first, second)
        #expect(fake.sends == 1)
        #expect(!s.sendingOtp)
        // Once the first request is done, Resend works again.
        await s.sendOtp(resend: true)
        #expect(fake.sends == 2)
    }
}
