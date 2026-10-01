import SwiftUI
import BucksCore

/// Confirm (and move) the pick-up: drag the map so the pin sits where the rider should come, or search a place; the address under the pin
/// updates. "Use my location" snaps back to where I am. An unmoved pin means "where I am" and is looked up fresh on tap (never booked from a
/// stale or default position); the fare is worked out again from the pin by road. Same flow as Android's ConfirmPickupScreen.
struct ConfirmPickupScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var cmds = MapCommands()
    @State private var center: LatLng?
    @State private var label = ""
    @State private var q = ""
    @State private var hits: [MapServices.PlaceHit] = []
    @State private var busy = false
    /// The rider picked a searched place (or came back with a pick-up already set).
    @State private var chosen = false
    /// The last lookup of where the phone is failed.
    @State private var noFix = false
    @State private var lookup: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var cloud: Bool { session.dispatch.enabled }
    private var waiting: Bool { cloud && !session.hereKnown }
    private var pinAt: LatLng { center ?? session.pickupAt }
    private var movedM: Double { Geo.distanceKm(pinAt, session.mePos) * 1000 }
    private var moved: Bool { chosen || movedM > 50 }

    var body: some View {
        ZStack {
            BucksMap(pins: [MapPin(id: "me", at: session.mePos, title: "You", tint: BucksColor.purple, isMe: true)], zoomMeters: 700,
                     onCenterChange: { center = $0 }, commands: cmds)
                .ignoresSafeArea()
            // The pin stays in the middle; the map moves under it.
            Image(systemName: "mappin").font(.system(size: 40, weight: .semibold)).foregroundStyle(BucksColor.primary)
                .padding(.bottom, 40).allowsHitTesting(false).accessibilityLabel("Pick-up")
            VStack(spacing: 0) {
                searchBar
                if !hits.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(hits, id: \.self) { h in
                            HitRow(hit: h, km: Geo.distanceKm(session.mePos, h.at), selected: false) {
                                q = ""; hits = []; focused = false; label = h.name; center = h.at; chosen = true; cmds.moveTo(h.at, zoom: 16)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BucksColor.surface))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2).padding(.top, 6)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    MapRoundButton(systemImage: "location.fill", label: "Use my location") { chosen = false; cmds.moveTo(session.mePos, zoom: 16) }
                }.padding(.horizontal, 12)
                HStack { MapAttribution(); Spacer() }.padding(.horizontal, 12).padding(.vertical, 4)
                sheet
            }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            chosen = session.ridePickup != nil
            label = session.ridePickup?.name ?? session.hereLabel ?? "Your location"
            let start = session.pickupAt
            Task { try? await Task.sleep(nanoseconds: 300_000_000); cmds.moveTo(start, zoom: 16) }
        }
        // The first fix arrived while the pin still sat on the map's default centre: put the pin where the phone is.
        .onChange(of: session.hereKnown) { _, known in
            if known { noFix = false; if !chosen && session.ridePickup == nil { cmds.moveTo(session.mePos, zoom: 16) } }
        }
        // The street name under the pin, a moment after the map stops moving.
        .task(id: center.map { "\(Int($0.lat * 20_000)),\(Int($0.lng * 20_000))" }) {
            guard let c = center else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            if let l = await MapServices.label(at: c), !Task.isCancelled { label = l }
        }
        .task(id: q) {
            guard q.trimmingCharacters(in: .whitespaces).count >= 3 else { hits = []; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            let r = await MapServices.search(q, near: pinAt)
            if !Task.isCancelled { hits = Array(r.prefix(5)) }
        }
        .onDisappear { lookup?.cancel() }   // leaving during a lookup must not pop the booking sheet up over wherever the rider went
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Button { router.pop() } label: { Image(systemName: "arrow.left").foregroundStyle(BucksColor.onSurface).frame(width: 48, height: 48) }.accessibilityLabel("Back")
            TextField("Search a pick-up place", text: $q).focused($focused).font(.bucks(.bodyLarge)).autocorrectionDisabled().frame(minHeight: 48)
            if !q.isEmpty {
                Button { q = ""; hits = [] } label: { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 48, height: 48) }.accessibilityLabel("Clear")
            }
        }
        .background(Capsule().fill(BucksColor.surface))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    private var sheet: some View {
        Sheet {
            Text("Pick-up").bucks(.labelMedium).foregroundStyle(BucksColor.onSurfaceVariant)
            Text(waiting && !moved ? "Finding where you are…" : label).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(2)
            Muted(movedM > 50 ? "\(mapsDistance(movedM)) from where you are. The rider comes to the pin. Riders within 5 km of it are rung."
                              : "Drag the map to move the pin. Riders within 5 km are rung; the first to accept comes here.").padding(.vertical, 8)
            if noFix || (waiting && !moved) { LocationNotice().padding(.bottom, 12) }
            DarkButton(busy ? "Checking the route…" : "Confirm pick-up", enabled: !busy && !session.dispatch.busy, action: confirm)
        }
    }

    private func confirm() {
        lookup = Task {
            busy = true; defer { busy = false }
            var at = pinAt, name = label
            // An unmoved pin means "where I am": looked up again on tap, never booked from a stale or default position.
            if cloud && !moved {
                guard await session.refreshLocation() else { noFix = true; return }
                if Task.isCancelled { return }
                noFix = false; at = session.mePos; name = session.hereLabel ?? label
            }
            session.setPickup(name, at: at)
            // The fare follows the road from the pin to the drop, so work the distance out again from here.
            if let dest = session.rideDest, let r = await MapServices.route(from: at, to: dest.at) { session.setDestKm(r.km) }
            if Task.isCancelled { return }
            session.requestRide()
        }
    }
}
