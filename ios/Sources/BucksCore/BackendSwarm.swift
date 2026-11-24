import Foundation

/// Swarm Phase 1: recovery and the demand field (supabase/migrations/swarm_phase1.sql). Same calls as Android's data/BackendSwarm.kt.
/// Recovery only proposes: every choice is the person's own tap, and booking again goes through today's flow and confirm sheet.

/// A shop near the drop that lists items from an order another shop turned down (order_alternatives).
public struct SimilarShop: Decodable, Hashable, Sendable, Identifiable {
    public var listingId: String
    public var title: String
    public var photoUrl: String?
    public var area: String
    public var distanceM: Double
    public var matchedItems: [String]
    public var minPrice: Int?
    public var id: String { listingId }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        listingId = try c.decode(String.self, forKey: .listingId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        photoUrl = (try? c.decodeIfPresent(String.self, forKey: .photoUrl)) ?? nil
        area = (try? c.decodeIfPresent(String.self, forKey: .area)) ?? ""
        distanceM = (try? c.decodeIfPresent(Double.self, forKey: .distanceM)) ?? 0
        matchedItems = (try? c.decodeIfPresent([String].self, forKey: .matchedItems)) ?? []
        minPrice = (try? c.decodeIfPresent(Int.self, forKey: .minPrice)) ?? nil
    }
    private enum K: String, CodingKey { case listingId, title, photoUrl, area, distanceM, matchedItems, minPrice }
}

/// The driver's "recent requests nearby" card (recent_requests_near). `requests3h` is nil under the privacy threshold.
public struct RecentRequests: Decodable, Hashable, Sendable {
    public var requests3h: Int?
    public var requests7d: Int
    public var unfilled7d: Int
    public var driversOnline: Int
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        requests3h = (try? c.decodeIfPresent(Int.self, forKey: .requests3h)) ?? nil
        requests7d = (try? c.decodeIfPresent(Int.self, forKey: .requests7d)) ?? 0
        unfilled7d = (try? c.decodeIfPresent(Int.self, forKey: .unfilled7d)) ?? 0
        driversOnline = (try? c.decodeIfPresent(Int.self, forKey: .driversOnline)) ?? 0
    }
    private enum K: String, CodingKey { case requests3h, requests7d, unfilled7d, driversOnline }
}

public enum Recovery {
    public static let task = "TASK", order = "ORDER"
    public static let tryAgain = "TRY_AGAIN", tryCab = "TRY_CAB", notifyMe = "NOTIFY_ME", similarShops = "SIMILAR_SHOPS"
    /// Orders worth suggesting other shops for: turned down, or cancelled by the shop for a reason another shop could fix.
    public static func similarShopsFor(status: String, cancelledBy: String?, reason: String?) -> Bool {
        status == "REJECTED" || (status == "CANCELLED" && cancelledBy == "SHOP" && ["OUT_OF_STOCK", "CLOSED", "CANT_DELIVER", "TOO_FAR"].contains(reason ?? ""))
    }
}

extension Backend {
    /// Records the person's tap on a recovery card (for recovery conversion). Books nothing.
    @discardableResult
    public func recoveryChoice(kind: String, subject: String, choice: String) async throws -> Bool {
        try await rpc("recovery_choice", ["p_kind": kind, "p_subject": subject, "p_choice": choice])
    }
    /// "Notify me when a driver is online" near `at`. False when the server has it switched off.
    public func notifyMeWhenDriverOnline(kind: VehicleKind, at: LatLng) async throws -> Bool {
        try await rpc("notify_me_when_driver_online", ["p_kind": kind.rawValue, "lat": at.lat, "lng": at.lng])
    }
    public func orderAlternatives(_ orderId: String) async throws -> [SimilarShop] { try await rpcList("order_alternatives", ["p_order": orderId]) }
    public func recentRequestsNear(_ at: LatLng) async throws -> RecentRequests? {
        let rows: [RecentRequests] = try await rpcList("recent_requests_near", ["lat": at.lat, "lng": at.lng])
        return rows.first
    }
}
