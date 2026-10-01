import Foundation

/// Place search, address lookup and road routes for the live map, all on OpenStreetMap data and free of keys (same servers and
/// fall-backs as MapServices.kt):
///  - Photon (photon.komoot.io): search as you type, biased to where the person is, and "what's at this point".
///  - Nominatim: the fall-back search when Photon can't be reached.
///  - OSRM (router.project-osrm.org): road distance, travel time and the route line between two points.
/// Every call fails soft (nil / empty), so the app falls back to straight lines and the built-in place list.
public enum MapServices {
    public struct PlaceHit: Hashable, Sendable { public var name: String; public var detail: String; public var at: LatLng }
    public struct RoadRoute: Hashable, Sendable { public var km: Double; public var minutes: Int; public var points: [LatLng] }

    private static let userAgent = "Bucks-iOS/1.0 (com.bucks.app)"
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 10; c.timeoutIntervalForResource = 15
        return URLSession(configuration: c)
    }()

    private static func get(_ url: String) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent"); req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? s }
    private static func str(_ o: [String: Any], _ k: String) -> String? { (o[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }

    private static func hit(of f: [String: Any]) -> PlaceHit? {
        guard let c = (f["geometry"] as? [String: Any])?["coordinates"] as? [Double], c.count >= 2, let p = f["properties"] as? [String: Any] else { return nil }
        let street = [str(p, "housenumber"), str(p, "street")].compactMap { $0 }.joined(separator: " ")
        let streetOrNil = street.isEmpty ? nil : street
        guard let name = str(p, "name") ?? streetOrNil ?? str(p, "district") ?? str(p, "city") else { return nil }
        var seen = Set<String>()
        let detail = [streetOrNil.flatMap { $0 != name ? $0 : nil }, str(p, "locality") ?? str(p, "district"), str(p, "city"), str(p, "state")]
            .compactMap { $0 }.filter { $0 != name && seen.insert($0).inserted }.joined(separator: ", ")
        return PlaceHit(name: name, detail: detail, at: LatLng(c[1], c[0]))
    }

    /// Nominatim (OpenStreetMap's own search) result row, used when Photon can't be reached.
    private static func nominatimHit(_ o: [String: Any]) -> PlaceHit? {
        guard let lat = str(o, "lat").flatMap(Double.init), let lon = str(o, "lon").flatMap(Double.init), let full = str(o, "display_name") else { return nil }
        let name = str(o, "name") ?? full.components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
        let rest = full.components(separatedBy: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(3).joined(separator: ", ")
        return PlaceHit(name: name, detail: rest, at: LatLng(lat, lon))
    }

    private static func dedupedNearestFirst(_ hits: [PlaceHit], near: LatLng) -> [PlaceHit] {
        var seen = Set<String>()
        return hits.filter { seen.insert($0.name + $0.detail).inserted }.sorted { Geo.distanceKm(near, $0.at) < Geo.distanceKm(near, $1.at) }
    }

    /// Places matching `query`, nearest to `near` first. Nil when no search server could be reached (so "offline" isn't shown as "no places").
    public static func searchOrNull(_ query: String, near: LatLng) async -> [PlaceHit]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }
        let photon = await get("https://photon.komoot.io/api/?q=\(enc(q))&lat=\(near.lat)&lon=\(near.lng)&limit=8&lang=en") as? [String: Any]
        let a = (photon?["features"] as? [[String: Any]])?.compactMap(hit(of:))
        if let a, !a.isEmpty { return dedupedNearestFirst(a, near: near) }
        let nom = await get("https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=\(enc(q))") as? [[String: Any]]
        if let b = nom?.compactMap(nominatimHit) { return dedupedNearestFirst(b, near: near) }
        return a != nil ? [] : nil
    }
    /// Places matching `query`, nearest first; empty when offline.
    public static func search(_ query: String, near: LatLng) async -> [PlaceHit] { await searchOrNull(query, near: near) ?? [] }

    /// A short name for the point: "12th Main, Indiranagar" or a landmark; nil when offline.
    public static func label(at: LatLng) async -> String? {
        guard let o = await get("https://photon.komoot.io/reverse?lat=\(at.lat)&lon=\(at.lng)&limit=1&lang=en") as? [String: Any],
              let f = (o["features"] as? [[String: Any]])?.first, let h = hit(of: f) else { return nil }
        let area = h.detail.components(separatedBy: ", ").first { !$0.isEmpty }
        return [h.name, area.flatMap { $0 != h.name ? $0 : nil }].compactMap { $0 }.joined(separator: ", ")
    }

    /// Driving route by road; nil when offline or no route (the caller draws a straight line instead).
    public static func route(from: LatLng, to: LatLng) async -> RoadRoute? {
        guard let o = await get("https://router.project-osrm.org/route/v1/driving/\(from.lng),\(from.lat);\(to.lng),\(to.lat)?overview=full&geometries=geojson") as? [String: Any],
              let r = (o["routes"] as? [[String: Any]])?.first, let metres = r["distance"] as? Double, let seconds = r["duration"] as? Double else { return nil }
        let pts: [LatLng] = ((r["geometry"] as? [String: Any])?["coordinates"] as? [[Double]] ?? []).compactMap { $0.count >= 2 ? LatLng($0[1], $0[0]) : nil }
        return RoadRoute(km: (metres / 100).rounded() / 10, minutes: max(1, Int((seconds / 60).rounded())), points: pts.isEmpty ? [from, to] : pts)
    }
}
