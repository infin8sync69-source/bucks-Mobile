import SwiftUI
import MapKit
import BucksCore

public struct MapPin: Identifiable {
    public let id: String
    public var at: LatLng
    public var title: String
    public var tint: Color
    public var isMe: Bool
    public init(id: String, at: LatLng, title: String = "", tint: Color = BucksColor.primary, isMe: Bool = false) {
        self.id = id; self.at = at; self.title = title; self.tint = tint; self.isMe = isMe
    }
}

extension LatLng {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// MapKit map with pins, an optional route line and radius circle.
/// - Normal mode: the camera fits all pins and the route whenever that set changes meaningfully (about 100 m), and tracks `followPin`.
/// - Pick mode (`onCenterChange` set): the user owns the camera. It centres once on the first pin, then only reports where the map centre is.
public struct BucksMap: View {
    var pins: [MapPin]
    var route: [LatLng]
    var circle: (center: LatLng, meters: Double)?
    var zoomMeters: Double
    var followPin: String?
    var onCenterChange: ((LatLng) -> Void)?

    public init(pins: [MapPin], route: [LatLng] = [], circle: (center: LatLng, meters: Double)? = nil, zoomMeters: Double = 3000, followPin: String? = nil, onCenterChange: ((LatLng) -> Void)? = nil) {
        self.pins = pins; self.route = route; self.circle = circle; self.zoomMeters = zoomMeters; self.followPin = followPin; self.onCenterChange = onCenterChange
    }

    @State private var position: MapCameraPosition = .automatic
    @State private var lastFit = ""
    @State private var centred = false
    @State private var spanMeters: Double?
    @State private var lastFollow: LatLng?

    public var body: some View {
        Map(position: $position) {
            if let circle {
                MapCircle(center: circle.center.coordinate, radius: circle.meters)
                    .foregroundStyle(BucksColor.purple.opacity(0.07)).stroke(BucksColor.purple.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            }
            if route.count > 1 {
                MapPolyline(coordinates: route.map(\.coordinate)).stroke(BucksColor.purple, lineWidth: 5)
            }
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.at.coordinate, anchor: .center) { PinView(pin: pin) }
            }
        }
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            let r = ctx.region
            spanMeters = r.span.latitudeDelta * 111_000
            onCenterChange?(LatLng(r.center.latitude, r.center.longitude))
        }
        .onAppear { sync() }
        .onChange(of: fitKey) { _, _ in sync() }
        .onChange(of: followedAt) { _, new in follow(new) }
    }

    // Pins + route rounded to ~110 m, so GPS jitter does not re-fit the camera.
    private var fitKey: String {
        func r(_ v: Double) -> Int { Int((v * 1000).rounded()) }
        let pts = pins.map(\.at) + route
        guard !pts.isEmpty else { return "" }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        return "\(r(lats.min()!)),\(r(lats.max()!)),\(r(lngs.min()!)),\(r(lngs.max()!)),\(pins.count)"
    }
    private var followedAt: LatLng? { followPin.flatMap { id in pins.first { $0.id == id }?.at } }

    private func sync() {
        let key = fitKey
        guard !key.isEmpty, key != lastFit else { return }
        if onCenterChange != nil {
            guard !centred, let first = pins.first else { return }
            centred = true; lastFit = key
            position = .region(MKCoordinateRegion(center: first.at.coordinate, latitudinalMeters: zoomMeters, longitudinalMeters: zoomMeters))
            return
        }
        lastFit = key
        position = .region(fitRegion())
    }

    private func follow(_ at: LatLng?) {
        guard onCenterChange == nil, let at else { return }
        // Moving pins already trigger a re-fit; follow only recentres when the pin leaves the middle third of the view.
        if let last = lastFollow, Geo.distanceKm(last, at) < 0.03 { return }
        lastFollow = at
        let m = spanMeters ?? zoomMeters
        position = .region(MKCoordinateRegion(center: at.coordinate, latitudinalMeters: m, longitudinalMeters: m))
    }

    private func fitRegion() -> MKCoordinateRegion {
        var pts = pins.map(\.at) + route
        if let circle { pts.append(circle.center) }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let spanLat = (maxLat - minLat) * 1.5, spanLng = (maxLng - minLng) * 1.5
        let minSpan = zoomMeters / 111_000 * (pts.count > 1 ? 0.25 : 1)
        if spanLat < 0.0005 && spanLng < 0.0005 {
            return MKCoordinateRegion(center: center, latitudinalMeters: zoomMeters, longitudinalMeters: zoomMeters)
        }
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: max(spanLat, minSpan), longitudeDelta: max(spanLng, minSpan)))
    }
}

private struct PinView: View {
    let pin: MapPin
    @State private var pulse = false
    var body: some View {
        ZStack {
            if pin.isMe {
                Circle().fill(pin.tint.opacity(0.2)).frame(width: 40, height: 40).scaleEffect(pulse ? 1.25 : 0.8)
                    .onAppear { if !bucksReduceMotion { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } } }
            } else { Circle().fill(pin.tint.opacity(0.18)).frame(width: 34, height: 34) }
            Circle().fill(.white).frame(width: pin.isMe ? 22 : 20, height: pin.isMe ? 22 : 20)
            Circle().fill(pin.tint).frame(width: pin.isMe ? 16 : 13, height: pin.isMe ? 16 : 13)
        }.accessibilityLabel(pin.title)
    }
}
