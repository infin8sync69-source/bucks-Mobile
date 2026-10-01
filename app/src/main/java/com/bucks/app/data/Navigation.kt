package com.bucks.app.data

/**
 * Where a moving position is along a route: how far along, how far off it, so the app can show the next turn, the distance left,
 * and notice a wrong turn. Pure maths, no Android, so it is easy to test.
 */
class RoutePath(val pts: List<LatLng>) {
    /** Metres from the start to each point. */
    val cum = DoubleArray(pts.size).also { for (i in 1 until pts.size) it[i] = it[i - 1] + metres(pts[i - 1], pts[i]) }
    val total get() = cum.lastOrNull() ?: 0.0

    /** [seg]: the segment (pts[seg]..pts[seg+1]) nearest the position; [along]: metres from the start; [off]: metres from the line. */
    data class Snap(val seg: Int, val along: Double, val off: Double)

    /** Nearest point on the route; looks a little behind and well ahead of [fromSeg] first (so a road that doubles back can't jump the position), then everywhere if that finds nothing close. */
    fun snap(p: LatLng, fromSeg: Int = 0): Snap {
        if (pts.size < 2) return Snap(0, 0.0, if (pts.isEmpty()) 0.0 else metres(pts[0], p))
        val last = pts.size - 2
        val near = scan(p, maxOf(0, fromSeg - 3), minOf(last, fromSeg + 250))
        return if (near.off <= 120.0) near else scan(p, 0, last)
    }

    private fun scan(p: LatLng, lo: Int, hi: Int): Snap {
        var best = Snap(lo, cum[lo], Double.MAX_VALUE)
        for (i in lo..hi) {
            // Flat-earth maths around the position: fine over the few hundred metres a segment spans.
            val k = Math.cos(Math.toRadians(p.lat))
            val ax = (pts[i].lng - p.lng) * k * 111_320.0; val ay = (pts[i].lat - p.lat) * 110_540.0
            val bx = (pts[i + 1].lng - p.lng) * k * 111_320.0; val by = (pts[i + 1].lat - p.lat) * 110_540.0
            val dx = bx - ax; val dy = by - ay; val len2 = dx * dx + dy * dy
            val t = if (len2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / len2).coerceIn(0.0, 1.0)
            val px = ax + t * dx; val py = ay + t * dy; val d = Math.sqrt(px * px + py * py)
            if (d < best.off) best = Snap(i, cum[i] + t * Math.sqrt(len2), d)
        }
        return best
    }

    companion object {
        fun metres(a: LatLng, b: LatLng) = Geo.distanceKm(a, b) * 1000.0
    }
}
