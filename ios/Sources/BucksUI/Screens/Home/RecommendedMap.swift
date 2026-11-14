import SwiftUI
import BucksCore

/*
 * The "Recommended here" layer on the Home map (RecommendedMap.kt; reports/Map feed for Gen Z India.md, Phase 1). Places, never people:
 * Bucks pages and locality centres that posts are tagged to, ranked by recommend votes (supabase/migrations/map_recommended.sql).
 * A pin opens a small card; its "See posts" opens the posts about that place. The places load for the area on screen once, then
 * again only on "Search this area" or a chip change, so panning on a slow network costs nothing.
 */

/// How many places get a numbered label on the map and a card in the strip; the rest are plain dots you can still tap.
private let recommendedTop = 10

/// The layer's state, kept by Home while Home is on screen.
@MainActor @Observable
final class RecommendedLayer {
    var on = true
    /// ALL, FOOD, SHOPS or SERVICES.
    var category = "ALL"
    /// 7 for "This week", 0 for all time.
    var days = 7
    var places: [MapPlace] = []
    var loaded = false
    var loading = false
    var failed = false
    /// The map has moved since the places were loaded: offer "Search this area".
    var stale = false
    var selected: MapPlace?
    var postsFor: MapPlace?
    var reload = 0

    /// What a load depends on: changing any of these loads again.
    var loadKey: String { "\(on)-\(category)-\(days)-\(reload)" }

    /// The pins this layer adds: the top places numbered with their recommend count, the rest as dots.
    var pins: [MapPin] {
        guard on else { return [] }
        return places.enumerated().map { i, p in
            MapPin(id: "rec-" + p.id, at: p.at, title: p.name, tint: BucksColor.primary,
                   badge: i < recommendedTop ? "\(i + 1) · ↑\(p.up)" : nil, selected: selected?.id == p.id)
        }
    }

    /// A tapped map pin: the place it stands for, if it's one of ours.
    func place(forPin id: String) -> MapPlace? {
        guard id.hasPrefix("rec-") else { return nil }
        let key = String(id.dropFirst(4))
        return places.first { $0.id == key }
    }

    func mapMoved() { if on && loaded { stale = true } }

    func load(_ cmds: MapCommands) async {
        guard on else { return }
        // The map needs a moment to be laid out before it knows its edges.
        var b = cmds.bounds(); var tries = 0
        while b == nil && tries < 20 { tries += 1; try? await Task.sleep(nanoseconds: 150_000_000); if Task.isCancelled { return }; b = cmds.bounds() }
        guard let b else { return }
        loading = true; failed = false
        do {
            let got = try await Backend.shared.mapPlaces(s: b.s, w: b.w, n: b.n, e: b.e, days: days, category: category == "ALL" ? nil : category)
            if Task.isCancelled { loading = false; return }
            places = got
            if let s = selected, !got.contains(where: { $0.id == s.id }) { selected = nil }
        } catch {
            if Task.isCancelled { loading = false; return }
            failed = true
        }
        loading = false; loaded = true; stale = false
    }
}

/// The chips over the map: the layer switch, the categories, the time window; and "Search this area" after the map has moved.
struct RecommendedControls: View {
    @Bindable var layer: RecommendedLayer
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Recommended", layer.on, "hand.thumbsup") { layer.on.toggle(); layer.selected = nil }
                    if layer.on {
                        ForEach([("ALL", "All"), ("FOOD", "Food and chai"), ("SHOPS", "Shops"), ("SERVICES", "Services")], id: \.0) { k, label in
                            chip(label, layer.category == k) { layer.category = k; layer.selected = nil }
                        }
                        chip(layer.days > 0 ? "This week" : "All time", false, "clock") { layer.days = layer.days > 0 ? 0 : 7 }
                    }
                }.padding(.horizontal, Gutter).padding(.vertical, 4)
            }
            if layer.on && (layer.stale || layer.loading) {
                Button { layer.reload += 1 } label: {
                    HStack(spacing: 6) {
                        if layer.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        Text(layer.loading ? "Looking for recommended places…" : "Search this area").bucks(.labelLarge)
                    }
                    .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(BucksColor.surface).shadow(color: .black.opacity(0.16), radius: 4, y: 1))
                }.buttonStyle(.plain).disabled(layer.loading)
            }
        }
    }

    /// A chip that reads on the map: a solid surface with a shadow, so it stays legible over any street.
    private func chip(_ text: String, _ selected: Bool, _ icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(text).bucks(.labelLarge).lineLimit(1)
            }
            .foregroundStyle(selected ? BucksColor.onPrimaryContainer : BucksColor.onSurface)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(Capsule().fill(selected ? BucksColor.primaryContainer : BucksColor.surface).shadow(color: .black.opacity(0.16), radius: 3, y: 1))
            .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What the layer puts in Home's sheet above the search pill: the chosen place's card, or a line about the area with the numbered strip,
/// or the "be the first" card when nothing here is recommended yet.
struct RecommendedSheetContent: View {
    @Bindable var layer: RecommendedLayer
    var me: LatLng?
    var onListing: (String) -> Void
    var onDirections: (MapPlace) -> Void
    var onPost: () -> Void

