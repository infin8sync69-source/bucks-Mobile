import SwiftUI
import BucksCore

/// One tile of the Services menu. Its state comes from the server (services_near, docs/SERVICES_UNLOCK.md): LOCKED and SOON
/// show a padlock and dim; QUIET (unlocked, nobody online right now) gets an amber dot; OPEN is plain.
struct ServiceTile: View {
    let def: ServiceDef
    let state: ServiceState?
    let index: Int
    var onTap: () -> Void
    @State private var nope = 0

    private var locked: Bool { !(state?.usable ?? false) }
    private var fg: Color { locked ? BucksColor.onSurface.opacity(0.38) : BucksColor.onSurface }
    private var spoken: String {
        def.label + {
            switch state?.state { case "OPEN": ""; case "QUIET": ", nobody online right now"; case "SOON": ", coming soon"; default: ", locked near you" }
        }()
    }

    var body: some View {
        Button {
            if locked { nope += 1; Haptics.tap() }
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: def.icon).font(.system(size: 22)).foregroundStyle(fg)
                    Text(def.label).bucks(.labelSmall).foregroundStyle(fg).lineLimit(1).minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 2)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
                .padding(.top, 4).padding(.trailing, 4)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(BucksColor.onSurfaceVariant)
                        .frame(width: 18, height: 18).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BucksColor.surface))
                } else if state?.state == "QUIET" {
                    Circle().fill(BucksColor.warn).frame(width: 8, height: 8).padding(.top, 8).padding(.trailing, 8)
                }
            }
            .frame(height: 64).contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .enterStagger(index: index).shake(on: nope)
        .accessibilityLabel(spoken)
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.93 : 1).animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// What a locked or coming-soon tile explains: what unlocks it here, how far along it is, "notify me", and the way in for
/// providers ("Run a restaurant? List it").
struct ServiceLockSheet: View {
    @Environment(AppSession.self) private var session
    let def: ServiceDef
    var onDismiss: () -> Void
    var onList: () -> Void
    var onRecommend: () -> Void
    @State private var shown: CGFloat = 0

    private var st: ServiceState? { session.services.state(def.key) }
    private var cloud: Bool { session.cloud }
    private var progress: CGFloat {
        guard let st else { return 0 }
        return st.minSupply == 0 ? 1 : min(1, max(0, CGFloat(st.supply) / CGFloat(st.minSupply)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: def.icon).font(.system(size: 20)).foregroundStyle(BucksColor.onPrimaryContainer)
                        .frame(width: 48, height: 48).background(Circle().fill(BucksColor.primaryContainer))
                    Text(st?.state == "SOON" || !cloud ? "\(def.label) is coming soon" : "\(def.label) isn't open near you yet").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    Spacer(minLength: 0)
                }
                if let st, st.state == "LOCKED" {
                    Text("Not enough \(st.supplyNoun) near you have joined Bucks and been recommended by locals yet. It opens once \(st.minSupply) within \(st.radiusKm) of you are live.")
                        .bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BucksColor.surfaceContainerHigh)
                            Capsule().fill(BucksColor.primary).frame(width: g.size.width * shown)
                        }
                    }.frame(height: 8).padding(.top, 14)
                    Muted("\(st.supply) of \(st.minSupply) so far").padding(.top, 6)
                } else {
                    Text(cloud ? "Bucks is still building \(def.label.lowercased()). Tell us you want it and we'll let you know when it opens." : "It opens in the online version of Bucks.")
                        .bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
                }
                if let st, st.interested > 0 {
                    Muted("\(st.interested) \(st.interested == 1 ? "person" : "people") near you \(st.interested == 1 ? "is" : "are") waiting for it.").padding(.top, 10)
                }
                if cloud {
                    Group {
                        if st?.mine == true { GhostButton("You'll be told when it opens · Stop") { session.services.toggleInterest(def.key) } }
                        else { PrimaryButton("Notify me when it opens") { session.services.toggleInterest(def.key) } }
                    }.padding(.top, 18)
                }
                // Help it open: bring the people it needs onto Bucks, or vouch for one you know.
                SectionTitle("Help it open here").padding(.top, 22).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ShareSmallButton(title: "Invite to Bucks", text: Invite.shareText(Invite.forService(label: def.label, supplyNoun: st?.supplyNoun ?? def.label.lowercased())), tonal: true)
                    if cloud { WideSmallButton(title: "Recommend a local", tonal: true, action: onRecommend) }
                }
                Muted("Know \(st?.supplyNoun ?? "someone who offers this") nearby? Send them Bucks through WhatsApp or any app, then scan their code in person to recommend them.").padding(.top, 8)
                HStack {
                    Muted(def.joinPrompt)
                    Spacer(minLength: 8)
                    Button(action: onList) { Text(def.joinAction).bucks(.labelLarge).foregroundStyle(BucksColor.primary).padding(.vertical, 10) }.buttonStyle(.plain)
                }.padding(.top, 12)
            }
            .padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { withAnimation(Motion.emphasized(0.9)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(Motion.emphasized(0.9)) { shown = p } }
    }
}

/// SmallButton look-alike that opens the system share sheet with `text`.
struct ShareSmallButton: View {
    let title: String
    let text: String
    var tonal = false
    var body: some View {
        ShareLink(item: text) {
            Text(title).font(.bucks(.labelMedium)).lineLimit(1).padding(.horizontal, 14).frame(minHeight: 38).frame(maxWidth: .infinity)
                .foregroundStyle(tonal ? BucksColor.onSecondaryContainer : BucksColor.onPrimary)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(tonal ? BucksColor.secondaryContainer : BucksColor.primary))
                .padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
