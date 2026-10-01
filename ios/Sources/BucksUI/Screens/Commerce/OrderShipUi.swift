import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Shipped orders (OrderShipUi.kt): the shop marks an accepted order shipped with a carrier and tracking; both sides see the shipment
// and where it goes.

/// Couriers a shop is likely to use; "Other" asks for a name, "Self delivery" means the shop delivers it itself.
private let carriers = ["Delhivery", "DTDC", "Blue Dart", "India Post", "Ecom Express", "XpressBees", "Shadowfax", "Self delivery", "Other"]

/// The shop hands an accepted order to a carrier: which one, the tracking number and (optionally) a link the customer can open.
struct ShipSheet: View {
    var onShip: (_ carrier: String, _ tracking: String, _ url: String) -> Void
    @State private var pick = "Delhivery"
    @State private var other = ""
    @State private var tracking = ""
    @State private var url = ""

    private var carrier: String { pick == "Other" ? other.trimmingCharacters(in: .whitespaces) : pick }
    private var urlOk: Bool {
        let u = url.trimmingCharacters(in: .whitespaces)
        return u.isEmpty || u.range(of: "^https?://\\S+$", options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Mark as shipped").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("The customer is told and sees the carrier and tracking number.").padding(.top, 4).padding(.bottom, 8)
                FieldLabel("Carrier")
                FlowLayout(spacing: 8) { ForEach(carriers, id: \.self) { c in BucksChip(c, selected: pick == c) { pick = c } } }
                Spacer().frame(height: 12)
                if pick == "Other" { BucksField(Binding(get: { other }, set: { other = String($0.prefix(60)) }), label: "Carrier name", placeholder: "e.g. Local courier") }
                if pick != "Self delivery" {
                    BucksField(Binding(get: { tracking }, set: { tracking = String($0.prefix(60)) }), label: "Tracking number", placeholder: "Optional but helps the customer")
                    BucksField(Binding(get: { url }, set: { url = String($0.prefix(300)) }), label: "Tracking link (optional)", placeholder: "https://…", keyboard: .url)
                    if !urlOk { Muted("The link must start with http:// or https://").padding(.bottom, 8) }
                } else {
                    Muted("You'll deliver it yourself, so no tracking number is needed. Mark it delivered once it reaches them.").padding(.bottom, 8)
                }
                PrimaryButton("Mark shipped", enabled: !carrier.isEmpty && urlOk) {
                    let selfDelivery = pick == "Self delivery"
                    onShip(carrier, selfDelivery ? "" : tracking.trimmingCharacters(in: .whitespaces), selfDelivery ? "" : url.trimmingCharacters(in: .whitespaces))
                }
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

/// Carrier and tracking for a shipped order, with a Copy button and a link that opens the carrier's tracking page.
struct ShipmentCard: View {
    let o: CloudOrderRow
    @Environment(AppSession.self) private var session
    var body: some View {
        if o.shipped && !o.carrier.isEmpty {
            BucksCard {
                HStack(spacing: 12) {
                    Image(systemName: "truck.box.fill").foregroundStyle(BucksColor.primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(o.carrier.caseInsensitiveCompare("Self delivery") == .orderedSame ? "Delivered by the shop" : "Shipped with \(o.carrier)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        if !o.trackingNo.isEmpty { Muted("Tracking \(o.trackingNo)") }
                        if let at = o.shippedAt { Muted("Shipped \(discoverAgo(at))") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !o.trackingNo.isEmpty || !o.trackingUrl.isEmpty {
                    HStack(spacing: 8) {
                        if !o.trackingNo.isEmpty { SmallButton("Copy number", tonal: true) { copy(o.trackingNo); session.toast("Tracking number copied") }.fixedSize() }
                        if !o.trackingUrl.isEmpty { SmallButton("Track shipment") { openSystemURL(o.trackingUrl) }.fixedSize() }
                    }.padding(.top, 10)
                }
            }
        }
    }
    private func copy(_ s: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = s
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

/// Where a shipped order goes, as the shop writes it on the parcel and the buyer confirms it.
struct ShipToCard: View {
    let o: CloudOrderRow
    var body: some View {
        if o.shipped && !o.shipToText.isEmpty {
            BucksCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(BucksColor.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ship to").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Text(o.shipToText).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
