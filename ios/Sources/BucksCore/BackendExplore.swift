import Foundation

/// A shop, pro or product the people I'm synced with recommend (explore.sql for_you_named). `kind`: LISTING, PRODUCT (POST rows are dropped).
public struct ForYouItem: Codable, Hashable, Sendable, Identifiable {
    public var kind: String
    public var itemId: String
    public var listingId: String?
    public var title: String
    public var subtitle: String
    public var photoUrl: String?
    public var recommenders: Int
    public var recommenderName: String?
    public var id: String { kind + ":" + itemId }
    enum CodingKeys: String, CodingKey { case kind, itemId = "id", listingId, title, subtitle, photoUrl, recommenders, recommenderName }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""; itemId = (try? c.decodeIfPresent(String.self, forKey: .itemId)) ?? ""
        listingId = try? c.decodeIfPresent(String.self, forKey: .listingId); title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = (try? c.decodeIfPresent(String.self, forKey: .subtitle)) ?? ""; photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        recommenders = (try? c.decodeIfPresent(Int.self, forKey: .recommenders)) ?? 0; recommenderName = try? c.decodeIfPresent(String.self, forKey: .recommenderName)
    }
}

/// Explore (BackendMap.kt ExploreBackend).
extension Backend {
    /// `kind`: ALL, VIDEO, IMAGE or FILE. `q`: words to look for in the post, its author or its page; empty for everything.
    /// Recommended by my synced people first, then public posts.
    public func explore(kind: String, q: String) async throws -> [FeedRow] {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await rpcList("explore", ["p_kind": kind, "q": t.isEmpty ? nil : t])
    }
    /// Shops, pros and products the people I'm synced with recommend.
    public func forYouNamed() async throws -> [ForYouItem] { (try await rpcList("for_you_named") as [ForYouItem]).filter { $0.kind != "POST" } }
}
