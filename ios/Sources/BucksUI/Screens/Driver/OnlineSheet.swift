import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#endif

extension Dispatch {
    /// The vehicle the online switch drives: the one on duty, else my first checked (ACTIVE) one.
    var cloudVehicle: VehicleRow? { (online ? vehicle : nil) ?? vehicles.first { $0.status == "ACTIVE" } }
    /// A vehicle the server hasn't activated yet (nothing checked to go online with), so Home can say why there is no button.
    var waitingVehicle: VehicleRow? { vehicles.isEmpty || vehicles.contains { $0.status == "ACTIVE" } ? nil : vehicles.first }
}

/// Round "bucks" button shown on Home for a driver; the rings around it say "you're live and receiving".
struct OnlineFab: View {
    var live: Bool
    var action: () -> Void
    var body: some View {
        Group {
            if live { PulseRings(periodMs: 2600) { core } } else { core }
        }.frame(width: 104, height: 104)
    }
    private var core: some View {
        Button(action: action) {
            BucksWordmark(color: BucksColor.onPrimary, height: 15)
                .frame(width: 72, height: 72).background(Circle().fill(BucksColor.primary)).shadow(color: .black.opacity(0.28), radius: 8, y: 4)
        }.buttonStyle(.plain).accessibilityLabel("Go online")
    }
}

/// Going online or offline with my checked vehicle, today's earnings, and the payment QR.
struct OnlineSheet: View {
    var onEarnings: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var alertProblem: RingAlert.Problem?
    @State private var switching = false

    private var d: Dispatch { session.dispatch }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(d.online ? "You're online" : "You're offline").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("Only online listings receive rides, orders and service requests.")
                if let cv = d.cloudVehicle { vehicleRow(cv).padding(.vertical, 14) } else { Spacer().frame(height: 14) }
                if session.mockLocation { Notice("Mock location is on. Turn it off to take rides.").padding(.bottom, 10) }
                // A request rings a driver outside the app only through a notification: say so when they can't.
                if d.online, let p = alertProblem {
                    VStack(alignment: .leading, spacing: 8) {
                        Notice(p.message)
                        #if canImport(UIKit)
                        SmallButton("Notification settings", tonal: true) { driverOpenURL(UIApplication.openSettingsURLString) }
                        #endif
                    }.padding(.bottom, 10)
                }
                BucksCard(onTap: { dismiss(); onEarnings() }, padding: 14) {
                    Text("₹\(session.earningsToday)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    Muted("Today")
                }
                if d.cloudVehicle != nil { paymentQrRow.padding(.top, 12) }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .task { await refreshAlert(); if !d.paymentLinkLoaded { d.refreshPaymentLink() } }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await refreshAlert() } } }
    }

    private func refreshAlert() async { alertProblem = await RingAlert.problem() }

    private func vehicleRow(_ v: VehicleRow) -> some View {
        let k = v.vehicleKind
        let detail = d.online ? (k == .bike ? "Receiving delivery requests" : "Receiving ride requests") : (switching ? "Going online…" : "Offline")
        return HStack(spacing: 12) {
            Avatar(systemImage: k.systemImage, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(v.model.isEmpty ? k.label : v.model) · \(v.plate)").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                Muted(detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ListingSwitch(Binding(get: { d.online }, set: { on in
                guard on != d.online else { return }
                switching = on
                Task { await session.setOnline(on, plate: v.plate); switching = false }
            }))
        }
    }

    /// Drivers are paid through the UPI QR they upload; the rider's app opens it with the fare filled in.
    private var paymentQrRow: some View {
        let link = d.paymentLink
        let text = link == nil && !d.paymentLinkLoaded ? "Checking…"
            : link == nil ? "Not set. Customers pay in cash until you add one."
            : (link.flatMap { upiPayee($0) }.map { "Customers pay \($0.name) by UPI" } ?? "UPI set up")
        return Button { dismiss(); router.push(.paymentQr) } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode").font(.system(size: 22)).foregroundStyle(BucksColor.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Payment QR").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(text)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
