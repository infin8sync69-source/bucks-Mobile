import SwiftUI
import BucksCore
#if canImport(AudioToolbox)
import AudioToolbox
#endif

// MARK: - words the buyer and the shopkeeper see (port of OrderUi.kt)

/// "₹1,250".
func rupees(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","; f.usesGroupingSeparator = true; f.locale = Locale(identifier: "en_US")
    return "₹" + (f.string(from: NSNumber(value: n)) ?? String(n))
}

/// Short order id for receipts and UPI notes: the last 6 characters, upper case.
func shortOrderId(_ id: String) -> String { String(id.replacingOccurrences(of: "-", with: "").suffix(6)).uppercased() }

func deliveryModeLabel(_ mode: String) -> String {
    switch mode { case "STORE_RIDER": "Store's own rider"; case "PICKUP": "Pick up from the shop"; case "SHIP": "Shipped to an address"; default: "Delivery by a Bucks rider" }
}
func paymentLabel(_ payment: String) -> String { payment == "COD" ? "Cash on delivery" : "UPI" }

/// Buyer-facing status, in plain words.
func orderStatusLabel(_ status: String, _ mode: String = "MARKETPLACE") -> String {
    switch status {
    case "PLACED": "Waiting for the shop"
    case "ACCEPTED": "Accepted"
    case "READY": mode == "PICKUP" ? "Ready to collect" : "Packed"
    case "PICKED_UP": "On the way"
    case "SHIPPED": "Shipped"
    case "DELIVERED": mode == "PICKUP" ? "Collected" : "Delivered"
    case "REJECTED": "Not accepted"
    case "CANCELLED": "Cancelled"
    default: status.lowercased().prefix(1).uppercased() + status.lowercased().dropFirst()
    }
}
func orderDone(_ status: String) -> Bool { ["DELIVERED", "REJECTED", "CANCELLED"].contains(status) }
func orderLive(_ status: String) -> Bool { ["PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED"].contains(status) }

@ViewBuilder func OrderStatusPill(_ status: String, _ mode: String = "MARKETPLACE") -> some View {
    switch status {
    case "DELIVERED": PillGood(orderStatusLabel(status, mode))
    case "REJECTED", "CANCELLED": PillBad(orderStatusLabel(status, mode))
    case "PLACED": PillWarn(orderStatusLabel(status, mode))
    default: PillPurple(orderStatusLabel(status, mode))
    }
}

/// "2 × Toor dal, 1 × Rice" for list rows.
func orderLinesSummary(_ lines: [OrderLine]) -> String { lines.map { "\($0.qty) × \($0.name)" }.joined(separator: ", ") }

struct OrderLineRow: View {
    let line: OrderLine
    var body: some View {
        HStack {
            Text("\(line.name) × \(line.qty)").bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
            Text(rupees(line.price * line.qty)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
        }.padding(.vertical, 4)
    }
}

/// Subtotal, delivery fee (and who it is paid to) and what goes to the shop. A marketplace rider's fee is paid to the rider at the
/// door, never through the shop, so it is shown under the shop's amount instead of inside it. `forShop` words it for the shop owner or admin.
struct OrderTotals: View {
    let o: CloudOrderRow
    var forShop = false

    private var payTitle: String {
        if forShop { return o.payment == "COD" ? "Customer pays in cash" : "Customer pays you" }
        if o.payment == "COD" { return "To pay in cash" }
        return o.feeAtDoor > 0 ? "To pay the shop" : "To pay"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Muted("Items").frame(maxWidth: .infinity, alignment: .leading); Muted(rupees(o.subtotal)) }.padding(.top, 6)
            if o.deliveryMode == "SHIP" {
                HStack { Muted("Shipping").frame(maxWidth: .infinity, alignment: .leading); Muted(o.deliveryFee == 0 ? "Free" : rupees(o.deliveryFee)) }.padding(.top, 4)
            } else if o.deliveryMode != "PICKUP" {
                HStack {
                    Muted(o.feeAtDoor > 0 ? "Delivery fee · to the rider" : "Delivery fee").frame(maxWidth: .infinity, alignment: .leading)
                    Muted(o.feePaidBy == "VENDOR" ? "\(rupees(o.deliveryFee)) · \(forShop ? "paid by you" : "paid by the shop")" : rupees(o.deliveryFee))
                }.padding(.top, 4)
            }
            BucksDivider().padding(.top, 8)
            HStack {
                Text(payTitle).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Text(rupees(o.toShop)).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            }.padding(.top, 8)
            if o.feeAtDoor > 0 {
                Muted(forShop ? "The customer pays the rider's \(rupees(o.feeAtDoor)) fee to the rider at the door." : "+ \(rupees(o.feeAtDoor)) to the rider at the door (UPI or cash).").padding(.top, 4)
            } else if forShop && o.feePaidBy == "VENDOR" && o.deliveryMode == "MARKETPLACE" {
                Muted("Free delivery: hand the rider \(rupees(o.deliveryFee)) when they collect it.").padding(.top, 4)
            }
        }
    }
}

