import Foundation
import Observation

/// The kind chips on the search screen; `kinds` is what search_listings receives (nil = every kind).
public enum KindFilter: String, CaseIterable, Sendable {
    case all, shops, pros, assets, drivers
    public var label: String { switch self { case .all: "All"; case .shops: "Shops"; case .pros: "Pros"; case .assets: "Buy & rent"; case .drivers: "Drivers" } }
    public var kinds: [String]? { switch self { case .all: nil; case .shops: ["BUSINESS"]; case .pros: ["SKILL"]; case .assets: ["ASSET"]; case .drivers: ["DRIVER"] } }
}
/// Search radius chips, in km.
public let radiusChoices = [3, 10, 25]

/// Everything the profile screen shows for one listing, loaded together by `DiscoverStore.open`.
public struct ListingProfile: Sendable {
    public var listing: ListingRow
    public var items: [ItemRow] = []
    public var reviews: [ReviewRow] = []
    public var posts: [PostRow] = []
    public var recommendations = 0
    public var synced = false
    public var syncs = 0
    public var members = 0
    public var openJobs = 0
    /// My role on the listing (OWNER / ADMIN / STORE_RIDER), nil for a listing that isn't mine.
    public var myRole: String?
    /// Where the listing is, when it has a location.
    public var at: LatLng?
    /// Other live listings of the same kind and category nearby, for "More <category> nearby".
    public var similar: [SearchHit] = []
    public init(listing: ListingRow, items: [ItemRow] = [], reviews: [ReviewRow] = [], posts: [PostRow] = [], recommendations: Int = 0, synced: Bool = false, syncs: Int = 0,
                members: Int = 0, openJobs: Int = 0, myRole: String? = nil, at: LatLng? = nil, similar: [SearchHit] = []) {
        self.listing = listing; self.items = items; self.reviews = reviews; self.posts = posts; self.recommendations = recommendations; self.synced = synced; self.syncs = syncs
        self.members = members; self.openJobs = openJobs; self.myRole = myRole; self.at = at; self.similar = similar
    }
    public var mine: Bool { myRole != nil }
    public var products: [ItemRow] { items.filter { $0.kind == "PRODUCT" } }
    /// Services of a pro; older rows without a kind still count when nothing is marked SERVICE.
    public var services: [ItemRow] {
        let s = items.filter { $0.kind == "SERVICE" }
        return s.isEmpty ? items.filter { $0.kind != "PRODUCT" } : s
    }
}

