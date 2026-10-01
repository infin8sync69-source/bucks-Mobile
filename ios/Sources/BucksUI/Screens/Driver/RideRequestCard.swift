import SwiftUI
import BucksCore

/// The incoming request card, shown over whichever screen a driver on duty is on. Accept before the countdown runs out; the bar on the
/// button drains with it while the label stays a solid, readable colour. The request details are announced when they appear; the
/// countdown is not (it would be read every second). `busy`: the claim is with the server.
struct RideRequestCard: View {
    var dr: DriverRide
    var busy: Bool
    var onAccept: () -> Void
    var onDecline: () -> Void

    private var urgent: Bool { dr.secondsLeft <= 5 }
    /// Bikes carry goods only, so a bike request is always a delivery: pick up at the shop, drop at the customer.
    private var delivery: Bool { dr.kind == .bike }
    private var summary: String { delivery ? "New delivery request" : "New \(dr.kind.label) ride request" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BrandPill(delivery ? "Delivery" : dr.kind.label)
                Spacer()
                Button(action: onDecline) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Decline this request")
            }
            // Never taller than the screen: the details scroll, the Accept button stays put.
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }
            }
            .padding(.trailing, 12)
            acceptButton.padding(.trailing, 12)
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.top, 4).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(BucksColor.surface).shadow(color: .black.opacity(0.22), radius: 12, y: 4))
        .overlay(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).strokeBorder(BucksColor.primary, lineWidth: 2))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .popIn()
        .onAppear { announce() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnimatedAmount(dr.fare, prefix: "₹", style: .headlineSmall)
            if delivery { Text("Delivery for \(driverBeforeDot(dr.pickupAt))").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 4) }
            HStack(spacing: 10) {
                Avatar(initials: initials(dr.customer), size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(dr.customer).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    TrustBadge(up: dr.customerTrust.up, down: dr.customerTrust.down, compact: true)
                }
            }.padding(.vertical, 8)
            RoutePoints(pickup: delivery ? "Collect at \(dr.pickupAt)" : dr.pickupAt, drop: delivery ? "Deliver to \(dr.dropAt)" : dr.dropAt)
            HStack(spacing: 24) {
                Muted("\(delivery ? "Shop" : "Pickup"): \(driverMetres(dr.pickupKm))")
                Muted("Drop: \(dr.km)km")
            }.padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
    }

    /// The whole button is the accept target; the thin bar along its foot is the countdown, so the label keeps a solid background.
    private var acceptButton: some View {
        Button {
            Haptics.tap(); onAccept()
        } label: {
            ZStack(alignment: .bottomLeading) {
                Text(busy ? "Accepting…" : "Accept · \(dr.secondsLeft)s").bucks(.labelLarge).foregroundStyle(BucksColor.onPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                GeometryReader { g in
                    Rectangle().fill(BucksColor.onPrimary.opacity(0.75))
                        .frame(width: g.size.width * CGFloat(min(max(Double(dr.secondsLeft) / 15, 0), 1)), height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.linear(duration: 1), value: dr.secondsLeft)
                }.accessibilityHidden(true)
            }
            .frame(height: 48).frame(maxWidth: .infinity)
            .background(BucksColor.primary)
            .clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .breathe(amount: urgent ? 0.035 : 0.015, period: urgent ? 0.45 : 0.9)
        .accessibilityLabel(busy ? "Accepting" : "Accept this request")
    }

    private func announce() {
        AccessibilityNotification.Announcement(summary).post()
    }
}
