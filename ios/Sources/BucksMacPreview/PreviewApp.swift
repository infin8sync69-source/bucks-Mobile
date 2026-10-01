#if os(macOS)
import SwiftUI
import AppKit
import BucksCore
import BucksUI

/// Phone sign-in that accepts the code 123456, so the whole flow can be tried without Firebase.
final class FakePhoneSignIn: PhoneSignIn, @unchecked Sendable {
    private let lock = NSLock()
    private var signedIn: Bool
    init(signedIn: Bool) { self.signedIn = signedIn }
    private func state() -> Bool { lock.lock(); defer { lock.unlock() }; return signedIn }
    private func set(_ v: Bool) { lock.lock(); signedIn = v; lock.unlock() }
    var uid: String? { state() ? "me" : nil }
    var projectName: String? { "bucks-preview" }
    func idToken(forceRefresh: Bool) async throws -> String? {
        guard uid != nil else { return nil }
        return "h." + Data(#"{"role":"authenticated"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") + ".s"
    }
    func sendCode(phone: String, resend: Bool) async throws -> PhoneSendResult { try? await Task.sleep(nanoseconds: 400_000_000); return .codeSent }
    func verify(code: String) async throws {
        guard code == "123456" else { throw NSError(domain: "preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "That code or number isn't valid. Check it and try again. (invalidVerificationCode)"]) }
        set(true)
    }
    func signOut() throws { set(false) }
    func deleteAccount() async throws { try signOut() }
}

@main
struct PreviewApp: App {
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

/// Owns the session and an ordinary AppKit window (390 × 844, a phone's size) so the harness can screenshot its own window reliably.
@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let session = AppSession()
    private let router = Router()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0)
        let args = ProcessInfo.processInfo.arguments
        RingAlert.enabled = false
        RootView.previewSkipPrompts = true
        HarnessRegistry.registerAll()
        Backend.shared.useProtocolClasses([FakeSupabase.self])
        let signedIn = args.contains("--signed-in")
        if signedIn { FakeSupabase.profileName = "Asha Rao"; FakeSupabase.profileArea = "Jayanagar" }
        session.configure(BackendConfig(url: "https://preview.supabase.co", anonKey: "anon"), auth: FakePhoneSignIn(signedIn: signedIn))
        if let i = args.firstIndex(of: "--auth-step"), i + 1 < args.count { RootView.previewAuthStep = Int(args[i + 1]) ?? 0 }

        let host = NSHostingController(rootView: RootView(session: session, router: router).frame(width: 390, height: 844))
        let w = NSWindow(contentViewController: host)
        w.title = "Bucks preview"; w.styleMask = [.titled, .closable]; w.setContentSize(NSSize(width: 390, height: 844)); w.center()
        NSApp.setActivationPolicy(.regular); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window = w

        // Jayanagar, Bengaluru: the pretend position of the phone.
        let session = session, router = router
        Task { @MainActor in
            for _ in 0..<60 { session.onLocation(LatLng(12.9279, 77.5836), mocked: false); try? await Task.sleep(nanoseconds: 3_000_000_000) }
        }
        if let i = args.firstIndex(of: "--scenario"), i + 1 < args.count {
            let name = args[i + 1]
            Task { @MainActor in await Scenarios.run(name, session: session, router: router); if args.contains("--quit") { exit(0) } }
        }
    }
}
#endif
