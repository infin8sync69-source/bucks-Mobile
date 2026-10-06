import SwiftUI
import BucksCore

/// The shop's order inbox: live list of orders for one listing. New orders show a 5-minute countdown with Accept / Reject;
/// accepted ones show their status, "Call customer" and, for pick-up orders, Ready / Collected. Rings when a new order lands.
struct VendorOrdersScreen: View {
    let listingId: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var filter = "New"
    @State private var rejectFor: CloudOrderRow?
    @State private var shipFor: CloudOrderRow?
    @State private var now = Int64(Date().timeIntervalSince1970 * 1000)
    @State private var seenTick = 0

    init(listingId: String) { self.listingId = listingId }

    private var commerce: CommerceStore { session.commerce }
    private var title: String { commerce.titleOf(listingId) }

    var body: some View {
        let all = commerce.vendorOrders
        let newOnes = all.filter { $0.status == "PLACED" }
        let active = all.filter { ["ACCEPTED", "READY", "PICKED_UP", "SHIPPED"].contains($0.status) }
        let done = all.filter { orderDone($0.status) }
        let shown = filter == "New" ? newOnes : filter == "Active" ? active : done
        return ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Orders · \(title)", onBack: { router.pop() }) {
                    Button { commerce.ordersFor(listingId) } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Refresh")
                }
                HStack(spacing: 8) {
                    BucksChip(newOnes.isEmpty ? "New" : "New · \(newOnes.count)", selected: filter == "New", systemImage: "bell.badge.fill") { filter = "New" }
                    BucksChip(active.isEmpty ? "Active" : "Active · \(active.count)", selected: filter == "Active", systemImage: "box.truck.fill") { filter = "Active" }
                    BucksChip("Done", selected: filter == "Done", systemImage: "checkmark") { filter = "Done" }
                    Spacer(minLength: 0)
                }.padding(.horizontal, Gutter).padding(.vertical, 6)
                paymentNotice
                if !commerce.vendorLoaded {
                    BucksLoader().frame(maxWidth: .infinity).padding(.top, 80)
                } else if shown.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(shown) { o in card(o) }
                            Spacer().frame(height: 24)
                        }.padding(.horizontal, Gutter).padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        // A reason is required; the sheet closes only once the server agreed to the rejection.
        .sheet(item: $rejectFor) { o in
            OrderReasonSheet(title: "Reject this order?",
                             message: "\(commerce.nameOf(o.buyerId)) will be told the shop couldn't take it. Rejecting often lowers how high \(title) shows in search.",
                             reasons: CancelReasons.shopReject, requireReason: true, confirmLabel: "Reject order", reasonTitle: "Why can't you take it?", run: { code, finish in
                commerce.respondOrder(o.id, accept: false, reason: code, done: finish)
            }, onClose: { rejectFor = nil })
        }
        .sheet(item: $shipFor) { o in ShipSheet { c, t, u in shipFor = nil; commerce.shipOrder(o.id, carrier: c, tracking: t, url: u) } }
        .onAppear { seenTick = commerce.newOrderTick; commerce.ordersFor(listingId) }
        .onDisappear { commerce.stopOrders() }
        .task(id: listingId) { await commerce.titlesFor([listingId]) }
        // Buyers pay by UPI to the owner's payment QR; tell the owner when there isn't one.
        .task(id: listingId) { if session.dispatch.enabled && !session.dispatch.paymentLinkLoaded { session.dispatch.refreshPaymentLink() } }
        // The clock for the countdowns, plus a 30-second reload in case the live feed drops.
        .task(id: listingId) {
            var n = 0
            while !Task.isCancelled {
                now = Int64(Date().timeIntervalSince1970 * 1000)
                n += 1
                if n % 30 == 0 { commerce.ordersFor(listingId) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        // Sound and buzz when a new PLACED order arrives while this screen is open (not for the first load).
        .onChange(of: commerce.newOrderTick) { _, tick in
            guard tick != seenTick else { return }
            seenTick = tick; alertNewOrder()
            if filter != "New" { session.toast("New order for \(title).") }
        }
    }

    /// Admins can't add a payment QR for the owner, so only the owner is asked.
    @ViewBuilder private var paymentNotice: some View {
        let d: Dispatch = session.dispatch
        if d.enabled && d.paymentLinkLoaded && d.paymentLink == nil && isOwner {
            VStack(alignment: .leading, spacing: 0) {
                Notice("Customers can't pay these orders by UPI: you haven't added your UPI QR yet. Add it and their Pay button fills in your account and the amount.")
                SmallButton("Add payment QR") { router.push(.paymentQr) }.fixedSize().padding(.top, 8)
            }.padding(.horizontal, Gutter).padding(.vertical, 4)
        }
    }
    /// True when I own this listing (admins and staff do not).
    private var isOwner: Bool { session.listings.listing(listingId).map { $0.ownerId == session.me?.id } ?? false }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Avatar(systemImage: filter == "New" ? "bell" : "shippingbox.fill", size: 72)
            Text(filter == "New" ? "No new orders" : filter == "Active" ? "Nothing in progress" : "No finished orders yet").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
            Muted(filter == "New" ? "Keep this screen open while the shop is online: new orders ring here. Local orders must be accepted within 5 minutes, shipped orders within 24 hours."
                  : filter == "Active" ? "Accepted orders stay here until they're delivered or collected." : "Delivered, rejected and cancelled orders are kept here.", align: .center).padding(.top, 6)
        }.frame(maxWidth: .infinity).padding(Gutter).padding(.top, 40)
    }

    // MARK: card

    private func card(_ o: CloudOrderRow) -> some View {
        let buyer = commerce.nameOf(o.buyerId)
        let busy = commerce.isActing(o.id)
        return BucksCard(onTap: { router.push(.order(o.id)) }) {
            HStack(spacing: 0) {
                Avatar(initials: initials(buyer.isEmpty ? "?" : buyer), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(buyer).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("\(orderAgo(o.createdAt)) · \(shortOrderId(o.id))")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
                if o.status == "PLACED" {
                    let left = epochMillis(o.acceptBy) - now
                    if left <= 0 { PillBad("Time's up") }
                    else { Pill("Accept in \(left > 3_600_000 ? "\(left / 3_600_000)h \(left / 60_000 % 60)m" : mmss(left))", bg: left < 60_000 ? BucksColor.badTint : BucksColor.warnTint, fg: left < 60_000 ? BucksColor.bad : BucksColor.warn) }
                } else { OrderStatusPill(o.status, o.deliveryMode) }
            }
            Text(orderLinesSummary(o.lines)).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10)
            // What the customer pays the shop: a Bucks rider's fee goes to the rider, a store rider's fee comes to the shop.
            HStack(spacing: 0) {
                Text(rupees(o.toShop)).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                if o.deliveryMode != "PICKUP" && o.feePaidBy == "VENDOR" { Muted("  + \(rupees(o.deliveryFee)) rider fee paid by you") }
                else if o.deliveryMode == "STORE_RIDER" && o.deliveryFee > 0 { Muted("  incl. \(rupees(o.deliveryFee)) delivery") }
                Spacer(minLength: 8)
                PillGrey(paymentLabel(o.payment))
            }.padding(.top, 6)
            HStack(spacing: 0) {
                Image(systemName: o.deliveryMode == "SHIP" ? "truck.box.fill" : o.deliveryMode == "PICKUP" ? "figure.walk" : o.deliveryMode == "STORE_RIDER" ? "storefront.fill" : "bicycle")
                    .font(.system(size: 14)).foregroundStyle(BucksColor.onSurfaceVariant)
                Muted(" \(deliveryModeLabel(o.deliveryMode))" + (o.deliveryMode != "PICKUP" && !o.dropLabel.trimmingCharacters(in: .whitespaces).isEmpty ? " · \(o.dropLabel)" : "")
                      + (o.shipped && !o.carrier.isEmpty ? " · \(o.carrier)" + (o.trackingNo.isEmpty ? "" : " \(o.trackingNo)") : ""), maxLines: 1)
            }.padding(.top, 6)
            actions(o, busy)
            let payRider = o.deliveryMode == "MARKETPLACE" && o.feePaidBy == "VENDOR" ? " Free delivery: pay the rider \(rupees(o.deliveryFee)) when they collect it." : ""
            if o.shipped && o.status == "ACCEPTED" { Muted("Pack it, then tap Mark shipped with the carrier and tracking number.").padding(.top, 8) }
            if o.status == "ACCEPTED" && !["PICKUP", "SHIP"].contains(o.deliveryMode) { Muted("A rider is being rung. Mark it packed when it's ready to hand over.\(payRider)").padding(.top, 8) }
            if o.status == "READY" && !["PICKUP", "SHIP"].contains(o.deliveryMode) { Muted("Hand it to the rider. They enter the customer's PIN when collecting.\(payRider)").padding(.top, 8) }
        }
    }

    @ViewBuilder private func actions(_ o: CloudOrderRow, _ busy: Bool) -> some View {
        switch o.status {
        case "PLACED":
            HStack(spacing: 8) {
                SmallButton(busy ? "Working…" : "Accept", enabled: !busy) { commerce.respondOrder(o.id, accept: true) }.frame(maxWidth: .infinity)
                SmallButton("Reject", tonal: true, enabled: !busy) { rejectFor = o }.frame(maxWidth: .infinity)
            }.padding(.top, 12)
        case "ACCEPTED", "READY", "PICKED_UP", "SHIPPED":
            HStack(spacing: 8) {
                SmallButton("Call customer", tonal: true) { call(o) }.frame(maxWidth: .infinity)
                if o.shipped {
                    if o.status == "ACCEPTED" { SmallButton(busy ? "Working…" : "Mark shipped", enabled: !busy) { shipFor = o }.frame(maxWidth: .infinity) }
                    else if o.status == "SHIPPED" { SmallButton(busy ? "Working…" : "Mark delivered", enabled: !busy) { commerce.markDelivered(o.id) }.frame(maxWidth: .infinity) }
                } else if o.status == "ACCEPTED" {
                    SmallButton(busy ? "Working…" : (o.deliveryMode == "PICKUP" ? "Ready to collect" : "Packed"), enabled: !busy) { commerce.updateOrderStatus(o.id, status: "READY") }.frame(maxWidth: .infinity)
                } else if o.status == "READY" && o.deliveryMode == "PICKUP" {
                    SmallButton(busy ? "Working…" : "Collected", enabled: !busy) { commerce.updateOrderStatus(o.id, status: "DELIVERED") }.frame(maxWidth: .infinity)
                }
            }.padding(.top, 12)
        default: EmptyView()
        }
    }

    private func call(_ o: CloudOrderRow) {
        Task {
            let phone = (try? await commerce.contactFor(o.id))?.phone ?? ""
            if phone.trimmingCharacters(in: .whitespaces).isEmpty { session.toast("This customer hasn't shared a phone number.") } else { dial(phone) }
        }
    }
}
