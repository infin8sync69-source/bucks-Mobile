import SwiftUI
import BucksCore

/// A rider accepted: where they are, the PIN to share, contact, and the cancel option until the trip starts.
struct DriverFoundScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var cancel = false
    @State private var loader = RoadRouteLoader()

    var body: some View {
        Group { if let r = session.dispatch.ride, let d = r.driver { content(r, d) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
            // A driver has accepted, so a reason is required and the driver hears it. The sheet closes only once the server has cancelled.
            .sheet(isPresented: $cancel) {
                RideCancelSheet(driverName: session.dispatch.ride?.driver?.name.components(separatedBy: " ")[0] ?? "Your rider",
                                arrived: session.dispatch.ride?.status == .arrived,
                                onCancelled: { cancel = false; router.popToRoot() }, onClose: { cancel = false })
            }
            .onChange(of: session.dispatch.ride?.id) { _, id in if id == nil { cancel = false } }
    }

    private func content(_ r: Ride, _ d: Driver) -> some View {
        let arrived = r.status == .arrived
        let me = session.mePos
        let car = r.driverPoint ?? me
        let first = d.name.components(separatedBy: " ")[0]
        let cancelling = session.dispatch.cancelling
        let headline = arrived ? "Your rider is here" : (etaText(r.etaMin).map { "Pick-up in \($0)" } ?? "Your rider is on the way")
        return VStack(spacing: 0) {
            BucksMap(pins: [MapPin(id: "me", at: me, title: "You", tint: BucksColor.primary, isMe: true), MapPin(id: "car", at: car, title: first, tint: BucksColor.good)],
                     route: MapServices.RoadRoute.line(loader.route, car, me), zoomMeters: 1500)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet(scrollable: true) {
                // The headline slides to the new status so "your rider is here" can't be missed.
                Text(headline).bucks(.titleMedium).foregroundStyle(arrived ? BucksColor.good : BucksColor.onSurface)
                    .frame(maxWidth: .infinity).id(headline)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                    .animation(.easeOut(duration: Motion.medium), value: headline)
                BucksDivider().padding(.vertical, 12)
                HStack(alignment: .center) {
                    VStack(spacing: 4) { Avatar(initials: initials(d.name), size: 44); TrustBadge(up: d.up, down: d.down, compact: true) }
                    Image(systemName: d.vehicle.systemImage).font(.system(size: 34)).frame(width: 44, height: 44).foregroundStyle(BucksColor.onSurface).padding(.leading, 12)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 6) {
                            ForEach(Array(r.pin.enumerated()), id: \.offset) { i, c in
                                Text(String(c)).bucks(.titleSmall).foregroundStyle(BucksColor.onPrimary)
                                    .frame(minWidth: 26, minHeight: 26).padding(.horizontal, 3)
                                    .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primary))
                                    .popIn(index: i)
                            }
                        }
                        Text(d.plate).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 6)
                        Muted(d.model, align: .trailing); Muted(d.name, align: .trailing)
                    }
                }
                Muted("Share this PIN with your rider when they arrive.").padding(.top, 6)
                MessageBar(hint: "Message your driver", onCall: { reach(d, first) { dial($0) } }, onMessage: { reach(d, first) { sms($0) } }).padding(.vertical, 14)
                RoutePoints(pickup: r.pickupLabel.isEmpty ? "Pick-up point" : r.pickupLabel, drop: r.dest.name) {
                    ShareLink(item: tripShareText(r, d)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                    }.accessibilityLabel("Share trip")
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Total fare").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Text("  ₹\(r.fare)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                }.padding(.vertical, 16)
                // The driver starts the trip once they've entered your PIN.
                GhostButton(cancelling ? "Cancelling…" : "Cancel ride", enabled: !cancelling) { cancel = true }
            }
            .frame(maxHeight: 520)
        }
        .task(id: RouteKey(car, me)) { await loader.load(from: car, to: me) }
        .onAppear { session.dispatch.mapShown() }
        .onDisappear { session.dispatch.mapHidden() }
    }

    private func reach(_ d: Driver, _ first: String, _ open: (String) -> Void) {
        if d.phone.isEmpty { session.toast("\(first)'s number isn't available yet. Try again in a moment.") } else { open(d.phone) }
    }
}
