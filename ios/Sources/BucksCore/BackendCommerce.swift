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
    /// Shipped orders (delivery_mode SHIP, ecommerce.sql): who it goes to, the carrier and tracking the shop entered, and when.
    public var shipTo: JSONValue?
    public var carrier: String
    public var trackingNo: String
    public var trackingUrl: String
    public var shippedAt: String?
    public var deliveredAt: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); buyerId = try c.decode(String.self, forKey: .buyerId)
        lines = (try? c.decodeIfPresent([OrderLine].self, forKey: .lines)) ?? []
        subtotal = try c.decode(Int.self, forKey: .subtotal); deliveryFee = (try? c.decodeIfPresent(Int.self, forKey: .deliveryFee)) ?? 0
        feePaidBy = (try? c.decodeIfPresent(String.self, forKey: .feePaidBy)) ?? "BUYER"; deliveryMode = (try? c.decodeIfPresent(String.self, forKey: .deliveryMode)) ?? "MARKETPLACE"
        payment = (try? c.decodeIfPresent(String.self, forKey: .payment)) ?? "UPI"; dropLabel = (try? c.decodeIfPresent(String.self, forKey: .dropLabel)) ?? ""
        status = try c.decode(String.self, forKey: .status); acceptBy = try c.decode(String.self, forKey: .acceptBy); createdAt = try c.decode(String.self, forKey: .createdAt)
        cancelledBy = (try? c.decodeIfPresent(String.self, forKey: .cancelledBy)) ?? nil
        shipTo = (try? c.decodeIfPresent(JSONValue.self, forKey: .shipTo)) ?? nil
        carrier = (try? c.decodeIfPresent(String.self, forKey: .carrier)) ?? ""
        trackingNo = (try? c.decodeIfPresent(String.self, forKey: .trackingNo)) ?? ""
        trackingUrl = (try? c.decodeIfPresent(String.self, forKey: .trackingUrl)) ?? ""
        shippedAt = (try? c.decodeIfPresent(String.self, forKey: .shippedAt)) ?? nil
        deliveredAt = (try? c.decodeIfPresent(String.self, forKey: .deliveredAt)) ?? nil
    }
    private enum K: String, CodingKey {
        case id, listingId, buyerId, lines, subtotal, deliveryFee, feePaidBy, deliveryMode, payment, dropLabel, status, acceptBy, createdAt, cancelledBy
        case shipTo, carrier, trackingNo, trackingUrl, shippedAt, deliveredAt
    }

    public var shipped: Bool { deliveryMode == "SHIP" }
    /// The address as the shop reads it on a label: name, phone, lines, city, state, pincode.
    public var shipToText: String {
        guard let a = shipTo else { return "" }
        func f(_ k: String) -> String { (a[k]?.string ?? "").trimmingCharacters(in: .whitespaces) }
        let place = [f("city"), f("state")].filter { !$0.isEmpty }.joined(separator: ", ") + " " + f("pincode")
        return [f("name"), f("phone"), f("line1"), f("line2"), place.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }.joined(separator: "\n")
    }

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
    /// The shop accepts or rejects a PLACED order. `reason` (a `CancelReasons.shopReject` code) says why it was rejected; sent only when given.
    public func respondOrder(_ id: String, accept: Bool, reason: String? = nil) async throws {
        var p: [String: Any?] = ["p_order": id, "p_accept": accept]
        if let reason { p["p_reason"] = reason }
        try await rpcVoid("respond_order", p)
    }

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
    /// Buyer cancels while the order is still PLACED. `reason` is a `CancelReasons.buyer` code; sent only when given.
    public func cancelOrder(_ orderId: String, reason: String? = nil) async throws {
        var p: [String: Any?] = ["p_order": orderId]
        if let reason { p["p_reason"] = reason }
        try await rpcVoid("cancel_order", p)
    }
    /// Vendor marks an accepted order READY, a pick-up order DELIVERED once collected, or CANCELLED when no rider has it (or the buyer never came).
    /// `reason` (a `CancelReasons.shop` code) goes with CANCELLED; sent only when given.
    public func updateOrderStatus(_ orderId: String, status: String, reason: String? = nil) async throws {
        var p: [String: Any?] = ["p_order": orderId, "p_status": status]
        if let reason { p["p_reason"] = reason }
        try await rpcVoid("update_order_status", p)
    }

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

// MARK: - Shipping: orders to an address anywhere, the address book (migration ecommerce.sql)

/// A saved delivery address; the server checks the mobile number (10 digits) and the pincode (6 digits) again at checkout.
public struct AddressRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String?
    public var label: String
    public var name: String
    public var phone: String
    public var line1: String
    public var line2: String
    public var city: String
    public var state: String
    public var pincode: String
    public var isDefault: Bool
    public init(id: String? = nil, label: String = "", name: String, phone: String, line1: String, line2: String = "", city: String, state: String, pincode: String, isDefault: Bool = false) {
        self.id = id; self.label = label; self.name = name; self.phone = phone; self.line1 = line1; self.line2 = line2; self.city = city; self.state = state; self.pincode = pincode; self.isDefault = isDefault
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func s(_ k: K) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        label = s(.label); name = s(.name); phone = s(.phone); line1 = s(.line1); line2 = s(.line2); city = s(.city); state = s(.state); pincode = s(.pincode)
        isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
    }
    private enum K: String, CodingKey { case id, label, name, phone, line1, line2, city, state, pincode, isDefault }

    public var oneLine: String { [line1, line2, "\(city), \(state) \(pincode)"].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ") }
    /// What place_order_ship takes as p_address.
    public var json: [String: Any] { ["name": name, "phone": phone, "line1": line1, "line2": line2, "city": city, "state": state, "pincode": pincode] }
}

extension Backend {
    public func addresses() async throws -> [AddressRow] { try await select("addresses", order: "created_at", ascending: false) }
    /// Saves a new address (no id) or edits one; returns the stored row.
    public func saveAddress(me: String, _ a: AddressRow) async throws -> AddressRow {
        let body: [String: Any?] = ["label": a.label, "name": a.name, "phone": a.phone, "line1": a.line1, "line2": a.line2, "city": a.city, "state": a.state, "pincode": a.pincode, "is_default": a.isDefault]
        if let id = a.id {
            guard let r = try await update("addresses", body, filters: [.eq("id", id)], returning: AddressRow.self) else { throw BackendError.decoding("addresses: empty update") }
            return r
        }
        var row = body; row["profile_id"] = me
        return try await insert("addresses", row)
    }
    public func deleteAddress(_ id: String) async throws { try await delete("addresses", filters: [.eq("id", id)]) }

    /// Orders from a shop that ships: the address is checked on the server, the shipping fee comes from the shop's own rule.
    public func placeShipOrder(listingId: String, lines: [(itemId: String, qty: Int)], address: [String: Any], payment: String) async throws -> String {
        try await rpc("place_order_ship", [
            "p_listing": listingId,
            "p_lines": lines.map { ["item_id": $0.itemId, "qty": $0.qty] as [String: Any] },
            "p_address": address, "p_payment": payment,
        ])
    }
    /// The shop hands an accepted shipped order to a carrier ("Self delivery" is fine) with an optional tracking number and link.
    public func shipOrder(_ orderId: String, carrier: String, tracking: String, url: String) async throws {
        try await rpcVoid("ship_order", ["p_order": orderId, "p_carrier": carrier, "p_tracking": tracking, "p_url": url])
    }
    /// The buyer received it, or the shop delivered it itself.
    public func markDelivered(_ orderId: String) async throws { try await rpcVoid("mark_delivered", ["p_order": orderId]) }
}
