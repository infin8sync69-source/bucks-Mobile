import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#endif

/// Home: a full-screen map of me and the riders online nearby, the search pill, and for a driver the round Online button.
/// An accepted driver trip takes Home over until it is closed.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnline = false
    @Environment(\.openBucksMenu) private var openMenu

    private var d: Dispatch { session.dispatch }

    var body: some View {
        Group {
            // An accepted ride takes over Home until it's closed.
            if let dr = d.driverRide, dr.status != .ringing { DriverTripScreen() } else { home }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        // The button and the "being checked" note follow the server: reload my vehicles whenever Home comes back on screen.
        .task { await d.refreshVehicles() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await d.refreshVehicles() } } }
    }

    private var home: some View {
        ZStack {
            BucksMap(pins: pins)
            VStack(spacing: 0) {
                BucksTopBar(onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
                    .background(LinearGradient(colors: [BucksColor.background.opacity(0.9), BucksColor.background.opacity(0)], startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 64)
                MapLegend(riders: riderCount).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Gutter).padding(.vertical, 8)
                Sheet { panel }
            }
            if showFab {
                OnlineFab(live: d.online) { showOnline = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Gutter - 16).padding(.bottom, 174)
            }
        }
        .onAppear {
            d.mapShown(); d.startDriversFeed()
        }
        .onDisappear { d.mapHidden() }
        .sheet(isPresented: $showOnline) { OnlineSheet(onEarnings: { router.push(.vehicleStats) }) }
    }

    /// Drivers with a checked vehicle get the button while offline too (it opens the sheet with their vehicle switch).
    private var showFab: Bool { d.online || d.cloudVehicle != nil }

    private var onlineRiders: [Driver] { d.drivers.filter { $0.online && $0.at != nil } }
    private var riderCount: Int { onlineRiders.count }

    private var pins: [MapPin] {
        [MapPin(id: "me", at: session.mePos, title: "You", tint: driverMeColor, isMe: true)]
            + onlineRiders.compactMap { r in r.at.map { MapPin(id: "d-\(r.id)", at: $0, title: "", tint: BucksColor.good) } }
    }

    @ViewBuilder private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = d.ride { ActiveRideCard(ride: r) { if let route = Route.ride(for: r.status) { router.showRide(route) } }.padding(.bottom, 12) }
            // A vehicle the server hasn't activated yet: say why there is no online button, and where to look.
            if let v = d.waitingVehicle, !showFab {
                VStack(alignment: .leading, spacing: 8) {
                    Notice(v.status == "SUSPENDED" ? "Your \(v.model.isEmpty ? "vehicle" : v.model) (\(v.plate)) is suspended, so you can't go online with it. Open Manage listings for details."
                           : "Bucks is still checking your \(v.model.isEmpty ? "vehicle" : v.model) (\(v.plate)). The online button appears here once it's active.")
                    SmallButton("Manage listings", tonal: true) { router.push(.vehicles) }
                }.padding(.bottom, 12)
            }
            if !session.locationGranted && session.location.denied { HomeLocationNotice().padding(.bottom, 12) }
            if session.cloud {
                HomeSearch(hint: "Where to, or what do you need?", onSearchAll: { openQuery(session, router, $0) },
                           onPlace: { MapsPick.place = $0; router.push(.maps) })
            } else {
                SearchBar(hint: "Where to, or what do you need?") { session.startRide(); router.push(.destination) }
            }
            Spacer().frame(height: 24)
        }
    }

}

/// The home search pill: opens the destination flow.
private struct SearchBar: View {
    var hint: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface)
                Text(hint).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).frame(height: 56).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(hint)
    }
}

/// Explains the pin colours: providers in the theme primary (only where the map shows them) and online riders in status good.
/// Cloud listings have no map position on Home, so `shops` stays off there.
private struct MapLegend: View {
    var riders: Int
    var shops = false
    var body: some View {
        HStack(spacing: 12) {
            if shops { dot(BucksColor.primary, "Shops & services") }
            dot(BucksColor.good, "Riders online")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(BucksColor.surface).shadow(color: .black.opacity(0.16), radius: 2, y: 1))
        .accessibilityElement(children: .combine)
    }
    private func dot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).bucks(.labelSmall).foregroundStyle(BucksColor.onSurfaceVariant).lineLimit(1)
        }
    }
}

/// The rider's unfinished ride, always one tap from Home: leaving a ride screen with Back never cancels it, so this is the way back in
/// until the trip is rated or skipped (the pay and rate screens included).
private struct ActiveRideCard: View {
    let ride: Ride
    var onReturn: () -> Void
    private var detail: String? {
        switch ride.status {
        case .searching: return "Looking for a nearby \(ride.kind.label.lowercased()) rider"
        case .noDriver: return "Nobody accepted yet. Return to ring again."
        case .matched:
            let first = ride.driver?.name.components(separatedBy: " ").first.flatMap { $0.isEmpty ? nil : "\($0) is on the way" } ?? "Your rider is on the way"
            let eta = ride.etaMin < 0 ? nil : (ride.etaMin == 0 ? "under a minute" : "\(ride.etaMin) min")
            return first + (eta.map { " · \($0) away" } ?? "")
        case .arrived: return "Your rider is here. Share PIN \(ride.pin) to start."
        case .inRide: return "On the way to \(ride.dest.name)"
        case .completed: return "Trip finished. Pay ₹\(ride.fare) to close it."
        case .paid: return "Paid. Rate your ride, or skip it."
        case .cancelled: return nil
        }
    }
    var body: some View {
        if let detail {
            BucksCard(tint: true, padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Ride in progress").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(detail)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 10)
                    SmallButton("Return", action: onReturn).fixedSize()
                }
            }
        }
    }
}

/// Location is off: say so, and offer the settings.
private struct HomeLocationNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Notice("Bucks can't see where you are: location permission is off. Your rider needs your exact pick-up point.")
            #if canImport(UIKit)
            SmallButton("Turn on location") { driverOpenURL(UIApplication.openSettingsURLString) }
            #endif
        }
    }
}
