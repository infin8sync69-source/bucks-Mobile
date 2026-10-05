import SwiftUI
import MapKit
import CoreImage
import BucksCore
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
public typealias MapViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
public typealias MapViewRepresentable = NSViewRepresentable
#endif

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

/// Lets a screen move and zoom the map it shows (my-location button, zoom buttons, following a moving position). Zoom levels are the
/// web-map ones Android uses (16 = a few streets).
@MainActor public final class MapCommands {
    weak var coordinator: BucksMapCoordinator?
    public init() {}
    public func zoomIn() { coordinator?.zoom(by: 0.5) }
    public func zoomOut() { coordinator?.zoom(by: 2) }
    public func moveTo(_ at: LatLng, zoom: Double? = nil) { coordinator?.move(to: at, zoom: zoom) }
}

/// Real street map, drawn from the same tiles as Android: Mapbox Streets (or Satellite with streets) when a token is built in, else
/// OpenStreetMap's own; the street map is desaturated and lifted towards the design's muted grey, and inverted in dark mode.
/// - Normal mode: the camera fits all pins and the route whenever that set changes meaningfully (about 100 m), and tracks `followPin`.
/// - Pick mode (`onCenterChange` set): the user owns the camera. It centres once on the first pin, then only reports where the map centre is.
/// `commands` moves and zooms it from outside, `onLongPress` drops a point, `onUserMove` fires when the person drags the map.
public struct BucksMap: MapViewRepresentable {
    var pins: [MapPin]
    var route: [LatLng]
    var circle: (center: LatLng, meters: Double)?
    var zoomMeters: Double
    var followPin: String?
    var onCenterChange: ((LatLng) -> Void)?
    var commands: MapCommands?
    var satellite: Bool
    var onLongPress: ((LatLng) -> Void)?
    var onUserMove: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    public init(pins: [MapPin], route: [LatLng] = [], circle: (center: LatLng, meters: Double)? = nil, zoomMeters: Double = 3000, followPin: String? = nil,
                onCenterChange: ((LatLng) -> Void)? = nil, commands: MapCommands? = nil, satellite: Bool = false,
                onLongPress: ((LatLng) -> Void)? = nil, onUserMove: (() -> Void)? = nil) {
        self.pins = pins; self.route = route; self.circle = circle; self.zoomMeters = zoomMeters; self.followPin = followPin; self.onCenterChange = onCenterChange
        self.commands = commands; self.satellite = satellite; self.onLongPress = onLongPress; self.onUserMove = onUserMove
    }

    public func makeCoordinator() -> BucksMapCoordinator { BucksMapCoordinator() }

