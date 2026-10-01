import Foundation

// Discover: search over live listings, the universal listing profile, sync with a listing, reviews and suggestions.
// Port of data/BackendDiscover.kt plus the search / listing / review / suggestion calls of data/Backend.kt.

/// One row of listing_syncs: `profileId` follows `listingId` (its posts show in their feed).
public struct ListingSyncRow: Codable, Hashable, Sendable { public var profileId: String; public var listingId: String }
/// A listing's coordinates as plain numbers (the listing_points view; PostGIS itself comes back as EWKB hex).
public struct ListingPoint: Codable, Hashable, Sendable { public var id: String; public var lat: Double; public var lng: Double }
/// The public numbers on a listing profile, from listing_counts() in supabase/migrations/discover.sql.
public struct ListingCounts: Codable, Hashable, Sendable {
    public var recommendations: Int, syncs: Int, members: Int, openJobs: Int
    public init(recommendations: Int = 0, syncs: Int = 0, members: Int = 0, openJobs: Int = 0) { self.recommendations = recommendations; self.syncs = syncs; self.members = members; self.openJobs = openJobs }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        recommendations = (try? c.decodeIfPresent(Int.self, forKey: .recommendations)) ?? 0; syncs = (try? c.decodeIfPresent(Int.self, forKey: .syncs)) ?? 0
        members = (try? c.decodeIfPresent(Int.self, forKey: .members)) ?? 0; openJobs = (try? c.decodeIfPresent(Int.self, forKey: .openJobs)) ?? 0
    }
    private enum K: String, CodingKey { case recommendations, syncs, members, openJobs }
}
private struct RecommenderRow: Decodable { var recommenderId: String }

extension Backend {
    // MARK: search and listings

    /// search_listings: `kinds` / `services` are only sent when set (null means every kind / every service).
    public func search(_ q: String, at: LatLng, radiusM: Int = 10_000, kinds: [String]? = nil, services: [String]? = nil) async throws -> [SearchHit] {
        var params: [String: Any?] = ["q": q, "lat": at.lat, "lng": at.lng, "radius_m": radiusM]
        if let kinds { params["kinds"] = kinds }
        if let services { params["services"] = services }
        return try await rpcList("search_listings", params)
    }
    public func listing(_ id: String) async throws -> ListingRow? { try await selectOne("listings", filters: [.eq("id", id)]) }
    /// Opens (or reuses) my chat with the people who run a listing.
    public func startListingChat(_ listingId: String) async throws -> String { try await rpc("start_listing_chat", ["p_listing": listingId]) }

    // MARK: reviews (`review(listingId:taskId:orderId:up:comment:)` lives in BackendRides.swift)

    public func reviews(_ listingId: String) async throws -> [ReviewRow] {
        try await select("reviews", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false)
    }

    // MARK: suggestions

    public func suggestPeople(at: LatLng) async throws -> [PersonSuggestion] { try await rpcList("suggest_people", ["lat": at.lat, "lng": at.lng]) }
    public func suggestListings(at: LatLng) async throws -> [ListingSuggestion] { try await rpcList("suggest_listings", ["lat": at.lat, "lng": at.lng]) }

    // MARK: sync with a listing

    /// Listings I follow.
    public func myListingSyncs(me: String) async throws -> [ListingSyncRow] { try await select("listing_syncs", filters: [.eq("profile_id", me)]) }
    public func syncListing(me: String, listingId: String) async throws { try await insertVoid("listing_syncs", ["profile_id": me, "listing_id": listingId]) }
    public func unsyncListing(me: String, listingId: String) async throws { try await delete("listing_syncs", filters: [.eq("profile_id", me), .eq("listing_id", listingId)]) }
    /// How many people follow a listing (rows are readable by everyone).
    public func listingSyncCount(_ listingId: String) async throws -> Int {
        let rows: [ListingSyncRow] = try await select("listing_syncs", filters: [.eq("listing_id", listingId)]); return rows.count
    }

    // MARK: public counts

    /// How many neighbours recommended a listing in person.
    public func recommendationCount(_ listingId: String) async throws -> Int {
        let rows: [RecommenderRow] = try await select("recommendations", columns: "recommender_id", filters: [.eq("listing_id", listingId)]); return rows.count
    }
    /// All four numbers in one call; nil when the listing is not visible to me (pending and not mine).
    public func listingCounts(_ listingId: String) async throws -> ListingCounts? {
        let rows: [ListingCounts] = try await rpcList("listing_counts", ["p_listing": listingId]); return rows.first
    }

    // MARK: where a listing is, and its photo

    public func listingPoint(_ listingId: String) async throws -> LatLng? {
        let p: ListingPoint? = try await selectOne("listing_points", filters: [.eq("id", listingId)]); return p.map { LatLng($0.lat, $0.lng) }
    }
    /// A listing or product photo: `photo_url` is either a full URL or a path inside the public listing-media bucket.
    public func listingPhoto(_ photoUrl: String?) -> URL? {
        guard let t = photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        return publicURL(bucket: "listing-media", path: t)
    }

    // MARK: profile parts (kept private to this area so other areas' calls of the same name never clash)

    func discoverItems(_ listingId: String) async throws -> [ItemRow] { try await select("items", filters: [.eq("listing_id", listingId)], order: "sort", ascending: true) }
    func discoverMembers(_ listingId: String) async throws -> [MemberRow] { try await select("listing_members", filters: [.eq("listing_id", listingId)]) }
    func discoverPosts(_ listingId: String) async throws -> [PostRow] { try await select("posts", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false) }
    func discoverOpenJobs(_ listingId: String) async throws -> Int {
        let rows: [JobRow] = try await select("jobs", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false); return rows.filter(\.open).count
    }
    /// A chat line, as `Backend.send` on Android (used for the request a profile button sends before opening the chat).
    func discoverSend(conversation: String, me: String, body: String) async throws {
        try await insertVoid("messages", ["conversation_id": conversation, "sender_id": me, "body": body])
    }
}
