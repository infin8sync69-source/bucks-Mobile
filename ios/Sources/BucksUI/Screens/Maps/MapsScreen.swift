import SwiftUI
import BucksCore

/// Maps: search anywhere, see the road route from where you are with its distance and time on the map, then Navigate to hand it to
/// turn-by-turn in Apple Maps. The preview route is by road (OpenStreetMap data); turn-by-turn and live traffic come from the maps app.
struct MapsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var q = ""
    @State private var hits: [MapServices.PlaceHit] = []
    @State private var searching = false
    @State private var dest: MapServices.PlaceHit?
    @State private var mode: Character = "d"
    @State private var offline = false
    @State private var retry = 0
    @State private var road = RoadRouteLoader()
    @FocusState private var focused: Bool

    private var here: LatLng? { session.hereKnown ? session.here : nil }
    private var start: LatLng { here ?? session.mePos }

    var body: some View {
        ZStack {
            BucksMap(pins: pins, route: line).ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                if searching { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary).padding(.horizontal, 24).padding(.top, 2) }
                results
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 720)
            VStack(spacing: 0) {
                Spacer()
                bottom
            }
        }
        .bucksBackground().bucksHideNavigationBar()
        .onAppear {
            MapsFeedback.noMapsApp = { session.toast("No maps app found. Open the address in Apple Maps or search again.") }
            if let p = MapsPick.place { dest = p; q = p.name; MapsPick.place = nil }
        }
        .onDisappear { MapsFeedback.noMapsApp = nil }
        .task(id: MapsSearchKey(q: q, retry: retry, chosen: dest != nil)) { await search() }
        .task(id: RouteKey(here, dest?.at)) { await road.load(from: here, to: dest?.at) }
    }

    // MARK: map

    private var line: [LatLng] {
        if let r = road.route { return r.points }
        if let d = dest, let h = here { return [h, d.at] }
        return []
    }
    private var pins: [MapPin] {
        var out = [MapPin(id: "me", at: start, title: "You", tint: BucksColor.purple, isMe: true)]
        if let d = dest { out.append(MapPin(id: "dest", at: d.at, title: d.name, tint: BucksColor.primary)) }
        return out
    }

    // MARK: search

    private var searchBar: some View {
        HStack(spacing: 0) {
            Button { router.pop() } label: { Image(systemName: "arrow.left").foregroundStyle(BucksColor.onSurface).frame(width: 48, height: 48) }.accessibilityLabel("Back")
            TextField("Search any place", text: Binding(get: { q }, set: { q = $0; dest = nil }))
                .focused($focused).font(.bucks(.bodyLarge)).submitLabel(.search).onSubmit { retry += 1 }
                .autocorrectionDisabled().frame(minHeight: 48)
            if !q.isEmpty {
                Button { q = ""; dest = nil; hits = [] } label: { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 48, height: 48) }.accessibilityLabel("Clear")
            }
        }
        .background(Capsule().fill(BucksColor.surface))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    @ViewBuilder private var results: some View {
        if !hits.isEmpty && dest == nil {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(hits, id: \.self) { h in
                        Button { dest = h; q = h.name; hits = []; focused = false } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin").foregroundStyle(BucksColor.onSurfaceVariant)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(h.name).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                                    if !h.detail.isEmpty { Muted(h.detail, maxLines: 1) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Muted(mapsDistance(Geo.distanceKm(start, h.at) * 1000))
                            }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        BucksDivider()
                    }
                }
            }
            .frame(maxHeight: 340).fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BucksColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2).padding(.top, 6)
        } else if q.trimmingCharacters(in: .whitespaces).count >= 3 && !searching && hits.isEmpty && dest == nil {
            VStack(alignment: .leading, spacing: 0) {
                Text(offline ? "Couldn't reach the map search" : "No places found").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                Muted(offline ? "Check your internet connection and try again." : "Try a landmark, an area or the town's name.").padding(.top, 2)
                if offline { SmallButton("Try again") { retry += 1 }.padding(.top, 8) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BucksColor.surface))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2).padding(.top, 6)
        }
    }

    private func search() async {
        if q.trimmingCharacters(in: .whitespaces).count < 3 || dest != nil { hits = []; searching = false; offline = false; return }
        searching = true; offline = false
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        let r = await MapServices.searchOrNull(q, near: start)
        if Task.isCancelled { return }
        hits = r ?? []; offline = r == nil; searching = false
    }

    // MARK: destination sheet

    @ViewBuilder private var bottom: some View {
        if let d = dest {
            Sheet {
                Text(d.name).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                if !d.detail.isEmpty { Muted(d.detail, maxLines: 2) }
                Text(summary(d)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 10)
                HStack(spacing: 6) {
                    ForEach(mapsTravelModes, id: \.mode) { m in BucksChip(m.label, selected: mode == m.mode) { mode = m.mode } }
                }.padding(.top, 10)
                Muted("The route shown is by road. Turn-by-turn, live traffic and walking routes come from your maps app.").padding(.top, 6)
                PrimaryButton("Navigate") { openDirections(to: d.at, label: d.name, mode: mode) }.padding(.top, 12)
            }
        } else {
            Muted("Search for a shop, address, landmark or town anywhere. You'll see the road route and can start turn-by-turn navigation.")
                .padding(.horizontal, 20).padding(.vertical, 12).background(BucksColor.surface)
        }
    }

    private func summary(_ d: MapServices.PlaceHit) -> String {
        guard let here else { return "Turn on location to see the route from where you are." }
        if let r = road.route { return "\(trim(r.km)) km by road · about \(r.minutes) min" }
        return "\(mapsDistance(Geo.distanceKm(here, d.at) * 1000)) away in a straight line"
    }
    /// Kotlin prints a Double: 4.0 as "4.0", 2.5 as "2.5".
    private func trim(_ km: Double) -> String { String(format: "%.1f", km) }
}