    private func make(_ context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        #if canImport(UIKit)
        map.showsScale = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(BucksMapCoordinator.longPressed(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
        #else
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        let press = NSPressGestureRecognizer(target: context.coordinator, action: #selector(BucksMapCoordinator.longPressed(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
        #endif
        let start = pins.first?.at ?? Geo.center
        context.coordinator.attach(map)
        context.coordinator.setRegion(MKCoordinateRegion(center: start.coordinate, latitudinalMeters: zoomMeters, longitudinalMeters: zoomMeters), animated: false)
        return map
    }

    private func update(_ map: MKMapView, _ context: Context) {
        let c = context.coordinator
        c.parent = self
        commands?.coordinator = c
        c.apply(dark: scheme == .dark)
    }

    #if canImport(UIKit)
    public func makeUIView(context: Context) -> MKMapView { make(context) }
    public func updateUIView(_ map: MKMapView, context: Context) { update(map, context) }
    #else
    public func makeNSView(context: Context) -> MKMapView { make(context) }
    public func updateNSView(_ map: MKMapView, context: Context) { update(map, context) }
    #endif
}

/// Map attribution the tile providers require.
public struct MapAttribution: View {
    public init() {}
    public var body: some View {
        Text(MapServices.token.isEmpty ? "© OpenStreetMap contributors" : "© Mapbox © OpenStreetMap")
            .font(.system(size: 9)).foregroundStyle(BucksColor.onSurfaceVariant)
    }
}

// MARK: - Coordinator

@MainActor public final class BucksMapCoordinator: NSObject, MKMapViewDelegate {
    var parent: BucksMap?
    private weak var map: MKMapView?
    private var annotations: [String: PinAnnotation] = [:]
    private var tiles: BucksTiles?
    private var tileKey = ""
    private var routeLine: MKPolyline?
    private var routeKey = ""
    private var ring: MKCircle?
    private var ringKey = ""
    private var lastFit = ""
    private var centred = false
    private var lastFollow: LatLng?
    /// Until when a region change is ours (a fit, a follow, a command), not the person's drag.
    private var ownChangeUntil = Date.distantPast

    func attach(_ map: MKMapView) { self.map = map }

    func apply(dark: Bool) {
        guard let map, let p = parent else { return }
        // Tiles: replaced when the style changes (street / satellite, light / dark).
        let key = "\(p.satellite && !MapServices.token.isEmpty)-\(dark)-\(MapServices.token.isEmpty)"
        if key != tileKey {
            tileKey = key
            if let t = tiles { map.removeOverlay(t) }
            let t = BucksTiles(satellite: p.satellite && !MapServices.token.isEmpty, dark: dark)
            map.insertOverlay(t, at: 0, level: .aboveLabels)
            tiles = t
        }
        syncPins(map, p.pins)
        syncRoute(map, p.route)
        syncCircle(map, p.circle)
        syncCamera(map, p)
    }

    // MARK: pins

    private func syncPins(_ map: MKMapView, _ pins: [MapPin]) {
        let ids = Set(pins.map(\.id))
        for (id, a) in annotations where !ids.contains(id) { map.removeAnnotation(a); annotations[id] = nil }
        for pin in pins {
            if let a = annotations[pin.id] {
                if a.coordinate.latitude != pin.at.lat || a.coordinate.longitude != pin.at.lng { a.coordinate = pin.at.coordinate }
                if a.title != pin.title || a.isMe != pin.isMe || a.tint != pin.tint {
                    a.title = pin.title; a.isMe = pin.isMe; a.tint = pin.tint
                    (map.view(for: a) as? PinAnnotationView)?.refresh()
                }
            } else {
                let a = PinAnnotation(pin); annotations[pin.id] = a; map.addAnnotation(a)
            }
        }
    }

    // MARK: overlays

    private func syncRoute(_ map: MKMapView, _ route: [LatLng]) {
        let key = route.count > 1 ? "\(route.count)|\(route.first!.lat),\(route.first!.lng)|\(route.last!.lat),\(route.last!.lng)" : ""
        guard key != routeKey else { return }
        routeKey = key
        if let r = routeLine { map.removeOverlay(r); routeLine = nil }
        guard route.count > 1 else { return }
        var coords = route.map(\.coordinate)
        let line = MKPolyline(coordinates: &coords, count: coords.count)
        map.addOverlay(line, level: .aboveLabels); routeLine = line
    }

    private func syncCircle(_ map: MKMapView, _ circle: (center: LatLng, meters: Double)?) {
        let key = circle.map { "\($0.center.lat),\($0.center.lng),\($0.meters)" } ?? ""
        guard key != ringKey else { return }
        ringKey = key
        if let c = ring { map.removeOverlay(c); ring = nil }
        guard let circle else { return }
        let c = MKCircle(center: circle.center.coordinate, radius: circle.meters)
        map.addOverlay(c, level: .aboveLabels); ring = c
    }

    // MapKit calls its delegate on the main thread; nonisolated + assumeIsolated works whether or not the SDK marks the protocol @MainActor.
    nonisolated public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        MainActor.assumeIsolated { MainBox(renderer(for: overlay)) }.value
    }
    private func renderer(for overlay: MKOverlay) -> MKOverlayRenderer {
        if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
        let brand = PlatformColor(BucksColor.purple)
        if let l = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: l); r.strokeColor = brand; r.lineWidth = 5; r.lineCap = .round; r.lineJoin = .round; return r
        }
        if let c = overlay as? MKCircle {
            let r = MKCircleRenderer(circle: c); r.fillColor = brand.withAlphaComponent(0.2); r.strokeColor = brand.withAlphaComponent(0.4); r.lineWidth = 2; return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    nonisolated public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        MainActor.assumeIsolated { MainBox(annotationView(mapView, annotation)) }.value
    }
    private func annotationView(_ mapView: MKMapView, _ annotation: MKAnnotation) -> MKAnnotationView? {
        guard let a = annotation as? PinAnnotation else { return nil }
        let v = (mapView.dequeueReusableAnnotationView(withIdentifier: PinAnnotationView.reuse) as? PinAnnotationView) ?? PinAnnotationView(annotation: a, reuseIdentifier: PinAnnotationView.reuse)
        v.annotation = a; v.refresh()
        return v
    }

    // MARK: camera

    func setRegion(_ r: MKCoordinateRegion, animated: Bool) {
        guard let map else { return }
        ownChangeUntil = Date().addingTimeInterval(animated ? 1.0 : 0.3)
        map.setRegion(r, animated: animated)
    }

    func zoom(by factor: Double) {
        guard let map else { return }
        var r = map.region
        r.span.latitudeDelta = min(150, max(0.0005, r.span.latitudeDelta * factor))
        r.span.longitudeDelta = min(300, max(0.0005, r.span.longitudeDelta * factor))
        setRegion(r, animated: true)
    }

    func move(to at: LatLng, zoom: Double?) {
        guard let map else { return }
        if let zoom {
            // A web-map zoom level shows 256 * 2^z points around the world: this many degrees across the map's width.
            let w = max(Double(map.bounds.width), 320), h = max(Double(map.bounds.height), 320)
            let lngSpan = w * 360 / (256 * pow(2, zoom))
            let latSpan = lngSpan * h / w * cos(at.lat * .pi / 180)
            setRegion(MKCoordinateRegion(center: at.coordinate, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lngSpan)), animated: true)
        } else {
            setRegion(MKCoordinateRegion(center: at.coordinate, span: map.region.span), animated: true)
        }
    }

