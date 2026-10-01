import SwiftUI
import BucksCore

/// The order page. For the buyer: lines and totals, a status timeline, pay the shop by UPI, call the shop, track the delivery,
/// cancel while the shop hasn't answered. For the shop owner or an admin opening it from the inbox (the viewer is not the buyer):
/// the same order in the shop's words, with accept / reject / packed / collected, "Call <customer>" and cancel for an accepted
/// order no rider has taken. Follows the row live and also polls every 10 seconds; a failed load keeps retrying.
struct CloudOrderScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var missing = false
    /// The last load threw (no signal, timeout, token refresh) and nothing is cached yet: not the same as "no such order".
    @State private var loadFailed = false
    @State private var attempt = 0
    @State private var task: TaskRow?
    @State private var contact: OrderContactRow?
    @State private var confirmCancel = false
    @State private var confirmReject = false

    init(id: String) { self.id = id }

    private var commerce: CommerceStore { session.commerce }
    private var o: CloudOrderRow? { commerce.orders[id] }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Order", onBack: { router.pop() })
                if missing {
                    message("This order isn't here", "It may belong to another account. Your orders are under Account > Activity.", button: "Go back") { router.pop() }
                } else if o == nil && loadFailed {
                    message("Couldn't load this order", "Check your connection. We'll keep trying every few seconds.", button: "Try again") { loadFailed = false; attempt += 1 }
                } else if let o {
                    content(o)
                } else {
                    BucksLoader().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: "\(id)#\(attempt)") { await poll() }
        .task(id: id) { for await row in Backend.shared.liveOrder(orderId: id) { commerce.receive(row) } }
        .bucksConfirm(isPresented: $confirmCancel, title: "Cancel this order?", message: cancelMessage, confirmTitle: "Cancel order", cancelTitle: "Keep it", destructive: true) {
            if shopSide { commerce.updateOrderStatus(id, status: "CANCELLED") } else { commerce.cancelOrder(id) }
        }
        .bucksConfirm(isPresented: $confirmReject, title: "Reject this order?", message: "The customer will be told the shop couldn't take it. Rejecting often lowers how high the shop shows in search.",
                      confirmTitle: "Reject", cancelTitle: "Keep it", destructive: true) { commerce.respondOrder(id, accept: false) }
    }

    // MARK: loading

    /// First load, then a 10-second poll: status, the delivery task once accepted, and contact details while live.
    private func poll() async {
        while !Task.isCancelled {
            var row: CloudOrderRow?
            var failed = false
            do { row = try await commerce.order(id) } catch is CancellationError { return } catch { failed = true }
            // Only a query that worked and found no row means the order is not ours; a failure is retried on the next round.
            if !failed && row == nil && commerce.orders[id] == nil { missing = true; return }
            loadFailed = failed && commerce.orders[id] == nil
            if let cur = row ?? commerce.orders[id] {
                let mine = cur.buyerId == session.me?.id
                if mine && cur.deliveryMode != "PICKUP" && ["ACCEPTED", "READY", "PICKED_UP", "DELIVERED"].contains(cur.status) && task?.status != "COMPLETED" {
                    if let t = try? await commerce.taskForOrder(id) { task = t }
                }
                if hasContact(cur), let c = try? await commerce.contactFor(id) { contact = c }
                if orderDone(cur.status) && (!hasContact(cur) || contact != nil) { return }
            }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    /// Contact details are shared while the order is live or delivered, and after the shop cancelled an accepted one (for a refund).
    private func hasContact(_ o: CloudOrderRow) -> Bool { orderLive(o.status) || o.status == "DELIVERED" || (o.status == "CANCELLED" && o.cancelledBy == "SHOP") }

    // MARK: states

    private func message(_ title: String, _ detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            Muted(detail, align: .center).padding(.top, 6)
            SmallButton(button, action: action).fixedSize().padding(.top, 18)
        }.frame(maxWidth: .infinity).padding(Gutter).padding(.top, 60)
    }

    /// The order as the shop sees it (nil for the buyer): decides which cancel the dialog runs.
    private var shopOrder: CloudOrderRow? { o.flatMap { $0.buyerId != session.me?.id ? $0 : nil } }
    private var shopSide: Bool { shopOrder != nil }
    private var cancelMessage: String {
        guard let s = shopOrder else { return "The shop hasn't accepted it yet, so nothing is charged. Once they accept, it can't be cancelled." }
        let refund = s.payment == "UPI" ? " If they already paid you by UPI, refund them." : ""
        if s.deliveryMode == "PICKUP" { return "Use this when the customer isn't coming to collect it. They'll be told it was cancelled." + refund }
        return "Use this when no rider has taken the delivery; once a rider has it, it can't be cancelled." + (s.payment == "UPI" ? " If the customer already paid you by UPI, refund them." : "")
    }

    private func content(_ o: CloudOrderRow) -> some View {
        let title = commerce.titleOf(o.listingId)
        let acting = commerce.isActing(o.id)
        // Anyone but the buyer who can read the order runs the shop (owner, admin); they get the shop's view.
        let vendor = o.buyerId != session.me?.id
        let name = commerce.nameOf(o.buyerId)
        let customer: String? = (name != "…" && !name.isEmpty) ? name : nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { router.push(.listing(o.listingId)) } label: {
                    HStack(spacing: 0) {
                        Avatar(systemImage: "storefront.fill", tinted: false)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                            Muted("Order \(shortOrderId(o.id)) · \(orderAgo(o.createdAt)) · \(deliveryModeLabel(o.deliveryMode))")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                        Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant).accessibilityLabel("Open shop")
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if vendor {
                    HStack(spacing: 0) {
                        Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(BucksColor.onSurfaceVariant)
                        Text(" For \(customer ?? "a customer")").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    }.padding(.top, 12)
                }
                HStack(spacing: 8) { OrderStatusPill(o.status, o.deliveryMode); PillGrey(paymentLabel(o.payment)) }.padding(.top, 12)

                BucksCard {
                    ForEach(Array(o.lines.enumerated()), id: \.offset) { _, l in OrderLineRow(line: l) }
                    OrderTotals(o: o, forShop: vendor)
                    if o.deliveryMode != "PICKUP" && !o.dropLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(spacing: 0) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(BucksColor.onSurfaceVariant)
                            Muted(" \(o.dropLabel)")
                        }.padding(.top, 10)
                    }
                }.padding(.top, 14)

                SectionTitle("Progress").padding(.top, 22).padding(.bottom, 10)
                OrderTimeline(status: o.status, mode: o.deliveryMode, task: task, forShop: vendor, cancelledBy: o.cancelledBy, ringWindowS: session.dispatch.ringWindowS)

                if !vendor { buyerActions(o, title) } else { vendorActions(o, acting) }
                if hasContact(o) { callButton(vendor: vendor, title: title, customer: customer) }
                // Buyer: only before the shop answers. Shop: an accepted order no rider has taken (the server refuses once one has).
                if (!vendor && o.status == "PLACED") || (vendor && ["ACCEPTED", "READY"].contains(o.status)) {
                    BadButton(acting ? "Working…" : "Cancel order", enabled: !acting) { confirmCancel = true }.padding(.top, 10)
                }
                Spacer().frame(height: 24)
            }.padding(Gutter)
        }
    }

    @ViewBuilder private func buyerActions(_ o: CloudOrderRow, _ title: String) -> some View {
        // The shop is paid for what it sells (and its own rider's fee); a Bucks rider's fee goes to the rider at the door.
        let payable = o.payment == "UPI" && ["ACCEPTED", "READY", "PICKED_UP", "DELIVERED"].contains(o.status)
        let riderNote = o.feeAtDoor > 0 ? " The rider's \(rupees(o.feeAtDoor)) fee is paid to the rider at the door, not here." : ""
        if payable {
            let upi = contact?.upiUri
            PrimaryButton("Pay \(rupees(o.toShop)) by UPI", enabled: upi != nil) {
                guard let upi else { return }
                openUpi(upiPayLink(base: upi, amountRupees: o.toShop, note: "Bucks order \(shortOrderId(o.id))")) { ok in
                    if !ok { session.toast("No UPI app found on this phone. Pay the shop directly.") }
                }
            }.padding(.top, 18)
            Muted(upi != nil ? "Opens your UPI app with \(title)'s QR and the amount filled in.\(riderNote)"
                  : contact == nil ? "Getting the shop's payment details…"
                  : "\(title) hasn't added a UPI QR yet. Pay them directly when you receive the order.\(riderNote)", align: .center)
                .frame(maxWidth: .infinity).padding(.top, 6)
        } else if o.payment == "UPI" && o.status == "PLACED" {
            Muted("You can pay by UPI once \(title) accepts.\(riderNote)", align: .center).frame(maxWidth: .infinity).padding(.top, 18)
        } else if o.payment == "COD" && orderLive(o.status) {
            Notice("Keep \(rupees(o.total)) in cash ready for the store's rider.").padding(.top, 18)
        }
        if let t = task, t.status != "COMPLETED", t.status != "PAID", t.status != "CANCELLED" {
            TintButton("Track delivery") { router.push(.deliveryTrack(t.id)) }.padding(.top, 10)
        }
    }

    @ViewBuilder private func vendorActions(_ o: CloudOrderRow, _ acting: Bool) -> some View {
        switch o.status {
        case "PLACED":
            HStack(spacing: 8) {
                SmallButton(acting ? "Working…" : "Accept", enabled: !acting) { commerce.respondOrder(o.id, accept: true) }.frame(maxWidth: .infinity)
                SmallButton("Reject", tonal: true, enabled: !acting) { confirmReject = true }.frame(maxWidth: .infinity)
            }.padding(.top, 18)
        case "ACCEPTED":
            PrimaryButton(acting ? "Working…" : (o.deliveryMode == "PICKUP" ? "Ready to collect" : "Packed"), enabled: !acting) { commerce.updateOrderStatus(o.id, status: "READY") }.padding(.top, 18)
        case "READY":
            if o.deliveryMode == "PICKUP" {
                PrimaryButton(acting ? "Working…" : "Collected", enabled: !acting) { commerce.updateOrderStatus(o.id, status: "DELIVERED") }.padding(.top, 18)
            }
        default: EmptyView()
        }
    }

    private func callButton(vendor: Bool, title: String, customer: String?) -> some View {
        let phone = contact?.phone
        let who: String
        if vendor { who = (phone != nil ? customer : nil) ?? "customer" } else { who = phone != nil ? title : "shop" }
        return GhostButton("Call \(who)", enabled: phone != nil) { if let phone { dial(phone) } }.padding(.top, 10)
    }
}
