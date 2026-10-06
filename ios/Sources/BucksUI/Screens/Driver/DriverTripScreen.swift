import SwiftUI
import BucksCore

/// Driver's active trip: to pick-up → PIN → drop → payment → rate customer.
struct DriverTripScreen: View {
    @Environment(AppSession.self) private var session
    var body: some View {
        if let dr = session.dispatch.driverRide { TripBody(dr: dr).id(dr.id) }
    }
}

private struct TripBody: View {
    let dr: DriverRide
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var pin = ""
    @State private var cash = false
    @State private var stars = 0
    @State private var cancel = false
    @State private var endAsk = false
    @State private var road = DriverRoadRoute()

    private var d: Dispatch { session.dispatch }
    private var delivery: Bool { dr.kind == .bike }
    private var working: Bool { d.busy || d.handingBack }

    private var me: LatLng { dr.driver ?? Geo.center }
    private var pickup: LatLng { dr.pickup ?? me }
    private var drop: LatLng { dr.drop ?? me }
    private func lerp(_ a: LatLng, _ b: LatLng, _ t: Double) -> LatLng { LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t) }
    /// From, to and where the car is drawn.
    private var leg: (from: LatLng, to: LatLng, car: LatLng) {
        switch dr.status {
        case .toPickup: (me, pickup, lerp(me, pickup, dr.progress))
        case .arrived: (pickup, pickup, pickup)
        default: (pickup, drop, lerp(pickup, drop, dr.progress))
        }
    }
    private var travelling: Bool { let l = leg; return l.from != l.to && l.car != l.to }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if dr.status != .done { mapArea }
                panel(maxHeight: geo.size.height * 0.75)
            }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .bucksConfirm(isPresented: $endAsk, title: delivery ? "Hand over the order here?" : "End the ride here?",
                      message: delivery ? "Only end the trip once the customer has their order. Then you collect any payment due." : "The customer is asked to pay ₹\(dr.fare) once you end the ride. Only end it at the drop point.",
                      confirmTitle: delivery ? "Yes, delivered" : "End ride", cancelTitle: "Not yet") { d.driverNext() }
        // Handing a trip back needs a reason (the customer or shop hears it); the sheet closes only once the server has agreed.
        .sheet(isPresented: $cancel) { DriverCancelSheet(delivery: delivery) { cancel = false } }
        // The field clears once the trip has really started, so a wrong PIN stays for a retry.
        .onChange(of: dr.status) { _, s in
            if s == .inRide { pin = "" }
            if s != .toPickup && s != .arrived { cancel = false }   // no hand-back once the trip has started
        }
        .task(id: "\(Int(leg.car.lat * 500)),\(Int(leg.car.lng * 500)),\(Int(leg.to.lat * 500)),\(Int(leg.to.lng * 500)),\(travelling)") {
            await road.load(from: travelling ? leg.car : nil, to: travelling ? leg.to : nil)
        }
    }

    // MARK: map

    private var mapArea: some View {
        let l = leg
        return ZStack(alignment: .topTrailing) {
            BucksMap(pins: [MapPin(id: "me", at: l.car, title: "You", tint: driverMeColor, isMe: true), MapPin(id: "to", at: l.to, title: "", tint: BucksColor.primary)],
                     route: travelling ? (road.route?.points ?? [l.car, l.to]) : [])
            // Turn-by-turn inside Bucks (the Maps screen starts guiding straight away).
            if l.from != l.to {
                SmallButton(road.route.map { "Navigate · \($0.minutes) min" } ?? "Navigate") {
                    openMapsTo(router, name: dr.status == .toPickup ? dr.pickupAt : dr.dropAt, at: l.to, autoStart: true)
                }
                    .fixedSize().padding(12)
            }
        }.frame(maxHeight: .infinity)
    }

    // MARK: panel

    /// Natural height (so the map keeps the rest), scrolling when it would not fit (large text, small phones); the payment step fills the screen.
    private func panel(maxHeight: CGFloat) -> some View {
        let body = VStack(spacing: 0) { content }.frame(maxWidth: .infinity).padding(20)
        return Group {
            if dr.status == .done { ScrollView { body }.frame(maxHeight: .infinity, alignment: .top) }
            else { ViewThatFits(in: .vertical) { body; ScrollView { body } }.frame(maxHeight: maxHeight) }
        }
        .frame(maxWidth: .infinity)
        .background(UnevenRoundedRectangle(topLeadingRadius: BucksRadius.sheet, topTrailingRadius: BucksRadius.sheet, style: .continuous)
            .fill(BucksColor.surface).shadow(color: .black.opacity(0.18), radius: 12, y: -2).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder private var content: some View {
        switch dr.status {
        case .toPickup: toPickup
        case .arrived: arrived
        case .inRide: inRide
        case .done: CloudPaymentPanel(dr: dr, cash: $cash)
        case .rate: rate
        case .ringing: EmptyView()
        }
    }

    private func noPhone() { session.toast("The customer's number isn't available yet. Try again in a moment.") }
    private func messageBar() -> some View {
        MessageBar(hint: "Message your customer", onCall: { dr.customerPhone.isEmpty ? noPhone() : driverDial(dr.customerPhone) },
                   onMessage: { dr.customerPhone.isEmpty ? noPhone() : driverSMS(dr.customerPhone) })
    }
    private func textButton(_ title: String, tint: Color = BucksColor.primary, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).bucks(.labelLarge).foregroundStyle(enabled ? tint : tint.opacity(0.4)).padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(!enabled)
    }

    private var toPickup: some View {
        let km = driverMetres(dr.pickupKm * (1 - dr.progress))
        let mins = max(1, Int((1 - dr.progress) * dr.pickupKm * 4))
        return VStack(spacing: 0) {
            Text(delivery ? "Delivery for \(driverBeforeDot(dr.pickupAt))" : dr.customer).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            if delivery {
                let rest = driverAfterDot(dr.pickupAt)
                Muted("Order for \(dr.customer)\(rest.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " · \(rest)")").padding(.top, 2)
            }
            HStack(spacing: 20) { Muted("\(mins) min"); Muted("\(delivery ? "Shop" : "Pickup"): \(km)") }.padding(.top, 4).padding(.bottom, 14)
            messageBar()
            HStack {
                textButton(delivery ? "Cancel delivery" : "Cancel ride", tint: BucksColor.error, enabled: !working) { cancel = true }
                Spacer()
                textButton(working ? "Working…" : (delivery ? "I'm at the shop" : "I've arrived"), enabled: !working) { d.driverNext() }
            }.padding(.top, 8)
        }
    }

    private var arrived: some View {
        let left = max(pinTries - dr.pinAttempts, 0)
        return VStack(spacing: 0) {
            Text(delivery ? "Enter the pickup PIN" : "Enter customer's PIN").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            // No auto-submit on the fourth digit: a typo would cost one of the five tries. "Confirm PIN" sends it, as Android's keyboard Done / button do.
            PinBoxes(value: Binding(get: { pin }, set: { if !dr.pinLocked { pin = $0 } }))
                .padding(.top, 20).padding(.bottom, 8)
            // Wrong PINs keep the boxes filled and count down; the fifth locks the trip (the server says so) and only a hand-back is left.
            if dr.pinAttempts > 0 {
                Text(dr.pinLocked ? "Too many wrong PINs. This trip is locked: hand it back so another rider can take it." : "That PIN didn't match. \(left) \(left == 1 ? "try" : "tries") left.")
                    .bucks(.bodySmall).foregroundStyle(BucksColor.error).multilineTextAlignment(.center).padding(.bottom, 8)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Muted(delivery ? "Call the customer for their 4-digit PIN before you leave the shop; it confirms you have their order." : "Ask the customer to read out the 4-digit PIN on their screen.", align: .center).padding(.bottom, 14)
            messageBar()
            DarkButton(d.busy ? "Checking…" : "Confirm PIN", enabled: pin.count == 4 && !working && !dr.pinLocked) { d.driverNext(pin: pin) }.padding(.top, 14)
            // The server lets a trip go back to other riders until the PIN is in.
            textButton(delivery ? "Can't collect it? Hand back" : "Customer not here? Hand back", tint: BucksColor.error, enabled: !working) { cancel = true }.padding(.top, 4)
        }
    }

    private var inRide: some View {
        VStack(spacing: 0) {
            Text(dr.customer).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted(dr.progress >= 1 ? "Arrived at destination" : "On the way to \(dr.dropAt)").padding(.top, 4)
            Muted(dr.progress >= 1 ? "Dropping off" : "\(String(format: "%.1f", (1 - dr.progress) * dr.km)) km left").padding(.bottom, 14)
            messageBar().padding(.bottom, 14)
            DarkButton(working ? "Working…" : (delivery ? "Delivered · end trip" : "End ride"), enabled: !working) { endAsk = true }
        }
    }

    private var rate: some View {
        VStack(spacing: 0) {
            Text("Rate your customer").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Avatar(initials: initials(dr.customer), size: 48).padding(.top, 8)
            Text(dr.customer).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 6)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { i in
                    Button { stars = i } label: {
                        Image(systemName: i <= stars ? "star.fill" : "star").font(.system(size: 30))
                            .foregroundStyle(i <= stars ? BucksColor.onSurface : BucksColor.onSurfaceVariant).frame(width: 48, height: 48)
                    }.buttonStyle(.plain).accessibilityLabel("\(i) star\(i > 1 ? "s" : "")")
                }
            }.padding(.vertical, 14)
            DarkButton("Submit", enabled: stars > 0) { session.driverRateCustomer(stars: stars) }
        }
    }
}

