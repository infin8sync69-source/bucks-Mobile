import SwiftUI
import BucksCore

/// Where to: search the built-in places and the map's address data, star favourites, or drop a pin on the map.
struct DestinationScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var picked: String?
    @State private var pickedHit: MapServices.PlaceHit?
    @State private var savedOpen = false
    @State private var onMap = false
    @State private var center: LatLng?
    @State private var hits: [MapServices.PlaceHit] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    private var me: LatLng { session.mePos }
    /// Without a real position the distance to anywhere would be measured from the map's default centre, so the booking waits for one.
    private var noFix: Bool { session.dispatch.enabled && !session.hereKnown }
    private var matches: [(name: String, at: LatLng)] {
        Geo.places.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group { if onMap { mapPicker } else { search } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
            .task(id: query) { await runSearch() }
    }

    // MARK: search

    private var search: some View {
        VStack(spacing: 0) {
            BucksTopBar(onBack: { router.pop() })
            fields
            if noFix { LocationNotice().padding(.horizontal, Gutter).padding(.vertical, 10) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { results }.padding(.horizontal, Gutter)
            }.scrollDismissesKeyboard(.interactively)
            mapPill
            DarkButton("Confirm", enabled: (picked != nil || pickedHit != nil) && !noFix, action: confirm)
                .padding(.horizontal, Gutter).padding(.bottom, Gutter)
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            // The pick-up is where the phone is now, named from the map when it can be, never the area in the profile.
            HStack(spacing: 12) {
                Circle().fill(BucksColor.good).frame(width: 8, height: 8)
                Text(noFix ? "Waiting for your location" : session.hereLabel.map { "Current location · \($0)" } ?? "Current location")
                    .bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(BucksColor.onSurface)
                    .accessibilityLabel(noFix ? "Location not found yet" : "Using current location")
            }.padding(.vertical, 8)
            BucksDivider()
            HStack(spacing: 12) {
                Circle().fill(BucksColor.bad).frame(width: 8, height: 8)
                TextField("", text: $query, prompt: Text("Enter destination").foregroundStyle(BucksColor.onSurfaceVariant))
                    .font(.bucks(.bodyMedium)).foregroundStyle(BucksColor.onSurface).tint(BucksColor.primary)
                    .focused($focused).submitLabel(.search)
                    .onChange(of: query) { _, new in if new != picked { picked = nil; pickedHit = nil } }
            }.padding(.vertical, 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
        .padding(.horizontal, Gutter)
    }

    @ViewBuilder private var results: some View {
        if !hits.isEmpty || searching {
            sectionTitle("Places")
            if searching && hits.isEmpty { Muted("Searching the map…").padding(.vertical, 8) }
            ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                HitRow(hit: h, km: Geo.distanceKm(me, h.at), selected: pickedHit == h) { pickedHit = h; picked = nil }
            }
        }
        if !matches.isEmpty { sectionTitle(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Frequently visited" : "Matches") }
        ForEach(matches, id: \.name) { p in placeRow(p.name, p.at, saved: session.savedPlaces.contains(p.name), pickHit: true) }
        if matches.isEmpty && hits.isEmpty && !searching && query.trimmingCharacters(in: .whitespaces).count >= 3 {
            Muted("No place with that name. Try another spelling, or pick it on the map.").padding(.vertical, 12)
        }
        Button { savedOpen.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(BucksColor.primary)
                Text("Saved places").bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: savedOpen ? "chevron.up" : "chevron.down").foregroundStyle(BucksColor.onSurface)
            }.padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if savedOpen {
            if session.savedPlaces.isEmpty { Muted("Star a place to save it.").padding(.bottom, 8) }
            ForEach(session.savedPlaces, id: \.self) { name in
                if let at = Geo.place(named: name) { placeRow(name, at, saved: true, pickHit: false) }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 20).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeRow(_ name: String, _ at: LatLng, saved: Bool, pickHit: Bool) -> some View {
        PlaceRow(name: name, km: Geo.distanceKm(me, at), saved: saved, selected: picked == name,
                 onStar: { session.toggleSavedPlace(name) }) {
            picked = name; pickedHit = nil; query = name
        }
    }

    private var mapPill: some View {
        Button { onMap = true; focused = false } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 14)).foregroundStyle(BucksColor.onSurfaceVariant)
                Text(" Select on map").bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant)
            }
            .padding(.horizontal, 18).frame(minHeight: 44)
            .overlay(Capsule().stroke(BucksColor.outline, lineWidth: 1))
            .contentShape(Capsule())
        }.buttonStyle(.plain).padding(.vertical, 10)
    }

    private func confirm() {
        if let h = pickedHit { session.chooseDestPlace(h.name, at: h.at); router.push(.chooseRide) }
        else if let p = picked { session.chooseDest(p); router.push(.chooseRide) }
    }

    /// Anywhere in the map's address data, nearest first; the built-in list stays for quick picks.
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 3 || query == picked { hits = []; searching = false; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        searching = true
        let found = await MapServices.search(query, near: me)
        if Task.isCancelled { return }
        hits = found; searching = false
    }

    // MARK: map picker

    private var mapPicker: some View {
        ZStack {
            BucksMap(pins: [MapPin(id: "me", at: me, title: "You", tint: BucksColor.purple, isMe: true)], zoomMeters: 3000, onCenterChange: { center = $0 })
                .ignoresSafeArea(edges: .bottom)
            Image(systemName: "mappin").font(.system(size: 44)).foregroundStyle(BucksColor.primary)
                .padding(.bottom, 36).allowsHitTesting(false).accessibilityLabel("Destination")
            VStack {
                HStack {
                    Button { onMap = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(BucksColor.onSurface)
                            .frame(width: 44, height: 44).background(Circle().fill(BucksColor.surface))
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                    Spacer()
                }.padding(12)
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Muted("Drag the map to place the pin").padding(.bottom, 10)
                    DarkButton("Set destination here", enabled: center != nil && !noFix) {
                        guard let c = center else { return }
                        session.chooseDestAt(c); picked = session.rideDest?.name; onMap = false; router.push(.chooseRide)
                    }
                }.padding(Gutter).frame(maxWidth: .infinity).background(BucksColor.surface.ignoresSafeArea(edges: .bottom))
            }
        }
    }
}

private struct PlaceRow: View {
    let name: String; let km: Double; let saved: Bool; let selected: Bool
    let onStar: () -> Void; let onTap: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onTap) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin").font(.system(size: 18)).foregroundStyle(BucksColor.primary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.components(separatedBy: ",")[0]).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                            Muted("\(name) · \(String(format: "%.1f", km)) km away", maxLines: 1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(action: onStar) {
                    Image(systemName: saved ? "star.fill" : "star").foregroundStyle(saved ? BucksColor.primary : BucksColor.onSurfaceVariant).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(saved ? "Unsave" : "Save place")
            }
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(selected ? BucksColor.primaryContainer : .clear))
            BucksDivider()
        }
    }
}

private struct HitRow: View {
    let hit: MapServices.PlaceHit; let km: Double; let selected: Bool; let onTap: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin").font(.system(size: 18)).foregroundStyle(BucksColor.primary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Muted([hit.detail, kmAway(km)].filter { !$0.isEmpty }.joined(separator: " · "), maxLines: 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10).padding(.horizontal, 4).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(selected ? BucksColor.primaryContainer : .clear))
            }.buttonStyle(.plain)
            BucksDivider()
        }
    }
}
