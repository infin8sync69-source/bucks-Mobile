import SwiftUI
import BucksCore

/// Tabs of a listing's dashboard.
enum DashTab: Hashable { case overview, items, photos, feed, reviews }

private func dashTabs(_ kind: String, manage: Bool) -> [(id: DashTab, label: String)] {
    if !manage { return [(.overview, "Overview"), (.reviews, "Reviews")] }
    switch kind {
    case "BUSINESS": return [(.overview, "Overview"), (.items, "Products"), (.photos, "Photos"), (.feed, "Feed"), (.reviews, "Reviews")]
    case "SKILL": return [(.overview, "Overview"), (.items, "Services"), (.photos, "Portfolio"), (.feed, "Feed"), (.reviews, "Reviews")]
    default: return [(.overview, "Overview"), (.photos, "Photos"), (.reviews, "Reviews")]
    }
}

/// One listing's control room: how to go live (a checklist of what's missing), the open / available switch, and tabs for everything the owner
/// manages: products or services, photos or portfolio, the listing's feed, and reviews.
struct ListingDashboardScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var tab: DashTab = .overview
    @State private var confirmDelete = false

    var body: some View {
        let m = session.listings
        Group {
            if let l = m.listing(id) { dashboard(m, l) } else { missing(m) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .onAppear { if !m.loaded { m.refresh() } }
    }

    private func missing(_ m: ListingsStore) -> some View {
        ContentColumn {
            VStack(alignment: .leading, spacing: 0) {
                BucksTopBar(title: "Listing", onBack: { router.pop() })
                if m.loaded {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Listing not found").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("It may have been deleted, or you're no longer part of it.").padding(.top, 4)
                    }.padding(Gutter)
                } else if let err = m.error { ListingsLoadError(message: err) { m.refresh() }.padding(Gutter) }
                else { CenteredLoading() }
            }
        }
    }

    private func dashboard(_ m: ListingsStore, _ l: ListingRow) -> some View {
        let manage = m.canManage(id), owner = m.isOwner(id)
        let tabs = dashTabs(l.kind, manage: manage)
        let current = tabs.contains { $0.id == tab } ? tab : .overview
        return VStack(spacing: 0) {
            BucksTopBar(title: l.title, onBack: { router.pop() }) {
                StudioBarIcon(systemImage: "eye", label: "See it as customers do", badge: 0) { router.push(.listing(id)) }
                ShareLink(item: "\(l.title) on Bucks" + shareDetail(l)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Share")
                if manage { moreMenu(l, owner: owner) }
            }
            StatusStrip(m: m, l: l, manage: manage)
            if tabs.count > 1 { StudioScrollTabs(tabs: tabs, selected: Binding(get: { current }, set: { tab = $0 })) }
            Group {
                switch current {
                case .overview: OverviewTab(m: m, l: l, manage: manage, owner: owner, goTo: { go($0, l) })
                case .items: ItemsTab(m: m, l: l)
                case .photos: PhotosTab(m: m, l: l)
                case .feed: FeedManageTab(m: m, l: l)
                case .reviews: ReviewsManageTab(m: m, l: l)
                }
            }.frame(maxWidth: 900).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // On every appearance, so coming back from Documents, Team or the item editor shows the new state.
        .onAppear {
            m.loadCounts(id)
            if l.kind == "BUSINESS" || l.kind == "SKILL" { m.loadItems(id) }
            if l.kind != "DRIVER" && manage { m.loadCompliance(id) }
        }
        .bucksConfirm(isPresented: $confirmDelete, title: "Delete \(l.title)?", message: "Its products, photos, members, recommendations and reviews go with it. Orders customers already placed stay in their history. This can't be undone.", confirmTitle: "Delete", destructive: true) {
            m.deleteListing(id) { router.pop() }
        }
    }

    private func shareDetail(_ l: ListingRow) -> String {
        let d = [l.category.isEmpty ? nil : l.category, l.area.isEmpty ? nil : l.area].compactMap { $0 }.joined(separator: ", ")
        return d.isEmpty ? "" : " · \(d)"
    }

    private func moreMenu(_ l: ListingRow, owner: Bool) -> some View {
        Menu {
            Button { router.push(.listingEdit(id: id, kind: l.kind, service: nil)) } label: { Label("Edit details", systemImage: "pencil") }
            if l.kind != "DRIVER" { Button { router.push(.listingDocs(id)) } label: { Label("Documents", systemImage: "doc.text") } }
            if l.kind != "DRIVER" { Button { router.push(.members(id)) } label: { Label("Team", systemImage: "person.3") } }
            if owner { Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") } }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
        }.menuIndicator(.hidden).buttonStyle(.plain).accessibilityLabel("More")
    }

    private func go(_ target: String, _ l: ListingRow) {
        switch target {
        case "EDIT": router.push(.listingEdit(id: id, kind: l.kind, service: nil))
        case "PHOTOS": tab = .photos
        case "ITEMS": tab = .items
        case "VEHICLES": router.push(.vehicles)
        case "DOCS": router.push(.listingDocs(id))
        case "RECOMMEND": router.push(.recommendShow(id))
        case "MEMBERS": router.push(.members(id))
        case "ORDERS": router.push(.vendorOrders(id))
        case "JOBS": router.push(.listingJobs(id))
        case "PAYMENT": router.push(.paymentQr)
        case "PROFILE": router.push(.listing(id))
        default: break
        }
    }
}

/// Under the top bar on every tab: where the listing stands, and the switch when it's live.
private struct StatusStrip: View {
    let m: ListingsStore
    let l: ListingRow
    let manage: Bool
    var body: some View {
        let recs = m.recommendations[l.id] ?? 0
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                switch l.status {
                case "LIVE":
                    Text(Studio.onlineLabel(l.kind, l.online)).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(l.online ? "Customers nearby can find and reach you now." : "Live, but hidden from search until you switch it on.")
                case "SUSPENDED":
                    Text(l.complianceHold ? "Paused for documents" : "Suspended").bucks(.titleSmall).foregroundStyle(BucksColor.error)
                    Muted(l.complianceHold ? "A document expired or is missing. Upload it and it comes back on its own." : "Hidden from customers. Contact Bucks support.")
                default:
                    Text("Not live yet").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted("\(recs) of \(m.needed) recommendations. See the checklist in Overview.")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if l.status == "LIVE" && manage { ListingSwitch(studioSwitchBinding(l.online) { m.setOnline(l.id, $0) }) } else { ListingStatusPill(listing: l, recs: recs) }
        }
        .padding(.horizontal, Gutter).padding(.vertical, 10).frame(maxWidth: .infinity).background(BucksColor.surfaceContainer)
    }
}

// MARK: Overview

private struct OverviewTab: View {
    let m: ListingsStore
    let l: ListingRow
    let manage: Bool, owner: Bool
    let goTo: (String) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        let recs = m.recommendations[l.id] ?? 0, c = m.counts[l.id]
        let hasVehicle = m.vehicles.contains { $0.status != "SUSPENDED" }
        let steps = Studio.goLiveSteps(l, items: (l.kind == "BUSINESS" || l.kind == "SKILL") ? m.items[l.id] : [], compliance: l.kind == "DRIVER" ? [] : m.compliance[l.id], recs: recs, hasVehicle: hasVehicle)
        let dispatch: Dispatch = session.dispatch
        let noUpi = session.cloud && dispatch.paymentLinkLoaded && dispatch.paymentLink == nil
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BucksCard(padding: 0) {
                    ListingCover(listing: l, height: 170)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                        Muted([Studio.kindLabel(l.kind), l.category.isEmpty ? nil : l.category, l.area.isEmpty ? nil : l.area].compactMap { $0 }.joined(separator: " · "))
                        if l.kind == "ASSET" { Text(Studio.assetPriceLine(l.details)).bucks(.titleMedium).foregroundStyle(BucksColor.primary).padding(.top, 6) }
                    }.padding(16)
                }.clipShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
                if manage && l.status != "LIVE" { goLiveCard(steps) }
                if manage && l.kind == "BUSINESS" && noUpi && owner {
                    VStack(alignment: .leading, spacing: 8) {
                        Notice("Add your UPI QR so customers can pay your orders by UPI. Until then they have to pay you directly.")
                        SmallButton("Add payment QR") { goTo("PAYMENT") }
                    }
                }
                HStack(spacing: 10) {
                    StatTile(value: "\(recs)", label: "Recommended")
                    StatTile(value: c.map { "\($0.syncs)" } ?? "–", label: "Synced")
                    StatTile(value: Studio.trustPct(l.trustUp, l.trustDown), label: "Positive")
                    if l.kind != "DRIVER" { StatTile(value: c.map { "\($0.members)" } ?? "–", label: "Team") }
                }
                AboutCard(l: l, manage: manage) { goTo("EDIT") }
                if manage { manageTiles } else { Notice("You're a store rider here: you deliver its orders. Only the owner and admins change the listing.") }
            }.padding(Gutter)
        }
        .task { let d: Dispatch = session.dispatch; if session.cloud && !d.paymentLinkLoaded { d.refreshPaymentLink() } }
    }

    private func goLiveCard(_ steps: [GoLiveStep]) -> some View {
        let done = steps.filter(\.done).count
        return BucksCard {
            HStack {
                Text("Go live").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Muted("\(done) of \(steps.count) done", align: .trailing)
            }
            StudioProgress(value: Double(done) / Double(max(1, steps.count)), height: 6).padding(.top, 8).padding(.bottom, 4)
            Muted("Two things take it live: \(m.needed) people nearby recommending it in person and Bucks checking any documents it needs. The rest makes people pick you.").padding(.bottom, 4)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in GoLiveRow(step: s) { goTo(s.target) } }
        }
    }

    private var manageTiles: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Manage")
            FlowLayout(spacing: 10) {
                ManageTile(systemImage: "pencil", label: "Edit details") { goTo("EDIT") }
                if l.kind != "DRIVER" { ManageTile(systemImage: "doc.text", label: "Documents") { goTo("DOCS") } }
                if l.kind != "DRIVER" { ManageTile(systemImage: "person.3.fill", label: "Team") { goTo("MEMBERS") } }
                if l.kind == "BUSINESS" {
                    ManageTile(systemImage: "list.clipboard", label: "Orders") { goTo("ORDERS") }
                    ManageTile(systemImage: "briefcase.fill", label: "Jobs") { goTo("JOBS") }
                }
                if l.kind == "BUSINESS" && owner { ManageTile(systemImage: "qrcode", label: "Payment QR") { goTo("PAYMENT") } }
                if l.kind == "DRIVER" { ManageTile(systemImage: "bicycle", label: "Vehicles") { goTo("VEHICLES") } }
                ManageTile(systemImage: "hand.thumbsup.fill", label: l.status == "PENDING" ? "Get recommended" : "Recommend code") { goTo("RECOMMEND") }
                ManageTile(systemImage: "eye", label: "Customer view") { goTo("PROFILE") }
            }
        }
    }
}