/// Cloud discovery: search over live listings near me and the universal profile of a shop, pro or driver.
/// Screens read the state and call the actions; every action reports a failure as a toast.
@MainActor @Observable
public final class DiscoverStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    public var query = ""
    /// The selected kind chip; change it through `selectKind`, which also re-runs the search.
    public private(set) var kind: KindFilter = .all
    public var radiusKm = 10
    /// A service tile (FOOD, GROCERY, …) the search is limited to, or nil. Set through `useService`.
    public private(set) var service: String?
    public private(set) var results: [SearchHit] = []
    public private(set) var searching = false
    /// True once a search has returned, so the empty state never shows before the first results.
    public private(set) var searched = false
    /// Listing id -> everything its profile shows.
    public private(set) var profiles: [String: ListingProfile] = [:]
    /// Ids whose profile is loading right now.
    public private(set) var loading: Set<String> = []
    /// Ids that could not be found (deleted, or pending and not mine).
    public private(set) var missing: Set<String> = []
    /// Ids whose last load failed (no network, server error); the screen offers a retry instead of spinning forever.
    public private(set) var failed: Set<String> = []
    /// Listings I am synced with.
    public private(set) var mySyncs: Set<String> = []
    /// Ids whose sync toggle is in flight.
    public private(set) var syncing: Set<String> = []
    /// True while a listing chat is being opened: the Message and request buttons are off, so a double tap can't send the first line twice or open two chats.
    public private(set) var chatStarting = false
    /// A query typed on Home or Services; the search screen takes it once when it opens.
    public var pendingQuery = ""
    /// Live shops and pros near me, best reviewed first, for the Recommended tab. `topLoaded` is true once they have been asked for.
    public private(set) var top: [SearchHit] = []
    public private(set) var topLoaded = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchSeq = 0
    @ObservationIgnored private var syncsLoaded = false

    private func go(_ block: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
        }
    }

    // MARK: search

    /// Runs the current query, kind and radius against listings near me. An empty query browses everything nearby.
    public func search() {
        searchTask?.cancel()
        searchSeq += 1
        let n = searchSeq
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines), at = session.here, radius = radiusKm * 1000, kinds = kind.kinds, services = service.map { [$0] }
        searchTask = Task { @MainActor in
            searching = true
            do { let hits = try await Backend.shared.search(q, at: at, radiusM: radius, kinds: kinds, services: services); guard n == searchSeq else { return }; results = hits; searched = true }
            catch is CancellationError {}
            catch { if n == searchSeq { session.toast(friendlyError(error)) } }
            if n == searchSeq { searching = false }
        }
    }
    public func selectKind(_ k: KindFilter) { if kind != k { kind = k; search() } }
    public func setRadius(_ km: Int) { if radiusKm != km { radiusKm = km; search() } }
    /// The next wider radius chip, or nil at the widest.
    public var widerRadius: Int? { radiusChoices.first { $0 > radiusKm } }
    public func clear() { query = ""; search() }
    /// Opens search limited to one service (a Services tile), or clears that limit (nil). Does not search by itself: the search
    /// screen runs one when it opens. The service's own radius is used, so results match what unlocked the tile.
    public func useService(_ key: String?, radiusM: Int? = nil) {
        service = key
        if key != nil {
            query = ""; kind = .all
            if let m = radiusM { radiusKm = radiusChoices.first { $0 * 1000 >= m } ?? radiusChoices.last ?? radiusKm }
        }
    }
    /// The query waiting from Home or Services, handed over once.
    public func takePendingQuery() -> String? {
        let q = pendingQuery.trimmingCharacters(in: .whitespacesAndNewlines); pendingQuery = ""; return q.isEmpty ? nil : q
    }

    // MARK: profile

    /// Loads (or reloads) everything the profile screen needs for `id`. A listing that isn't there goes to `missing`; a fetch that
    /// throws (offline, server error) goes to `failed` so the screen shows "Try again" rather than an endless spinner.
    /// Only the listing row itself is required; every other part degrades to empty when its own call fails.
    public func open(_ id: String) {
        guard !loading.contains(id) else { return }
        loading.insert(id); failed.remove(id)
        go { [self] in
            defer { loading.remove(id) }
            do {
                let b = Backend.shared
                if !syncsLoaded { try? await refreshSyncsNow() }
                guard let l = try await b.listing(id) else { missing.insert(id); profiles[id] = nil; return }
                missing.remove(id)
                let me = session.me?.id
                // A store's Products tab needs names, prices and one photo each, not every description: the slim catalogue is about a quarter of the size.
                let slim = l.kind == "BUSINESS" ? (try? await b.catalogItems(id)) : nil
                let items = slim ?? ((try? await b.discoverItems(id)) ?? [])
                let reviews = (try? await b.reviews(id)) ?? []
                let posts = (l.kind == "SKILL" || l.kind == "BUSINESS") ? ((try? await b.discoverPosts(id)) ?? []) : []
                let members = (try? await b.discoverMembers(id)) ?? []
                let myRole = members.first { $0.profileId == me }?.role
                // One call once the discover migration is applied; the plain tables otherwise.
                var counts: ListingCounts
                if let c = try? await b.listingCounts(id) { counts = c } else {
                    counts = ListingCounts(recommendations: (try? await b.recommendationCount(id)) ?? 0, syncs: (try? await b.listingSyncCount(id)) ?? 0, members: members.count,
                                           openJobs: l.kind == "BUSINESS" ? ((try? await b.discoverOpenJobs(id)) ?? 0) : 0)
                }
                let at = try? await b.listingPoint(id)
                var similar: [SearchHit] = []
                if let at {
                    let hits = (try? await b.search("", at: at, radiusM: 5_000, kinds: [l.kind])) ?? []
                    similar = Array(hits.filter { $0.id != id && (l.category.trimmingCharacters(in: .whitespaces).isEmpty || $0.category.caseInsensitiveCompare(l.category) == .orderedSame) }.prefix(4))
                }
                await session.social.namesFor(Array(Set(reviews.map(\.authorId) + posts.map(\.authorId) + [l.ownerId])))
                profiles[id] = ListingProfile(listing: l, items: items, reviews: reviews, posts: posts, recommendations: counts.recommendations, synced: mySyncs.contains(id), syncs: counts.syncs,
                                              members: max(counts.members, members.count), openJobs: counts.openJobs, myRole: myRole, at: at ?? nil, similar: similar)
            } catch is CancellationError { throw CancellationError() }
            catch { failed.insert(id); throw error }
        }
    }

    public func refreshSyncs() { go { [self] in try await refreshSyncsNow() } }
    private func refreshSyncsNow() async throws {
        guard let me = session.me?.id else { return }
        let rows = try await Backend.shared.myListingSyncs(me: me)
        guard session.me?.id == me else { return }
        mySyncs = Set(rows.map(\.listingId)); syncsLoaded = true
    }
    /// Sign-out and account deletion: results, profiles (which carry "mine" and "synced") and my listing syncs belong to this person only.
    public func signedOut() {
        searchTask?.cancel(); searchTask = nil; searchSeq += 1
        query = ""; service = nil; results = []; searching = false; searched = false; pendingQuery = ""
        profiles = [:]; loading = []; missing = []; failed = []
        mySyncs = []; syncing = []; syncsLoaded = false
        top = []; topLoaded = false
    }
    public func isSynced(_ id: String) -> Bool { mySyncs.contains(id) }

    /// Follow or unfollow a listing: its posts then show up in my feed.
    public func syncListing(_ id: String, on: Bool) {
        go { [self] in
            guard let me = session.me?.id, !syncing.contains(id), on != mySyncs.contains(id) else { return }
            syncing.insert(id)
            defer { syncing.remove(id) }
            if on { try await Backend.shared.syncListing(me: me, listingId: id) } else { try await Backend.shared.unsyncListing(me: me, listingId: id) }
            if on { mySyncs.insert(id) } else { mySyncs.remove(id) }
            if var p = profiles[id] { p.synced = on; p.syncs = max(0, p.syncs + (on ? 1 : -1)); profiles[id] = p }
            let title = profiles[id]?.listing.title ?? results.first { $0.id == id }?.title ?? "them"
            session.toast(on ? "Synced with \(title). Their posts now show in your feed." : "Unsynced from \(title).")
        }
    }

    /// Opens (or reuses) my chat with the people who run a listing; `firstLine` is sent before the chat opens, e.g. a service request.
    public func startListingChat(_ id: String, firstLine: String? = nil, onOpen: @escaping (String) -> Void) {
        guard !chatStarting else { return }
        chatStarting = true
        go { [self] in
            defer { chatStarting = false }
            let conv = try await Backend.shared.startListingChat(id)
            if let me = session.me?.id, let line = firstLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty { try await Backend.shared.discoverSend(conversation: conv, me: me, body: line) }
            session.chat.refreshInbox()
            onOpen(conv)
        }
    }

    // MARK: the Recommended tab

    /// Live shops and pros near me (search_listings ranks by trust), shown as "Top rated near you".
    public func loadTop() {
        let at = session.here
        Task { @MainActor in
            if let hits = try? await Backend.shared.search("", at: at, kinds: ["BUSINESS", "SKILL"]) { top = hits }
            topLoaded = true
        }
    }
}

