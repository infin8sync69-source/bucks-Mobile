import SwiftUI
import BucksCore

/// Chips for searching live listings: the categories shops and pros pick from when they list (not "Other").
private let cloudCategories: [String] = {
    let business = businessServices.flatMap { serviceDef($0)?.categories ?? [] }
    let skills = ["Plumber", "Electrician", "Tutor", "Doctor", "Carpenter", "Painter", "Cleaner", "Driver", "Designer", "Software developer", "Other"]
    var seen = Set<String>()
    return (business + skills).filter { $0 != "Other" && seen.insert($0).inserted }
}()
/// "Skills A to Z": the first 18 of Bucks' skill list.
private let skillChips = ["Plumber", "Electrician", "Doctor", "Gym trainer", "Photographer", "Software developer", "Carpenter", "Painter", "Tutor", "Yoga instructor", "Lawyer", "Accountant",
                          "Mechanic", "AC technician", "Beautician", "Driver (hire)", "Cook", "Tailor"]

/// The Services tab: a map of me with a foldable sheet holding a tile for every service (locked ones explain what unlocks them),
/// the search pill, category chips and skills.
struct ServicesScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    @State private var sheetFor: ServiceDef?
    @State private var folded = false
    @State private var contentHeight: CGFloat = 400

    private struct Spot: Hashable { var lat: Int; var lng: Int }
    /// Which services are open here is read when the screen opens and whenever I move a real distance (the counts are per place).
    private var spot: Spot? { session.hereKnown ? Spot(lat: Int(session.here.lat * 200), lng: Int(session.here.lng * 200)) : nil }

    var body: some View {
        GeometryReader { geo in
            let sheetMax = max(0, min(geo.size.height * 0.6, geo.size.height - 120))
            ZStack(alignment: .bottom) {
                BucksMap(pins: [MapPin(id: "me", at: session.here, title: "You", tint: driverMeColor, isMe: true)]).ignoresSafeArea()
                VStack(spacing: 0) {
                    BucksTopBar(onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
                        .background(LinearGradient(colors: [BucksColor.background.opacity(0.9), BucksColor.background.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Spacer(minLength: 0)
                }
                panel(maxHeight: sheetMax)
            }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .task(id: spot) { if spot != nil { session.services.refresh() } }
        .onAppear { session.dispatch.mapShown() }
        .onDisappear { session.dispatch.mapHidden() }
        .sheet(item: $sheetFor) { def in
            ServiceLockSheet(def: def, onDismiss: { sheetFor = nil },
                             onList: { sheetFor = nil; listService(def.key) },
                             onRecommend: { sheetFor = nil; router.push(.recommendScan) })
        }
    }

    // MARK: sheet

    private func panel(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            handle
            if !folded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        tiles
                        if let e = session.services.error { Muted("Couldn't check which services are open here. \(e)").padding(.top, 8) }
                        if !session.hereKnown { Muted("Turn on location to see which services are open where you are.").padding(.top, 8) }
                        SearchPill(hint: "Search or ask anything") { session.discover.useService(nil); router.push(.search) }.padding(.top, 14)
                        SectionTitle("Categories").padding(.top, 18).padding(.bottom, 10)
                        FlowChips(cloudCategories) { openQuery(session, router, $0.lowercased()) }
                        SectionTitle("Skills A to Z").padding(.top, 18).padding(.bottom, 10)
                        FlowChips(skillChips) { openQuery(session, router, $0.lowercased()) }
                        // Room under the last chip row so scrolling to the end never leaves it sliced by the sheet edge.
                        Spacer().frame(height: 24)
                    }
                    .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, max(0, maxHeight - 64)))
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, folded ? 12 : 16)
        .frame(maxWidth: .infinity)
        .background(UnevenRoundedRectangle(topLeadingRadius: BucksRadius.sheet, topTrailingRadius: BucksRadius.sheet, style: .continuous)
            .fill(BucksColor.surface).shadow(color: .black.opacity(0.18), radius: 12, y: -2).ignoresSafeArea(edges: .bottom))
        .animation(.easeOut(duration: 0.25), value: folded)
    }

    /// Drag the handle down to fold the panel away and see the map; drag up or tap to open.
    private var handle: some View {
        VStack(spacing: 0) {
            Capsule().fill(BucksColor.outline).frame(width: 36, height: 4)
            HStack {
                Text("Services near you").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                if folded && session.cloud { Muted("\(session.services.openCount) of \(serviceCatalog.count) open").padding(.trailing, 6) }
                Image(systemName: folded ? "chevron.up" : "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant)
                    .accessibilityLabel(folded ? "Show services" : "Hide services")
            }.padding(.top, 12).padding(.bottom, folded ? 0 : 14)
        }
        .padding(.top, 12).contentShape(Rectangle())
        .onTapGesture { folded.toggle() }
        .gesture(DragGesture(minimumDistance: 12).onEnded { v in
            if v.translation.height > 60 { folded = true } else if v.translation.height < -60 { folded = false }
        })
    }

    /// Every service gets a tile, 5 per row (the last row padded so tiles keep their width). Locked ones open a sheet saying
    /// what unlocks them here; open ones go straight in; quiet ones go in with a word about nobody being online.
    private var tiles: some View {
        VStack(spacing: 6) {
            ForEach(Array(serviceCatalog.chunked(5).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { def in
                        let st = session.services.state(def.key)
                        ServiceTile(def: def, state: st, index: serviceCatalog.firstIndex(of: def) ?? 0) { tapped(def, st) }
                    }
                    ForEach(0..<(5 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private func tapped(_ def: ServiceDef, _ st: ServiceState?) {
        guard let st, st.usable else { sheetFor = def; return }
        if st.state == "QUIET" && st.minOnline > 0 {
            session.toast(st.delivery ? "Most \(st.supplyNoun) near you are closed right now." : "No \(st.supplyNoun) online near you right now. Try again in a few minutes.")
        }
        openService(def.key)
    }

    /// An open (or quiet) tile: taxi and auto book a ride of that kind, jobs open jobs near me, the rest search that service.
    private func openService(_ key: String) {
        switch key {
        case "TAXI": startRide(session, router, kind: .cab)
        case "AUTO": startRide(session, router, kind: .auto)
        case "JOBS": openQuery(session, router, "jobs")
        default: session.discover.useService(key, radiusM: session.services.state(key)?.radiusM); router.push(.search)
        }
    }

    /// "List it" on a locked tile: the supply side of that service signs up.
    private func listService(_ key: String) {
        switch key {
        case "TAXI", "AUTO", "PARCEL": router.push(.vehicles)
        case "GIGS": router.push(.listingEdit(id: nil, kind: "SKILL", service: nil))
        case "JOBS": router.push(.myListings)
        default: router.push(.listingEdit(id: nil, kind: "BUSINESS", service: key))
        }
    }
}

/// The search pill that opens the search screen (Android's SearchBar).
struct SearchPill: View {
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

private extension Array {
    func chunked(_ n: Int) -> [[Element]] { stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) } }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
