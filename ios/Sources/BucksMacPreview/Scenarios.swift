#if os(macOS)
import SwiftUI
import AppKit
import BucksCore
import BucksUI

/// Scripted walk-throughs: drive the real session and router through a flow and save a screenshot of the app window at each step.
@MainActor
enum Scenarios {
    /// Extra scenarios registered by area files: name -> script.
    static var extra: [String: @MainActor (AppSession, Router) async -> Void] = [:]
    static let dir = "/private/tmp/claude-501/shots"
    static func snap(_ name: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let all = NSApplication.shared.windows
        guard let w = all.first(where: { $0.contentView != nil && $0.frame.width > 100 && $0.frame.width < 500 }) else { print("no window for \(name); windows: \(all.map { "\($0.frame) visible=\($0.isVisible)" })"); return }
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("capture failed \(name)"); return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        print("snap \(name)")
    }
    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func run(_ name: String, session: AppSession, router: Router) async {
        await pause(3.5)
        switch name {
        case "rider": await rider(session, router)
        case "driver": await driver(session, router)
        case "screens": await screens(session, router)
        case let n where extra[n] != nil: await extra[n]!(session, router)
        case let n where n.hasPrefix("snap-"): snap(String(n.dropFirst(5)))
        default: snap("home")
        }
        print("scenario \(name) done")
    }

    static func rider(_ session: AppSession, _ router: Router) async {
        snap("r01-home")
        session.startRide(); router.push(.destination); await pause(1.2); snap("r02-destination")
        session.chooseDest("MG Road"); await pause(0.5); snap("r03-destination-picked")
        router.push(.chooseRide); await pause(2.5); snap("r04-choose-ride")
        router.push(.confirmPickup); await pause(1.2); snap("r05-confirm-pickup")
        session.requestRide(); await pause(1.0); snap("r06-booking-sheet")
        if let p = session.pending { session.confirmPending(p) }
        await pause(1.5); snap("r07-searching")
        await pause(6.0); snap("r08-driver-found")
        await pause(8.0); snap("r09-arrived")
        await pause(8.0); snap("r10-in-ride")
        await pause(15.0); snap("r11-pay")
        session.dispatch.payRide(method: "CASH"); await pause(1.5); snap("r12-rate")
        _ = session.finishRide(vote: nil, comment: "", skip: true); await pause(1.2); snap("r13-home-after")
    }

    static func driver(_ session: AppSession, _ router: Router) async {
        snap("d01-home")
        _ = await session.setOnline(true); await pause(1.0); snap("d02-online")
        await pause(9.0); snap("d03-ring")
        session.dispatch.driverAccept(); await pause(2.5); snap("d04-to-pickup")
        session.dispatch.driverNext(); await pause(2.0); snap("d05-arrived-pin")
        session.dispatch.driverNext(pin: "0000"); await pause(1.5); snap("d06-wrong-pin")
        session.dispatch.driverNext(pin: "4321"); await pause(2.0); snap("d07-in-ride")
        session.dispatch.driverNext(); await pause(2.0); snap("d08-payment")
        session.driverPaid(method: "CASH"); await pause(1.0); snap("d09-rate-customer")
        session.driverRateCustomer(stars: 5); await pause(1.0); snap("d10-home-after")
    }

    static func screens(_ session: AppSession, _ router: Router) async {
        for (n, r) in [("v01-vehicles", Route.vehicles), ("v02-vehicle-new", .vehicleEdit(nil)), ("v03-vehicle-edit", .vehicleEdit("v1")), ("v04-stats", .vehicleStats), ("v05-payment-qr", .paymentQr), ("v06-account", .account), ("v07-edit-profile", .editProfile)] {
            router.popToRoot(); router.push(r); await pause(4.0); snap(n)
        }
    }
}
#endif
