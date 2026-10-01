import SwiftUI
import BucksCore

/// Cart and checkout (CloudCartScreen.kt): one section per shop, each its own order with its own delivery mode, fee and payment.
/// Local delivery (a Bucks rider or the shop's own) only inside the shop's delivery radius; farther away a shop that ships can send it to
/// an address from the address book; pick-up works from anywhere. The server prices every line and adds the fees.
struct CloudCartScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var modes: [String: String] = [:]
    @State private var payments: [String: String] = [:]
    @State private var hasRiders: [String: Bool] = [:]
    @State private var points: [String: LatLng] = [:]
    @State private var dropLabel = ""
    @State private var confirmClear = false
    @State private var seeded = false
    @State private var addressId: String?
    @State private var addressSheet = false

    private var commerce: CommerceStore { session.commerce }
    private var stores: [CommerceStore.StoreCart] { commerce.stores }
    /// The phone's real position, nil until a fix arrives.
    private var here: LatLng? { session.hereKnown ? session.here : nil }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Cart", onBack: { router.pop() }) {
                    if !stores.isEmpty {
                        Button { confirmClear = true } label: {
                            Image(systemName: "trash").font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Empty the cart")
                    }
                }
                if stores.isEmpty { empty } else { cart }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .bucksConfirm(isPresented: $confirmClear, title: "Empty the cart?",
                      message: stores.count > 1 ? "Everything from all \(stores.count) shops will be removed." : "Everything from \(stores.first?.listing.title ?? "this shop") will be removed.",
                      confirmTitle: "Empty it", cancelTitle: "Keep", destructive: true) { commerce.clear() }
        .onAppear { if !seeded { seeded = true; dropLabel = session.me?.area ?? "" } }
        .task(id: stores.map(\.listing.id)) {
            for id in stores.map(\.listing.id) {
                if hasRiders[id] == nil { hasRiders[id] = (try? await commerce.hasStoreRiders(id)) ?? false }
                if points[id] == nil, let p = try? await Backend.shared.listingPoint(id) { points[id] = p }
            }
            commerce.loadAddresses()
        }
        .sheet(isPresented: $addressSheet) {
            AddressSheet(selectedId: address?.id, startNew: commerce.addresses.isEmpty, onPick: { addressId = $0.id }, onDismiss: { addressSheet = false })
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Avatar(systemImage: "bag.fill", size: 72)
            Text("Your cart is empty").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
            Muted("Open a shop and tap Add on what you need. You can mix shops: each shop's items become their own order, delivered separately.", align: .center).padding(.top, 6)
            SmallButton("Find shops") { router.pop() }.fixedSize().padding(.top, 18)
        }
        .frame(maxWidth: .infinity).padding(Gutter).padding(.top, 60)
    }

    // MARK: rules per store

    /// A shop is "near" when it is inside its own delivery radius (5 km when it hasn't set one); farther away only shipping works.
    /// Until the position or the shop's location is known, treat it as near so the usual options show.
    private func near(_ st: CommerceStore.StoreCart) -> Bool {
        guard let here, let at = points[st.listing.id] else { return true }
        let radius = st.listing.details.str("delivery_radius_km").flatMap(Double.init) ?? 5
        return Geo.distanceKm(here, at) <= max(radius, 1)
    }
    private func ships(_ st: CommerceStore.StoreCart) -> Bool { st.listing.details.flag("ships_india") }
    private func num(_ st: CommerceStore.StoreCart, _ key: String) -> Int { st.listing.details.str(key).flatMap(Double.init).map { Int($0) } ?? 0 }
    /// What the shop charges to ship this part of the cart: its flat fee, free once the items reach its free-shipping line.
    private func shipFee(_ st: CommerceStore.StoreCart) -> Int {
        let above = num(st, "free_ship_above")
        return above > 0 && st.amount >= above ? 0 : num(st, "ship_fee")
    }
    private func modeOf(_ st: CommerceStore.StoreCart) -> String {
        let id = st.listing.id
        let m = modes[id] ?? ((!near(st) && ships(st)) ? "SHIP" : "MARKETPLACE")
        if m == "SHIP" && !ships(st) { return "MARKETPLACE" }
        if m == "STORE_RIDER" && hasRiders[id] != true { return "MARKETPLACE" }
        if m != "SHIP" && !near(st) && ships(st) { return "SHIP" }
        return m
    }
    private func paymentOf(_ st: CommerceStore.StoreCart) -> String {
        let p = payments[st.listing.id] ?? "UPI"
        let codOk = ["STORE_RIDER", "SHIP"].contains(modeOf(st)) && st.listing.details.flag("cod")
        return p == "COD" && !codOk ? "UPI" : p
    }
    /// A store that is too far and does not ship cannot be ordered from at all.
    private func blocked(_ st: CommerceStore.StoreCart) -> Bool { !near(st) && !ships(st) }
    private var address: AddressRow? {
        let list = commerce.addresses
        return list.first { $0.id == addressId } ?? list.first { $0.isDefault } ?? list.first
    }
    private var needsDrop: Bool { stores.contains { ["MARKETPLACE", "STORE_RIDER"].contains(modeOf($0)) } }
    private var needsAddress: Bool { stores.contains { modeOf($0) == "SHIP" } }
    private var grand: Int { commerce.subtotal + stores.filter { modeOf($0) == "SHIP" }.reduce(0) { $0 + shipFee($1) } }

    // MARK: the cart

    private var cart: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if stores.count > 1 {
                        Notice("\(stores.count) shops, so \(stores.count) separate orders and deliveries. Each has its own delivery fee, payment and time.").padding(.bottom, 12)
                    }
                    ForEach(Array(stores.enumerated()), id: \.element.id) { i, st in storeSection(st, index: i) }
                    if needsAddress {
                        Text("Ship to").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                        AddressCard(a: address) { addressSheet = true }
                        Spacer().frame(height: 14)
                    }
                    // Delivery needs the phone's real position: it is the rider's drop pin and what each fee is worked out from.
                    if needsDrop {
                        BucksField(Binding(get: { dropLabel }, set: { dropLabel = String($0.prefix(120)) }), label: "Deliver to", placeholder: "e.g. 4th block, near the park, 2nd floor")
                        if here == nil {
                            Notice("Turn on location to get it delivered. The rider needs your exact drop point, and the fee is worked out from it. You can still choose \"I'll pick up\".").padding(.bottom, 14)
                        } else {
                            Muted("Your current location is used as the drop point for every delivery. The label helps the rider find the door.").padding(.bottom, 14)
                        }
                    }
                    Spacer().frame(height: 12)
                }.padding(Gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 0) {
                PrimaryButton(commerce.placing ? "Placing…" : stores.count == 1 ? "Place order · \(rupees(grand))" : "Place \(stores.count) orders · \(rupees(grand))", enabled: canPlace) { place() }
                Muted(footNote, align: .center).frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal, Gutter).padding(.vertical, 12)
            .background(BucksColor.surface.shadow(.drop(color: .black.opacity(0.12), radius: 8, y: -2)), ignoresSafeAreaEdges: .bottom)
        }
    }

    private func storeSection(_ st: CommerceStore.StoreCart, index: Int) -> some View {
        let shop = st.listing, mode = modeOf(st), payment = paymentOf(st)
        let codAllowed = ["STORE_RIDER", "SHIP"].contains(mode) && shop.details.flag("cod")
        let freeDelivery = shop.details.flag("free_delivery")
        return VStack(alignment: .leading, spacing: 0) {
            Text(stores.count > 1 ? "Order \(index + 1) of \(stores.count)" : "Your order").bucks(.labelMedium).foregroundStyle(BucksColor.onSurfaceVariant).accessibilityAddTraits(.isHeader)
            ListRow(shop.title, subtitle: [shop.category, shop.area].filter { !$0.isEmpty }.joined(separator: " · ")) {
                Avatar(systemImage: "storefront.fill", tinted: false)
            } trailing: { TrustBadge(up: shop.trustUp, down: shop.trustDown, compact: true) }
            BucksCard {
                ForEach(st.lines) { l in line(shop, l) }
                BucksDivider()
                HStack {
                    Text("Items from \(shop.title)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                    Text(rupees(st.amount)).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                }.padding(.top, 8)
            }.padding(.top, 6)

            FieldLabel("How do you want it?").padding(.top, 16)
            if blocked(st) { Notice("\(shop.title) is too far for local delivery and doesn't ship. Remove it from the cart, or ask them to switch on shipping.").padding(.bottom, 8) }
            FlowLayout(spacing: 8) {
                if ships(st) { BucksChip("Ship to my address", selected: mode == "SHIP", systemImage: "truck.box.fill") { modes[shop.id] = "SHIP" } }
                if near(st) {
                    BucksChip("Delivery by a Bucks rider", selected: mode == "MARKETPLACE", systemImage: "bicycle") { modes[shop.id] = "MARKETPLACE" }
                    if hasRiders[shop.id] == true { BucksChip("Store's own rider", selected: mode == "STORE_RIDER", systemImage: "storefront.fill") { modes[shop.id] = "STORE_RIDER" } }
                    BucksChip("I'll pick up", selected: mode == "PICKUP", systemImage: "figure.walk") { modes[shop.id] = "PICKUP" }
                }
            }
            Notice(modeNotice(st, mode: mode, freeDelivery: freeDelivery)).padding(.top, 12).padding(.bottom, 12)
            if mode == "SHIP" {
                HStack {
                    Muted("Items \(rupees(st.amount)) + shipping \(shipFee(st) == 0 ? "free" : rupees(shipFee(st)))")
                    Text(rupees(st.amount + shipFee(st))).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                }.padding(.top, 8)
            }
            FieldLabel("Pay \(shop.title) with").padding(.top, 8)
            HStack(spacing: 8) {
                BucksChip("Pay by UPI", selected: payment == "UPI", systemImage: "qrcode") { payments[shop.id] = "UPI" }
                if codAllowed { BucksChip("Cash on delivery", selected: payment == "COD", systemImage: "banknote") { payments[shop.id] = "COD" } }
            }
            Muted(payNote(mode: mode, payment: payment, freeDelivery: freeDelivery)).padding(.top, 8)
            if index < stores.count - 1 { BucksDivider().padding(.top, 20) }
        }.padding(.bottom, 20)
    }

    private func line(_ shop: ListingRow, _ l: CommerceStore.Line) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(l.item.name).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                Muted(([rupees(l.item.price)] + (l.item.unit.isEmpty ? [] : [l.item.unit])).joined(separator: " · "))
            }.frame(maxWidth: .infinity, alignment: .leading)
            AddStepper(qty: l.qty) { d in commerce.add(shop, l.item, d) }
            Button { if let id = l.item.id { commerce.remove(id) } } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Remove \(l.item.name)")
            Text(rupees(l.amount)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(minWidth: 56, alignment: .trailing)
        }.padding(.vertical, 6)
    }

    private func modeNotice(_ st: CommerceStore.StoreCart, mode: String, freeDelivery: Bool) -> String {
        let shop = st.listing
        if mode == "SHIP" {
            let fee = shipFee(st), above = num(st, "free_ship_above")
            let days = shop.details.str("dispatch_days").map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : " Ships in \($0) days." } ?? ""
            return "Shipping \(fee == 0 ? "is free" : rupees(fee))" + (above > 0 && fee > 0 ? ", free above \(rupees(above))" : "") + "." + days
                + " \(shop.title) has 24 hours to accept, then ships it with a tracking number."
        }
        if mode == "PICKUP" { return "No delivery fee. Collect it from \(shop.title)" + (shop.area.isEmpty ? "" : " in \(shop.area)") + " once they mark it ready." }
        if freeDelivery { return "Free delivery: \(shop.title) pays the rider's fee on this order. You pay for the items only." }
        if mode == "STORE_RIDER" { return "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. It goes to \(shop.title) with the items, since it's their rider." }
        return "Delivery fee is ₹20 + ₹8 per km from the shop to your drop point. You pay it to the Bucks rider at the door (UPI or cash); the order page shows the amount."
    }

    private func payNote(mode: String, payment: String, freeDelivery: Bool) -> String {
        if payment == "COD" { return mode == "SHIP" ? "Pay the courier in cash when it arrives." : "Pay the store's rider in cash when it arrives." }
        if mode == "MARKETPLACE" && !freeDelivery { return "You pay the shop for the items through your UPI app from the order page; the shop's QR is filled in for you. The rider's fee is paid to the rider." }
        return "You pay the shop through your UPI app from the order page; the shop's QR is filled in for you."
    }

    private var footNote: String {
        if stores.count > 1 { return "Each shop accepts its own order (local shops within 5 minutes, shops that ship within 24 hours). If one doesn't, only that order is cancelled; nothing is charged." }
        guard let only = stores.first else { return "" }
        return modeOf(only) == "SHIP" ? "\(only.listing.title) has 24 hours to accept. If they don't, nothing is charged and you can try another shop."
            : "\(only.listing.title) has 5 minutes to accept. If they don't, nothing is charged and you can try another shop."
    }

    private var canPlace: Bool {
        !commerce.placing && !stores.contains(where: blocked)
            && (!needsDrop || (!dropLabel.trimmingCharacters(in: .whitespaces).isEmpty && here != nil))
            && (!needsAddress || address != nil)
    }

    private func place() {
        var choices: [String: CommerceStore.Choice] = [:]
        for st in stores {
            let m = modeOf(st)
            choices[st.listing.id] = CommerceStore.Choice(mode: m, payment: paymentOf(st), dropLabel: m == "PICKUP" ? st.listing.area : dropLabel, address: m == "SHIP" ? address : nil)
        }
        commerce.checkoutAll(choices: choices, drop: here) { ids in
            // The cart page is replaced by the order (or, for several shops, My orders), so back goes to where the cart was opened from.
            router.path.removeAll { $0 == .cart }
            router.push(ids.count == 1 ? .order(ids[0]) : .myOrders)
        }
    }
}

extension View {
    /// The cart used to ask before mixing shops; it no longer does (each shop is its own order), so this changes nothing. Kept so screens
    /// that attach it still compile (Android keeps CartSwitchDialog the same way).
    func cartSwitchDialog() -> some View { self }
}
