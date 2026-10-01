import SwiftUI
import BucksCore

private let rideWords = try? NSRegularExpression(pattern: "\\b(auto|cab|taxi|ride|rickshaw)\\b", options: .caseInsensitive)

/// Cloud search over live listings near me. Typing searches after a 300 ms pause; an empty query browses
/// everything nearby. Kind chips (All / Shops / Pros / Drivers) and radius chips (3 / 10 / 25 km) search at once.
struct CloudSearchScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool
    @State private var started = false
    @State private var places: [MapServices.PlaceHit] = []

    private var d: DiscoverStore { session.discover }

    private var wantsRide: Bool {
        if d.kind == .drivers { return true }
        let q = d.query
        return rideWords?.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil
    }

    var body: some View {
        @Bindable var d = session.discover
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Search", onBack: { router.pop() })
                field(query: $d.query)
                kindChips
                if let st = d.service.flatMap({ session.services.state($0) }), st.delivery, !st.deliveryNow {
                    Notice("No Bucks riders are online near you right now. Order for pickup, or from shops with their own riders.").padding(.horizontal, Gutter).padding(.top, 10)
                }
                radiusChips
                // Fixed-height slot so the list doesn't jump while a search runs.
                ZStack { if d.searching { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary) } }
                    .frame(height: 12).padding(.horizontal, Gutter).padding(.vertical, 4)
                results
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        // A query typed on Home or Services arrives through the store; take it once, then it's ours.
        .task(id: d.query) {
            if !started {
                started = true
                if let q = d.takePendingQuery() { d.query = q; return }
                focused = true
                d.refreshSyncs()
            }
            if !d.query.isEmpty, d.query.trimmingCharacters(in: .whitespaces).count > 0 { try? await Task.sleep(nanoseconds: 300_000_000); if Task.isCancelled { return } }
            d.search()
        }
        // Places (streets, landmarks, towns) from the map search sit under the same bar; tapping one opens it on the map with directions.
        .task(id: d.query) {
            places = []
            let q = d.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            places = Array(await MapServices.search(q, near: session.here).prefix(4))
        }
    }

    private func field(query: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface)
            TextField("", text: query, prompt: Text("Shops, pros, drivers or an item, like sugar").foregroundStyle(BucksColor.onSurfaceVariant))
                .bucksFont(.bodyLarge).foregroundStyle(BucksColor.onSurface).tint(BucksColor.primary).focused($focused)
                .submitLabel(.search).onSubmit { d.search() }
            if !d.query.isEmpty {
                Button { d.clear() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 40, height: 40).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18).padding(.trailing, 4).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
        .padding(.horizontal, Gutter)
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Opened from a Services tile: that service is the first chip; tapping it widens the search to everything.
                if let key = d.service, let def = serviceDef(key) {
                    BucksChip("\(def.label) ✕", selected: true, systemImage: def.icon) { d.useService(nil); d.search() }
                }
                ForEach(KindFilter.allCases, id: \.self) { k in
                    BucksChip(k.label, selected: d.kind == k && d.service == nil, systemImage: k.kinds?.first.map(kindIcon)) { d.useService(nil); d.selectKind(k); d.search() }
                }
            }.padding(.horizontal, Gutter)
        }.padding(.top, 12)
    }

    private var radiusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Muted("Within")
                ForEach(radiusChoices, id: \.self) { km in BucksChip("\(km) km", selected: d.radiusKm == km) { d.setRadius(km) } }
            }.padding(.horizontal, Gutter)
        }.padding(.top, 4)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !session.locationGranted {
                    Notice("Turn on location to see what's near you. Until then, results are around Jayanagar.").padding(.horizontal, Gutter).padding(.vertical, 4)
                }
                if wantsRide { RideBanner { startRide(session, router, kind: $0) } }
                if !places.isEmpty {
                    Text("Places").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.horizontal, Gutter).padding(.vertical, 8)
                    ForEach(places, id: \.self) { h in
                        ListRow(h.name, subtitle: h.detail, onTap: { MapsPick.place = h; router.push(.maps) }, leading: { Avatar(systemImage: "mappin.circle.fill", size: 40) }, trailing: { Muted("Directions") })
                        BucksDivider()
                    }
                }
                HStack {
                    Text(d.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Everything nearby" : "Results for “\(d.query.trimmingCharacters(in: .whitespaces))”").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Spacer(minLength: 8)
                    if !d.results.isEmpty { Muted("\(d.results.count) within \(d.radiusKm) km") }
                }.padding(.horizontal, Gutter).padding(.vertical, 8)
                ForEach(d.results) { h in DiscoverListingCard(hit: h).padding(.horizontal, Gutter).padding(.bottom, 12) }
                if d.searched && !d.searching && d.results.isEmpty { EmptyResults() }
            }.padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively)
    }
}

private struct RideBanner: View {
    var onRide: (VehicleKind) -> Void
    var body: some View {
        BucksCard(tint: true) {
            Text("Need a ride now?").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted("Bucks rings the nearest online rider. Pay after the trip, cash or UPI.").padding(.top, 2)
            HStack(spacing: 8) {
                SmallButton("Book an auto") { onRide(.auto) }.fixedSize()
                SmallButton("Book a cab", tonal: true) { onRide(.cab) }.fixedSize()
            }.padding(.top, 10)
        }.padding(.horizontal, Gutter).padding(.vertical, 4)
    }
}

/// No results: says why and offers the next step (widen the radius, drop the kind filter, or list yourself).
private struct EmptyResults: View {
    @Environment(AppSession.self) private var session
    var body: some View {
        let d: DiscoverStore = session.discover; let wider = d.widerRadius, q = d.query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundStyle(BucksColor.onSurfaceVariant)
            Text(q.isEmpty ? "Nothing listed within \(d.radiusKm) km yet" : "No results for “\(q)” within \(d.radiusKm) km").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                .multilineTextAlignment(.center).padding(.top, 12)
            Muted(wider != nil ? "Widen the search to see more."
                  : q.isEmpty ? "Be the first: list your shop, skill or vehicle from Menu > Bucks Pro."
                  : "Try another word, like the item you need (sugar, tap repair), or a category (grocery, electrician).", align: .center).padding(.top, 6)
            if let wider { SmallButton("Search within \(wider) km") { d.setRadius(wider) }.fixedSize().padding(.top, 14) }
            if d.kind != .all {
                Button { d.selectKind(.all) } label: { Text("Show shops, pros and drivers").bucks(.labelLarge).foregroundStyle(BucksColor.primary).padding(12) }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, Gutter).padding(.vertical, 32)
    }
}
