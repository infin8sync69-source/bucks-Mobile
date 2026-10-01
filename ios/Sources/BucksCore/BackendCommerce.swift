import Foundation

/// One priced line of an order, as place_order stored it.
public struct OrderLine: Codable, Hashable, Sendable {
    public var itemId: String
    public var name: String
    public var price: Int
    public var qty: Int
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        itemId = try c.decodeIfPresent(String.self, forKey: .itemId) ?? ""; name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        price = try c.decodeIfPresent(Int.self, forKey: .price) ?? 0; qty = try c.decodeIfPresent(Int.self, forKey: .qty) ?? 1
    }
    private enum K: String, CodingKey { case itemId, name, price, qty }
}

/// Items plus the delivery fee when the buyer pays it; the same rule for [CloudOrderRow] and [OrderRow] lists.
public func buyerTotal(_ subtotal: Int, _ deliveryFee: Int, _ feePaidBy: String) -> Int { subtotal + (feePaidBy == "BUYER" ? deliveryFee : 0) }

/// An orders row including its lines; `OrderRow` leaves them out.
public struct CloudOrderRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var buyerId: String
    public var lines: [OrderLine]
    public var subtotal: Int
    public var deliveryFee: Int
    public var feePaidBy: String
    public var deliveryMode: String
    public var payment: String
    public var dropLabel: String
    public var status: String
    public var acceptBy: String
    public var createdAt: String
    /// BUYER or SHOP once the order is CANCELLED (see commerce.sql); nil otherwise and on older rows.
    public var cancelledBy: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); buyerId = try c.decode(String.self, forKey: .buyerId)
        lines = (try? c.decodeIfPresent([OrderLine].self, forKey: .lines)) ?? []
        subtotal = try c.decode(Int.self, forKey: .subtotal); deliveryFee = (try? c.decodeIfPresent(Int.self, forKey: .deliveryFee)) ?? 0
        feePaidBy = (try? c.decodeIfPresent(String.self, forKey: .feePaidBy)) ?? "BUYER"; deliveryMode = (try? c.decodeIfPresent(String.self, forKey: .deliveryMode)) ?? "MARKETPLACE"
        payment = (try? c.decodeIfPresent(String.self, forKey: .payment)) ?? "UPI"; dropLabel = (try? c.decodeIfPresent(String.self, forKey: .dropLabel)) ?? ""
        status = try c.decode(String.self, forKey: .status); acceptBy = try c.decode(String.self, forKey: .acceptBy); createdAt = try c.decode(String.self, forKey: .createdAt)
        cancelledBy = (try? c.decodeIfPresent(String.self, forKey: .cancelledBy)) ?? nil
    }
    private enum K: String, CodingKey { case id, listingId, buyerId, lines, subtotal, deliveryFee, feePaidBy, deliveryMode, payment, dropLabel, status, acceptBy, createdAt, cancelledBy }

    /// Everything the buyer pays for this order: items plus the rider's fee unless the shop offers free delivery.
    public var total: Int { buyerTotal(subtotal, deliveryFee, feePaidBy) }
    /// The part of `total` the buyer pays the Bucks rider directly at the door (UPI or cash): the fee of a marketplace delivery.
    /// The rider is independent of the shop and collects their own fare, so it never goes into the shop's UPI amount. With free delivery it is 0.
    public var feeAtDoor: Int { deliveryMode == "MARKETPLACE" && feePaidBy == "BUYER" ? deliveryFee : 0 }
    /// What the buyer pays the shop: items, plus the delivery fee only when the shop's own rider delivers (the shop pays that rider).
    public var toShop: Int { total - feeAtDoor }
}

/// Counterparty details while an order is live: the buyer gets the shop owner's phone and UPI link, the shop gets the buyer's phone.
public struct OrderContactRow: Codable, Hashable, Sendable {
    public var phone: String?
    public var upiUri: String?
    public var name: String?
}

