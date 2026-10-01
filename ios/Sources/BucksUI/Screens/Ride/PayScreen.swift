import SwiftUI
import BucksCore

/// Arrived: pay through the driver's UPI QR or hand over cash.
struct PayScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group { if let r = session.dispatch.ride, let d = r.driver { content(r, d) } else { Color.clear } }
            .bucksBackground()
            .navigationBarBackButtonHidden(true)
            .bucksHideNavigationBar()
    }

    private func content(_ r: Ride, _ d: Driver) -> some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar()
                ScrollView {
                    VStack(spacing: 0) {
                        Avatar(systemImage: "flag.fill", size: 64).popIn()
                        Headline("Arrived at \(r.dest.name)").multilineTextAlignment(.center).padding(.top, 16)
                        Muted("\(r.dest.km) km with \(d.name)", align: .center)
                        BucksCard(tint: true) {
                            VStack(spacing: 4) {
                                Muted("Total payable", align: .center)
                                AnimatedAmount(r.fare, style: .displaySmall)
                            }.frame(maxWidth: .infinity)
                        }.padding(.vertical, 22)
                        CloudPayPanel(ride: r, driver: d)
                    }.padding(Gutter).padding(.top, 24)
                }
            }
        }
    }
}

/// Pay through the driver's UPI QR (their app opens with the fare filled in) or hand over cash; both tell the driver.
/// "Done · I paid" only appears once the rider has been to their UPI app and come back to Bucks, or chose cash: Bucks can't see the
/// payment itself, so the least it can do is not offer the confirmation before the rider has even tried.
private struct CloudPayPanel: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let ride: Ride; let driver: Driver

    @State private var contact: ContactRow?
    @State private var loaded = false
    @State private var upiOpened = false
    @State private var away = false
    @State private var returned = false
    @State private var confirmCash = false

    var body: some View {
        let paying = session.dispatch.paying
        let first = driver.name.components(separatedBy: " ")[0]
        let upi = contact?.upiUri.flatMap { $0.lowercased().hasPrefix("upi://pay") ? $0 : nil }
        VStack(spacing: 10) {
            if !loaded {
                HStack(spacing: 8) { ProgressView(); Muted("Checking how \(first) takes payments") }.frame(maxWidth: .infinity).frame(height: 52)
            } else if let upi {
                if let payee = upiPayee(upi) { Muted("UPI goes to \(payee.name) (\(payee.address))", align: .center) }
                DarkButton(upiOpened ? "Open UPI app again" : "Pay ₹\(ride.fare) by UPI", enabled: !paying) { openUPI(upi) }
                if upiOpened && !returned { Muted("Finish the payment in your UPI app, then come back here to confirm.", align: .center) }
                if upiOpened && returned { PrimaryButton(paying ? "Saving…" : "Done · I paid ₹\(ride.fare) by UPI", enabled: !paying) { session.dispatch.payRide(method: "UPI") } }
            } else {
                Notice("\(first) hasn't added a UPI QR yet. Pay ₹\(ride.fare) in cash.")
            }
            if loaded { GhostButton(paying ? "Saving…" : "Paid in cash", enabled: !paying) { confirmCash = true } }
            Muted("Only tap after you've paid. Your rider sees what you chose; Bucks can't check it.", align: .center)
        }
        .task(id: ride.id) {
            contact = (try? await session.dispatch.contact(taskId: ride.id)) ?? nil
            loaded = true
        }
        // Leaving Bucks for the UPI app and coming back is what "returned" means.
        .onChange(of: scenePhase) { _, p in
            if p == .active { if away { returned = true } } else if upiOpened { away = true }
        }
        .bucksConfirm(isPresented: $confirmCash, title: "Paid ₹\(ride.fare) in cash?", message: "\(first) will be told you paid in cash.",
                      confirmTitle: "Yes, paid", cancelTitle: "Not yet") { session.dispatch.payRide(method: "CASH") }
    }

    private func openUPI(_ upi: String) {
        let link = upiPayLink(base: upi, amountRupees: ride.fare, note: "Bucks ride")
        openSystemURL(link) { ok in
            if ok { upiOpened = true; away = false; returned = false }
            else { session.toast("No UPI app found on this phone. Pay in cash instead.") }
        }
    }
}