    private func syncCamera(_ map: MKMapView, _ p: BucksMap) {
        let key = p.commands == nil ? fitKey(p) : targetKey(p)
        if !key.isEmpty, key != lastFit {
            if p.onCenterChange != nil {
                // Pick mode: centre once, then the person owns the camera.
                if !centred, let first = p.pins.first {
                    centred = true; lastFit = key
                    setRegion(MKCoordinateRegion(center: first.at.coordinate, latitudinalMeters: p.zoomMeters, longitudinalMeters: p.zoomMeters), animated: false)
                }
            } else {
                let first = lastFit.isEmpty
                lastFit = key
                setRegion(fitRegion(p), animated: !first)
            }
        }
        follow(map, p)
    }

    /// A screen that also moves the camera itself (commands, e.g. Maps while navigating) is framed again only when where it is heading
    /// changes: the route's end or the other pins, not my own dot moving along (Android frames the trip when its target changes).
    private func targetKey(_ p: BucksMap) -> String {
        func r(_ v: Double) -> Int { Int((v * 1000).rounded()) }
        if p.route.count > 1, let t = p.route.last { return "route \(r(t.lat)),\(r(t.lng))" }
        let others = p.pins.filter { !$0.isMe }.map(\.at)
        let pts = others.isEmpty ? p.pins.map(\.at) : others
        return pts.map { "\(r($0.lat)),\(r($0.lng))" }.joined(separator: ";")
    }

