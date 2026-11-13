import Foundation

/// One place on the Recommended map (supabase/migrations/map_recommended.sql: map_places): a Bucks page (`place` LISTING, with
/// `listingId`) or a locality centre (LOCALITY). Never a person. `category`: FOOD, SHOPS, SERVICES or AREA. Same as BackendMap.kt MapPlace.
public struct MapPlace: Codable, Hashable, Sendable, Identifiable {
    public var place: String
    public var placeId: String
    public var listingId: String?
    public var name: String
    public var category: String
    public var lat: Double
    public var lng: Double
    public var posts: Int
    public var up: Int
    public var down: Int
    public var score: Double
    public var id: String { place + ":" + placeId }
    public var at: LatLng { LatLng(lat, lng) }
    enum CodingKeys: String, CodingKey { case place, placeId, listingId, name, category, lat, lng, posts, up, down, score }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""; placeId = (try? c.decodeIfPresent(String.self, forKey: .placeId)) ?? ""
        listingId = try? c.decodeIfPresent(String.self, forKey: .listingId); name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "AREA"
        lat = try c.decode(Double.self, forKey: .lat); lng = try c.decode(Double.self, forKey: .lng)
        posts = (try? c.decodeIfPresent(Int.self, forKey: .posts)) ?? 0; up = (try? c.decodeIfPresent(Int.self, forKey: .up)) ?? 0
        down = (try? c.decodeIfPresent(Int.self, forKey: .down)) ?? 0; score = (try? c.decodeIfPresent(Double.self, forKey: .score)) ?? 0
    }
}

/// The Recommended layer on the Home map (BackendMap.kt MapBackend.places / placePosts).
extension Backend {
    /// Recommended places in a box, best first. `days` 0 = all time; `category` FOOD, SHOPS, SERVICES or nil for all.
    public func mapPlaces(s: Double, w: Double, n: Double, e: Double, days: Int, category: String?) async throws -> [MapPlace] {
        try await rpcList("map_places", ["s": s, "w": w, "n": n, "e": e, "p_days": days, "p_cat": category])
    }
    /// The posts behind one place, best first, as feed rows.
    public func mapPlacePosts(place: String, placeId: String) async throws -> [FeedRow] {
        try await rpcList("map_place_posts", ["p_place": place, "p_place_id": placeId])
    }
}
