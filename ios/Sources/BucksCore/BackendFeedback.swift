import Foundation

/// One post on the feedback board (feedback_board.sql). `status`: OPEN, PLANNED, IN_PROGRESS, DONE or DECLINED. `category`: IDEA, BUG or OTHER.
public struct FeedbackRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var category: String
    public var title: String
    public var body: String
    public var status: String
    public var staffNote: String
    public var votes: Int
    public var voted: Bool
    public var isMine: Bool
    public var authorName: String
    public var createdAt: String
    enum CodingKeys: String, CodingKey { case id, category, title, body, status, staffNote, votes, voted, isMine, authorName, createdAt }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        id = try c.decode(String.self, forKey: .id); category = s(.category); title = s(.title); body = s(.body); status = s(.status)
        staffNote = s(.staffNote); votes = (try? c.decodeIfPresent(Int.self, forKey: .votes)) ?? 0
        voted = (try? c.decodeIfPresent(Bool.self, forKey: .voted)) ?? false; isMine = (try? c.decodeIfPresent(Bool.self, forKey: .isMine)) ?? false
        authorName = s(.authorName); createdAt = s(.createdAt)
    }
}

/// The feedback board (BackendFeedback.kt).
extension Backend {
    /// `sort`: TOP or NEW. `status`: nil = everything but declined.
    public func feedbackList(sort: String, status: String? = nil, mine: Bool = false) async throws -> [FeedbackRow] {
        try await rpcList("feedback_list", ["sort": sort, "p_status": status, "mine": mine])
    }
    /// Answers the new post's id.
    public func feedbackPost(title: String, body: String, category: String) async throws -> String {
        try await rpc("feedback_post", ["p_title": title, "p_body": body, "p_category": category])
    }
    /// Answers the post's vote count after my vote is set or removed.
    public func feedbackVote(_ id: String, on: Bool) async throws -> Int { try await rpc("feedback_vote", ["p_post": id, "p_on": on]) }
    public func feedbackDelete(_ id: String) async throws { try await rpcVoid("feedback_delete", ["p_post": id]) }
    /// Staff only: a status and a public note.
    public func feedbackSetStatus(_ id: String, status: String, note: String?) async throws {
        try await rpcVoid("feedback_set_status", ["p_post": id, "p_status": status, "p_note": note])
    }
}
