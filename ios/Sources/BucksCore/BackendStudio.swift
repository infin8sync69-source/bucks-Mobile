import Foundation

// Calls for the Studio (port of data/BackendStudio.kt, listing parts): galleries, listing media and the recommendation threshold.

public extension Backend {
    /// A photo list as the jsonb the server stores: `caption` only when there is one.
    static func mediaJSON(_ photos: [MediaPhoto]) -> [[String: String]] {
        photos.map { p in p.caption.trimmingCharacters(in: .whitespaces).isEmpty ? ["url": p.url] : ["url": p.url, "caption": p.caption] }
    }
    /// Replaces a listing's gallery (the server keeps only photos from the listing's own listing-media folder, at most 20).
    func setGallery(listingId: String, photos: [MediaPhoto]) async throws {
        try await update("listings", ["gallery": Self.mediaJSON(photos)], filters: [.eq("id", listingId)])
    }
    /// Uploads a photo to listing-media/<listing id>/ and returns its public URL.
    func uploadListingMedia(listingId: String, photo: Picked) async throws -> String {
        let path = "\(listingId)/\(photo.objectName())"
        try await upload(bucket: "listing-media", path: path, data: photo.data, contentType: photo.mime)
        guard let url = publicURL(bucket: "listing-media", path: path) else { throw BackendError.notSignedIn }
        return url.absoluteString
    }
    /// Removes files of listing-media by their public URLs (photos taken out of a gallery or a product). Callers ignore failures.
    func deleteListingMedia(urls: [String]) async throws {
        let marker = "/object/public/listing-media/"
        let paths = urls.compactMap { u -> String? in
            guard let r = u.range(of: marker) else { return nil }
            let p = String(u[r.upperBound...]); return p.isEmpty ? nil : p
        }
        try await deleteFiles(bucket: "listing-media", paths: paths)
    }
    /// How many in-person recommendations take a listing live (settings.min_recommendations); nil when it can't be read.
    func minRecommendations() async throws -> Int? { try await settingValue("min_recommendations").map { Int($0) } }
}

// MARK: - Store catalogue and product feedback (migration product_feedback.sql)

/// How one product is rated: recommends and not-recommends, comments, and my own vote (1, -1 or nil). Options of a product share one rating.
public struct RatingSummary: Codable, Hashable, Sendable {
    public var productKey: String
    public var up: Int
    public var down: Int
    public var comments: Int
    public var mine: Int?
    public init(productKey: String, up: Int = 0, down: Int = 0, comments: Int = 0, mine: Int? = nil) { self.productKey = productKey; self.up = up; self.down = down; self.comments = comments; self.mine = mine }
    public var key: String { productKey }
    public var votes: Int { up + down }
    /// Share of people who recommend it, in percent; nil while nobody has voted.
    public var percent: Int? { votes == 0 ? nil : Int((Double(up) * 100 / Double(votes)).rounded()) }
}

public struct ProductComment: Decodable, Hashable, Sendable {
    public var profileId: String
    public var name: String
    public var vote: Int
    public var comment: String
    public var updatedAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        profileId = try c.decode(String.self, forKey: .profileId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        vote = (try? c.decodeIfPresent(Int.self, forKey: .vote)) ?? 1
        comment = (try? c.decodeIfPresent(String.self, forKey: .comment)) ?? ""
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? ""
    }
    private enum K: String, CodingKey { case profileId, name, vote, comment, updatedAt }
}

public extension Backend {
    /// A store's items without descriptions or extra photos, a fraction of the size, for the Products tab.
    func catalogItems(_ listingId: String) async throws -> [ItemRow] { try await rpcList("catalog_items", ["p_listing": listingId]) }
    /// One full item (all photos, description), fetched when a product is opened.
    func itemById(_ id: String) async throws -> ItemRow? { try await selectOne("items", filters: [.eq("id", id)]) }

    func productRatings(_ listingId: String) async throws -> [RatingSummary] { try await rpcList("product_ratings_summary", ["p_listing": listingId]) }
    /// Recommend (1) or not recommend (-1) a product with an optional comment; a second call replaces the first.
    func rateProduct(listingId: String, key: String, vote: Int, comment: String) async throws {
        try await rpcVoid("rate_product", ["p_listing": listingId, "p_key": key, "p_vote": vote, "p_comment": comment])
    }
    func clearProductRating(listingId: String, key: String) async throws { try await rpcVoid("clear_product_rating", ["p_listing": listingId, "p_key": key]) }
    /// Comments on a product, newest first, 20 at a time; `before` pages back (left out on the first page: the server's default is now()).
    func productComments(listingId: String, key: String, before: String? = nil) async throws -> [ProductComment] {
        var params: [String: Any?] = ["p_listing": listingId, "p_key": key]
        if let before { params["p_before"] = before }
        return try await rpcList("product_ratings_list", params)
    }

    // MARK: direct recommendations on any profile (migration ecommerce.sql: rate_listing)

    /// Recommend (1) or not recommend (-1) a shop, pro, asset or driver with an optional comment; it shows in Reviews. A second call replaces the first.
    func rateListing(_ listingId: String, vote: Int, comment: String) async throws {
        try await rpcVoid("rate_listing", ["p_listing": listingId, "p_vote": vote, "p_comment": comment])
    }
    func clearListingRating(_ listingId: String) async throws { try await rpcVoid("clear_listing_rating", ["p_listing": listingId]) }
}
