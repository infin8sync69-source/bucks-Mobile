import SwiftUI
import LocalAuthentication
import BucksCore

/// Holds the action waiting for a yes. The assistant (or any screen) can only propose; `ConfirmationSheet` is where the person confirms.
@MainActor @Observable
public final class ConfirmationCenter {
    public static let shared = ConfirmationCenter()
    public var pending: PendingAction?
    public init() {}
}

public extension AppSession {
    /// Proposes `action`; the confirmation gate (`.confirmationGate()`) shows it and runs it only after the person confirms
    /// (and, when `needsBiometric`, proves it is them). Nothing moves money before that.
    func confirmAction(_ action: PendingAction) { ConfirmationCenter.shared.pending = action }

    /// What is waiting for a yes: a proposed action, else the ride booking (`pending`).
    var pendingAction: PendingAction? { ConfirmationCenter.shared.pending ?? pending.map(PendingAction.init(booking:)) }

    /// Runs the waiting action if it is still `action` (Called after the person tapped Confirm and passed the check).
    func confirmPendingAction(_ action: PendingAction) {
        let c = ConfirmationCenter.shared
        if let p = c.pending, p.id == action.id { c.pending = nil; p.run() }
        else if let b = pending, b.id == action.id { confirmPending(b) }
    }
    func cancelPendingAction() {
        if ConfirmationCenter.shared.pending != nil { ConfirmationCenter.shared.pending = nil } else { cancelPending() }
    }
}

public extension View {
    /// Presents the confirmation sheet for `session.confirmAction(_)` proposals and for the ride booking (`session.pending`).
    func confirmationGate() -> some View { modifier(ConfirmationGate()) }
}

private struct ConfirmationGate: ViewModifier {
    @Environment(AppSession.self) private var session
    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { session.pendingAction },
            set: { if $0 == nil { session.cancelPendingAction() } }
        )) { p in ConfirmationSheet(pending: p) }
    }
}

/// Device-owner check (fingerprint, face or the device passcode) before a protected action.
@MainActor
enum DeviceAuth {
    static func canAuthenticate() -> Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }
    /// nil when the person passed; otherwise the system's reason it did not.
    static func authenticate(reason: String) async -> String? {
        let ctx = LAContext()
        do { _ = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason); return nil }
        catch { return error.localizedDescription }
    }
}

/// The gate every money-moving action passes through (Confirm.kt's ConfirmationSheet): what is being done, the amount and who with,
/// and above ₹500 or with a first-time counterparty a biometric / passcode check before Confirm runs it.
public struct ConfirmationSheet: View {
    @Environment(AppSession.self) private var session
    let pending: PendingAction
    @State private var checking = false
    public init(pending: PendingAction) { self.pending = pending }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(pending.title).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
                Muted(pending.summary).padding(.top, 6)
                BucksCard(tint: true) {
                    VStack(spacing: 10) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 0) {
                                Muted("Amount")
                                Text("₹\(pending.amount)").bucks(.headlineMedium).foregroundStyle(BucksColor.onSurface)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 0) {
                                Muted("With", align: .trailing)
                                Text(pending.counterparty).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).multilineTextAlignment(.trailing)
                            }
                        }
                        // The full badge on its own row under the counterparty name, so it never shares width with the amount.
                        if let t = pending.counterpartyTrust {
                            HStack { Spacer(); TrustBadge(up: t.up, down: t.down) }
                        }
                    }
                }.padding(.vertical, 16)
                if pending.needsBiometric {
                    Notice("This needs your fingerprint, face or device PIN because it's over ₹500 or your first time with this provider.").padding(.bottom, 12)
                }
                PrimaryButton(pending.needsBiometric ? "Confirm with biometrics" : "Confirm", enabled: !checking) { confirm() }
                GhostButton("Cancel") { session.cancelPendingAction() }.padding(.top, 10)
                Muted("Nothing is booked or ordered until you confirm. The assistant can only propose.", align: .center).frame(maxWidth: .infinity).padding(.top, 12)
            }
            .padding(Gutter).padding(.top, 8)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: pending.id) { Speaker.shared.say("\(pending.title). \(pending.summary).", lang: VoiceSettings.shared.lang) }
        .onDisappear { Speaker.shared.stop() }
    }

    private func confirm() {
        guard pending.needsBiometric else { return session.confirmPendingAction(pending) }
        guard DeviceAuth.canAuthenticate() else {
            return session.toast("Set a screen lock (PIN, pattern or fingerprint) in Settings to confirm this.")
        }
        checking = true
        Task {
            let failure = await DeviceAuth.authenticate(reason: "Confirm ₹\(pending.amount) · \(pending.title)")
            checking = false
            if let failure { session.toast("Not confirmed: \(failure)") } else { session.confirmPendingAction(pending) }
        }
    }
}