/// Handing a ride or delivery back through `release_task`: a reason is required so the customer or shop hears why, and it counts against
/// the driver's record. A refusal from the server is shown in the sheet (it covers the toasts) and leaves the trip and the sheet where they are.
private struct DriverCancelSheet: View {
    let delivery: Bool
    let onClose: () -> Void
    @Environment(AppSession.self) private var session
    @State private var busy = false
    @State private var stats: CancelStats?
    @State private var error: String?

    var body: some View {
        let n = stats?.driverDay ?? 0
        return CancelSheet(
            title: delivery ? "Hand this delivery back?" : "Hand this ride back?",
            message: "The \(delivery ? "order" : "customer") goes to the next rider. Cancelling after accepting counts against your recommendations.",
            reasons: CancelReasons.driver, requireReason: true, confirmLabel: delivery ? "Cancel delivery" : "Cancel ride", keepLabel: "Keep it",
            nudge: n >= 2 ? "You've handed back \(n) trips today. Customers and shops rely on riders who finish what they accept." : nil, busy: busy, error: error,
            onConfirm: { code, note in
                busy = true; error = nil
                Task { let err = await session.driverHandBack(reason: code, note: note); busy = false; if let err { error = err } else { onClose() } }
            }, onDismiss: onClose)
        .task { stats = try? await Backend.shared.myCancelStats() }
    }
}
