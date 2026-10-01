import SwiftUI
import BucksCore

/// How the trip is made when handed to the maps app: d = car, l = motorcycle / scooter, w = walking.
let mapsTravelModes: [(mode: Character, label: String)] = [("d", "Drive"), ("l", "Two-wheeler"), ("w", "Walk")]

/// Directions to any place, opened in Apple Maps. Apple Maps has driving and walking, so two-wheelers use the driving route.
/// Used from the Maps screen, from a shop's profile and from an address in Contacts.
@MainActor func openDirections(to: LatLng, label: String = "", mode: Character = "d") {
    let flag = mode == "w" ? "w" : "d"
    var s = "http://maps.apple.com/?daddr=\(to.lat),\(to.lng)&dirflg=\(flag)"
    if !label.isEmpty, let q = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) { s += "&q=\(q)" }
    openSystemURL(s) { ok in if !ok { MapsFeedback.noMapsApp?() } }
}

/// Where "no maps app" is reported (the app's toast); set by the Maps screen while it is on screen, harmless otherwise.
@MainActor enum MapsFeedback { static var noMapsApp: (() -> Void)? }

/// A place chosen elsewhere (the app's search bar) for the Maps screen to open on; taken once.
@MainActor enum MapsPick { static var place: MapServices.PlaceHit? }

/// "350 m" / "2.4 km".
func mapsDistance(_ meters: Double) -> String { meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000) }

/// A search that re-runs when the text or the retry counter changes (and only while no place is chosen).
struct MapsSearchKey: Hashable { var q: String; var retry: Int; var chosen: Bool }
