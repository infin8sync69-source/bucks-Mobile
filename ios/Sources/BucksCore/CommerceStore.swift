import Foundation
import Observation

/// Cloud commerce state: a single-shop cart over cloud items, checkout through `place_order`, the buyer's orders,
/// and the vendor's live order inbox (port of the Android `Commerce`). Reached as `session.commerce`.
/// Actions are wrapped so a failure becomes a toast.
@MainActor @Observable
public final class CommerceStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    /// One cart line: a cloud item and how many of it.
    public struct Line: Hashable, Sendable, Identifiable {
        public var item: ItemRow
        public var qty: Int
        public var id: String { item.id ?? item.name }
        public var amount: Int { item.price * qty }
    }
    /// An add() for a different shop than the cart holds; the UI asks before replacing the cart.
    public struct PendingSwitch: Hashable, Sendable {
        public var listing: ListingRow
        public var item: ItemRow
        public var delta: Int
    }

    // MARK: cart

    /// The shop the cart belongs to; nil while the cart is empty.
    public private(set) var shop: ListingRow?
    public private(set) var lines: [Line] = []
    public private(set) var pendingSwitch: PendingSwitch?
    /// True while an order is being placed.
    public private(set) var placing = false
    /// Total number of pieces in the cart, for the cart badge.
    public var count: Int { lines.reduce(0) { $0 + $1.qty } }
    public var subtotal: Int { lines.reduce(0) { $0 + $1.amount } }

    public func qty(_ itemId: String) -> Int { lines.first { $0.item.id == itemId }?.qty ?? 0 }

    /// Adds `delta` pieces (negative removes). One shop at a time: adding from another shop sets `pendingSwitch` instead of changing anything.
    public func add(_ listing: ListingRow, _ item: ItemRow, _ delta: Int) {
        guard let id = item.id else { return }
        if let cur = shop, cur.id != listing.id, !lines.isEmpty {
            if delta > 0 { pendingSwitch = PendingSwitch(listing: listing, item: item, delta: delta) }
            return
        }
        let next = max(qty(id) + delta, 0)
        if next == 0 { lines.removeAll { $0.item.id == id } }
        else if let i = lines.firstIndex(where: { $0.item.id == id }) { lines[i].qty = next }
        else { lines.append(Line(item: item, qty: next)) }
        shop = lines.isEmpty ? nil : listing
    }
    public func remove(_ itemId: String) {
        lines.removeAll { $0.item.id == itemId }
        if lines.isEmpty { shop = nil }
    }
    /// The user agreed to drop the old shop's cart and start with the item they just tapped.
    public func confirmSwitch() {
        guard let p = pendingSwitch else { return }
        pendingSwitch = nil; clear(); add(p.listing, p.item, p.delta)
    }
    public func dismissSwitch() { pendingSwitch = nil }
    public func clear() { lines = []; shop = nil; pendingSwitch = nil }

    /// True when the shop has its own delivery riders (listing_members with role STORE_RIDER is readable by everyone).
    public func hasStoreRiders(_ listingId: String) async throws -> Bool {
        try await Backend.shared.shopMembers(listingId).contains { $0.role == "STORE_RIDER" }
    }

    /// Places the order with the drop at `drop`, the phone's real position (nil until a fix arrives). Delivery needs it:
    /// the rider's map and the fee are worked out from it, so without one only pick-up can be placed. The server prices the lines and adds the delivery fee.
    public func checkout(mode: String, payment: String, dropLabel: String, drop: LatLng?, onPlaced: @escaping (String) -> Void) {
        go {
            guard let s = self.shop else { self.toast("Your cart is empty."); return }
            let ls = self.lines.compactMap { l in l.item.id.map { (itemId: $0, qty: l.qty) } }.filter { $0.qty > 0 }
            if ls.isEmpty { self.toast("Your cart is empty."); return }
            let at: LatLng
            if let drop { at = drop }
            else if mode == "PICKUP" { at = self.session.here }
            else { self.toast("Turn on location to get it delivered, or choose pick-up."); return }
            if self.placing { return }
            self.placing = true
            defer { self.placing = false }
            let id = try await Backend.shared.placeOrder(listingId: s.id, lines: ls, drop: at, dropLabel: dropLabel.trimmingCharacters(in: .whitespacesAndNewlines), payment: payment, mode: mode)
            self.clear(); self.toast("Order placed. \(s.title) has 5 minutes to accept.")
            self.refreshMyOrders(); onPlaced(id)
        }
    }

    // MARK: my orders (buyer)

    public private(set) var myOrders: [OrderRow] = []
    /// False until the first load finishes, so the empty state is not shown while loading.
    public private(set) var myOrdersLoaded = false
    /// Listing id -> title, for order lists.
    public private(set) var listingTitles: [String: String] = [:]
    /// Order id -> the latest full row seen, shared by the order page and the lists.
    public private(set) var orders: [String: CloudOrderRow] = [:]

    public func refreshMyOrders() {
        go {
            guard let me = self.session.me else { return }
            let rows = try await Backend.shared.myOrders(me: me.id)
            if self.session.me?.id != me.id { return }
            self.myOrders = rows; self.myOrdersLoaded = true
            await self.titlesFor(rows.map(\.listingId))
        }
    }
    public func titlesFor(_ ids: [String]) async {
        var seen = Set<String>()
        let missing = ids.filter { listingTitles[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty, let rows = try? await Backend.shared.listingsByIds(missing) else { return }
        for r in rows { listingTitles[r.id] = r.title }
    }
    public func titleOf(_ listingId: String) -> String { listingTitles[listingId] ?? "Shop" }

    /// Names of the people behind some profile ids (the session's name cache).
    public func namesFor(_ ids: [String]) async {
        var seen = Set<String>()
        let missing = ids.filter { session.names[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty, let rows = try? await Backend.shared.profiles(missing) else { return }
        for r in rows { session.names[r.id] = r.name }
    }
    public func nameOf(_ id: String) -> String { session.names[id] ?? "…" }

    /// Loads one order with its lines, caches it in `orders` and returns it (nil when it is not mine or does not exist).
    @discardableResult
    public func order(_ id: String) async throws -> CloudOrderRow? {
        guard let o = try await Backend.shared.orderDetail(id) else { return nil }
        orders[id] = o; await titlesFor([o.listingId]); await namesFor([o.buyerId])
        return o
    }
    /// A row pushed by the live feed.
    public func receive(_ o: CloudOrderRow) { orders[o.id] = o }
    public func loadOrder(_ id: String) { go { _ = try await self.order(id) } }
    public func taskForOrder(_ orderId: String) async throws -> TaskRow? { try await Backend.shared.taskForOrder(orderId) }
    public func contactFor(_ orderId: String) async throws -> OrderContactRow? { try await Backend.shared.contactForOrder(orderId) }
    public func cancelOrder(_ id: String, then: @escaping () -> Void = {}) {
        act(id) {
            try await Backend.shared.cancelOrder(id); self.toast("Order cancelled. Nothing to pay.")
            _ = try await self.order(id); self.refreshMyOrders(); then()
        }
    }

    // MARK: vendor inbox

    public private(set) var vendorOrders: [CloudOrderRow] = []
    public private(set) var vendorLoaded = false
    /// Goes up each time a new PLACED order arrives live while the inbox is open; the screen plays a sound on change.
    public private(set) var newOrderTick = 0
    @ObservationIgnored private var liveJob: Task<Void, Never>?
    @ObservationIgnored private var liveListing: String?

    /// Loads a shop's orders (newest first) and follows them live until `stopOrders`.
    public func ordersFor(_ listingId: String) {
        if liveListing != listingId { stopOrders(); vendorOrders = []; vendorLoaded = false }
        go {
            let rows = try await Backend.shared.vendorOrders(listingId: listingId)
            self.vendorOrders = rows; self.vendorLoaded = true
            await self.namesFor(rows.map(\.buyerId)); for o in rows { self.orders[o.id] = o }
        }
        if liveListing == listingId, liveJob != nil { return }
        stopOrders()
        liveListing = listingId
        liveJob = Task { [weak self] in
            for await o in Backend.shared.liveOrders(listingId: listingId) { await self?.merge(o) }
        }
    }
    private func merge(_ o: CloudOrderRow) async {
        let known = vendorOrders.contains { $0.id == o.id }
        vendorOrders = ([o] + vendorOrders.filter { $0.id != o.id }).sorted { $0.createdAt > $1.createdAt }
        orders[o.id] = o
        await namesFor([o.buyerId])
        if !known && o.status == "PLACED" { newOrderTick += 1 }
    }
    public func stopOrders() { liveJob?.cancel(); liveJob = nil; liveListing = nil }

    /// Sign-out and account deletion: nothing of this person's cart, orders or shop inbox stays for the next account on the phone.
    public func signedOut() {
        stopOrders(); clear(); placing = false
        myOrders = []; myOrdersLoaded = false; listingTitles = [:]; orders = [:]
        vendorOrders = []; vendorLoaded = false; actingOn = []
    }

    /// Owner or admin accepts (which creates the delivery task) or rejects a PLACED order.
    public func respondOrder(_ id: String, accept: Bool) {
        act(id) {
            try await Backend.shared.respondOrder(id, accept: accept)
            self.toast(accept ? "Accepted. The customer can see it is on the way." : "Rejected. The customer has been told.")
            await self.refreshVendorOrder(id)
        }
    }
    /// READY for any accepted order; DELIVERED only for pick-up orders once collected; CANCELLED when no rider has it (or the buyer never came).
    public func updateOrderStatus(_ id: String, status: String) {
        act(id) {
            try await Backend.shared.updateOrderStatus(id, status: status)
            self.toast(status == "READY" ? "Marked ready." : status == "CANCELLED" ? "Order cancelled. The customer has been told." : "Marked as collected. Thanks!")
            await self.refreshVendorOrder(id)
        }
    }
    private func refreshVendorOrder(_ id: String) async {
        guard let o = try? await Backend.shared.orderDetail(id) else { return }
        orders[id] = o; vendorOrders = vendorOrders.map { $0.id == id ? o : $0 }
    }

    // MARK: actions

    /// Orders with an action in flight (accept, reject, packed, collected, cancel): their buttons are off, so a second tap can't fire it twice.
    public private(set) var actingOn: Set<String> = []
    public func isActing(_ orderId: String) -> Bool { actingOn.contains(orderId) }

    private func toast(_ m: String) { session.toast(m) }
    private func go(_ block: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { toast(friendlyError(error)) }
        }
    }
    /// One action per order at a time. Whatever went wrong (a lost answer, "cannot go from X to Y"), the order is read again so the screen shows its real status.
    private func act(_ id: String, _ block: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            if actingOn.contains(id) { return }
            actingOn.insert(id)
            defer { actingOn.remove(id) }
            do { try await block() }
            catch is CancellationError {}
            catch {
                toast(friendlyError(error))
                await refreshVendorOrder(id); _ = try? await order(id)
            }
        }
    }
}
