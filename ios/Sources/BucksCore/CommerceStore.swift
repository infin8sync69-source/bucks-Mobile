import Foundation
import Observation

/// Cloud commerce state: a cart over cloud items with one part per store, checkout through `place_order` / `place_order_ship` (one order
/// per store), the address book, the buyer's orders, and the vendor's live order inbox (port of the Android `Commerce`). Reached as
/// `session.commerce`. Actions are wrapped so a failure becomes a toast.
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
    /// One store's part of the cart. Each store becomes its own order with its own delivery, fee and payment.
    public struct StoreCart: Hashable, Sendable, Identifiable {
        public var listing: ListingRow
        public var lines: [Line]
        public var id: String { listing.id }
        public var amount: Int { lines.reduce(0) { $0 + $1.amount } }
        public var count: Int { lines.reduce(0) { $0 + $1.qty } }
    }
    /// How one store's order is delivered and paid; chosen per store in the cart.
    public struct Choice: Sendable {
        public var mode: String
        public var payment: String
        public var dropLabel: String
        public var address: AddressRow?
        public init(mode: String, payment: String, dropLabel: String, address: AddressRow? = nil) { self.mode = mode; self.payment = payment; self.dropLabel = dropLabel; self.address = address }
    }

    // MARK: cart

    /// The cart, by store, in the order the first item from each was added. Empty while nothing is in it.
    public private(set) var stores: [StoreCart] = []
    /// True while orders are being placed.
    public private(set) var placing = false
    /// Total number of pieces in the cart across every store, for the cart badge.
    public var count: Int { stores.reduce(0) { $0 + $1.count } }
    public var subtotal: Int { stores.reduce(0) { $0 + $1.amount } }

    public func qty(_ itemId: String) -> Int {
        for st in stores { if let l = st.lines.first(where: { $0.item.id == itemId }) { return l.qty } }
        return 0
    }

    /// Adds `delta` pieces of `item` from `listing` (negative removes). Stores mix freely: each keeps its own part of the cart.
    public func add(_ listing: ListingRow, _ item: ItemRow, _ delta: Int) {
        guard let id = item.id else { return }
        let si = stores.firstIndex { $0.listing.id == listing.id }
        let was = si.flatMap { stores[$0].lines.first { $0.item.id == id }?.qty } ?? 0
        let cap = item.stock.map { max($0, 0) } ?? 99
        let next = min(max(was + delta, 0), cap)
        if next == was {
            if delta > 0, let stock = item.stock, was >= stock { toast("Only \(stock) of \(item.name) in stock.") }
            return
        }
        var lines = si.map { stores[$0].lines } ?? []
        if next == 0 { lines.removeAll { $0.item.id == id } }
        else if let li = lines.firstIndex(where: { $0.item.id == id }) { lines[li].qty = next }
        else { lines.append(Line(item: item, qty: next)) }
        if let si {
            if lines.isEmpty { stores.remove(at: si) } else { stores[si].lines = lines }
        } else if !lines.isEmpty {
            stores.append(StoreCart(listing: listing, lines: lines))
        }
    }
    public func remove(_ itemId: String) {
        stores = stores.compactMap { st in
            var st = st; st.lines.removeAll { $0.item.id == itemId }
            return st.lines.isEmpty ? nil : st
        }
    }
    public func clearStore(_ listingId: String) { stores.removeAll { $0.listing.id == listingId } }
    public func clear() { stores = [] }

    /// True when the shop has its own delivery riders (listing_members with role STORE_RIDER is readable by everyone).
    public func hasStoreRiders(_ listingId: String) async throws -> Bool {
        try await Backend.shared.shopMembers(listingId).contains { $0.role == "STORE_RIDER" }
    }

    /// Places one order per store in the cart, each with its own delivery mode and payment, one after another. The drop is the phone's
    /// real location (nil until a fix arrives; only pick-up can be placed without it). A store whose order fails stays in the cart with
    /// its reason in a toast; the ones that went through are removed. `onDone` gets the ids of the orders placed, in order.
    public func checkoutAll(choices: [String: Choice], drop: LatLng?, onDone: @escaping ([String]) -> Void) {
        go {
            if self.placing { return }
            let todo = self.stores
            if todo.isEmpty { self.toast("Your cart is empty."); return }
            self.placing = true
            defer { self.placing = false }
            var placed: [String] = [], failed = 0, shipped = 0
            for st in todo {
                guard let c = choices[st.listing.id] else { continue }
                let ls = st.lines.compactMap { l in l.item.id.map { (itemId: $0, qty: l.qty) } }.filter { $0.qty > 0 }
                if ls.isEmpty { continue }
                do {
                    let id: String
                    if c.mode == "SHIP" {
                        guard let a = c.address else { failed += 1; self.toast("Add a delivery address for \(st.listing.title)'s order."); continue }
                        id = try await Backend.shared.placeShipOrder(listingId: st.listing.id, lines: ls, address: a.json, payment: c.payment)
                        shipped += 1
                    } else {
                        let fix: LatLng? = drop ?? (c.mode == "PICKUP" ? self.session.here : nil)
                        guard let at = fix else { failed += 1; self.toast("Turn on location to get \(st.listing.title)'s order delivered, or choose pick-up."); continue }
                        id = try await Backend.shared.placeOrder(listingId: st.listing.id, lines: ls, drop: at, dropLabel: c.dropLabel.trimmingCharacters(in: .whitespacesAndNewlines), payment: c.payment, mode: c.mode)
                    }
                    placed.append(id); self.clearStore(st.listing.id)
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1; self.toast("\(st.listing.title): \(friendlyError(error))") }
            }
            if !placed.isEmpty {
                self.toast(placed.count == 1 && shipped == 1 ? "Order placed. The shop has 24 hours to accept and ship it."
                           : placed.count == 1 ? "Order placed. The shop has 5 minutes to accept."
                           : "\(placed.count) orders placed, each delivered separately. Shops that ship have 24 hours to accept; local shops 5 minutes.")
                self.refreshMyOrders(); onDone(placed)
            } else if failed == 0 { self.toast("Nothing to place.") }
        }
    }

    // MARK: address book (delivery addresses for shipped orders)

    public private(set) var addresses: [AddressRow] = []
    public private(set) var addressesLoaded = false
    public func loadAddresses() { go { self.addresses = try await Backend.shared.addresses(); self.addressesLoaded = true } }
    /// Saves a new address or edits one (id set); `onSaved` gets the saved row so checkout can pick it.
    public func saveAddress(_ a: AddressRow, onSaved: @escaping (AddressRow) -> Void = { _ in }) {
        go {
            guard let me = self.session.me?.id else { return }
            let saved = try await Backend.shared.saveAddress(me: me, a)
            self.addresses = try await Backend.shared.addresses(); self.addressesLoaded = true
            self.toast("Address saved."); onSaved(saved)
        }
    }
    public func deleteAddress(_ id: String) {
        go { try await Backend.shared.deleteAddress(id); self.addresses.removeAll { $0.id == id }; self.toast("Address deleted.") }
    }

    // MARK: shipping (shop side and buyer side)

    /// The shop hands an accepted shipped order to a carrier; the customer is told and sees the tracking.
    public func shipOrder(_ id: String, carrier: String, tracking: String, url: String, then: @escaping () -> Void = {}) {
        act(id) {
            try await Backend.shared.shipOrder(id, carrier: carrier, tracking: tracking, url: url)
            self.toast("Marked shipped. The customer has been told."); await self.refreshVendorOrder(id); then()
        }
    }
    /// The buyer received it, or the shop delivered it itself: closes the shipped order.
    public func markDelivered(_ id: String) {
        act(id) {
            try await Backend.shared.markDelivered(id); self.toast("Marked delivered.")
            _ = try await self.order(id); self.refreshMyOrders(); await self.refreshVendorOrder(id)
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
        addresses = []; addressesLoaded = false
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