    private func follow(_ map: MKMapView, _ p: BucksMap) {
        guard p.onCenterChange == nil, let id = p.followPin, let at = p.pins.first(where: { $0.id == id })?.at else { return }
        // Moving pins already trigger a re-fit; follow only recentres after the pin has moved ~30 m.
        if let last = lastFollow, Geo.distanceKm(last, at) < 0.03 { return }
        lastFollow = at
        setRegion(MKCoordinateRegion(center: at.coordinate, span: map.region.span), animated: true)
    }

    // Pins + route rounded to ~110 m, so GPS jitter does not re-fit the camera.
    private func fitKey(_ p: BucksMap) -> String {
        func r(_ v: Double) -> Int { Int((v * 1000).rounded()) }
        let pts = p.pins.map(\.at) + p.route
        guard !pts.isEmpty else { return "" }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        return "\(r(lats.min()!)),\(r(lats.max()!)),\(r(lngs.min()!)),\(r(lngs.max()!)),\(p.pins.count)"
    }

    private func fitRegion(_ p: BucksMap) -> MKCoordinateRegion {
        var pts = p.pins.map(\.at) + p.route
        if let circle = p.circle { pts.append(circle.center) }
        let lats = pts.map(\.lat), lngs = pts.map(\.lng)
        let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        if let circle = p.circle, pts.count <= 2 {
            let m = max(p.zoomMeters, circle.meters * 2.4)
            return MKCoordinateRegion(center: circle.center.coordinate, latitudinalMeters: m, longitudinalMeters: m)
        }
        let spanLat = (maxLat - minLat) * 1.5, spanLng = (maxLng - minLng) * 1.5
        let minSpan = p.zoomMeters / 111_000 * (pts.count > 1 ? 0.25 : 1)
        if spanLat < 0.0005 && spanLng < 0.0005 {
            return MKCoordinateRegion(center: center, latitudinalMeters: p.zoomMeters, longitudinalMeters: p.zoomMeters)
        }
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: max(spanLat, minSpan), longitudeDelta: max(spanLng, minSpan)))
    }

    // MARK: the person moving the map

    private func userIsTouching(_ mapView: MKMapView) -> Bool {
        #if canImport(UIKit)
        let recognizers = (mapView.subviews.first?.gestureRecognizers ?? []) + (mapView.gestureRecognizers ?? [])
        if recognizers.contains(where: { $0.state == .began || $0.state == .changed }) { return true }
        #endif
        return Date() > ownChangeUntil
    }

    nonisolated public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            guard userIsTouching(mapView), let cb = parent?.onUserMove else { return }
            DispatchQueue.main.async { cb() }
        }
    }

    nonisolated public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            guard let cb = parent?.onCenterChange else { return }
            let c = mapView.region.center
            DispatchQueue.main.async { cb(LatLng(c.latitude, c.longitude)) }
        }
    }

    #if canImport(UIKit)
    @objc func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let map, let cb = parent?.onLongPress else { return }
        let c = map.convert(g.location(in: map), toCoordinateFrom: map)
        cb(LatLng(c.latitude, c.longitude))
    }
    #else
    @objc func longPressed(_ g: NSPressGestureRecognizer) {
        guard g.state == .began, let map, let cb = parent?.onLongPress else { return }
        let c = map.convert(g.location(in: map), toCoordinateFrom: map)
        cb(LatLng(c.latitude, c.longitude))
    }
    #endif
}

/// Carries a main-thread object out of MainActor.assumeIsolated (which wants a Sendable result); it never leaves the main thread.
private struct MainBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Pins

final class PinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var isMe: Bool
    var tint: Color
    init(_ pin: MapPin) { coordinate = pin.at.coordinate; title = pin.title; isMe = pin.isMe; tint = pin.tint }
}

