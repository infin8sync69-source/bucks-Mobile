import SwiftUI
import BucksCore

/// Ringing nearby riders inside 5 km; once nobody takes it, the recovery card: try again, try a cab, notify me, or change the ride type.
struct SearchingScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var ask = false
    @State private var notifyBusy = false

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
                    recovery(r)
                    GhostButton("Change ride type") { router.path = [.chooseRide] }.padding(.top, 10)
                }
            }
        }
    }

    /// Swarm Phase 1 recovery card: Try again, Try a cab (or an auto), Notify me when a driver is online. Each is one tap that records the
    /// choice (recovery_choice) and then runs today's flow: booking again opens the usual confirm sheet, so nothing is booked unconfirmed.
    @ViewBuilder private func recovery(_ r: Ride) -> some View {
        let alt: VehicleKind = r.kind == .cab ? .auto : .cab
        PrimaryButton("Try again") { record(r, Recovery.tryAgain); session.requestRide() }.padding(.top, 14)
        GhostButton(alt == .cab ? "Try a cab" : "Try an auto") { record(r, Recovery.tryCab); session.setRideKind(alt); session.requestRide() }.padding(.top, 10)
        if session.cloud {
            GhostButton("Notify me when a driver is online", enabled: !notifyBusy) {
                notifyBusy = true; record(r, Recovery.notifyMe)
                let at = session.pickupAt
                Task {
                    let ok = (try? await Backend.shared.notifyMeWhenDriverOnline(kind: r.kind, at: at)) ?? false
                    session.toast(ok ? "We'll tell you when a driver comes online nearby (for the next 2 hours)." : "That isn't switched on yet. Try again in a few minutes.")
                    notifyBusy = false
                }
            }.padding(.top, 10)
        }
    }

    private func record(_ r: Ride, _ choice: String) {
        guard session.cloud else { return }
        Task { _ = try? await Backend.shared.recoveryChoice(kind: Recovery.task, subject: r.id, choice: choice) }
    }

    private func leave() { session.dispatch.dismissEndedRide(); router.popToRoot() }

    private func cancel() {
        Task { if await session.cancelRide() { router.popToRoot() } }
    }
}
