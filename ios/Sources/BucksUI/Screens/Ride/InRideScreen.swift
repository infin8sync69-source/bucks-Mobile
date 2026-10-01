import SwiftUI
import BucksCore

/// The trip itself: the car on the road to the destination, distance left, SOS and share.
struct InRideScreen: View {
    @Environment(AppSession.self) private var session
    @State private var loader = RoadRouteLoader()

    var body: some View {
        Group { if let r = session.dispatch.ride, let d = r.driver { content(r, d) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
    }

    private func content(_ r: Ride, _ d: Driver) -> some View {
        let car = r.driverPoint ?? session.mePos
        let left = String(format: "%.1f", (1 - r.progress) * r.dest.km)
        return VStack(spacing: 0) {
            BucksTopBar()
            BucksMap(pins: [MapPin(id: "dest", at: r.dest.at, title: r.dest.name, tint: BucksColor.bad), MapPin(id: "car", at: car, title: "You", tint: BucksColor.good, isMe: true)],
                     route: MapServices.RoadRoute.line(loader.route, car, r.dest.at), zoomMeters: 1500)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet {
                Text("On the way to \(r.dest.name)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("\(left) km left · \(d.name) · \(d.plate)")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BucksColor.surfaceContainerHigh)
                        Capsule().fill(BucksColor.primary).frame(width: g.size.width * min(1, max(0, r.progress)))
                    }
                }.frame(height: 6).padding(.vertical, 14)
                HStack {
                    Spacer()
                    IconAction("exclamationmark.triangle.fill", "SOS") { dial("112") }
                    Spacer()
                    ShareAction(label: "Share trip", text: tripShareText(r, d))
                    Spacer()
                }
            }
        }
        .task(id: RouteKey(car, r.dest.at)) { await loader.load(from: car, to: r.dest.at) }
        .onAppear { session.dispatch.mapShown() }
        .onDisappear { session.dispatch.mapHidden() }
    }
}
