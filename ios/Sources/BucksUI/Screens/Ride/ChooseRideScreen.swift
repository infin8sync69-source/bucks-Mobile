import SwiftUI
import BucksCore

private let etaFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "h:mma"; return f
}()

/// Pick the vehicle type: fare range, the nearest rider's distance and ETA, and why a trip can't be booked.
struct ChooseRideScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var loader = RoadRouteLoader()

    var body: some View {
        Group { if let dest = session.rideDest { content(dest) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
    }

    private func content(_ dest: Place) -> some View {
        let me = session.pickupAt
        let road = loader.route
        var pins = [MapPin(id: "me", at: me, title: "You", tint: BucksColor.purple, isMe: true),
                    MapPin(id: "dest", at: dest.at, title: dest.name, tint: BucksColor.primary)]
        pins += session.dispatch.drivers.filter(\.online).compactMap { d in d.at.map { MapPin(id: "d-\(d.id)", at: $0, tint: BucksColor.good) } }
        let problem = session.bookingProblem(dest)
        return VStack(spacing: 0) {
            BucksMap(pins: pins, route: MapServices.RoadRoute.line(road, me, dest.at))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet {
                ZStack {
                    Text("Choose vehicle").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    HStack {
                        Button { router.pop() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Back")
                        Spacer()
                    }
                }
                VStack(spacing: 10) { ForEach(VehicleKind.passenger, id: \.self) { row($0, dest: dest, me: me) } }.padding(.top, 12)
                // Fares are estimates until the server prices the trip; a trip the server would refuse is stopped here with the reason.
                if let problem { Notice(problem).padding(.top, 12) }
                else { Muted("Fares are estimates. Bucks sets the final fare from the distance when you book.").padding(.top, 10) }
                DarkButton("Confirm", enabled: problem == nil && session.onlineCount(session.rideKind) > 0) { router.push(.confirmPickup) }.padding(.top, 14)
            }
        }
        // The road distance replaces the straight-line one for the fare once the route arrives.
        .task(id: RouteKey(me, dest.at)) {
            await loader.load(from: me, to: dest.at)
            if let r = loader.route { session.setDestKm(r.km) }
        }
        .onAppear { session.dispatch.mapShown() }
        .onDisappear { session.dispatch.mapHidden() }
    }

    private func row(_ k: VehicleKind, dest: Place, me: LatLng) -> some View {
        let nearest = session.dispatch.ring(from: me, kind: k).first
        let on = session.rideKind == k
        let f = session.fare(k, km: dest.km)
        let away = nearest.map { max(1, Int($0.distanceKm * 2.5)) }
        let eta = away.map { etaFormatter.string(from: Date().addingTimeInterval(Double(($0 + Int(dest.km * 3)) * 60))).lowercased() }
        let shape = RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous)
        return Button { session.setRideKind(k) } label: {
            HStack(spacing: 12) {
                Image(systemName: k.systemImage).font(.system(size: 28)).frame(width: 40, height: 40)
                    .foregroundStyle(nearest != nil ? BucksColor.onSurface : BucksColor.outline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.label).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(away.map { "\($0) \($0 == 1 ? "min" : "mins") away · ETA \(eta ?? "")" } ?? "No riders online nearby")
                    Muted("Max \(k.maxPassengers) · ₹\(k.farePerKm)/per km")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("₹\(f)–\(Int(Double(f) * 1.15))").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
            }
            .padding(12)
            .background(shape.fill(on ? BucksColor.primaryContainer : BucksColor.surfaceContainer))
            .overlay(shape.stroke(on ? BucksColor.primary : .clear, lineWidth: on ? 2 : 0))
            .contentShape(shape)
        }.buttonStyle(.plain).disabled(nearest == nil)
    }
}
