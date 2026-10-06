import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "Pick-up in 4 min" / "under a minute"; nil when the rider's position isn't known yet (a negative estimate).
func etaText(_ min: Int) -> String? { min < 0 ? nil : (min == 0 ? "under a minute" : "\(min) min") }

/// Opens a URL with the system (phone, messages, UPI apps, Settings). Reports whether the system took it.
@MainActor func openSystemURL(_ s: String, completion: ((Bool) -> Void)? = nil) {
    guard let url = URL(string: s) else { completion?(false); return }
    #if canImport(UIKit)
    UIApplication.shared.open(url, options: [:]) { completion?($0) }
    #elseif canImport(AppKit)
    completion?(NSWorkspace.shared.open(url))
    #else
    completion?(false)
    #endif
}

/// Profiles store 10-digit Indian numbers; short codes like 112 pass through.
func fullNumber(_ p: String) -> String {
    let d = p.filter { $0.isNumber || $0 == "+" }
    return d.count == 10 ? "+91\(d)" : d
}
@MainActor func dial(_ phone: String) { openSystemURL("tel:\(fullNumber(phone))") }
@MainActor func sms(_ phone: String) { openSystemURL("sms:\(fullNumber(phone))") }

/// Name-and-km text such as "2.4 km away".
func kmAway(_ km: Double) -> String { String(format: "%.1f km away", km) }

/// The point a ride's driver is at, from the live position the server reports.
extension Ride { var driverPoint: LatLng? { driverAt ?? driver?.at } }

/// The road route between two points: its line for the map and its distance for the fare. Starts nil, keeps the last route while a new
/// one loads, and stays nil offline (callers draw the straight line then).
@MainActor @Observable
final class RoadRouteLoader {
    private(set) var route: MapServices.RoadRoute?
    @ObservationIgnored private var key: [Int]?

    /// Re-queries only when an end moved by about 200 m (the same rounding as Android).
    func load(from: LatLng?, to: LatLng?) async {
        guard let from, let to else { route = nil; key = nil; return }
        let k = [from.lat, from.lng, to.lat, to.lng].map { Int(($0 * 500).rounded()) }
        guard k != key else { return }
        key = k
        if let r = await MapServices.route(from: from, to: to) { route = r }
    }
}

extension MapServices.RoadRoute {
    /// Line for BucksMap: the road when there is one, else the straight line.
    static func line(_ road: MapServices.RoadRoute?, _ a: LatLng, _ b: LatLng) -> [LatLng] { road?.points ?? [a, b] }
}

/// A key that changes when either end of a route moves enough to need a new road.
struct RouteKey: Hashable {
    var k: [Int]
    init(_ a: LatLng?, _ b: LatLng?) {
        if let a, let b { k = [a.lat, a.lng, b.lat, b.lng].map { Int(($0 * 500).rounded()) } } else { k = [] }
    }
}

/// Shown while a booking can't start because Bucks has no position for the rider (permission off, location switched off, or no fix yet):
/// says which, and the button asks for the permission, opens the phone's settings, or looks again. Never booked from the map's default centre.
struct LocationNotice: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var switchedOn = true
    @State private var looking = false
    var onEnable: () -> Void = {}

    init(onEnable: @escaping () -> Void = {}) { self.onEnable = onEnable }

    private var perm: Bool { session.locationGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Notice(text)
            SmallButton(perm && switchedOn ? (looking ? "Looking…" : "Try again") : "Turn on location", enabled: !looking, action: enable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: scenePhase) { switchedOn = await session.location.switchedOn() }
    }

    private var text: String {
        if !perm { return "Bucks can't see where you are: location permission is off. Your rider needs your exact pick-up point." }
        if !switchedOn { return "Location is switched off on this phone. Turn it on so your rider can find you." }
        return "Bucks hasn't found your position yet. Step outside or check your GPS signal, then try again."
    }

    private func enable() {
        if perm && switchedOn {
            looking = true
            Task { _ = await session.refreshLocation(); looking = false; onEnable() }
        } else if session.location.notDetermined {
            session.location.requestPermission(); onEnable()
        } else {
            #if os(iOS)
            openSystemURL(UIApplication.openSettingsURLString)
            #endif
            onEnable()
        }
    }
}

/// IconAction look-alike that opens the system share sheet with `text`.
struct ShareAction: View {
    let label: String; let text: String; var systemImage = "square.and.arrow.up"
    var body: some View {
        ShareLink(item: text) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 19)).foregroundStyle(BucksColor.onSurface)
                    .frame(width: 46, height: 46).background(Circle().fill(BucksColor.surfaceContainerHigh))
                Text(label).font(.bucks(.labelSmall)).foregroundStyle(BucksColor.onSurfaceVariant)
            }.padding(6).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// The sentence a rider shares from a trip.
func tripShareText(_ r: Ride, _ d: Driver) -> String { "I'm on a Bucks ride to \(r.dest.name) with \(d.name), \(d.model) \(d.plate)." }

/// The reason sheet for cancelling a ride. While nobody has accepted (`driverName` nil) no reason is needed; once a driver did, one is
/// required and the driver is told why. The sheet stays open until the server has cancelled: a refusal shows its message as a toast and
/// leaves the ride and this sheet in place. `onCancelled` runs once the ride is gone; `onClose` when the rider keeps it.
struct RideCancelSheet: View {
    let driverName: String?
    let arrived: Bool
    let onCancelled: () -> Void
    let onClose: () -> Void
    @Environment(AppSession.self) private var session
    @State private var busy = false
    @State private var stats: CancelStats?

    private var message: String {
        guard let driverName else { return "No driver has accepted yet, so nothing is charged." }
        return arrived ? "\(driverName) is waiting at your pickup. Cancelling wastes their trip." : "\(driverName) is already on the way to you."
    }

    var body: some View {
        let n = stats?.riderDay ?? 0
        return CancelSheet(
            title: driverName == nil ? "Cancel the request?" : "Cancel this ride?", message: message,
            reasons: CancelReasons.rider, requireReason: driverName != nil, confirmLabel: driverName == nil ? "Cancel request" : "Cancel ride",
            keepLabel: driverName == nil ? "Keep waiting" : "Keep ride",
            nudge: n >= 2 ? "You've cancelled \(n) rides after a driver accepted today. Drivers lose time and fuel when that happens." : nil, busy: busy,
            onConfirm: { code, note in
                busy = true
                Task { let ok = await session.cancelRide(reason: code, note: note); busy = false; if ok { onCancelled() } }
            }, onDismiss: onClose)
        .task { if driverName != nil { stats = try? await Backend.shared.myCancelStats() } }
    }
}
