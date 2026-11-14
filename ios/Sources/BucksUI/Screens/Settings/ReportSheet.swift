import SwiftUI
import BucksCore

/// Report flow (ui/social/Report.kt): pick a reason, add detail if you like, optionally block the person too. Reasons that mean someone
/// may be in danger show emergency and helpline numbers straight away, before anything is sent.
struct ReportSheet: View {
    let target: ReportTarget
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var detail = ""
    @State private var alsoBlock: Bool

    init(target: ReportTarget) {
        self.target = target
        _alsoBlock = State(initialValue: target.kind == "PROFILE" || target.kind == "MESSAGE")
    }

    private var canBlock: Bool { target.ownerId != nil && target.ownerId != session.me?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "flag.fill").foregroundStyle(BucksColor.bad).accessibilityHidden(true)
                    Text(target.title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).accessibilityAddTraits(.isHeader)
                }
                Muted(target.ownerName.isEmpty ? "They won't know who reported it." : "\(target.ownerName) won't know who reported it.").padding(.top, 6).padding(.bottom, 12)
                ForEach(ReportReason.allCases) { r in
                    Button { reason = r } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: reason == r ? "largecircle.fill.circle" : "circle").font(.system(size: 20))
                                .foregroundStyle(reason == r ? BucksColor.primary : BucksColor.onSurfaceVariant)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                                if !r.hint.isEmpty { Text(r.hint).bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(reason == r ? [.isSelected] : [])
                }
                if reason?.urgent == true { helplines }
                if reason != nil {
                    BucksField(Binding(get: { detail }, set: { detail = String($0.prefix(500)) }), label: "Anything to add? (optional)", placeholder: "What happened", singleLine: false, minLines: 2).padding(.top, 14)
                }
                if canBlock {
                    Toggle(isOn: $alsoBlock) {
                        Text(target.ownerName.isEmpty ? "Also block this person" : "Also block \(target.ownerName)").bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                    }.tint(BucksColor.primary).padding(.top, 12)
                }
                PrimaryButton(session.reporting ? "Sending…" : "Send report", enabled: reason != nil && !session.reporting) {
                    guard let r = reason else { return }
                    Task { if await session.sendReport(target, reason: r, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), alsoBlock: alsoBlock && canBlock) { dismiss() } }
                }.padding(.top, 14)
            }
            .padding(20).padding(.bottom, 24)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(BucksRadius.sheet)
    }

    private var helplines: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("If someone is in danger right now, call for help first.").bucks(.titleSmall).foregroundStyle(BucksColor.bad)
            helpline("Emergency", "112"); helpline("Childline", "1098"); helpline("Tele-MANAS (mental health)", "14416")
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.badTint))
        .padding(.top, 10)
    }

    private func helpline(_ name: String, _ number: String) -> some View {
        Button { openSystemURL("tel:\(number)") } label: {
            HStack {
                Text(name).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                Spacer()
                Text(number).bucks(.titleSmall).foregroundStyle(BucksColor.bad)
                Image(systemName: "phone.fill").font(.system(size: 14)).foregroundStyle(BucksColor.bad).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Call \(name), \(number)")
    }
}
