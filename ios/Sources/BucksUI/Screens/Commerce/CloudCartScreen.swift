import SwiftUI
import BucksCore

/// Cart and checkout for a cloud shop: lines with steppers, delivery mode, payment, drop label, then place_order.
/// The delivery fee is worked out by the server from the shop to the drop point and shown on the order page.
struct CloudCartScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var mode = "MARKETPLACE"
    @State private var payment = "UPI"
    @State private var dropLabel = ""
    @State private var hasStoreRiders = false
    @State private var confirmClear = false
    @State private var seeded = false

    private var commerce: CommerceStore { session.commerce }
    private var codAllowed: Bool { mode == "STORE_RIDER" && (commerce.shop?.details.flag("cod") ?? false) }
    private var freeDelivery: Bool { commerce.shop?.details.flag("free_delivery") ?? false }
    /// The phone's real position, nil until a fix arrives.
    private var here: LatLng? { session.hereKnown ? session.here : nil }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Cart", onBack: { router.pop() }) {
                    if commerce.shop != nil {
                        Button { confirmClear = true } label: {
                            Image(systemName: "trash").font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Empty the cart")
                    }
                }
                if let shop = commerce.shop { cart(shop) } else { empty }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .bucksConfirm(isPresented: $confirmClear, title: "Empty the cart?", message: "Everything from \(commerce.shop?.title ?? "this shop") will be removed.",
                      confirmTitle: "Empty it", cancelTitle: "Keep", destructive: true) { commerce.clear() }
        .cartSwitchDialog()
        .onAppear { if !seeded { seeded = true; dropLabel = session.me?.area ?? "" } }
        .task(id: commerce.shop?.id) {
            if let id = commerce.shop?.id { hasStoreRiders = (try? await commerce.hasStoreRiders(id)) ?? false } else { hasStoreRiders = false }
        }
        // Options that stop applying fall back to a valid choice, so the button never sends something the server rejects.
        .onChange(of: hasStoreRiders) { _, _ in settle() }
        .onChange(of: codAllowed) { _, _ in settle() }
    }

    private func settle() {
        if mode == "STORE_RIDER" && !hasStoreRiders { mode = "MARKETPLACE" }
        if payment == "COD" && !codAllowed { payment = "UPI" }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Avatar(systemImage: "bag.fill", size: 72)
            Text("Your cart is empty").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
            Muted("Open a shop near you and tap Add on what you need. One shop per order.", align: .center).padding(.top, 6)
            SmallButton("Find shops") { router.pop() }.fixedSize().padding(.top, 18)
        }
        .frame(maxWidth: .infinity).padding(Gutter).padding(.top, 60)
    }

    private func cart(_ shop: ListingRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ListRow(shop.title, subtitle: [shop.category, shop.area].filter { !$0.isEmpty }.joined(separator: " · ")) {
                    Avatar(systemImage: "storefront.fill", tinted: false)
                } trailing: { TrustBadge(up: shop.trustUp, down: shop.trustDown, compact: true) }
                BucksCard {
                    ForEach(commerce.lines) { l in line(shop, l) }
                    BucksDivider()
                    HStack {
                        Text("Items").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                        Text(rupees(commerce.subtotal)).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    }.padding(.top, 8)
                }.padding(.top, 6)

                FieldLabel("How do you want it?").padding(.top, 16)
                FlowLayout(spacing: 8) {
                    BucksChip("Delivery by a Bucks rider", selected: mode == "MARKETPLACE", systemImage: "bicycle") { mode = "MARKETPLACE" }
                    if hasStoreRiders { BucksChip("Store's own rider", selected: mode == "STORE_RIDER", systemImage: "storefront.fill") { mode = "STORE_RIDER" } }
                    BucksChip("I'll pick up", selected: mode == "PICKUP", systemImage: "figure.walk") { mode = "PICKUP" }
                }
                Notice(modeNotice(shop)).padding(.top, 12).padding(.bottom, 16)

                FieldLabel("Pay with")
                HStack(spacing: 8) {
                    BucksChip("Pay by UPI", selected: payment == "UPI", systemImage: "qrcode") { payment = "UPI" }
                    if codAllowed { BucksChip("Cash on delivery", selected: payment == "COD", systemImage: "banknote") { payment = "COD" } }
                }
                Muted(payNote).padding(.top, 8).padding(.bottom, 16)

                // Delivery needs the phone's real position: it is the rider's drop pin and what the fee is worked out from.
                if mode != "PICKUP" {
                    BucksField(Binding(get: { dropLabel }, set: { dropLabel = String($0.prefix(120)) }), label: "Deliver to", placeholder: "e.g. 4th block, near the park, 2nd floor")
                    if here == nil {
                        Notice("Turn on location to get it delivered. The rider needs your exact drop point, and the fee is worked out from it. You can still choose \"I'll pick up\".").padding(.bottom, 14)
                    } else {
                        Muted("Your current location is used as the drop point. The label helps the rider find the door.").padding(.bottom, 14)
                    }
                }
                PrimaryButton(commerce.placing ? "Placing…" : "Place order · \(rupees(commerce.subtotal))", enabled: canPlace) {
                    commerce.checkout(mode: mode, payment: payment, dropLabel: mode == "PICKUP" ? shop.area : dropLabel, drop: here) { id in
                        // The cart page is replaced by the order page, so back goes to where the cart was opened from.
                        router.path.removeAll { $0 == .cart }; router.push(.order(id))
                    }
                }
                Muted("\(shop.title) has 5 minutes to accept. If they don't, nothing is charged and you can try another shop.", align: .center)
                    .frame(maxWidth: .infinity).padding(.top, 12)
                Spacer().frame(height: 24)
            }.padding(Gutter)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var canPlace: Bool {
        !commerce.placing && !commerce.lines.isEmpty && (mode == "PICKUP" || (!dropLabel.trimmingCharacters(in: .whitespaces).isEmpty && here != nil))
    }

    private func line(_ shop: ListingRow, _ l: CommerceStore.Line) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(l.item.name).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                Muted(([rupees(l.item.price)] + (l.item.unit.isEmpty ? [] : [l.item.unit])).joined(separator: " · "))
            }.frame(maxWidth: .infinity, alignment: .leading)
            AddStepper(qty: l.qty) { d in commerce.add(shop, l.item, d) }
            Button { if let id = l.item.id { commerce.remove(id) } } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 36, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Remove \(l.item.name)")
            Text(rupees(l.amount)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(minWidth: 56, alignment: .trailing)
        }.padding(.vertical, 6)
    }

    private func modeNotice(_ shop: ListingRow) -> String {
        if mode == "PICKUP" { return "No delivery fee. Collect it from \(shop.title)" + (shop.area.isEmpty ? "" : " in \(shop.area)") + " once they mark it ready." }
        if freeDelivery { return "Free delivery: \(shop.title) pays the rider's fee on this order. You pay for the items only." }
        if mode == "STORE_RIDER" { return "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. It goes to \(shop.title) with the items, since it's their rider." }
        return "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. You pay it to the Bucks rider at the door (UPI or cash); the order page shows the amount."
    }

    private var payNote: String {
        if payment == "COD" { return "Pay the store's rider in cash when it arrives." }
        if mode == "MARKETPLACE" && !freeDelivery { return "You pay the shop for the items through your UPI app from the order page; the shop's QR is filled in for you. The rider's fee is paid to the rider." }
        return "You pay the shop through your UPI app from the order page; the shop's QR is filled in for you."
    }
}

/// Asks before replacing a cart from another shop; any screen that adds to the cart attaches it with `.cartSwitchDialog()`.
struct CartSwitchDialog: ViewModifier {
    @Environment(AppSession.self) private var session

    func body(content: Content) -> some View {
        let commerce: CommerceStore = session.commerce
        let p = commerce.pendingSwitch
        content.alert("Start a new cart?", isPresented: Binding(get: { commerce.pendingSwitch != nil }, set: { if !$0 { commerce.dismissSwitch() } })) {
            Button("Keep my cart", role: .cancel) { commerce.dismissSwitch() }
            Button("Replace cart") { commerce.confirmSwitch() }
        } message: {
            if let p {
                Text("Your cart has \(commerce.count) item\(commerce.count == 1 ? "" : "s") from \(commerce.shop?.title ?? "another shop"). One order goes to one shop, so adding \(p.item.name) from \(p.listing.title) empties it.")
            }
        }
    }
}

extension View {
    /// Shows the "Start a new cart?" question when an add came from another shop than the cart's.
    func cartSwitchDialog() -> some View { modifier(CartSwitchDialog()) }
}
