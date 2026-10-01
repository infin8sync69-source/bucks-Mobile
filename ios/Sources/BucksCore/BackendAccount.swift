import Foundation

/// A recommendation I gave in person (BackendStudio.kt RecGiven).
public struct RecGiven: Codable, Hashable, Sendable {
    public var listingId: String
    public var createdAt: String
    public init(listingId: String, createdAt: String = "") { self.listingId = listingId; self.createdAt = createdAt }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self); listingId = try c.decode(String.self, forKey: .listingId); createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
    private enum K: String, CodingKey { case listingId, createdAt }
}

/// The calls behind the Account tab: my profile tabs, my order history and renewing my Bucks ID (BackendStudio.kt, Backend.kt).
extension Backend {
    /// Renews the Bucks ID card for another year; answers the new issue time (studio.sql renew_bucks_id).
    public func renewBucksIdCard() async throws -> String { try await rpc("renew_bucks_id") }

    /// My own posts (photos, videos, text), newest first, for the profile's Feed and Media tabs.
    public func accountMyPosts(me: String, limit: Int = 60) async throws -> [PostRow] {
        try await select("posts", filters: [.eq("author_id", me), .raw("deleted_at", "is.null")], order: "created_at", ascending: false, limit: limit)
    }

    /// Files and photos shared in my chats, sent or received, newest first (chat bucket paths are in attachment.path).
    public func accountChatFiles(limit: Int = 60) async throws -> [MessageRow] {
        try await select("messages", filters: [.raw("attachment", "not.is.null"), .raw("deleted_at", "is.null")], order: "created_at", ascending: false, limit: limit)
    }

    /// Listings by id, for the rows that point at one.
    public func accountListings(_ ids: [String]) async throws -> [String: ListingRow] {
        let unique = Array(Set(ids)); guard !unique.isEmpty else { return [:] }
        let rows: [ListingRow] = try await select("listings", filters: [.isIn("id", unique)])
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Listings I recommended in person, with the listing when it is still visible to me.
    public func accountRecommendationsIGave(me: String) async throws -> [(RecGiven, ListingRow?)] {
        let rows: [RecGiven] = try await select("recommendations", filters: [.eq("recommender_id", me)], order: "created_at", ascending: false)
        let by = try await accountListings(rows.map(\.listingId)); return rows.map { ($0, by[$0.listingId]) }
    }

    /// Reviews I wrote after orders and trips, with the listing they were for.
    public func accountReviewsIWrote(me: String) async throws -> [(ReviewRow, ListingRow?)] {
        let rows: [ReviewRow] = try await select("reviews", filters: [.eq("author_id", me)], order: "created_at", ascending: false, limit: 40)
        let by = try await accountListings(rows.map(\.listingId)); return rows.map { ($0, by[$0.listingId]) }
    }

    /// My orders as the buyer, newest first.
    public func accountMyOrders(me: String) async throws -> [OrderRow] {
        try await select("orders", filters: [.eq("buyer_id", me)], order: "created_at", ascending: false)
    }

    /// My rides as the rider, newest first (tasks of type RIDE I requested).
    public func accountMyRides(me: String, limit: Int = 30) async throws -> [TaskRow] {
        try await select("tasks", filters: [.eq("requester_id", me), .eq("type", "RIDE")], order: "created_at", ascending: false, limit: limit)
    }

    /// Listing title lookup for order lists.
    public func accountListingTitles(_ ids: [String]) async throws -> [String: String] { try await accountListings(ids).mapValues(\.title) }
}

extension Backend {
    /// Whether I am Bucks staff (shows "Review documents" in Settings).
    public func accountIsStaff() async throws -> Bool { try await rpc("is_staff") }

    /// How many people I am synced with (accepted syncs, either direction).
    public func accountSyncedCount() async throws -> Int {
        let rows: [SyncRow] = try await select("syncs")
        return rows.filter { $0.status == "ACCEPTED" }.count
    }

    /// My vote (1 or -1) on each of these posts; posts I haven't voted on are missing.
    public func accountMyVotes(me: String, postIds: [String]) async throws -> [String: Int] {
        guard !postIds.isEmpty else { return [:] }
        struct Vote: Decodable { var postId: String; var vote: Int }
        let rows: [Vote] = try await select("post_votes", filters: [.eq("profile_id", me), .isIn("post_id", postIds)])
        return Dictionary(rows.map { ($0.postId, $0.vote) }, uniquingKeysWith: { a, _ in a })
    }

    /// Sets my vote on a post; 0 takes it back.
    public func accountVote(postId: String, me: String, vote: Int) async throws {
        if vote == 0 { try await delete("post_votes", filters: [.eq("post_id", postId), .eq("profile_id", me)]) }
        else { try await upsert("post_votes", ["post_id": postId, "profile_id": me, "vote": vote]) }
    }

    /// Deletes one of my posts.
    public func accountDeletePost(_ id: String) async throws { try await delete("posts", filters: [.eq("id", id)]) }
}

extension Backend {
    /// The listings I am a member of (own or run), for "For my listings" on the profile.
    public func accountMyListings(me: String) async throws -> [ListingRow] {
        let members: [MemberRow] = try await select("listing_members", filters: [.eq("profile_id", me)])
        let ids = members.map(\.listingId); if ids.isEmpty { return [] }
        let rows: [ListingRow] = try await select("listings", filters: [.isIn("id", ids)])
        return rows.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// How many people recommended each of these listings.
    public func accountRecommendationCounts(_ listingIds: [String]) async throws -> [String: Int] {
        if listingIds.isEmpty { return [:] }
        struct Row: Decodable { var listingId: String }
        let rows: [Row] = try await select("recommendations", columns: "listing_id", filters: [.isIn("listing_id", listingIds)])
        return Dictionary(grouping: rows, by: \.listingId).mapValues(\.count)
    }
}
