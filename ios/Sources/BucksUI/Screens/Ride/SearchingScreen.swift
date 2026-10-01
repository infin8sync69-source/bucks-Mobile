import SwiftUI
import BucksCore

/// Ringing nearby riders inside 5 km; once nobody takes it, offers to ring again or change the ride type.
struct SearchingScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var ask = false

    var body: some View {
        Group { if let r = session.dispatch.ride { content(r) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
            .bucksConfirm(isPresented: $ask, title: "Cancel this ride request?", message: "Riders nearby will stop being rung. You can book again any time.",
                          confirmTitle: "Cancel ride", cancelTitle: "Keep searching", destructive: true, onConfirm: cancel)
            .onAppear { session.dispatch.mapShown() }
            .onDisappear { session.dispatch.mapHidden() }
    }

    private func content(_ r: Ride) -> some View {
        let me = session.pickupAt
        let n = session.onlineCount(r.kind)
        let cancelling = session.dispatch.cancelling
        var pins = [MapPin(id: "me", at: me, title: "Pick-up", tint: BucksColor.purple, isMe: true), MapPin(id: "dest", at: r.dest.at, title: r.dest.name, tint: BucksColor.bad)]
        pins += session.dispatch.drivers.filter { $0.online && $0.vehicle == r.kind }.compactMap { d in d.at.map { MapPin(id: "d-\(d.id)", at: $0, tint: BucksColor.primary) } }
        return VStack(spacing: 0) {
            // Back while searching asks first (leaving would leave the request ringing); once nobody took it, Back just leaves.
            BucksTopBar(onBack: { if r.status == .searching { ask = true } else { leave() } })
            // The 5 km circle the request rings within, with the riders of this kind that are in it.
            BucksMap(pins: pins, circle: (me, 5000), zoomMeters: 10000).frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet {
                if r.status == .searching {
                    HStack(spacing: 12) {
                        PulseRings { Image(systemName: r.kind.systemImage).font(.system(size: 24)).foregroundStyle(BucksColor.primary).breathe(amount: 0.08) }.frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Looking for nearby \(r.kind.label.lowercased()) riders").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                            Muted("\(r.kind.label) · riders nearby are rung · first to accept gets the ride")
                        }
                    }
                    BadButton(cancelling ? "Cancelling…" : "Cancel request", enabled: !cancelling, action: cancel).padding(.top, 14)
                } else {
                    Text("No rider accepted").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    Muted(n > 0 ? "All nearby riders were busy. Try again or switch vehicle type." : "Nobody is online nearby.")
                    PrimaryButton("Ring again") { session.requestRide() }.padding(.top, 14)
                    GhostButton("Change ride type") { router.path = [.chooseRide] }.padding(.top, 10)
                }
            }
        }
    }

    private func leave() { session.dispatch.dismissEndedRide(); router.popToRoot() }

    private func cancel() {
        Task { if await session.cancelRide() { router.popToRoot() } }
    }
}
