import Foundation
import CoreLocation

/// A position and whether it comes from simulated location (a fake-location tool).
public struct Fix: Sendable {
    public var at: LatLng
    public var mocked: Bool
    public init(at: LatLng, mocked: Bool) { self.at = at; self.mocked = mocked }
}

/// Where the phone is: permission, a fresh fix with a timeout, and the continuous updates a driver on duty needs.
/// Foreground use needs "When In Use"; a driver who is online keeps updating in the background (UIBackgroundModes: location).
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    public var onFix: ((Fix) -> Void)?
    public var onAuthorizationChange: (() -> Void)?
    public private(set) var authorization: CLAuthorizationStatus
    private var waiting: [Int: CheckedContinuation<Fix?, Never>] = [:]
    private var nextWaiter = 0
    private var driverMode = false
    private var precise = false
    private var updating = false

    public override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
    }

    public var hasPermission: Bool {
        #if os(iOS)
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        #else
        authorization == .authorizedAlways
        #endif
    }
    public var denied: Bool { authorization == .denied || authorization == .restricted }
    public var notDetermined: Bool { authorization == .notDetermined }

    /// The phone's location switch (Settings > Privacy > Location Services).
    public func switchedOn() async -> Bool { await Task.detached { CLLocationManager.locationServicesEnabled() }.value }

    public func requestPermission() {
        guard notDetermined else { return }
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        #else
        manager.requestAlwaysAuthorization()
        #endif
    }

    /// Starts following the phone while the app is in use (pick-up, "near me" lists).
    public func startUpdates() {
        guard hasPermission, !updating else { return }
        updating = true; manager.startUpdatingLocation()
    }
    public func stopUpdates() { if !driverMode { manager.stopUpdatingLocation(); updating = false } }

    /// A driver on duty: best accuracy, keeps going with the screen off, and shows the system's location indicator.
    public func setDriverMode(_ on: Bool) {
        driverMode = on
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = on
        manager.pausesLocationUpdatesAutomatically = false
        #endif
        applyAccuracy()
        if on { if hasPermission { updating = true; manager.startUpdatingLocation() } } else if !updating { manager.stopUpdatingLocation() }
    }

    /// Turn-by-turn on the Maps screen: best accuracy and an update every few metres while it guides (Android asks for a fix every 2 s).
    public func setPrecise(_ on: Bool) {
        precise = on
        applyAccuracy()
        if on, hasPermission { updating = true; manager.startUpdatingLocation() }
    }

    private func applyAccuracy() {
        manager.desiredAccuracy = (precise || driverMode) ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = precise ? 3 : driverMode ? 15 : 25
    }

    /// A fix taken now; nil without permission, with location switched off, or when none arrives within `timeout` seconds.
    public func fresh(timeout: Double = 8) async -> Fix? {
        guard hasPermission, await switchedOn() else { return nil }
        let result: Fix? = await withCheckedContinuation { cont in
            nextWaiter += 1; let id = nextWaiter
            waiting[id] = cont
            manager.requestLocation()
            // Only this caller's own wait ends at its timeout; another caller that arrived later keeps waiting for its fix.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.waiting.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
        return result
    }
    private func resolveWaiting(_ fix: Fix?) {
        let w = waiting; waiting = [:]
        w.values.forEach { $0.resume(returning: fix) }
    }

    nonisolated private static func fix(of l: CLLocation) -> Fix {
        Fix(at: LatLng(l.coordinate.latitude, l.coordinate.longitude), mocked: l.sourceInformation?.isSimulatedBySoftware == true)
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let f = Self.fix(of: l)
        Task { @MainActor in self.onFix?(f); self.resolveWaiting(f) }
    }
    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let unknown = (error as? CLError)?.code == .locationUnknown
        // "Can't tell yet" while continuous updates run is not an answer: the next update (or the timeout) ends the wait.
        Task { @MainActor in if !(unknown && self.updating) { self.resolveWaiting(nil) } }
    }
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = s
            if self.hasPermission { self.startUpdates() }
            self.onAuthorizationChange?()
        }
    }
}
