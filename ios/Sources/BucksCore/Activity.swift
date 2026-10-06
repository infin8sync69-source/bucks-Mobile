import Foundation

// The customer's open ride and orders, for the pill on Home (port of ActivityFab.kt's `activityItems`), and the two flags that decide whether
// a provider sees the round Online button or the small "Go online" chip (BucksViewModel.providerOnline and canGoOnline).

/// One thing the customer is waiting on: a ride or an order. `target` says which screen opens it.
public struct ActivityItem: Hashable, Sendable, Identifiable {
    public enum Target: Hashable, Sendable {
        /// The ride screen for this status (Home maps it with `Route.ride(for:)`).
        case ride(RideStatus)
        /// The order page of this order id.
        case order(String)
    }
    /// "ride" or "order-<id>".
    public var id: String
    /// SF Symbol name.
    public var systemImage: String
    public var title: String
    public var status: String
    public var target: Target
    /// The person has to do something now (the driver is here, pay, collect): the pill breathes.
    public var needsYou: Bool
    public init(id: String, systemImage: String, title: String, status: String, target: Target, needsYou: Bool = false) {
        self.id = id; self.systemImage = systemImage; self.title = title; self.status = status; self.target = target; self.needsYou = needsYou
    }
}

/// The parts of a ride the pill needs.
public struct ActivityRide: Hashable, Sendable {
    public var status: RideStatus
    public var fare: Int
    /// Minutes until pick-up; -1 means no position yet.
    public var etaMin: Int
    public var destName: String
    public var kind: VehicleKind
    public init(status: RideStatus, fare: Int, etaMin: Int, destName: String, kind: VehicleKind) {
        self.status = status; self.fare = fare; self.etaMin = etaMin; self.destName = destName; self.kind = kind
    }
}

/// The parts of one of my orders the pill needs; `shop` is the shop's title.
public struct ActivityOrder: Hashable, Sendable {
    public var id: String
    public var buyerId: String
    public var status: String
    public var deliveryMode: String
    public var shop: String
    public init(id: String, buyerId: String, status: String, deliveryMode: String, shop: String) {
        self.id = id; self.buyerId = buyerId; self.status = status; self.deliveryMode = deliveryMode; self.shop = shop
    }
}

/// Order states that are still moving; once delivered, rejected or cancelled the order leaves the activity pill.
public let openOrderStatuses: Set<String> = ["PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED"]

/// The open ride (if any) first, then every open order of mine, oldest list order kept. `me` nil keeps every order in the list.
public func activityItems(ride: ActivityRide?, orders: [ActivityOrder], me: String?) -> [ActivityItem] {
    var items: [ActivityItem] = []
    if let r = ride {
        let text: String?
        switch r.status {
        case .searching: text = "Finding a driver"
        case .noDriver: text = "No driver accepted yet"
        case .matched: text = "Driver on the way" + (r.etaMin < 0 ? "" : r.etaMin == 0 ? " · under a minute" : " · \(r.etaMin) min")
        case .arrived: text = "Your driver is here"
        case .inRide: text = "On your trip"
        case .completed: text = "Pay ₹\(r.fare)"
        case .paid, .cancelled: text = nil
        }
        if let text {
            items.append(ActivityItem(id: "ride", systemImage: r.kind.systemImage, title: "Ride to \(r.destName)", status: text, target: .ride(r.status),
                                      needsYou: r.status == .arrived || r.status == .completed))
        }
    }
    for o in orders where openOrderStatuses.contains(o.status) && (me == nil || o.buyerId == me) {
        let pickup = o.deliveryMode == "PICKUP"
        let text: String
        switch o.status {
        case "PLACED": text = "Waiting for \(o.shop) to accept"
        case "ACCEPTED": text = o.deliveryMode == "SHIP" ? "Accepted, getting ready to ship" : "Accepted, being prepared"
        case "READY": text = pickup ? "Ready to collect" : "Ready, a rider is on the way"
        case "PICKED_UP": text = "On its way to you"
        case "SHIPPED": text = "Shipped"
        default: text = o.status.lowercased()
        }
        items.append(ActivityItem(id: "order-\(o.id)", systemImage: "storefront.fill", title: "Order from \(o.shop)", status: text, target: .order(o.id),
                                  needsYou: o.status == "READY" && pickup))
    }
    return items
}

/// Which listings of mine take work: a live shop or pro profile (drivers have their vehicle, assets take no requests).
public func isWorkListing(_ l: ListingRow) -> Bool { l.status == "LIVE" && (l.kind == "BUSINESS" || l.kind == "SKILL") }

public extension AppSession {
    /// My open ride and orders as the Home pill lists them. Reads the ride from dispatch and the orders Home keeps refreshing.
    var activity: [ActivityItem] {
        let ride = dispatch.ride.map { ActivityRide(status: $0.status, fare: $0.fare, etaMin: $0.etaMin, destName: $0.dest.name, kind: $0.kind) }
        let orders = commerce.myOrders.map { ActivityOrder(id: $0.id, buyerId: $0.buyerId, status: $0.status, deliveryMode: $0.deliveryMode, shop: commerce.titleOf($0.listingId)) }
        return activityItems(ride: ride, orders: orders, me: me?.id)
    }

    /// True while I'm online as anything that takes work: my vehicle on duty, or a live shop or pro listing that is switched on.
    /// The round Online button on Home shows only then.
    var providerOnline: Bool { dispatch.online || listings.listings.contains { isWorkListing($0) && $0.online } }

    /// Offline but able to go online (a checked vehicle, a live shop or pro listing): Home offers a small "Go online" chip instead of the button.
    var canGoOnline: Bool {
        !providerOnline && (dispatch.vehicles.contains { $0.status == "ACTIVE" } || listings.listings.contains { isWorkListing($0) })
    }
}