// MARK: - time

private let isoFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
private let isoPlain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

/// The date of a Postgres timestamp ("2025-01-02 10:11:12.345+00", "...+00:00" or "...Z"); nil when unreadable.
func orderDate(_ iso: String) -> Date? {
    var t = iso.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
    if t.isEmpty { return nil }
    let hasZone = t.hasSuffix("Z") || t.range(of: "[+-]\\d\\d(:?\\d\\d)?$", options: .regularExpression) != nil
    if !hasZone { t += "Z" }
    if t.range(of: "[+-]\\d\\d$", options: .regularExpression) != nil { t += ":00" }
    return isoFraction.date(from: t) ?? isoPlain.date(from: t)
}
/// Epoch milliseconds of a Postgres timestamp; 0 when unreadable.
func epochMillis(_ iso: String) -> Int64 { orderDate(iso).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0 }
func mmss(_ millis: Int64) -> String { let s = max(millis / 1000, 0); return String(format: "%d:%02d", s / 60, s % 60) }

/// "now", "2m", "3h", "Yesterday", "12 Mar" from an ISO timestamp.
func orderAgo(_ iso: String) -> String {
    guard let t = orderDate(iso) else { return "" }
    let s = max(Int(Date().timeIntervalSince(t)), 0)
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    if s < 172800 { return "Yesterday" }
    let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: t)
}

// MARK: - listing flags, UPI, alerts

extension JSONValue {
    /// A true/false switch inside a listing's `details` (stored as a boolean or the text "true").
    func flag(_ key: String) -> Bool {
        guard let v = self[key] else { return false }
        if let b = v.bool { return b }
        return v.string?.lowercased() == "true"
    }
}

/// Opens the UPI app chooser; false when no UPI app is installed.
@MainActor func openUpi(_ uri: String, completion: @escaping (Bool) -> Void) { openSystemURL(uri, completion: completion) }

/// A short ring and buzz for a new order while the inbox is open.
@MainActor func alertNewOrder() {
    #if os(iOS) && canImport(AudioToolbox)
    AudioServicesPlaySystemSound(1007)
    Haptics.success()
    #endif
}

// MARK: - timeline

/// PLACED -> ACCEPTED -> (READY) -> PICKED_UP -> DELIVERED, or a terminal REJECTED / CANCELLED with a plain explanation.
/// `forShop` words it for the shop; the buyer sees the pickup PIN while the rider is on the way to or at the shop, which is when
/// the rider calls for it (advance_task checks it at pick-up, not at the door).
struct OrderTimeline: View {
    let status: String
    let mode: String
    let task: TaskRow?
    var forShop = false
    var cancelledBy: String?
    /// The carrier of a shipped order, for the Shipped step.
    var carrier = ""
    var ringWindowS = 180

    var body: some View {
        if status == "REJECTED" || status == "CANCELLED" { terminal } else { steps }
    }

