import Foundation

/// Where a moving position is along a route: how far along, how far off it, so the app can show the next turn, the distance left,
/// and notice a wrong turn. Pure maths (same as Navigation.kt), so it is easy to test.
public struct RoutePath: Sendable {
    public let pts: [LatLng]
    /// Metres from the start to each point.
    public let cum: [Double]
    public var total: Double { cum.last ?? 0 }

    public init(_ pts: [LatLng]) {
        self.pts = pts
        var c = [Double](repeating: 0, count: pts.count)
        if pts.count > 1 { for i in 1..<pts.count { c[i] = c[i - 1] + Self.metres(pts[i - 1], pts[i]) } }
        cum = c
    }

    /// `seg`: the segment (pts[seg]..pts[seg+1]) nearest the position; `along`: metres from the start; `off`: metres from the line.
    public struct Snap: Equatable, Sendable { public var seg: Int; public var along: Double; public var off: Double }

    /// Nearest point on the route; looks a little behind and well ahead of `fromSeg` first (so a road that doubles back can't jump the
    /// position), then everywhere if that finds nothing close.
    public func snap(_ p: LatLng, fromSeg: Int = 0) -> Snap {
        if pts.count < 2 { return Snap(seg: 0, along: 0, off: pts.isEmpty ? 0 : Self.metres(pts[0], p)) }
        let last = pts.count - 2
        let near = scan(p, max(0, fromSeg - 3), min(last, fromSeg + 250))
        return near.off <= 120 ? near : scan(p, 0, last)
    }

    private func scan(_ p: LatLng, _ lo: Int, _ hi: Int) -> Snap {
        var best = Snap(seg: lo, along: cum[lo], off: .greatestFiniteMagnitude)
        guard lo <= hi else { return best }
        // Flat-earth maths around the position: fine over the few hundred metres a segment spans.
        let k = cos(p.lat * .pi / 180)
        for i in lo...hi {
            let ax = (pts[i].lng - p.lng) * k * 111_320, ay = (pts[i].lat - p.lat) * 110_540
            let bx = (pts[i + 1].lng - p.lng) * k * 111_320, by = (pts[i + 1].lat - p.lat) * 110_540
            let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : min(1, max(0, -(ax * dx + ay * dy) / len2))
            let px = ax + t * dx, py = ay + t * dy, d = (px * px + py * py).squareRoot()
            if d < best.off { best = Snap(seg: i, along: cum[i] + t * len2.squareRoot(), off: d) }
        }
        return best
    }

    public static func metres(_ a: LatLng, _ b: LatLng) -> Double { Geo.distanceKm(a, b) * 1000 }
}
