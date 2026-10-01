import Foundation
import Testing
@testable import BucksCore

/// Cart rules, order money rules and what the commerce calls put on the wire (RPC names and `p_` parameters, filters), written against
/// supabase/migrations/commerce.sql and the Kotlin in Backend.kt / BackendCommerce.kt.
@MainActor @Suite(.serialized) struct CommerceTests {
    func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) {
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
    }
    func wait(timeout: Double = 4, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 50_000_000) }
        return cond()
    }
    private func call(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }

    private func listing(_ id: String, _ title: String = "Fresh Mart") -> ListingRow {
        try! Backend.decoder.decode(ListingRow.self, from: JSONSerialization.data(withJSONObject: ["id": id, "kind": "BUSINESS", "owner_id": "o1", "title": title, "area": "Jayanagar"]))
    }
    private func item(_ id: String, _ price: Int, listing: String = "L1") -> ItemRow { ItemRow(id: id, listingId: listing, name: "Item \(id)", price: price) }
    private func orderJSON(status: String = "PLACED", mode: String = "MARKETPLACE", paidBy: String = "BUYER") -> [String: Any] {
        ["id": "o-1", "listing_id": "L1", "buyer_id": "me", "lines": [["item_id": "i1", "name": "Dal", "price": 120, "qty": 2]], "subtotal": 240, "delivery_fee": 36,
         "fee_paid_by": paidBy, "delivery_mode": mode, "payment": "UPI", "drop_label": "4th block", "status": status, "accept_by": "2026-10-01T10:05:00+00:00", "created_at": "2026-10-01T10:00:00+00:00"]
    }

    @Test func eachShopIsItsOwnPartOfTheCart() {
        let s = AppSession(); var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        let c = s.commerce
        let a = listing("L1"), b = listing("L2", "Other")
        c.add(a, item("i1", 100), 2); c.add(a, item("i2", 50), 1); c.add(a, item("i1", 100), 1)
        #expect(c.count == 4); #expect(c.subtotal == 350); #expect(c.qty("i1") == 3); #expect(c.stores.map(\.listing.id) == ["L1"])
        // Another shop joins the cart as its own part (its own order at checkout), nothing is asked or dropped.
        c.add(b, item("j1", 10, listing: "L2"), 2)
        #expect(c.stores.map(\.listing.id) == ["L1", "L2"]); #expect(c.count == 6); #expect(c.subtotal == 370); #expect(c.stores[1].amount == 20)
        // Going down to zero drops the line, and a store with no lines left.
        c.add(b, item("j1", 10, listing: "L2"), -5)
        #expect(c.stores.map(\.listing.id) == ["L1"]); #expect(c.qty("j1") == 0)
        c.remove("i2"); #expect(c.stores.first?.lines.map(\.item.id) == ["i1"])
        c.clearStore("L1"); #expect(c.stores.isEmpty); #expect(c.count == 0)
        // Never more than the shop has in stock.
        var few = item("k1", 30); few.stock = 2
        c.add(a, few, 5); #expect(c.qty("k1") == 2)
        c.add(a, few, 1); #expect(c.qty("k1") == 2); #expect(toasts.last == "Only 2 of Item k1 in stock.")
    }

    @Test func orderMoneyFollowsWhoPaysTheRider() throws {
        func row(_ mode: String, _ paidBy: String) throws -> CloudOrderRow { try Backend.decoder.decode(CloudOrderRow.self, from: JSONSerialization.data(withJSONObject: orderJSON(mode: mode, paidBy: paidBy))) }
        let bucks = try row("MARKETPLACE", "BUYER")
        #expect(bucks.total == 276); #expect(bucks.feeAtDoor == 36); #expect(bucks.toShop == 240)
        let free = try row("MARKETPLACE", "VENDOR")
        #expect(free.total == 240); #expect(free.feeAtDoor == 0); #expect(free.toShop == 240)
        let own = try row("STORE_RIDER", "BUYER")
        #expect(own.total == 276); #expect(own.feeAtDoor == 0); #expect(own.toShop == 276)
        #expect(try row("MARKETPLACE", "BUYER").lines.first?.itemId == "i1")
        #expect(buyerTotal(100, 20, "VENDOR") == 100); #expect(buyerTotal(100, 20, "BUYER") == 120)
    }

    @Test func checkoutSendsTheServersParametersAndClearsTheCart() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/place_order": return (200, "o-1")
            case "/rest/v1/orders": return (200, [self.orderJSON()])
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "BUSINESS", "owner_id": "o1", "title": "Fresh Mart"]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        let c = s.commerce
        c.add(listing("L1"), item("i1", 120), 2)
        var placed: [String]?
        c.checkoutAll(choices: ["L1": .init(mode: "MARKETPLACE", payment: "UPI", dropLabel: "  4th block ")], drop: LatLng(12.93, 77.58)) { placed = $0 }
        #expect(await wait { placed != nil })
        #expect(placed == ["o-1"]); #expect(c.stores.isEmpty); #expect(!c.placing)
        let b = try #require(call("/rest/v1/rpc/place_order").first).body
        #expect(Set(b.keys) == ["p_listing", "p_lines", "p_lat", "p_lng", "p_drop_label", "p_payment", "p_mode"])
        #expect(b["p_listing"] as? String == "L1"); #expect(b["p_drop_label"] as? String == "4th block")
        #expect(b["p_payment"] as? String == "UPI"); #expect(b["p_mode"] as? String == "MARKETPLACE")
        #expect(b["p_lat"] as? Double == 12.93); #expect(b["p_lng"] as? Double == 77.58)
        let lines = try #require(b["p_lines"] as? [[String: Any]])
        #expect(lines.count == 1); #expect(lines[0]["item_id"] as? String == "i1"); #expect(lines[0]["qty"] as? Int == 2)
        #expect(await wait { c.myOrdersLoaded })
        #expect(call("/rest/v1/orders").first?.query.contains("buyer_id=eq.me") == true)
        #expect(call("/rest/v1/orders").first?.query.contains("order=created_at.desc") == true)
    }

    @Test func twoShopsAreTwoOrdersAndAFailedOneStaysInTheCart() async throws {
        boot { path, _, body in
            switch path {
            case "/rest/v1/rpc/place_order":
                return body["p_listing"] as? String == "L2" ? (400, ["message": "this shop is closed right now"]) : (200, "o-1")
            case "/rest/v1/rpc/place_order_ship": return (200, "o-3")
            default: return (200, [Any]())
            }
        }
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        let c = s.commerce
        c.add(listing("L1"), item("i1", 120), 1); c.add(listing("L2", "Corner Shop"), item("j1", 40, listing: "L2"), 1); c.add(listing("L3", "Silk House"), item("k1", 900, listing: "L3"), 1)
        let home = AddressRow(name: "Asha Rao", phone: "9876543210", line1: "12 MG Road", city: "Mysuru", state: "Karnataka", pincode: "570001")
        var placed: [String]?
        c.checkoutAll(choices: ["L1": .init(mode: "PICKUP", payment: "UPI", dropLabel: "Jayanagar"),
                                "L2": .init(mode: "MARKETPLACE", payment: "UPI", dropLabel: "Home"),
                                "L3": .init(mode: "SHIP", payment: "COD", dropLabel: "", address: home)], drop: LatLng(12.93, 77.58)) { placed = $0 }
        #expect(await wait { placed != nil })
        #expect(placed == ["o-1", "o-3"])
        // The shop that refused stays in the cart with its reason; the others are cleared.
        #expect(c.stores.map(\.listing.id) == ["L2"])
        #expect(toasts.contains("Corner Shop: This shop is closed right now"))
        let ship = try #require(call("/rest/v1/rpc/place_order_ship").first).body
        #expect(Set(ship.keys) == ["p_listing", "p_lines", "p_address", "p_payment"])
        #expect(ship["p_payment"] as? String == "COD")
        let addr = try #require(ship["p_address"] as? [String: Any])
        #expect(addr["pincode"] as? String == "570001"); #expect(addr["phone"] as? String == "9876543210"); #expect(addr["line2"] as? String == "")
    }

    @Test func deliveryWithoutAPositionIsNotPlaced() async throws {
        boot { _, _, _ in (404, ["message": "no stub"]) }
        let s = AppSession(); var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        let c = s.commerce
        c.add(listing("L1"), item("i1", 120), 1)
        c.checkoutAll(choices: ["L1": .init(mode: "MARKETPLACE", payment: "UPI", dropLabel: "x")], drop: nil) { _ in }
        #expect(await wait { !toasts.isEmpty })
        #expect(toasts.first == "Turn on location to get Fresh Mart's order delivered, or choose pick-up.")
        #expect(call("/rest/v1/rpc/place_order").isEmpty); #expect(c.count == 1)
        // A shipped order needs an address.
        toasts = []
        c.checkoutAll(choices: ["L1": .init(mode: "SHIP", payment: "UPI", dropLabel: "")], drop: nil) { _ in }
        #expect(await wait { !toasts.isEmpty }); #expect(toasts.first == "Add a delivery address for Fresh Mart's order.")
        // Empty cart.
        c.clear(); toasts = []
        c.checkoutAll(choices: [:], drop: nil) { _ in }
        #expect(await wait { !toasts.isEmpty }); #expect(toasts.first == "Your cart is empty.")
    }

    @Test func shippedOrdersCarryTheirAddressAndTracking() throws {
        var j = orderJSON(status: "SHIPPED", mode: "SHIP")
        j["ship_to"] = ["name": "Asha Rao", "phone": "9876543210", "line1": "12 MG Road", "line2": "", "city": "Mysuru", "state": "Karnataka", "pincode": "570001"]
        j["carrier"] = "DTDC"; j["tracking_no"] = "D123"; j["tracking_url"] = "https://dtdc.in/t/D123"; j["shipped_at"] = "2026-10-01T11:00:00+00:00"
        let o = try Backend.decoder.decode(CloudOrderRow.self, from: JSONSerialization.data(withJSONObject: j))
        #expect(o.shipped); #expect(o.carrier == "DTDC"); #expect(o.trackingNo == "D123"); #expect(o.shippedAt != nil)
        #expect(o.shipToText == "Asha Rao\n9876543210\n12 MG Road\nMysuru, Karnataka 570001")
        // Older rows without the shipping columns still decode.
        let plain = try Backend.decoder.decode(CloudOrderRow.self, from: JSONSerialization.data(withJSONObject: orderJSON()))
        #expect(!plain.shipped); #expect(plain.carrier.isEmpty); #expect(plain.shipToText.isEmpty)
    }

    @Test func vendorAndBuyerActionsUseTheOrderFunctions() async throws {
        var status = "PLACED"
        boot { path, query, params in
            switch path {
            case "/rest/v1/rpc/respond_order": status = (params["p_accept"] as? Bool) == true ? "ACCEPTED" : "REJECTED"; return (204, [:])
            case "/rest/v1/rpc/update_order_status": status = params["p_status"] as? String ?? status; return (204, [:])
            case "/rest/v1/rpc/cancel_order": status = "CANCELLED"; return (204, [:])
            case "/rest/v1/rpc/contact_for_order": return (200, [["phone": "9000000001", "upi_uri": "upi://pay?pa=shop@upi&pn=Shop"]])
            case "/rest/v1/orders": return (200, query.contains("listing_id=eq.L1") ? [self.orderJSON(status: status)] : [self.orderJSON(status: status)])
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "BUSINESS", "owner_id": "o1", "title": "Fresh Mart"]])
            case "/rest/v1/profiles": return (200, [["id": "me", "short_code": "ME0001", "name": "Asha Rao"]])
            case "/rest/v1/tasks_geo": return (200, [["id": "t1", "type": "DELIVERY", "requester_id": "me", "order_id": "o-1", "vehicle_kind": "BIKE", "status": "SEARCHING", "pin": "4321"]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        let c = s.commerce
        c.respondOrder("o-1", accept: true)
        #expect(await wait { !c.isActing("o-1") && c.orders["o-1"]?.status == "ACCEPTED" })
        #expect(try #require(call("/rest/v1/rpc/respond_order").first).body as NSDictionary == ["p_order": "o-1", "p_accept": true] as NSDictionary)
        c.updateOrderStatus("o-1", status: "READY")
        #expect(await wait { c.orders["o-1"]?.status == "READY" })
        #expect(try #require(call("/rest/v1/rpc/update_order_status").first).body as NSDictionary == ["p_order": "o-1", "p_status": "READY"] as NSDictionary)
        var done = false
        c.cancelOrder("o-1") { done = true }
        #expect(await wait { done })
        #expect(try #require(call("/rest/v1/rpc/cancel_order").first).body as NSDictionary == ["p_order": "o-1"] as NSDictionary)
        #expect(c.orders["o-1"]?.status == "CANCELLED")

        let contact = try #require(try await c.contactFor("o-1"))
        #expect(contact.phone == "9000000001"); #expect(contact.upiUri == "upi://pay?pa=shop@upi&pn=Shop")
        #expect(try #require(call("/rest/v1/rpc/contact_for_order").first).body as NSDictionary == ["p_order": "o-1"] as NSDictionary)
        // The delivery task is read through the view that carries the pin, newest first, one row.
        let t = try #require(try await c.taskForOrder("o-1"))
        #expect(t.id == "t1"); #expect(t.pin == "4321")
        let q = try #require(call("/rest/v1/tasks_geo").first).query
        #expect(q.contains("order_id=eq.o-1")); #expect(q.contains("order=created_at.desc")); #expect(q.contains("limit=1"))
    }

    @Test func aFailedActionToastsAndReadsTheOrderAgain() async throws {
        var reads = 0
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/respond_order": return (400, ["message": "cannot go from ACCEPTED to ACCEPTED"])
            case "/rest/v1/orders": reads += 1; return (200, [self.orderJSON(status: "ACCEPTED")])
            case "/rest/v1/listings": return (200, [["id": "L1", "kind": "BUSINESS", "owner_id": "o1", "title": "Fresh Mart"]])
            case "/rest/v1/profiles": return (200, [])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let s = AppSession(); var toasts: [String] = []; s.toastHandler = { toasts.append($0) }
        let c = s.commerce
        c.respondOrder("o-1", accept: true)
        #expect(await wait { !toasts.isEmpty && !c.isActing("o-1") })
        #expect(await wait { c.orders["o-1"]?.status == "ACCEPTED" }); #expect(reads >= 1)
    }

    @Test func shopOrdersAreReadNewestFirstAndRidersLookedUpOnMembers() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/orders": return (200, [self.orderJSON()])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "r1", "role": "STORE_RIDER"]])
            case "/rest/v1/profiles": return (200, [["id": "me", "short_code": "ME0001", "name": "Asha Rao"]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let s = AppSession(); let c = s.commerce
        c.ordersFor("L1")
        #expect(await wait { c.vendorLoaded }); c.stopOrders()
        #expect(c.vendorOrders.count == 1)
        let q = try #require(call("/rest/v1/orders").first).query
        #expect(q.contains("listing_id=eq.L1")); #expect(q.contains("order=created_at.desc"))
        #expect(try await c.hasStoreRiders("L1"))
        #expect(call("/rest/v1/listing_members").first?.query.contains("listing_id=eq.L1") == true)
        c.signedOut(); #expect(c.vendorOrders.isEmpty); #expect(!c.vendorLoaded); #expect(c.orders.isEmpty)
    }
}
