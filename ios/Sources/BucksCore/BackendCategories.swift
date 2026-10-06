import Foundation

/// A category some owner already used: the picker lists these under "Added by others".
public struct CategorySuggestion: Decodable, Hashable, Sendable {
    public var category: String
    public var uses: Int
    public init(category: String, uses: Int = 1) { self.category = category; self.uses = uses }
    private enum K: String, CodingKey { case category, uses }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        category = try c.decode(String.self, forKey: .category)
        uses = (try? c.decodeIfPresent(Int.self, forKey: .uses)) ?? 1
    }
}

public extension Backend {
    /// Categories used by live or pending listings of this kind (most used first), so a category one owner typed can be picked by the next
    /// (`category_suggestions(p_kind, p_q)`; `q` narrows by text).
    func categorySuggestions(kind: String, q: String = "") async throws -> [CategorySuggestion] {
        try await rpcList("category_suggestions", ["p_kind": kind, "p_q": q])
    }
}
