import Foundation

// Cancelling a ride or an order with a reason (migration cancellation.sql; port of data/BackendCancel.kt). The codes are checked by the
// server; the labels are what people read. Rider and driver reasons are required once someone has accepted; the screens ask for them.

/// One choice in a cancel sheet: the code the server keeps and the words people read.
public struct CancelReason: Hashable, Sendable, Identifiable {
    public let code: String
    public let label: String
    public var id: String { code }
    public init(_ code: String, _ label: String) { self.code = code; self.label = label }
}

public enum CancelReasons {
    /// Rider cancelling a ride.
    public static let rider: [CancelReason] = [
        CancelReason("TOO_LONG", "Taking too long"), CancelReason("DRIVER_FAR", "Driver is too far"), CancelReason("DRIVER_ASKED", "Driver asked me to cancel"),
        CancelReason("PLANS_CHANGED", "My plans changed"), CancelReason("BOOKED_BY_MISTAKE", "Booked by mistake"), CancelReason("WRONG_ADDRESS", "Wrong pickup or drop"),
        CancelReason("OTHER", "Something else"),
    ]
    /// Driver handing a ride back.
    public static let driver: [CancelReason] = [
        CancelReason("RIDER_NO_SHOW", "Customer isn't at the pickup"), CancelReason("RIDER_UNREACHABLE", "Can't reach the customer"), CancelReason("RIDER_ASKED", "Customer asked me to cancel"),
        CancelReason("TOO_FAR", "Pickup is too far"), CancelReason("VEHICLE_ISSUE", "Vehicle problem"), CancelReason("UNSAFE", "I don't feel safe"),
        CancelReason("OTHER", "Something else"),
    ]
    /// Buyer cancelling an order before the shop accepts.
    public static let buyer: [CancelReason] = [
        CancelReason("CHANGED_MIND", "I changed my mind"), CancelReason("ORDERED_BY_MISTAKE", "Ordered by mistake"), CancelReason("WRONG_ADDRESS", "Wrong address"),
        CancelReason("TOO_SLOW", "Shop is taking too long"), CancelReason("FOUND_BETTER", "Found it elsewhere"), CancelReason("OTHER", "Something else"),
    ]
    /// Shop cancelling an order it had accepted.
    public static let shop: [CancelReason] = [
        CancelReason("OUT_OF_STOCK", "Out of stock"), CancelReason("CANT_DELIVER", "Can't deliver there"), CancelReason("CUSTOMER_UNREACHABLE", "Can't reach the customer"),
        CancelReason("CUSTOMER_ASKED", "Customer asked to cancel"), CancelReason("CLOSED", "We're closed"), CancelReason("OTHER", "Something else"),
    ]
    /// Shop declining a new order.
    public static let shopReject: [CancelReason] = [
        CancelReason("OUT_OF_STOCK", "Out of stock"), CancelReason("CLOSED", "We're closed"), CancelReason("TOO_FAR", "Too far to deliver"),
        CancelReason("CANT_DELIVER", "Can't deliver there"), CancelReason("OTHER", "Something else"),
    ]
}

/// How often I cancelled after someone accepted: today and in the last 7 days, as a rider and as a driver (`my_cancel_stats`).
public struct CancelStats: Decodable, Hashable, Sendable {
    public var riderDay: Int
    public var riderWeek: Int
    public var driverDay: Int
    public var driverWeek: Int
    public init(riderDay: Int = 0, riderWeek: Int = 0, driverDay: Int = 0, driverWeek: Int = 0) {
        self.riderDay = riderDay; self.riderWeek = riderWeek; self.driverDay = driverDay; self.driverWeek = driverWeek
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        riderDay = (try? c.decodeIfPresent(Int.self, forKey: .riderDay)) ?? 0; riderWeek = (try? c.decodeIfPresent(Int.self, forKey: .riderWeek)) ?? 0
        driverDay = (try? c.decodeIfPresent(Int.self, forKey: .driverDay)) ?? 0; driverWeek = (try? c.decodeIfPresent(Int.self, forKey: .driverWeek)) ?? 0
    }
    private enum K: String, CodingKey { case riderDay, riderWeek, driverDay, driverWeek }
}

extension Backend {
    /// Rider cancels a ride. `reason` (a `CancelReasons.rider` code) is required once a driver accepted. The server refuses once the trip has started.
    public func cancelTask(_ taskId: String, reason: String?, note: String = "") async throws {
        try await rpcVoid("cancel_task", ["p_task": taskId, "p_reason": reason, "p_note": note])
    }
    /// Driver hands an accepted ride back so it rings other drivers. `reason` (a `CancelReasons.driver` code) is required.
    public func releaseTask(_ taskId: String, reason: String, note: String = "") async throws {
        try await rpcVoid("release_task", ["p_task": taskId, "p_reason": reason, "p_note": note])
    }
    public func myCancelStats() async throws -> CancelStats { try await rpc("my_cancel_stats") }
}

extension AppSession {
    /// Rider: cancel before the trip starts, with the reason from the sheet. Returns nil once the ride is gone (the caller may close its sheet
    /// and leave the screen), otherwise the server's sentence for the sheet to show; the ride and the sheet then stay where they are.
    public func cancelRide(reason: String?, note: String) async -> String? {
        guard let r = dispatch.ride else { return nil }
        if dispatch.cancelling { return "Still cancelling. One moment." }   // a cancel is already on its way
        guard [.searching, .noDriver, .matched, .arrived].contains(r.status) else { return "This trip has already started, so it can't be cancelled here." }
        if let err = await dispatch.cancelRide(reason: reason, note: note) { return err }
        toast("Ride cancelled. Nothing to pay."); return nil
    }
    /// Driver: hand the trip back with the reason from the sheet. Returns nil once it is handed back, otherwise the sentence for the sheet to show.
    public func driverHandBack(reason: String?, note: String) async -> String? {
        if let err = await dispatch.driverCancel(reason: reason, note: note) { return err }
        toast("Handed back. Other riders will be rung for it."); return nil
    }
}
