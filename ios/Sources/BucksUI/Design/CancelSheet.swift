import SwiftUI
import BucksCore

/// "Are you sure, and why?" for cancelling a ride or an order (Android `CancelSheet`). One tap on the keep button keeps everything;
/// cancelling needs a reason when `requireReason` (someone has already accepted), so the other side hears why. The reasons are
/// `CancelReasons` (BucksCore); "OTHER" opens a short note (200 characters). `nudge` is a gentle reminder, e.g. how often I cancelled today.
/// `onConfirm` does not close the sheet: the caller closes it once the server has agreed (so a refusal leaves it open), shows `busy`
/// while the call is in flight, and passes the server's refusal as `error`, which this sheet prints itself (a sheet covers the app's toasts).
/// Present it with `.sheet`; it cannot be swiped away while busy.
public struct CancelSheet: View {
    let title: String
    let message: String
    let reasons: [CancelReason]
    let requireReason: Bool
    let confirmLabel: String
    var keepLabel: String
    var reasonTitle: String
    var nudge: String?
    var busy: Bool
    var error: String?
    let onConfirm: (_ code: String?, _ note: String) -> Void
    let onDismiss: () -> Void

    @State private var sel: String?
    @State private var note = ""

    public init(title: String, message: String, reasons: [CancelReason], requireReason: Bool, confirmLabel: String,
                keepLabel: String = "Keep it", reasonTitle: String = "Why are you cancelling?", nudge: String? = nil, busy: Bool = false, error: String? = nil,
                onConfirm: @escaping (_ code: String?, _ note: String) -> Void, onDismiss: @escaping () -> Void) {
        self.title = title; self.message = message; self.reasons = reasons; self.requireReason = requireReason; self.confirmLabel = confirmLabel
        self.keepLabel = keepLabel; self.reasonTitle = reasonTitle; self.nudge = nudge; self.busy = busy; self.error = error
        self.onConfirm = onConfirm; self.onDismiss = onDismiss
    }

    private var canConfirm: Bool { !busy && (!requireReason || sel != nil) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).accessibilityAddTraits(.isHeader)
                Muted(message).padding(.top, 4)
                if let nudge { Notice(nudge).padding(.top, 12) }
                Text(requireReason ? reasonTitle : "\(reasonTitle) (optional)").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    .padding(.top, 16).padding(.bottom, 4)
                ForEach(reasons) { r in row(r) }
                if sel == "OTHER" {
                    BucksField(Binding(get: { note }, set: { note = String($0.prefix(200)) }), placeholder: "Tell them in a few words (optional)", singleLine: false, minLines: 2)
                        .padding(.top, 8)
                    Muted("\(note.count)/200", align: .trailing).padding(.top, -8).padding(.bottom, 4)
                }
                if let error {
                    Text(error).bucks(.bodySmall).foregroundStyle(BucksColor.error).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 12).accessibilityAddTraits(.updatesFrequently)
                }
                PrimaryButton(keepLabel, enabled: !busy) { onDismiss() }.padding(.top, 16)
                BadButton(busy ? "Cancelling…" : confirmLabel, enabled: canConfirm) { onConfirm(sel, note.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if requireReason && sel == nil { Muted("Pick a reason to cancel.", align: .center).padding(.top, 2) }
            }
            .padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
    }

    /// One radio row, at least 48 pt tall. Tapping the chosen row again clears it when a reason is optional.
    private func row(_ r: CancelReason) -> some View {
        let picked = sel == r.code
        return Button {
            Haptics.light()
            sel = (picked && !requireReason) ? nil : r.code
        } label: {
            HStack(spacing: 12) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle").font(.system(size: 20))
                    .foregroundStyle(picked ? BucksColor.primary : BucksColor.onSurfaceVariant)
                Text(r.label).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
