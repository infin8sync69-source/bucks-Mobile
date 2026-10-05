import Foundation

// Feed, posts, comments, votes and Moments calls (port of the feed/moments sections of data/Backend.kt and data/BackendSocialExtras.kt).
// RPC parameter names are the ones in supabase/schema.sql and migrations/social-extras.sql: `feed`, `moments_tray` and `open_moments` take plain
// lat / lng; the rest take `p_` parameters.

/// A person whose Moments I've hidden from my tray (row-level security returns only my own rows).
public struct MomentMuteRow: Codable, Hashable, Sendable {
    public var profileId: String
    public var mutedId: String
}

extension Backend {
    // MARK: feed

    /// A page of the feed (30 rows) as seen from `at`; `before` is the created_at of the last row already shown.
    public func feed(at: LatLng, before: String? = nil) async throws -> [FeedRow] {
        var p: [String: Any?] = ["lat": at.lat, "lng": at.lng]
        if let before { p["before"] = before }
        return try await rpcList("feed", p)
    }

    /// `media`: storage path in the posts bucket with its mime type (image/jpeg, video/mp4), so the feed knows what to show.
    public func post(me: String, body: String, media: [(path: String, mime: String)], visibility: String, at: LatLng?, area: String, listingId: String? = nil) async throws {
        var row: [String: Any?] = ["author_id": me, "body": body, "visibility": visibility, "area": area,
                                   "media": media.map { ["path": $0.path, "mime": $0.mime] }]
        if let listingId { row["listing_id"] = listingId }
        if let at { row["location"] = Backend.point(at) }
        try await insertVoid("posts", row)
    }

    public func deletePost(_ id: String) async throws { try await delete("posts", filters: [.eq("id", id)]) }

    /// `vote` is 1, -1 or 0 (take my vote back).
    public func vote(postId: String, me: String, vote: Int) async throws {
        if vote == 0 { try await delete("post_votes", filters: [.eq("post_id", postId), .eq("profile_id", me)]) }
        else { try await upsert("post_votes", ["post_id": postId, "profile_id": me, "vote": vote]) }
    }

    public func comments(postId: String) async throws -> [CommentRow] {
        try await select("post_comments", filters: [.eq("post_id", postId)], order: "created_at", ascending: true)
    }
    public func comment(postId: String, me: String, body: String) async throws {
        try await insertVoid("post_comments", ["post_id": postId, "author_id": me, "body": body])
    }

    /// One post that hasn't been deleted; nil when it's gone or I can't see it.
    public func postById(_ id: String) async throws -> PostRow? {
        try await selectOne("posts", filters: [.eq("id", id), .raw("deleted_at", "is.null")])
    }

    // MARK: moments

    public func momentsTray(at: LatLng) async throws -> [TrayRow] { try await rpcList("moments_tray", ["lat": at.lat, "lng": at.lng]) }

    /// An author's live moments as I open them from where I am. Also records access to the nearby (LOCAL) ones so their media can be signed.
    public func openMoments(author: String, at: LatLng) async throws -> [MomentRow] {
        try await rpcList("open_moments", ["p_author": author, "lat": at.lat, "lng": at.lng])
    }

    public func postMoment(me: String, mediaPath: String, type: String, caption: String, audience: String, at: LatLng?, listingId: String? = nil) async throws {
        var row: [String: Any?] = ["author_id": me, "media_path": mediaPath, "media_type": type, "caption": caption, "audience": audience]
        if let listingId { row["listing_id"] = listingId }
        if let at { row["location"] = Backend.point(at) }
        try await insertVoid("moments", row)
    }

    public func deleteMoment(_ id: String) async throws { try await delete("moments", filters: [.eq("id", id)]) }

    /// Marks a moment seen, optionally with an emoji reaction (`p_reaction` goes out as null otherwise).
    public func viewMoment(_ id: String, reaction: String? = nil) async throws { try await rpcVoid("view_moment", ["p_moment": id, "p_reaction": reaction]) }

    public func momentViewers(_ id: String) async throws -> [ViewerRow] { try await rpcList("moment_viewers", ["p_moment": id]) }

    /// Replies to a moment in a direct chat with its author; returns the conversation id.
    public func replyToMoment(_ id: String, body: String) async throws -> String { try await rpc("reply_to_moment", ["p_moment": id, "p_body": body]) }

    public func muteMoments(me: String, other: String, on: Bool) async throws {
        if on { try await upsert("moment_mutes", ["profile_id": me, "muted_id": other]) }
        else { try await delete("moment_mutes", filters: [.eq("profile_id", me), .eq("muted_id", other)]) }
    }

    public func momentMutes() async throws -> [MomentMuteRow] { try await select("moment_mutes") }
}
