import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#endif

/// How the trip is made: the routing profile, and the Apple Maps flag for "Open in another maps app".
enum TravelMode: CaseIterable {
    case drive, two, cycle, walk
    var label: String { switch self { case .drive: "Drive"; case .two: "Two-wheeler"; case .cycle: "Cycle"; case .walk: "Walk" } }
    var icon: String? { switch self { case .drive: "car.fill"; case .two: "scooter"; case .cycle: nil; case .walk: "figure.walk" } }
    var profile: String { switch self { case .drive: "driving-traffic"; case .two: "driving"; case .cycle: "cycling"; case .walk: "walking" } }
    var appleFlag: Character { self == .walk ? "w" : "d" }
}

/// Rotation of the arrow for a maneuver: straight 0, right +90, left -90, U-turn 180.
func turnAngle(_ type: String, _ mod: String) -> Double {
    if type == "arrive" { return 0 }
    switch mod {
    case "uturn": return 180
    case "sharp right": return 135
    case "right": return 90
    case "slight right": return 45
    case "sharp left": return -135
    case "left": return -90
    case "slight left": return -45
    default: return 0
    }
}

private func spoken(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f kilometres", m / 1000) : "\(Int((m / 10).rounded()) * 10) metres" }

/// Maps, inside the app (MapsScreen.kt): search anywhere or press and hold the map to drop a pin, see the road route with distance and time
/// (drive, two-wheeler, cycle, walk), read its steps, then Start for live turn-by-turn: the next turn and how far, distance and time left,
/// voice, re-routing when you leave the route. Search, routes and tiles come from Mapbox when a token is built in, else OpenStreetMap.
struct MapsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var cmds = MapCommands()
    @State private var q = ""
    @State private var hits: [MapServices.PlaceHit] = []
    @State private var searching = false
    @State private var offline = false
    @State private var retry = 0
    @State private var dest: MapServices.PlaceHit?
    @State private var mode: TravelMode = .drive
    @State private var route: MapServices.RoadRoute?
    @State private var path: RoutePath?
    @State private var stepAt: [Double] = []
    @State private var routing = false
    @State private var routeFailed = false
    @State private var reroute = 0
    @State private var navigating = false
    @State private var arrived = false
    @State private var pendingStart = false
    @State private var seg = 0
    @State private var offCount = 0
    @State private var lastReroute = Date.distantPast
    @State private var lastSpoken = ""
    @State private var muted = false
    @State private var follow = true
    @State private var satellite = false
    @State private var showSteps = false
    @State private var locating = false
    @FocusState private var focused: Bool

    private var here: LatLng? { session.hereKnown ? session.here : nil }
    private var start: LatLng { here ?? session.mePos }

    var body: some View {
        ZStack {
            BucksMap(pins: pins, route: line, commands: cmds, satellite: satellite,
                     onLongPress: navigating ? nil : { p in dropPin(p) }, onUserMove: { follow = false })
                .ignoresSafeArea()
            if navigating { navigationOverlay } else { browseOverlay }
        }
        .bucksBackground().bucksHideNavigationBar()
        .onAppear(perform: appeared)
        .onDisappear { setNavigating(false, quiet: true) }
        .task(id: MapsSearchKey(q: q, retry: retry, chosen: dest != nil)) { await search() }
        .task(id: RouteRequest(dest: dest?.at, mode: mode, reroute: reroute, located: here != nil)) { await loadRoute() }
        .onChange(of: session.here) { _, _ in tick() }
        .alert("You have arrived", isPresented: $arrived) {
            Button("Done") { dest = nil; q = "" }
        } message: { Text(dest?.name ?? "") }
    }

    // MARK: map

    private var line: [LatLng] {
        if let r = route { return r.points }
        if let d = dest, let h = here { return [h, d.at] }
        return []
    }
    private var pins: [MapPin] {
        var out = [MapPin(id: "me", at: start, title: "You", tint: BucksColor.purple, isMe: true)]
        if let d = dest { out.append(MapPin(id: "dest", at: d.at, title: d.name, tint: BucksColor.primary)) }
        return out
    }

    private func appeared() {
        if let p = MapsPick.place { dest = p; q = p.name; MapsPick.place = nil }
        if let s = MapsPick.query { q = s; MapsPick.query = nil }
        pendingStart = MapsPick.autoStart; MapsPick.autoStart = false
        if !session.hereKnown { locate(quiet: true) }
    }

    private func dropPin(_ p: LatLng) {
        let pin = MapServices.PlaceHit(name: "Dropped pin", detail: "", at: p)
        dest = pin; q = pin.name; hits = []; focused = false
        // A dropped pin gets a street name when the search server answers.
        Task {
            if let l = await MapServices.label(at: p), dest?.at == p { dest = MapServices.PlaceHit(name: l, detail: "", at: p); q = l }
        }
    }

    /// The location button: asks for permission if it's missing, takes a fresh fix, updates the app's position and centres the map on it.
    private func locate(quiet: Bool = false) {
        let loc = session.location
        if loc.notDetermined { loc.requestPermission(); return }
        guard loc.hasPermission else { if !quiet { session.toast("Location is off for Bucks. Turn it on in Settings.") }; return }
        locating = true
        Task {
            let ok = await session.refreshLocation()
            locating = false
            if ok { cmds.moveTo(session.here, zoom: 16) } else if !quiet { session.toast("Couldn't get a fix. Check that location is on.") }
        }
    }

    // MARK: search

    private var searchBar: some View {
        HStack(spacing: 0) {
            Button { if dest != nil { dest = nil; q = "" } else { router.pop() } } label: {
                Image(systemName: "arrow.left").foregroundStyle(BucksColor.onSurface).frame(width: 48, height: 48)
            }.accessibilityLabel("Back")
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
                                Muted(mapsDistance(Geo.distanceKm(start, h.at) * 1000)).fixedSize()
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

    // MARK: browsing (search, buttons, the destination sheet)

    private var browseOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar
                if searching { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary).padding(.horizontal, 24).padding(.top, 2) }
                results
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 720)
            // Map buttons: where am I, zoom, satellite.
            VStack(alignment: .trailing, spacing: 8) {
                MapRoundButton(systemImage: "location.fill", label: "My location", busy: locating) { locate() }
                MapRoundButton(systemImage: "plus", label: "Zoom in") { cmds.zoomIn() }
                MapRoundButton(systemImage: "minus", label: "Zoom out") { cmds.zoomOut() }
                if !MapServices.token.isEmpty {
                    Button { satellite.toggle() } label: {
                        Text("Satellite").bucks(.labelMedium).foregroundStyle(satellite ? BucksColor.onPrimary : BucksColor.onSurface)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(satellite ? BucksColor.primary : BucksColor.surface))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 150).padding(.trailing, 12)
            VStack(spacing: 0) {
                Spacer()
                HStack { MapAttribution(); Spacer() }.padding(.horizontal, 12).padding(.vertical, 4)
                destinationSheet
            }
        }
    }

    @ViewBuilder private var destinationSheet: some View {
        if let d = dest {
            Sheet {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.name).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                        if !d.detail.isEmpty { Muted(d.detail, maxLines: 2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { dest = nil; q = ""; showSteps = false } label: {
                        Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Clear destination")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(TravelMode.allCases, id: \.self) { m in BucksChip(m.label, selected: mode == m, systemImage: m.icon) { mode = m } }
                    }
                }.padding(.top, 10)
                Text(summary(d)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 10)
                if routeFailed && route == nil && here != nil { SmallButton("Try again") { reroute += 1 }.padding(.top, 6) }
                let steps = route?.steps ?? []
                if steps.count > 1 {
                    Button(showSteps ? "Hide steps" : "Show \(steps.count) steps") { showSteps.toggle() }
                        .buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary).padding(.top, 8)
                    if showSteps {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { _, st in
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.up").rotationEffect(.degrees(turnAngle(st.type, st.modifier))).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 20)
                                        Text(st.text).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                                        if st.metres > 0 { Muted(mapsDistance(st.metres)).fixedSize() }
                                    }.padding(.vertical, 6)
                                }
                            }
                        }.frame(maxHeight: 200)
                    }
                }
                PrimaryButton("Start", enabled: route != nil && here != nil) { startNavigation() }.padding(.top, 8)
                Button("Open in another maps app") { openDirections(to: d.at, label: d.name, mode: mode.appleFlag) }
                    .buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                    .frame(maxWidth: .infinity).padding(.top, 8)
            }
        } else {
            Muted("Search for a shop, address, landmark or town anywhere, or press and hold the map to drop a pin. You'll see the road route and can start turn-by-turn navigation here.")
                .padding(.horizontal, 20).padding(.vertical, 12).background(BucksColor.surface)
        }
    }

    private func summary(_ d: MapServices.PlaceHit) -> String {
        guard let here else { return "Turn on location to see the route from where you are." }
        if routing && route == nil { return "Finding the best route…" }
        if let r = route { return "\(String(format: "%.1f", r.km)) km · about \(r.minutes) min by \(mode.label.lowercased())" }
        if routeFailed { return "Couldn't get a road route. \(mapsDistance(Geo.distanceKm(here, d.at) * 1000)) away in a straight line." }
        return ""
    }

    // MARK: route

    private func loadRoute() async {
        guard let d = dest, let from = here else { route = nil; path = nil; stepAt = []; routeFailed = false; return }
        routing = true; routeFailed = false
        let r = await MapServices.route(from: from, to: d.at, profile: mode.profile)
        if Task.isCancelled { return }
        // A failed re-route keeps the old line rather than dropping guidance.
        if r != nil || reroute == 0 { setRoute(r) }
        routeFailed = r == nil; routing = false
        // Opened from a driver's Navigate button: start guiding as soon as the route and my position are known.
        if pendingStart, route != nil, here != nil { pendingStart = false; startNavigation() }
    }

    private func setRoute(_ r: MapServices.RoadRoute?) {
        route = r; seg = 0
        if let r, r.points.count >= 2 {
            let p = RoutePath(r.points); path = p
            stepAt = r.steps.map { p.snap($0.at).along }
        } else { path = nil; stepAt = [] }
    }

    // MARK: turn-by-turn

    private struct Progress {
        var snap: RoutePath.Snap?
        var remainingM: Double
        var remainingMin: Int
        var nextIdx: Int?
        var toNext: Double
    }

    private var progress: Progress {
        let snap: RoutePath.Snap? = (navigating && path != nil && here != nil) ? path!.snap(here!, fromSeg: seg) : nil
        let total = path?.total ?? 0
        let remainingM = snap.map { total - $0.along } ?? total
        let totalMin = route?.minutes ?? 0
        let remainingMin = total > 0 ? max(1, Int((Double(totalMin) * (remainingM / total)).rounded())) : totalMin
        var nextIdx: Int?
        if let s = snap {
            nextIdx = stepAt.indices.first { $0 >= 1 && stepAt[$0] > s.along - 10 } ?? (stepAt.count - 1 >= 1 ? stepAt.count - 1 : nil)
        }
        let toNext = (snap != nil && nextIdx != nil) ? max(0, stepAt[nextIdx!] - snap!.along) : 0
        return Progress(snap: snap, remainingM: remainingM, remainingMin: remainingMin, nextIdx: nextIdx, toNext: toNext)
    }

    private func startNavigation() {
        arrived = false; showSteps = false; lastSpoken = ""; offCount = 0
        setNavigating(true)
        say("Starting navigation. \(route?.steps.dropFirst().first?.text ?? "")")
    }

    private func setNavigating(_ on: Bool, quiet: Bool = false) {
        navigating = on
        session.location.setPrecise(on)
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
        if on { follow = true; cmds.moveTo(here ?? start, zoom: 17) } else if quiet { Speaker.shared.stop() }
    }

    private func say(_ text: String) { if !muted { Speaker.shared.say(text) } }

    /// Each new position while navigating: progress, voice at about 200 m and at the turn, re-routing after three fixes off the route,
    /// arrival, and following my dot.
    private func tick() {
        guard navigating, let here else { return }
        let p = progress
        guard let snap = p.snap else { return }
        seg = snap.seg
        if follow { cmds.moveTo(here) }
        // Voice: the turn is announced at about 200 m and again as you reach it.
        if let i = p.nextIdx, let step = route?.steps[safe: i] {
            let bucket = p.toNext <= 40 ? 0 : p.toNext <= 220 ? 1 : 2
            let key = "\(i)-\(bucket)"
            if bucket < 2, key != lastSpoken { lastSpoken = key; say(bucket == 1 ? "In \(spoken(p.toNext)), \(step.text)" : step.text) }
        }
        // Off the route for three fixes in a row: find a new way from here (at most every 8 seconds).
        offCount = snap.off > 60 ? offCount + 1 : 0
        if offCount >= 3, Date().timeIntervalSince(lastReroute) > 8 { offCount = 0; lastReroute = Date(); say("Rerouting"); reroute += 1 }
        if p.remainingM < 25, let path, path.total > 50 { say("You have arrived"); setNavigating(false); arrived = true }
    }

    private var navigationOverlay: some View {
        let p = progress
        let next = p.nextIdx.flatMap { route?.steps[safe: $0] }
        return ZStack {
            VStack {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.up").font(.system(size: 34, weight: .semibold))
                        .rotationEffect(.degrees(next.map { turnAngle($0.type, $0.modifier) } ?? 0)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next != nil ? mapsDistance(p.toNext) : "Follow the route").bucks(.headlineSmall)
                        Text(next?.text ?? "Continue to \(dest?.name ?? "")").bucks(.bodyLarge).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(BucksColor.onPrimary).padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BucksColor.primary))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .padding(12)
                Spacer()
            }
            if !follow {
                HStack { Spacer(); MapRoundButton(systemImage: "location.fill", label: "Recentre") { follow = true; cmds.moveTo(here ?? start, zoom: 17); locate() } }
                    .padding(.trailing, 12)
            }
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date().addingTimeInterval(Double(p.remainingMin) * 60), format: .dateTime.hour().minute()).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                        Muted("\(p.remainingMin) min · \(mapsDistance(p.remainingM)) · \(dest?.name ?? "")", maxLines: 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { muted.toggle(); if muted { Speaker.shared.stop() } } label: {
                        Image(systemName: muted ? "xmark" : "speaker.wave.2.fill").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(muted ? "Voice is off" : "Turn voice off")
                    Button { setNavigating(false) } label: {
                        Text("End").bucks(.labelLarge).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 40)
                            .background(Capsule().fill(BucksColor.error))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous).fill(BucksColor.surface).ignoresSafeArea(edges: .bottom))
                .shadow(color: .black.opacity(0.15), radius: 12, y: -2)
            }
        }
    }
}

/// A round floating map button (my location, zoom); shows a spinner while busy.
struct MapRoundButton: View {
    let systemImage: String; let label: String; var busy = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(BucksColor.surface).shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: systemImage).foregroundStyle(BucksColor.onSurface) }
            }.frame(width: 44, height: 44)
        }.buttonStyle(.plain).disabled(busy).accessibilityLabel(label)
    }
}

/// The route is fetched again when the destination, the travel mode or the re-route counter changes, or once a position is known.
private struct RouteRequest: Hashable { var dest: LatLng?; var mode: TravelMode; var reroute: Int; var located: Bool }

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
