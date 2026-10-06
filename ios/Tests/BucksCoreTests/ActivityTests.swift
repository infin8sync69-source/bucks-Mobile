import Foundation
import Testing
@testable import BucksCore

/// The Home activity pill's items: an open ride and open orders, with Android's wording (ActivityFab.kt).
struct ActivityTests {
    private func ride(_ status: RideStatus, eta: Int = 3, fare: Int = 180) -> ActivityRide {
        ActivityRide(status: status, fare: fare, etaMin: eta, destName: "Indiranagar", kind: .auto)
    }
    private func order(_ id: String, _ status: String, mode: String = "MARKETPLACE", buyer: String = "me", shop: String = "Sri Stores") -> ActivityOrder {
        ActivityOrder(id: id, buyerId: buyer, status: status, deliveryMode: mode, shop: shop)
    }

    @Test func aRideShowsWhereItStands() {
        let cases: [(RideStatus, Int, String, Bool)] = [
            (.searching, 3, "Finding a driver", false),
            (.noDriver, 3, "No driver accepted yet", false),
            (.matched, 4, "Driver on the way · 4 min", false),
            (.matched, 0, "Driver on the way · under a minute", false),
            (.matched, -1, "Driver on the way", false),
            (.arrived, 3, "Your driver is here", true),
            (.inRide, 3, "On your trip", false),
            (.completed, 3, "Pay ₹180", true),
        ]
        for (status, eta, text, needs) in cases {
            let items = activityItems(ride: ride(status, eta: eta), orders: [], me: "me")
            #expect(items.count == 1)
            #expect(items.first?.status == text)
            #expect(items.first?.title == "Ride to Indiranagar")
            #expect(items.first?.id == "ride")
            #expect(items.first?.needsYou == needs)
            #expect(items.first?.target == .ride(status))
            #expect(items.first?.systemImage == VehicleKind.auto.systemImage)
        }
    }

    @Test func aPaidOrCancelledRideLeavesThePill() {
        #expect(activityItems(ride: ride(.paid), orders: [], me: "me").isEmpty)
        #expect(activityItems(ride: ride(.cancelled), orders: [], me: "me").isEmpty)
        #expect(activityItems(ride: nil, orders: [], me: "me").isEmpty)
    }

    @Test func anOpenOrderShowsItsStateAndOpensItsPage() {
        func one(_ status: String, _ mode: String) -> ActivityItem? { activityItems(ride: nil, orders: [order("o1", status, mode: mode)], me: "me").first }
        #expect(one("PLACED", "MARKETPLACE")?.status == "Waiting for Sri Stores to accept")
        #expect(one("ACCEPTED", "SHIP")?.status == "Accepted, getting ready to ship")
        #expect(one("ACCEPTED", "PICKUP")?.status == "Accepted, being prepared")
        #expect(one("READY", "PICKUP")?.status == "Ready to collect")
        #expect(one("READY", "PICKUP")?.needsYou == true)
        #expect(one("READY", "MARKETPLACE")?.status == "Ready, a rider is on the way")
        #expect(one("READY", "MARKETPLACE")?.needsYou == false)
        #expect(one("PICKED_UP", "MARKETPLACE")?.status == "On its way to you")
        #expect(one("SHIPPED", "SHIP")?.status == "Shipped")
        let o = one("PLACED", "MARKETPLACE")
        #expect(o?.title == "Order from Sri Stores"); #expect(o?.id == "order-o1"); #expect(o?.target == .order("o1")); #expect(o?.systemImage == "storefront.fill")
    }

    @Test func finishedOrdersAndOtherPeoplesOrdersAreLeftOut() {
        let orders = [order("a", "DELIVERED"), order("b", "REJECTED"), order("c", "CANCELLED"), order("d", "PLACED", buyer: "someone"), order("e", "SHIPPED")]
        #expect(activityItems(ride: nil, orders: orders, me: "me").map(\.id) == ["order-e"])
        // Not signed in as anyone yet: every open order stays.
        #expect(activityItems(ride: nil, orders: orders, me: nil).map(\.id) == ["order-d", "order-e"])
    }

    @Test func theRideComesFirstThenOrdersInTheirOrder() {
        let items = activityItems(ride: ride(.inRide), orders: [order("x", "PLACED", shop: "Cafe One"), order("y", "READY", mode: "PICKUP", shop: "Bakery Two")], me: "me")
        #expect(items.map(\.id) == ["ride", "order-x", "order-y"])
        #expect(items.map(\.title) == ["Ride to Indiranagar", "Order from Cafe One", "Order from Bakery Two"])
    }
}