/// Commerce calls of Backend.kt / BackendCommerce.kt: place_order, the buyer's and the shop's order lists, order detail with its lines,
/// and the functions from supabase/migrations/commerce.sql (contact_for_order, cancel_order, update_order_status).
extension Backend {
    /// The server prices the lines and adds the delivery fee; returns the new order's id.
    public func placeOrder(listingId: String, lines: [(itemId: String, qty: Int)], drop: LatLng, dropLabel: String, payment: String, mode: String) async throws -> String {
        try await rpc("place_order", [
            "p_listing": listingId,
            "p_lines": lines.map { ["item_id": $0.itemId, "qty": $0.qty] as [String: Any] },
            "p_lat": drop.lat, "p_lng": drop.lng, "p_drop_label": dropLabel, "p_payment": payment, "p_mode": mode,
        ])
    }
    public func myOrders(me: String) async throws -> [OrderRow] {
        try await select("orders", filters: [.eq("buyer_id", me)], order: "created_at", ascending: false)
    }
    public func respondOrder(_ id: String, accept: Bool) async throws { try await rpcVoid("respond_order", ["p_order": id, "p_accept": accept]) }

    public func orderDetail(_ id: String) async throws -> CloudOrderRow? { try await selectOne("orders", filters: [.eq("id", id)]) }
    public func vendorOrders(listingId: String) async throws -> [CloudOrderRow] {
        try await select("orders", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false)
    }
    public func listingsByIds(_ ids: [String]) async throws -> [ListingRow] {
        ids.isEmpty ? [] : try await select("listings", filters: [.isIn("id", ids)])
    }
    /// listing_members of a shop (readable by everyone): STORE_RIDER rows are its own delivery riders.
    public func shopMembers(_ listingId: String) async throws -> [MemberRow] { try await select("listing_members", filters: [.eq("listing_id", listingId)]) }

    /// The delivery task an accepted delivery order created; readable by the buyer (requester) and the rider who took it.
    /// Read through `tasks_geo`: the API may not read `tasks.pin` directly (dispatch.sql), the view gives it to the buyer only.
    public func taskForOrder(_ orderId: String) async throws -> TaskRow? {
        (try await select("tasks_geo", filters: [.eq("order_id", orderId)], order: "created_at", ascending: false, limit: 1) as [TaskRow]).first
    }
    public func contactForOrder(_ orderId: String) async throws -> OrderContactRow? {
        (try await rpcList("contact_for_order", ["p_order": orderId]) as [OrderContactRow]).first
    }
    /// Buyer cancels while the order is still PLACED.
    public func cancelOrder(_ orderId: String) async throws { try await rpcVoid("cancel_order", ["p_order": orderId]) }
    /// Vendor marks an accepted order READY, a pick-up order DELIVERED once collected, or CANCELLED when no rider has it (or the buyer never came).
    public func updateOrderStatus(_ orderId: String, status: String) async throws { try await rpcVoid("update_order_status", ["p_order": orderId, "p_status": status]) }

    /// Inserts and updates on a shop's orders as they happen (row-level security still applies). Cancel the consuming task to close it.
    public func liveOrders(listingId: String) -> AsyncStream<CloudOrderRow> { liveOrderRows(filter: "listing_id=eq.\(listingId)", events: ["INSERT", "UPDATE"]) }
    /// Status changes on one order, for the buyer's order page.
    public func liveOrder(orderId: String) -> AsyncStream<CloudOrderRow> { liveOrderRows(filter: "id=eq.\(orderId)", events: ["UPDATE"]) }

    private func liveOrderRows(filter: String, events: Set<String>) -> AsyncStream<CloudOrderRow> {
        AsyncStream { cont in
            let pump = Task {
                for await change in changes(table: "orders", filter: filter, events: Array(events)) {
                    guard events.contains(change.event), let data = change.record, let row = try? Backend.decoder.decode(CloudOrderRow.self, from: data) else { continue }
                    cont.yield(row)
                }
                cont.finish()
            }
            cont.onTermination = { _ in pump.cancel() }
        }
    }
}