// MARK: - helpers shared by the discover screens

/// Shop / Pro / Driver, the word people use for each listing kind.
public func kindLabel(_ kind: String) -> String {
    switch kind { case "BUSINESS": "Shop"; case "SKILL": "Pro"; case "DRIVER": "Driver"; default: kind.isEmpty ? kind : kind.lowercased().prefix(1).uppercased() + kind.lowercased().dropFirst() }
}
/// "650 m" or "1.2 km".
public func formatDistance(_ meters: Double) -> String { meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000) }

public extension JSONValue {
    /// A string field of a listing's details, or nil when missing or blank. Booleans and numbers come back as text.
    func str(_ key: String) -> String? {
        guard let v = self[key] else { return nil }
        let text: String
        switch v {
        case .string(let s): text = s
        case .bool(let b): text = b ? "true" : "false"
        case .number(let n): text = n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        default: return nil
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "null" ? nil : t
    }
    /// A list field of details ("languages": ["Kannada", "Hindi"]) or a comma-separated string.
    func list(_ key: String) -> [String] {
        switch self[key] {
        case .array(let a)?: return a.compactMap { v in v.string?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        case .string(let s)?: return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        default: return []
        }
    }
}
/// The vehicle a driver listing drives, from details (vehicle_kind / vehicle / kind) or the category ("Auto").
public func driverKind(_ details: JSONValue, category: String = "") -> VehicleKind? {
    let raw = ["vehicle_kind", "vehicle", "kind"].lazy.compactMap { details.str($0) }.first ?? (category.trimmingCharacters(in: .whitespaces).isEmpty ? nil : category)
    guard let raw else { return nil }
    return VehicleKind.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame || $0.label.caseInsensitiveCompare(raw) == .orderedSame || raw.range(of: $0.label, options: .caseInsensitive) != nil }
}
/// The rate line of a pro: details.rate, else the cheapest service.
public func proRate(_ details: JSONValue, minPrice: Int?) -> String { details.str("rate") ?? minPrice.map { "From ₹\($0)" } ?? "Rate on request" }