private struct ManageTile: View {
    let systemImage: String, label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(BucksColor.primary)
                Text(label).font(.bucks(.labelMedium)).foregroundStyle(BucksColor.onSurface).multilineTextAlignment(.center).lineLimit(2)
            }
            .padding(.vertical, 14).padding(.horizontal, 6).frame(width: 104)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The listing's public facts, read-only, with Edit.
private struct AboutCard: View {
    let l: ListingRow
    let manage: Bool
    let onEdit: () -> Void
    var body: some View {
        let d = l.details
        BucksCard {
            HStack {
                Text("About").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                if manage { Button("Edit", action: onEdit).buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary) }
            }
            if !l.description.isEmpty { Text(l.description).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface) }
            else { Muted("No description yet. A few lines about what you offer helps people choose you.") }
            ForEach(Array(facts(d).enumerated()), id: \.offset) { _, f in
                HStack(alignment: .top) {
                    Muted(f.0).frame(width: 120, alignment: .leading)
                    Text(f.1).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 8)
            }
        }
    }

    private func facts(_ d: JSONValue) -> [(String, String)] {
        var out: [(String, String)] = []
        switch l.kind {
        case "BUSINESS":
            if !d.sStr("hours").isEmpty { out.append(("Hours", d.sStr("hours"))) }
            if let r = d.sInt("delivery_radius_km") { out.append(("Delivers within", "\(r) km")) }
            out.append(("Delivery", d.sBool("free_delivery") ? "Free for customers" : "Customer pays"))
            if d.sBool("cod") { out.append(("Cash on delivery", "With your own riders")) }
        case "SKILL":
            if !d.sStr("rate").isEmpty { out.append(("Rate", d.sStr("rate"))) }
            if !d.sStr("level").isEmpty { out.append(("Experience", d.sStr("level"))) }
            if !d.sStrings("languages").isEmpty { out.append(("Languages", d.sStrings("languages").joined(separator: ", "))) }
        case "ASSET":
            out.append(("Listing", Studio.assetPriceLine(d)))
            if let dep = d.sNum("deposit"), dep > 0 { out.append(("Deposit", Studio.rupees(Int(dep)))) }
            if let a = d.sNum("area_sqft"), a > 0 { out.append(("Size", "\(Int(a)) sq ft")) }
            if let b = d.sInt("bedrooms") { out.append(("Bedrooms", "\(b)")) }
            if !d.sStr("furnishing").isEmpty { out.append(("Furnishing", d.sStr("furnishing"))) }
            if !d.sStr("available_from").isEmpty { out.append(("Available from", d.sStr("available_from"))) }
            if let y = d.sInt("year") { out.append(("Year", "\(y)")) }
            if let k = d.sInt("km_driven") { out.append(("Driven", "\(Studio.rupees(k).dropFirst()) km")) }
            if d.sBool("negotiable") { out.append(("Price", "Negotiable")) }
        case "DRIVER":
            if !d.sStr("vehicle_kind").isEmpty { out.append(("Drives", vehicleKindLabel(d.sStr("vehicle_kind")))) }
            if !d.sStr("model").isEmpty { out.append(("Model", d.sStr("model"))) }
            if !d.sStrings("languages").isEmpty { out.append(("Languages", d.sStrings("languages").joined(separator: ", "))) }
        default: break
        }
        return out
    }
}
