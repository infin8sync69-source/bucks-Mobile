import Foundation

/// Why a ride was cancelled or handed back (migration cancellation.sql). The codes are checked by the server (`cancel_reason_ok`);
/// the labels are what people read. Same lists as the Android app (data/BackendCancel.kt).
public struct CancelReason: Identifiable, Hashable, Sendable {
    public let code: String
    public let label: String
    public var id: String { code }
}

public enum CancelReasons {
    /// A rider cancelling a ride. Required once a driver has accepted (MATCHED or ARRIVED); optional while searching.
    public static let rider: [CancelReason] = [
        .init(code: "TOO_LONG", label: "Taking too long"), .init(code: "DRIVER_FAR", label: "Driver is too far"),
        .init(code: "DRIVER_ASKED", label: "Driver asked me to cancel"), .init(code: "PLANS_CHANGED", label: "My plans changed"),
        .init(code: "BOOKED_BY_MISTAKE", label: "Booked by mistake"), .init(code: "WRONG_ADDRESS", label: "Wrong pickup or drop"),
        .init(code: "OTHER", label: "Something else"),
    ]
    /// A driver handing a ride or delivery back. Always required.
    public static let driver: [CancelReason] = [
        .init(code: "RIDER_NO_SHOW", label: "Customer isn't at the pickup"), .init(code: "RIDER_UNREACHABLE", label: "Can't reach the customer"),
        .init(code: "RIDER_ASKED", label: "Customer asked me to cancel"), .init(code: "TOO_FAR", label: "Pickup is too far"),
        .init(code: "VEHICLE_ISSUE", label: "Vehicle problem"), .init(code: "UNSAFE", label: "I don't feel safe"),
        .init(code: "OTHER", label: "Something else"),
    ]
}
