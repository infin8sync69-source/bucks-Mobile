import SwiftUI
import BucksCore

/// Confirm the pick-up point (the phone's position, looked up again on tap) before the booking sheet.
struct ConfirmPickupScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var checking = false
    @State private var noFix = false
    @State private var lookup: Task<Void, Never>?

    private var waiting: Bool { session.dispatch.enabled && !session.hereKnown }

    var body: some View {
        let me = session.mePos
        VStack(spacing: 0) {
            BucksMap(pins: [MapPin(id: "me", at: me, title: "Pick-up", tint: BucksColor.primary, isMe: true)], circle: (me, 500), zoomMeters: 1500)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet {
                HStack(spacing: 12) {
                    Button { router.pop() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                    Text("Confirm pick-up location").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                }
                // The pick-up is where the phone is right now; it is looked up again when you tap, and the name is the map's, never the profile's area.
                Muted(waiting ? "Finding where you are…" : "\(session.hereLabel ?? "Your current location") · nearby riders are rung; the first to accept comes here.").padding(.vertical, 12)
                if noFix || waiting { LocationNotice().padding(.bottom, 12) }
                DarkButton(checking ? "Finding you…" : "Confirm pick-up", enabled: !checking && !session.dispatch.busy, action: confirm)
            }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .navigationBarBackButtonHidden(true)
        .onChange(of: session.hereKnown) { _, known in if known { noFix = false } }
        .onDisappear { lookup?.cancel() }   // leaving during the lookup must not pop the booking sheet up over wherever the rider went
    }

    private func confirm() {
        lookup = Task {
            checking = true; defer { checking = false }
            let ok = await session.refreshLocation()
            if Task.isCancelled { return }
            if ok { noFix = false; session.requestRide() } else { noFix = true }
        }
    }
}