    private var terminal: some View {
        let byShop = cancelledBy == "SHOP"
        let head: String
        let detail: String
        if status == "REJECTED" {
            head = forShop ? "This order wasn't taken" : "The shop didn't take this order"
            detail = forShop ? "It was rejected or not accepted in time. The customer wasn't charged." : "Either they were too busy or they didn't respond in time. Nothing has been charged. Try another shop."
        } else if byShop {
            head = forShop ? "You cancelled this order" : "The shop cancelled this order"
            detail = forShop ? "If the customer already paid you by UPI, refund them." : "If you already paid by UPI, the shop owes you a refund. Call them if it hasn't reached you."
        } else {
            head = forShop ? "The customer cancelled this order" : "You cancelled this order"
            detail = forShop ? "They cancelled before you accepted, so nothing was charged." : "Nothing has been charged."
        }
        return BucksCard {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").font(.system(size: 22)).foregroundStyle(BucksColor.error)
                Text(head).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            }
            Muted(detail).padding(.top, 8)
        }
    }

    private var steps: some View {
        let pickup = mode == "PICKUP", ship = mode == "SHIP"
        let list: [(String, String)] = ship
            ? [("PLACED", "Order placed"), ("ACCEPTED", "Shop accepted"), ("SHIPPED", "Shipped"), ("DELIVERED", "Delivered")]
            : pickup
            ? [("PLACED", "Order placed"), ("ACCEPTED", "Shop accepted"), ("READY", "Ready to collect"), ("DELIVERED", "Collected")]
            : [("PLACED", "Order placed"), ("ACCEPTED", "Shop accepted"), ("PICKED_UP", "Rider picked it up"), ("DELIVERED", "Delivered")]
        let order = ["PLACED", "ACCEPTED", "READY", "PICKED_UP", "SHIPPED", "DELIVERED"]
        let at = max(order.firstIndex(of: status) ?? 0, 0)
        let cur = (!pickup && status == "READY") ? "ACCEPTED" : status
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, step in
                let idx = order.firstIndex(of: step.0) ?? 0
                StatusLine(step.1, detail: detail(step.0, pickup: pickup, ship: ship), done: idx < at && step.0 != cur, now: step.0 == cur, last: i == list.count - 1)
            }
        }
    }

    private func detail(_ key: String, pickup: Bool, ship: Bool) -> String {
        let via = carrier.trimmingCharacters(in: .whitespaces).isEmpty ? "the carrier" : carrier
        switch key {
        case "PLACED":
            if ship { return forShop ? "Accept or reject within 24 hours." : "The shop has 24 hours to accept." }
            return forShop ? "Accept or reject within 5 minutes." : "The shop has 5 minutes to accept."
        case "SHIPPED": return forShop ? "With \(via). Mark it delivered when it arrives, or the customer will confirm." : "On its way with \(via). Tap I received it when it arrives."
        case "ACCEPTED":
            if ship { return forShop ? "Pack it and tap Mark shipped with the carrier and tracking number." : "They're packing it. You'll get the tracking number when it ships." }
            if pickup { return forShop ? "Get it ready, then mark it ready to collect." : "They're getting it ready." }
            if forShop { return status == "READY" ? "Packed. Hand it to the rider; they enter the customer's PIN when collecting." : "A rider is being rung. Mark it packed when it's ready to hand over." }
            // A request still SEARCHING past the ring window has run out, even before the server's expiry has marked it (same rule as the delivery tracker).
            let stale = task?.status == "SEARCHING" && (secondsSince(task.map { $0.statusAt.isEmpty ? $0.createdAt : $0.statusAt } ?? "") ?? 0) >= ringWindowS
            let rider: String
            switch stale ? "NO_DRIVER" : task?.status {
            case nil: rider = "Finding a rider near the shop."
            case "SEARCHING": rider = "Ringing riders near the shop."
            case "NO_DRIVER": rider = "No rider free right now. Call the shop: they can send their own rider or cancel the order."
            case "CANCELLED": rider = "The delivery was cancelled. Call the shop to sort it out."
            case "ARRIVED": rider = "The rider is at the shop."
            default: rider = "A rider is on the way to the shop."
            }
            // The rider asks for the PIN at the shop (ARRIVED -> IN_PROGRESS), so it is shown until then and not after.
            let pin = task.flatMap { ["SEARCHING", "MATCHED", "ARRIVED"].contains($0.status) && !$0.pin.isEmpty ? $0.pin : nil }
            return (status == "READY" ? "Packed. " : "") + rider + (pin.map { " The rider will call you for PIN \($0) at the shop." } ?? "")
        case "READY": return forShop ? "Waiting for the customer. Tap Collected when they pick it up." : "Go to the shop and collect it."
        case "PICKED_UP": return forShop ? "On the way to the customer." : "On the way to you."
        default: return forShop ? "Done." : "Tell others how it went with a review on the shop's page."
        }
    }
}

/// A reason sheet that runs one order action: the buyer cancelling, the shop cancelling an accepted order, or the shop rejecting a new one.
/// `run` starts the action with the chosen code and reports back through `finish` (nil once the server agreed, otherwise its sentence).
/// The sheet closes only on success; a refusal stays in the sheet with its message and leaves the order where it is.
struct OrderReasonSheet: View {
    let title: String
    let message: String
    let reasons: [CancelReason]
    let requireReason: Bool
    let confirmLabel: String
    var reasonTitle = "Why are you cancelling?"
    let run: (_ code: String?, _ finish: @escaping (String?) -> Void) -> Void
    let onClose: () -> Void
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        CancelSheet(
            title: title, message: message, reasons: reasons, requireReason: requireReason, confirmLabel: confirmLabel,
            reasonTitle: reasonTitle, busy: busy, error: error,
            onConfirm: { code, _ in
                busy = true; error = nil
                run(code) { err in busy = false; if let err { error = err } else { onClose() } }
            }, onDismiss: onClose)
    }
}
