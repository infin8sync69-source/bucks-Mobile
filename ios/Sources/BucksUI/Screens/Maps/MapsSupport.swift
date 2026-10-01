import SwiftUI
import BucksCore

/// Directions to any place, opened in Apple Maps ("Open in another maps app" on the Maps screen). Apple Maps has driving and walking,
/// so two-wheelers and cycles use the driving route.
@MainActor func openDirections(to: LatLng, label: String = "", mode: Character = "d") {
    let flag = mode == "w" ? "w" : "d"
    var s = "http://maps.apple.com/?daddr=\(to.lat),\(to.lng)&dirflg=\(flag)"
    if !label.isEmpty, let q = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) { s += "&q=\(q)" }
    openSystemURL(s) { ok in if !ok { MapsFeedback.noMapsApp?() } }
}

/// Where "no maps app" is reported (the app's toast); set by the Maps screen while it is on screen, harmless otherwise.
@MainActor enum MapsFeedback { static var noMapsApp: (() -> Void)? }

/// A place or search picked elsewhere (the app's search bars, a shop's Directions button, an address in Contacts) for the Maps screen to
/// open on; taken once. `autoStart` begins turn-by-turn as soon as the route is ready (the driver's Navigate button).
@MainActor enum MapsPick {
    static var place: MapServices.PlaceHit?
    static var query: String?
    static var autoStart = false
}

/// Opens the in-app map on a place (Android's openMapsTo).
@MainActor func openMapsTo(_ router: Router, name: String, detail: String = "", at: LatLng, autoStart: Bool = false) {
    MapsPick.place = MapServices.PlaceHit(name: name, detail: detail, at: at); MapsPick.autoStart = autoStart
    router.push(.maps)
}

/// "350 m" / "2.4 km".
func mapsDistance(_ meters: Double) -> String { meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000) }

/// A search that re-runs when the text or the retry counter changes (and only while no place is chosen).
struct MapsSearchKey: Hashable { var q: String; var retry: Int; var chosen: Bool }
