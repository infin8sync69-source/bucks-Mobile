import Foundation

/// Place search, address lookup and road routes for the live map (same providers, order and fall-backs as MapServices.kt):
///  - Mapbox (when a token is built in, `MapServices.token`): forward geocoding v6 for search, Directions v5 for routes with turn-by-turn steps.
///  - Photon (photon.komoot.io): search as you type when Mapbox is unavailable, and "what's at this point".
///  - Nominatim: the fall-back search when Photon can't be reached.
///  - OSRM (router.project-osrm.org, routing.openstreetmap.de for bike and foot): routes without Mapbox.
/// Every call fails soft (nil / empty), so the app falls back to straight lines and the built-in place list.
public enum MapServices {
    public struct PlaceHit: Hashable, Sendable {
        public var name: String; public var detail: String; public var at: LatLng
        public init(name: String, detail: String, at: LatLng) { self.name = name; self.detail = detail; self.at = at }
    }
    /// One instruction of a route: what to do, how long the step is, where the maneuver happens, and its type and modifier (for the arrow).
    public struct Step: Hashable, Sendable { public var text: String; public var metres: Double; public var at: LatLng; public var type: String; public var modifier: String }
    public struct RoadRoute: Hashable, Sendable {
        public var km: Double; public var minutes: Int; public var points: [LatLng]; public var steps: [Step] = []
    }

    /// Mapbox public token (pk.*, made to ship inside apps), set at launch from Info.plist (MapboxToken). Empty: OpenStreetMap servers only.
    nonisolated(unsafe) public static var token = ""

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
    private static func mapboxHit(_ f: [String: Any]) -> PlaceHit? {
        guard let c = (f["geometry"] as? [String: Any])?["coordinates"] as? [Double], c.count >= 2, let p = f["properties"] as? [String: Any],
              let name = str(p, "name") else { return nil }
        return PlaceHit(name: name, detail: str(p, "place_formatted") ?? "", at: LatLng(c[1], c[0]))
    }
    private static func deduped(_ hits: [PlaceHit]) -> [PlaceHit] { var seen = Set<String>(); return hits.filter { seen.insert($0.name + $0.detail).inserted } }

    public static func searchOrNull(_ query: String, near: LatLng) async -> [PlaceHit]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }
        if !token.isEmpty {
            let m = await get("https://api.mapbox.com/search/geocode/v6/forward?q=\(enc(q))&proximity=\(near.lng),\(near.lat)&limit=8&language=en&access_token=\(token)") as? [String: Any]
            let hits = (m?["features"] as? [[String: Any]])?.compactMap(mapboxHit) ?? []
            if !hits.isEmpty { return deduped(hits) }   // Mapbox already ranks by relevance and proximity
        }
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

    /// Road route for `profile` (driving, driving-traffic, cycling, walking) with its turn-by-turn steps; nil when offline or no route
    /// (the caller draws a straight line instead).
    public static func route(from: LatLng, to: LatLng, profile: String = "driving") async -> RoadRoute? {
        let xy = "\(from.lng),\(from.lat);\(to.lng),\(to.lat)"
        if !token.isEmpty, let r = parseRoute(await get("https://api.mapbox.com/directions/v5/mapbox/\(profile)/\(xy)?overview=full&geometries=geojson&steps=true&language=en&access_token=\(token)") as? [String: Any], from: from, to: to) {
            return r
        }
        let host = profile.hasPrefix("cycling") ? "https://routing.openstreetmap.de/routed-bike" : profile.hasPrefix("walking") ? "https://routing.openstreetmap.de/routed-foot" : "https://router.project-osrm.org"
        return parseRoute(await get("\(host)/route/v1/driving/\(xy)?overview=full&geometries=geojson&steps=true") as? [String: Any], from: from, to: to)
    }

    /// The instruction when the server gives none (OSRM): same wording as Android.
    static func words(type: String, modifier mod: String, name: String) -> String {
        let onto = name.isEmpty ? "" : " onto \(name)"
        switch type {
        case "depart": return name.isEmpty ? "Start" : "Head out on \(name)"
        case "arrive": return "You have arrived"
        case "roundabout", "rotary", "roundabout turn": return "Take the roundabout\(onto)"
        case "merge": return "Merge\(onto)"
        case "fork": return "Keep \(mod.isEmpty ? "straight" : mod) at the fork\(onto)"
        case "end of road": return "At the end of the road, turn \(mod.isEmpty ? "ahead" : mod)\(onto)"
        case "on ramp", "off ramp": return "Take the ramp\(onto)"
        case "new name", "continue": return mod == "uturn" ? "Make a U-turn" : "Continue\(onto)"
        default: return mod == "uturn" ? "Make a U-turn" : (mod.isEmpty || mod == "straight") ? "Continue straight\(onto)" : "Turn \(mod)\(onto)"
        }
    }

    /// Mapbox and OSRM answer alike: routes[0] with distance (m), duration (s), a GeoJSON line and legs[].steps[] (maneuver with type,
    /// modifier, location, and Mapbox's own instruction text).
    static func parseRoute(_ o: [String: Any]?, from: LatLng, to: LatLng) -> RoadRoute? {
        guard let r = (o?["routes"] as? [[String: Any]])?.first, let metres = r["distance"] as? Double, let seconds = r["duration"] as? Double else { return nil }
        let pts: [LatLng] = ((r["geometry"] as? [String: Any])?["coordinates"] as? [[Double]] ?? []).compactMap { $0.count >= 2 ? LatLng($0[1], $0[0]) : nil }
        let steps: [Step] = ((r["legs"] as? [[String: Any]]) ?? []).flatMap { ($0["steps"] as? [[String: Any]]) ?? [] }.compactMap { so in
            guard let mv = so["maneuver"] as? [String: Any], let loc = mv["location"] as? [Double], loc.count >= 2 else { return nil }
            let type = str(mv, "type") ?? "", mod = str(mv, "modifier") ?? ""
            return Step(text: str(mv, "instruction") ?? words(type: type, modifier: mod, name: str(so, "name") ?? ""), metres: so["distance"] as? Double ?? 0,
                        at: LatLng(loc[1], loc[0]), type: type, modifier: mod)
        }
        return RoadRoute(km: (metres / 100).rounded() / 10, minutes: max(1, Int((seconds / 60).rounded())), points: pts.isEmpty ? [from, to] : pts, steps: steps)
    }
}