/// A filled dot with a white ring, larger for "me" (the markers Android draws).
final class PinAnnotationView: MKAnnotationView {
    static let reuse = "bucks-pin"
    func refresh() {
        guard let a = annotation as? PinAnnotation else { return }
        let size: CGFloat = a.isMe ? 18 : 12, ring: CGFloat = 2.5
        let full = size + ring * 2
        #if canImport(UIKit)
        image = UIGraphicsImageRenderer(size: CGSize(width: full, height: full)).image { ctx in
            UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: full, height: full))
            UIColor(a.tint).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: ring, y: ring, width: size, height: size))
        }
        #else
        image = NSImage(size: NSSize(width: full, height: full), flipped: false) { _ in
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: full, height: full)).fill()
            NSColor(a.tint).setFill(); NSBezierPath(ovalIn: NSRect(x: ring, y: ring, width: size, height: size)).fill()
            return true
        }
        #endif
        centerOffset = .zero
        displayPriority = a.isMe ? .required : .defaultHigh
        zPriority = a.isMe ? .max : .defaultUnselected
        canShowCallout = false
        #if canImport(UIKit)
        isAccessibilityElement = true; accessibilityLabel = a.title
        #else
        setAccessibilityLabel(a.title)
        #endif
    }
}

// MARK: - Tiles

/// The street tiles Android shows: Mapbox Streets / Satellite Streets (512 px "@2x" tiles for 256-point cells) with a token, else
/// OpenStreetMap. Street tiles are muted like Android's colour filter: saturation 0.15, then lifted (light) or inverted (dark).
final class BucksTiles: MKTileOverlay {
    private let muted: Bool
    private let dark: Bool
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 150 << 20, directory: nil)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()
    private static let ci = CIContext(options: [.cacheIntermediates: false])

    init(satellite: Bool, dark: Bool) {
        muted = !satellite; self.dark = dark
        let token = MapServices.token
        let template: String
        if token.isEmpty {
            template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        } else {
            template = "https://api.mapbox.com/styles/v1/mapbox/\(satellite ? "satellite-streets-v12" : "streets-v12")/tiles/256/{z}/{x}/{y}@2x?access_token=\(token)"
        }
        super.init(urlTemplate: template)
        canReplaceMapContent = true
        minimumZ = 2
        maximumZ = token.isEmpty ? 19 : 22
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        var req = URLRequest(url: url(forTilePath: path))
        req.setValue("Bucks-iOS/1.0 (com.bucks.app)", forHTTPHeaderField: "User-Agent")   // OpenStreetMap's tile policy asks for one
        let muted = self.muted, dark = self.dark
        Self.session.dataTask(with: req) { data, resp, err in
            guard let data, (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { result(nil, err); return }
            result(muted ? (Self.mute(data, dark: dark) ?? data) : data, nil)
        }.resume()
    }

    /// Android's mutedTiles(): ColorMatrix saturation 0.15, then 0.9x + 22 (light) or -0.85x + 235 (dark, blue 240).
    private static func mute(_ data: Data, dark: Bool) -> Data? {
        guard let img = CIImage(data: data), let sat = CIFilter(name: "CIColorControls"), let tone = CIFilter(name: "CIColorMatrix") else { return nil }
        sat.setValue(img, forKey: kCIInputImageKey); sat.setValue(0.15, forKey: kCIInputSaturationKey)
        tone.setValue(sat.outputImage, forKey: kCIInputImageKey)
        let k: CGFloat = dark ? -0.85 : 0.9
        tone.setValue(CIVector(x: k, y: 0, z: 0, w: 0), forKey: "inputRVector")
        tone.setValue(CIVector(x: 0, y: k, z: 0, w: 0), forKey: "inputGVector")
        tone.setValue(CIVector(x: 0, y: 0, z: k, w: 0), forKey: "inputBVector")
        tone.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        tone.setValue(dark ? CIVector(x: 235.0 / 255, y: 235.0 / 255, z: 240.0 / 255, w: 0) : CIVector(x: 22.0 / 255, y: 22.0 / 255, z: 26.0 / 255, w: 0), forKey: "inputBiasVector")
        guard let out = tone.outputImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return ci.pngRepresentation(of: out.cropped(to: img.extent), format: .RGBA8, colorSpace: space)
    }
}
