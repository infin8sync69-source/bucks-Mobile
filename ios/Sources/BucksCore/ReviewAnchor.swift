import Foundation

/// A fixed position for an App Store or Play reviewer's account (supabase/migrations/review_accounts.sql). Reviewers sign in from outside
/// India, where Bucks has nothing nearby. For a number the server lists, the app uses this position instead of the phone's GPS, so the
/// reviewer sees the demo shops, pros and drivers. Every other account gets no row and keeps its real position.
public struct ReviewAnchor: Codable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double
    public var label: String

    public init(lat: Double, lng: Double, label: String) { self.lat = lat; self.lng = lng; self.label = label }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        lat = try c.decode(Double.self, forKey: .lat); lng = try c.decode(Double.self, forKey: .lng)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
    }
    private enum K: String, CodingKey { case lat, lng, label }

    public var at: LatLng { LatLng(lat, lng) }
    /// Only a real point counts: a row with an impossible position is ignored rather than moving the reviewer into the sea at 0,0.
    public var valid: Bool { (-90...90).contains(lat) && (-180...180).contains(lng) && !(lat == 0 && lng == 0) }
}

extension Backend {
    /// The signed-in number's review position, or nil for everyone else (and on a database without the function).
    public func reviewAnchor() async throws -> ReviewAnchor? {
        (try await rpcList("review_anchor") as [ReviewAnchor]).first.flatMap { $0.valid ? $0 : nil }
    }
}
