import SwiftUI
import BucksCore

/// Trip done: show the fare QR from the driver's uploaded UPI code (the customer's app also opens it by itself), or take cash.
/// What the customer taps on their phone is only their word; Bucks can't see the bank or the cash, so the driver checks and then
/// confirms for themselves, once, with the amount in front of them.
struct CloudPaymentPanel: View {
    let dr: DriverRide
    @Binding var cash: Bool
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    /// Deliveries: the amount at the door comes from the order (free delivery = 0, store-rider COD = the whole bill), not the fee.
    @State private var collect: Int?
    @State private var confirm = false

    private var d: Dispatch { session.dispatch }
    private var delivery: Bool { dr.kind == .bike }
    private var link: String? { d.paymentLink }
    private var amount: Int { collect ?? dr.fare }

    init(dr: DriverRide, cash: Binding<Bool>) {
        self.dr = dr; self._cash = cash
        self._collect = State(initialValue: dr.kind == .bike ? nil : dr.fare)
    }

    var body: some View {
        Group {
            if delivery && collect == 0 { nothingToCollect } else { collectPanel }
        }
        .task(id: dr.id) {
            if !d.paymentLinkLoaded { d.refreshPaymentLink() }
            if delivery { collect = (try? await d.task(dr.id))??.collect }
        }
    }

    private var nothingToCollect: some View {
        VStack(spacing: 0) {
            Text("Delivered · nothing to collect").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 8).padding(.bottom, 6)
            Muted("This order is already paid. Your ₹\(dr.fare) delivery fee comes from the shop.", align: .center)
            Spacer().frame(height: 20)
            DarkButton("Done") { session.driverPaid(method: "shop") }
        }
    }

    private var collectPanel: some View {
        let theyPaid = dr.paidWith
        let first = dr.customer.components(separatedBy: " ").first ?? dr.customer
        return VStack(spacing: 0) {
            Text(delivery ? "Delivered · collect ₹\(amount)" : "Total payable ₹\(amount)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 8).padding(.bottom, 6)
            if delivery && collect == nil { Muted("Checking what to collect…", align: .center) }
            if let theyPaid {
                PillWarn("\(first) says they paid by \(payWord(theyPaid))")
                Muted("Bucks can't see it. Check \(isCash(theyPaid) ? "you have the cash" : "your UPI app") before you continue.", align: .center).padding(.top, 6)
            } else {
                Muted("\(first) sees the amount on their phone and can pay by UPI or cash.", align: .center)
            }
            Spacer().frame(height: 14)
            if let link {
                let pay = upiPayLink(base: link, amountRupees: amount, note: "Bucks \(delivery ? "delivery" : "ride")")
                QRBox(text: pay, side: 200, label: "UPI QR for ₹\(amount)")
                if let p = upiPayee(link) { Muted("\(p.name) · \(p.address)").padding(.top, 6) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Muted(d.paymentLinkLoaded ? "No UPI QR on your account yet, so this customer pays in cash. Add your QR to get paid by UPI next time." : "Checking your payment QR…")
                    if d.paymentLinkLoaded { SmallButton("Add my UPI QR", tonal: true) { router.push(.paymentQr) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { cash.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "banknote").font(.system(size: 20)).foregroundStyle(BucksColor.good)
                    Text("Cash received").bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: cash ? "largecircle.fill.circle" : "circle").font(.system(size: 20)).foregroundStyle(cash ? BucksColor.primary : BucksColor.onSurfaceVariant)
                }
                .padding(14).contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(cash ? BucksColor.primary : BucksColor.outline, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 24)
            .accessibilityAddTraits(cash ? .isSelected : [])
            Spacer().frame(height: 20)
            DarkButton(cash ? "Cash received · continue" : "UPI received · continue", enabled: cash || link != nil || theyPaid != nil) { confirm = true }
            Muted("Nothing to collect yet? Wait for the customer; their payment shows up here.", align: .center).padding(.top, 8)
        }
        .bucksConfirm(isPresented: $confirm, title: cash ? "Did you receive ₹\(amount) in cash?" : "Did ₹\(amount) reach your UPI account?",
                      message: cash ? "Count it before you continue. This closes the payment step for this \(delivery ? "delivery" : "trip")."
                                    : "Look for it in your UPI app first. Bucks can't check your bank, and this closes the payment step for this \(delivery ? "delivery" : "trip").",
                      confirmTitle: cash ? "Yes, I have the cash" : "Yes, it arrived", cancelTitle: "Not yet") { session.driverPaid(method: cash ? "CASH" : "UPI") }
    }
}
