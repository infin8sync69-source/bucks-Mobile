import Foundation

public struct LatLng: Hashable, Codable, Sendable {
    public var lat: Double
    public var lng: Double
    public init(_ lat: Double, _ lng: Double) { self.lat = lat; self.lng = lng }
    public init(lat: Double, lng: Double) { self.lat = lat; self.lng = lng }
}

/// Distances and the built-in place list (same data as Geo.kt on Android).
public enum Geo {
    /// Jayanagar, Bengaluru: only a default for maps before a real fix arrives. Never sent to the server as someone's position.
    public static let center = LatLng(12.9250, 77.5938)

    public static func distanceKm(_ a: LatLng, _ b: LatLng) -> Double {
        let r = 6371.0
        let dLat = (b.lat - a.lat) * .pi / 180, dLng = (b.lng - a.lng) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(sqrt(h))
    }

    /// Frequently visited places, in the order Android lists them.
    public static let places: [(name: String, at: LatLng)] = [
        ("Koramangala, Bengaluru", LatLng(12.9352, 77.6245)), ("Nexus Mall, Koramangala", LatLng(12.9345, 77.6113)),
        ("Jayanagar 4th block", LatLng(12.9279, 77.5836)), ("MG Road", LatLng(12.9757, 77.6063)),
        ("Indiranagar 100 ft Rd", LatLng(12.9784, 77.6408)), ("Whitefield, ITPL", LatLng(12.9855, 77.7363)),
        ("Majestic bus stand", LatLng(12.9774, 77.5713)), ("Kempegowda airport", LatLng(13.1989, 77.7068)),
    ]
    public static func place(named name: String) -> LatLng? { places.first { $0.name == name }?.at }

    /// Short name of the known place nearest to `p`, e.g. "Koramangala".
    public static func nearestArea(_ p: LatLng) -> String {
        let n = places.min { distanceKm(p, $0.at) < distanceKm(p, $1.at) }?.name ?? ""
        return n.components(separatedBy: ",")[0].components(separatedBy: " 4th")[0].components(separatedBy: " 100")[0]
    }

    /// Straight-line km rounded to one decimal, the way the ring and the fare quote it.
    public static func round1(_ km: Double) -> Double { (km * 10).rounded() / 10 }
}
