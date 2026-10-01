import SwiftUI
import BucksCore

private let myListingTabs = ["Businesses", "Skills", "Driver", "Vehicles"]
private let myListingKinds = ["BUSINESS", "SKILL", "DRIVER"]

/// The owner's hub: everything they run on Bucks, by kind. Pending listings show how many of the recommendations they have and a way to
/// collect more; live ones get the open / online switch.
struct MyListingsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var tab = 0

    var body: some View {
        let m = session.listings
        let kind = myListingKinds[min(max(tab, 0), 2)]
        let rows = m.listings.filter { $0.kind == kind }
        // Buyers pay a shop order by UPI to the owner's payment QR; without one the Pay button is off.
        let dispatch: Dispatch = session.dispatch
        let noUpi = session.cloud && dispatch.paymentLinkLoaded && dispatch.paymentLink == nil
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "My listings", onBack: { router.pop() }) {
                    StudioBarIcon(systemImage: "envelope", label: "Invites", badge: m.pendingCount) { router.push(.invites) }
                }
                tabRow
                if m.loading && !m.loaded { StudioBusyBar() }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // A failed load is not "no business yet": that empty state, with its big Add button, would invite a duplicate listing.
                        if let err = m.error, !m.loaded, rows.isEmpty { ListingsLoadError(message: err) { m.refresh() } }
                        if rows.isEmpty && m.loaded { EmptyListings(kind: kind, needed: m.needed) { create(kind) } }
                        ForEach(rows) { l in
                            ListingManageCard(m: m, l: l, showPaymentQr: noUpi && l.kind == "BUSINESS" && m.isOwner(l.id))
                        }
                        if !rows.isEmpty && kind != "DRIVER" { GhostButton(kind == "BUSINESS" ? "Add another business" : "Add another skill") { create(kind) } }
                        if m.loaded {
                            BucksCard(tint: true) {
                                Text("Recommend a local").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted("Know a shop, driver or worker nearby who does good work? Scan the code on their phone and help them go live. \(m.needed) recommendations from people nearby take a listing live.").padding(.top, 4)
                                SmallButton("Scan their code") { router.push(.recommendScan) }.padding(.top, 10)
                            }
                        }
                        Spacer().frame(height: 12)
                    }.padding(Gutter)
                }
                .refreshable { await m.refresh().value }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .onAppear { m.refresh(); let d: Dispatch = session.dispatch; if session.cloud && !d.paymentLinkLoaded { d.refreshPaymentLink() } }
    }

    private func create(_ kind: String) { router.push(.listingEdit(id: nil, kind: kind, service: nil)) }

    private var tabRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(myListingTabs.enumerated()), id: \.offset) { i, l in
                    Button { if i == 3 { router.push(.vehicles) } else { tab = i } } label: {
                        Text(l).bucks(.labelLarge).foregroundStyle(tab == i ? BucksColor.primary : BucksColor.onSurfaceVariant)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .overlay(alignment: .bottom) { if tab == i { Rectangle().fill(BucksColor.primary).frame(height: 2) } }
                    }.buttonStyle(.plain)
                }
            }
            BucksDivider()
        }.background(BucksColor.surface)
    }
}

private struct EmptyListings: View {
    let kind: String, needed: Int
    let onCreate: () -> Void
    var body: some View {
        BucksCard {
            switch kind {
            case "BUSINESS":
                Text("No business yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                Muted("Add your shop, restaurant, pharmacy or any business. Put your products in with prices so customers nearby can order. It goes live once \(needed) people nearby recommend it by scanning your QR code in person.").padding(.top, 4)
                PrimaryButton("Add a business", action: onCreate).padding(.top, 14)
            case "SKILL":
                Text("No skills yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                Muted("Add what you do: plumber, electrician, tutor, doctor, carpenter, designer. Each skill is its own listing with services and prices. It goes live once \(needed) people nearby recommend you.").padding(.top, 4)
                PrimaryButton("Add a skill", action: onCreate).padding(.top, 14)
            default:
                Text("No driver profile yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                Muted("Create your driver profile to take auto and cab rides or bike deliveries. You have one driver profile; add the vehicles you drive under Vehicles. It goes live once \(needed) people nearby recommend you.").padding(.top, 4)
                PrimaryButton("Create your driver profile", action: onCreate).padding(.top, 14)
            }
        }
    }
}

private struct ListingManageCard: View {
    let m: ListingsStore
    let l: ListingRow
    let showPaymentQr: Bool
    @Environment(Router.self) private var router

    var body: some View {
        let role = m.roleIn(l.id), manage = m.canManage(l.id), recs = m.recommendations[l.id] ?? 0, needed = m.needed
        BucksCard {
            HStack(alignment: .top, spacing: 14) {
                PhotoOrIcon(url: l.photoUrl, systemImage: Studio.listingIcon(l.kind, l.category))
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted([l.category.isEmpty ? nil : l.category, l.area.isEmpty ? nil : l.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    HStack(spacing: 6) {
                        switch l.status {
                        case "LIVE": PillGood("Live")
                        case "SUSPENDED": PillBad("Suspended")
                        default: PillWarn("\(recs) of \(needed) recommendations")
                        }
                        if let role, role != "OWNER" { PillGrey(Studio.roleLabel(role, vehicle: false)) }
                    }.padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            switch l.status {
            case "PENDING":
                Muted(recs == 0 ? "Not visible to customers yet. Ask \(needed) people nearby who know your work to scan your code." : "\(max(0, needed - recs)) more people nearby need to scan your code before customers can find you.").padding(.top, 10)
                if manage { PrimaryButton("Get recommended") { router.push(.recommendShow(l.id)) }.padding(.top, 10) }
            case "LIVE":
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Studio.onlineLabel(l.kind, l.online)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                        Muted(l.online ? "Shown first in search; customers can reach you now." : "Hidden until you switch it on.")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
                    if manage { ListingSwitch(studioSwitchBinding(l.online) { m.setOnline(l.id, $0) }) }
                }.padding(.top, 10)
            default:
                Notice("This listing is suspended and hidden from customers. Contact Bucks support to sort it out.").padding(.top, 10)
            }
            if showPaymentQr {
                Notice("Add your UPI QR so customers can pay your orders by UPI. Until then they have to pay you directly.").padding(.top, 10)
                SmallButton("Add payment QR") { router.push(.paymentQr) }.padding(.top, 8)
            }
            FlowLayout(spacing: 8) {
                if manage { SmallButton("Edit", tonal: true) { router.push(.listingEdit(id: l.id, kind: l.kind, service: nil)) } }
                if manage && l.kind == "BUSINESS" { SmallButton("Products", tonal: true) { router.push(.itemEdit(listing: l.id, item: nil)) } }
                if manage && l.kind == "SKILL" { SmallButton("Services", tonal: true) { router.push(.itemEdit(listing: l.id, item: nil)) } }
                if manage && l.kind != "DRIVER" { SmallButton("Documents", tonal: true) { router.push(.listingDocs(l.id)) } }
                if l.kind != "DRIVER" { SmallButton("Members", tonal: true) { router.push(.members(l.id)) } }
                if manage && l.kind == "BUSINESS" {
                    SmallButton("Orders", tonal: true) { router.push(.vendorOrders(l.id)) }
                    SmallButton("Jobs", tonal: true) { router.push(.listingJobs(l.id)) }
                }
                SmallButton("View profile", tonal: true) { router.push(.listing(l.id)) }
            }.padding(.top, 12)
        }
    }
}