    var body: some View {
        if layer.on {
            if let sel = layer.selected {
                PlaceCardView(place: sel, index: layer.places.firstIndex { $0.id == sel.id }, me: me, onClose: { layer.selected = nil },
                              onPosts: { layer.postsFor = sel }, onListing: onListing, onDirections: { onDirections(sel) })
            } else if layer.failed {
                HStack {
                    Muted("Couldn't load recommended places. Check your connection.")
                    Button("Try again") { layer.reload += 1 }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                }.padding(.bottom, 12)
            } else if layer.loaded && layer.places.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if layer.days > 0 {
                        Text("Nothing recommended here this week.").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                        Button("Show all time") { layer.days = 0 }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary).padding(.vertical, 6)
                    } else {
                        Text("Be the first to recommend a place here").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                        Muted("Post about a shop, café or service you like and tag it. It shows here once people vote.")
                        SmallButton("Write a post", tonal: true, action: onPost).fixedSize().padding(.top, 8)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            } else if layer.loaded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(layer.places.count == 1 ? "1 place recommended in this area" : "\(layer.places.count) places recommended in this area")
                        .bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(layer.places.prefix(recommendedTop).enumerated()), id: \.element.id) { i, p in
                                Button { layer.selected = p } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(i + 1)  \(p.name)").bucks(.labelLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                                        Text("Recommended by \(p.up)").bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant).lineLimit(1)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10).frame(minWidth: 120, maxWidth: 200, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BucksColor.outlineVariant))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("\(p.name), number \(i + 1), recommended by \(p.up)")
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }
        }
    }
}

/// The chosen place: name, the counts in words (the "no" votes shown too), distance, then See posts, Directions, Open page and Share.
private struct PlaceCardView: View {
    let place: MapPlace; let index: Int?; let me: LatLng?
    let onClose: () -> Void, onPosts: () -> Void, onListing: (String) -> Void, onDirections: () -> Void

    private var numbered: String { if let index, index < recommendedTop { return "\(index + 1)  " }; return "" }
    private var detail: String {
        var bits: [String] = [place.up > 0 ? "Recommended by \(place.up)" : (place.posts == 1 ? "1 post" : "\(place.posts) posts")]
        if place.down > 0 { bits.append(place.down == 1 ? "1 doesn't" : "\(place.down) don't") }
        if let me { bits.append(mapsDistance(Geo.distanceKm(me, place.at) * 1000)) }
        switch place.category { case "FOOD": bits.append("Food and chai"); case "SHOPS": bits.append("Shops"); case "SERVICES": bits.append("Services"); case "AREA": bits.append("Area"); default: break }
        return bits.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(numbered + place.name).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                    Muted(detail, maxLines: 2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                PrimaryButton("See posts", action: onPosts)
                SmallButton("Directions", tonal: true, action: onDirections).fixedSize()
                ShareLink(item: "\(place.name): recommended by \(place.up) people near you on Bucks") {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                }.accessibilityLabel("Share")
            }.padding(.top, 10)
            if let id = place.listingId {
                Button("Open page") { onListing(id) }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary).padding(.top, 8)
            }
        }.padding(.bottom, 12)
    }
}

/// "See posts": the posts about one place, best first, with the feed's own post card, votes and comments.
struct PlacePostsSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let place: MapPlace
    @State private var rows: [FeedRow]?
    @State private var commentsFor: String?

    var body: some View {
        NavigationStack {
            Group {
                if let rows {
                    if rows.isEmpty { Muted("No posts to show here right now.").padding(Gutter).frame(maxHeight: .infinity, alignment: .top) }
                    else { ScrollView { LazyVStack(spacing: 0) { ForEach(rows) { p in PostCard(post: p, onVote: { vote(p, $0) }, onComments: { commentsFor = p.id }, onDelete: {}) } }.padding(.bottom, 24) } }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .navigationTitle("Posts about \(place.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task(id: place.id) {
            do { rows = try await Backend.shared.mapPlacePosts(place: place.place, placeId: place.placeId) }
            catch { rows = []; session.toast("Couldn't load recommended places. Check your connection.") }
        }
        .sheet(item: Binding(get: { commentsFor.map(PlacePostId.init) }, set: { commentsFor = $0?.id })) { b in CommentsSheet(postId: b.id) }
    }

    /// The arrow answers at once; the server call follows, and a failure puts the numbers back.
    private func vote(_ p: FeedRow, _ v: Int) {
        guard let me = session.me?.id, let cur = rows?.first(where: { $0.id == p.id }) else { return }
        let prev = cur.myVote ?? 0, next = prev == v ? 0 : v
        shift(p.id, prev, next)
        Task { do { try await Backend.shared.vote(postId: p.id, me: me, vote: next) } catch { shift(p.id, next, prev); session.toast(friendlyError(error)) } }
    }
    private func shift(_ id: String, _ from: Int, _ to: Int) {
        guard let i = rows?.firstIndex(where: { $0.id == id }) else { return }
        rows?[i].myVote = to == 0 ? nil : to
        rows?[i].up += (to == 1 ? 1 : 0) - (from == 1 ? 1 : 0)
        rows?[i].down += (to == -1 ? 1 : 0) - (from == -1 ? 1 : 0)
    }
}

private struct PlacePostId: Identifiable { let id: String }
