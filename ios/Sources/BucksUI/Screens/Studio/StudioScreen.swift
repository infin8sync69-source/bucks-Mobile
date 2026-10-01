import SwiftUI
import BucksCore

/// What the Studio hub filters by. DRIVING holds the driver profile and the vehicles.
private enum StudioFilter: CaseIterable {
    case all, business, skill, asset, driving
    var label: String { switch self { case .all: "All"; case .business: "Businesses"; case .skill: "Skills"; case .asset: "Assets"; case .driving: "Driving" } }
    var kind: String? { switch self { case .business: "BUSINESS"; case .skill: "SKILL"; case .asset: "ASSET"; default: nil } }
}

/// What "Create" offers: kind to open, title, one line, icon.
struct CreateOption: Identifiable {
    let kind: String, title: String, detail: String, systemImage: String
    var id: String { kind }
}
let createOptions: [CreateOption] = [
    CreateOption(kind: "BUSINESS", title: "Business", detail: "Shop, restaurant, store. Products with prices, orders, delivery.", systemImage: "storefront.fill"),
    CreateOption(kind: "SKILL", title: "Skill profile", detail: "Plumber, tutor, designer. Your services, prices and portfolio.", systemImage: "wrench.and.screwdriver.fill"),
    CreateOption(kind: "ASSET", title: "Asset to sell, rent or lease", detail: "House, flat, plot, shop, office, vehicle, equipment.", systemImage: "building.2.fill"),
    CreateOption(kind: "VEHICLE", title: "Vehicle", detail: "Bike, auto or cab for rides and deliveries, with its documents.", systemImage: "bicycle"),
    CreateOption(kind: "DRIVER", title: "Driver profile", detail: "Take rides and deliveries with a checked vehicle.", systemImage: "car.fill"),
]

/// The Studio: everything I run on Bucks in one place, as cards in a grid that grows to 2-3 columns on wide screens.
/// Each card opens its dashboard; live ones switch on and off right from the card. "Create" starts any new listing or vehicle.
struct StudioScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var filter: StudioFilter = .all
    @State private var creating = false

    var body: some View {
        let m = session.listings
        let listings = m.listings.filter { l in
            switch filter { case .all: true; case .driving: l.kind == "DRIVER"; default: l.kind == filter.kind }
        }
        let vehicles = (filter == .all || filter == .driving) ? m.vehicles : []
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                BucksTopBar(title: "Bucks Pro", onBack: { router.pop() }) {
                    StudioBarIcon(systemImage: "qrcode.viewfinder", label: "Recommend someone", badge: 0) { router.push(.recommendScan) }
                    StudioBarIcon(systemImage: "envelope", label: "Invites", badge: m.pendingCount) { router.push(.invites) }
                }
                if m.loading { StudioBusyBar() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(m)
                        chips(m)
                        if !m.invites.isEmpty { inviteCard(m) }
                        if let err = m.error, !m.loaded { ListingsLoadError(message: err) { m.refresh() } }
                        else if m.loaded && listings.isEmpty && vehicles.isEmpty { StudioEmpty(filter: filter) { create($0) } }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                            ForEach(listings) { l in ListingStreamCard(m: m, l: l) { router.push(.studio(l.id)) } }
                            ForEach(vehicles) { v in VehicleStreamCard(m: m, v: v) { router.push(.vehicleEdit(v.id)) } }
                        }
                        if !vehicles.isEmpty { GhostButton("Vehicles, drivers and earnings") { router.push(.vehicles) } }
                        if m.loaded { footerCards }
                    }
                    .padding(.horizontal, Gutter).padding(.top, 4).padding(.bottom, 96)
                    .frame(maxWidth: 1200).frame(maxWidth: .infinity)
                }
                .refreshable { await m.refresh().value }
            }
            Button { creating = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold)); Text("Create").bucks(.labelLarge)
                }
                .foregroundStyle(BucksColor.onPrimary).padding(.horizontal, 20).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BucksColor.primary).shadow(color: .black.opacity(0.18), radius: 6, y: 3))
            }.buttonStyle(.plain).padding(Gutter)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        // Refresh each time the hub shows (also when coming back from a dashboard), like Android re-composing it.
        .onAppear { m.refresh() }
        .sheet(isPresented: $creating) {
            CreateSheet(hasDriver: m.driverProfile() != nil) { kind in creating = false; create(kind) }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private func create(_ kind: String) {
        if kind == "VEHICLE" { router.push(.vehicleEdit(nil)) } else { router.push(.listingEdit(id: nil, kind: kind, service: nil)) }
    }

    private func header(_ m: ListingsStore) -> some View {
        let live = m.listings.filter { $0.status == "LIVE" }.count, pending = m.listings.filter { $0.status == "PENDING" }.count
        let on = m.listings.filter { $0.status == "LIVE" && $0.online }.count
        let line: String
        if m.listings.isEmpty && m.vehicles.isEmpty { line = "Businesses, skills, assets and vehicles you run live here. Your personal profile stays under Profile." }
        else {
            line = ["\(live) live", pending > 0 ? "\(pending) waiting to go live" : nil, live > 0 ? "\(on) open now" : nil,
                    m.vehicles.isEmpty ? nil : "\(m.vehicles.count) vehicle\(m.vehicles.count == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · ")
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Your professional space").bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
            Muted(line)
        }
    }

    private func chips(_ m: ListingsStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudioFilter.allCases, id: \.self) { f in
                    let n: Int = {
                        switch f {
                        case .all: return m.listings.count + m.vehicles.count
                        case .driving: return m.listings.filter { $0.kind == "DRIVER" }.count + m.vehicles.count
                        default: return m.listings.filter { $0.kind == f.kind }.count
                        }
                    }()
                    BucksChip(n > 0 ? "\(f.label) \(n)" : f.label, selected: filter == f) { filter = f }
                }
            }
        }
    }

    private func inviteCard(_ m: ListingsStore) -> some View {
        BucksCard(tint: true, onTap: { router.push(.invites) }) {
            HStack(spacing: 12) {
                Image(systemName: "envelope").foregroundStyle(BucksColor.onPrimaryContainer)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(m.invites.count) invite\(m.invites.count == 1 ? "" : "s") waiting").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted("Someone asked you to help run their listing or drive their vehicle.")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant)
            }
        }
    }

    private var footerCards: some View {
        HStack(alignment: .top, spacing: 12) {
            BucksCard(onTap: { router.push(.bucksId) }) {
                Image(systemName: "qrcode").font(.system(size: 22)).foregroundStyle(BucksColor.primary)
                Text("Your Bucks Pro ID").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 8)
                Muted("Show it so people sync with you.")
            }
            BucksCard(onTap: { router.push(.recommendScan) }) {
                Image(systemName: "hand.thumbsup.fill").font(.system(size: 22)).foregroundStyle(BucksColor.primary)
                Text("Recommend a local").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 8)
                Muted("Scan their code in person.")
            }
        }
    }
}

/// A top-bar icon with an optional count badge.
struct StudioBarIcon: View {
    let systemImage: String, label: String, badge: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 21)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { Text("\(badge)").font(.bucks(.labelSmall)).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(BucksColor.purple)).offset(x: -2, y: 4) }
                }
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

private struct StudioEmpty: View {
    let filter: StudioFilter
    let onCreate: (String) -> Void
    var body: some View {
        let (title, text, kind): (String, String, String) = {
            switch filter {
            case .business: return ("No business yet", "Add your shop or restaurant, put in products with prices, and customers nearby can order.", "BUSINESS")
            case .skill: return ("No skill profile yet", "Show what you do, what you charge and photos of your work. Neighbours request you directly.", "SKILL")
            case .asset: return ("No assets listed", "Sell, rent or lease a house, flat, plot, shop, vehicle or equipment to people nearby.", "ASSET")
            case .driving: return ("Not driving yet", "Add your vehicle with its documents, then your driver profile, to take rides and deliveries.", "VEHICLE")
            case .all: return ("Start your professional space", "Pick what you want to offer. Every listing goes live once people nearby recommend it in person and Bucks checks any documents it needs.", "")
            }
        }()
        BucksCard {
            Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted(text).padding(.top, 4)
            if !kind.isEmpty { PrimaryButton("Create") { onCreate(kind) }.padding(.top, 14) }
            else { VStack(spacing: 0) { ForEach(createOptions.filter { $0.kind != "DRIVER" }) { o in CreateRow(option: o) { onCreate(o.kind) } } }.padding(.top, 10) }
        }
    }
}

private struct CreateRow: View {
    let option: CreateOption
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: option.systemImage).foregroundStyle(BucksColor.onPrimaryContainer).frame(width: 44, height: 44).background(Circle().fill(BucksColor.primaryContainer))
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(option.detail)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant)
            }.padding(.vertical, 10).padding(.horizontal, 4).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The "Create" bottom sheet: what do you want to offer?
struct CreateSheet: View {
    let hasDriver: Bool
    let onPick: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Create").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("What do you want to offer?").padding(.bottom, 8)
                ForEach(createOptions.filter { $0.kind != "DRIVER" || !hasDriver }) { o in CreateRow(option: o) { onPick(o.kind) } }
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
        }.background(BucksColor.surface)
    }
}

private struct ListingStreamCard: View {
    let m: ListingsStore
    let l: ListingRow
    let onTap: () -> Void
    var body: some View {
        let recs = m.recommendations[l.id] ?? 0, role = m.roleIn(l.id)
        VStack(alignment: .leading, spacing: 0) {
            ListingCover(listing: l, height: 124)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Pill(Studio.kindLabel(l.kind), bg: BucksColor.surface, fg: BucksColor.onSurface)
                        if let role, role != "OWNER" { Pill(Studio.roleLabel(role, vehicle: false), bg: BucksColor.surface, fg: BucksColor.onSurface) }
                    }.padding(10)
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Muted([l.kind == "ASSET" ? Studio.assetPriceLine(l.details) : (l.category.isEmpty ? nil : l.category), l.area.isEmpty ? nil : l.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if l.status == "LIVE" && m.canManage(l.id) { ListingSwitch(studioSwitchBinding(l.online) { m.setOnline(l.id, $0) }) }
                }
                ListingStatusPill(listing: l, recs: recs).padding(.top, 8)
                if l.status == "PENDING" { StudioProgress(value: Double(recs) / Double(max(1, m.needed))).padding(.top, 10) }
            }.padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(BucksColor.surfaceContainer))
        .clipShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
    }
}

private struct VehicleStreamCard: View {
    let m: ListingsStore
    let v: VehicleRow
    let onTap: () -> Void
    var body: some View {
        let docs = m.vehicleDocs[v.id] ?? [], kinds = vehicleDocKinds(v.kind)
        let needed = kinds.filter(\.required).count
        let have = kinds.filter { k in k.required && docs.contains { $0.kind == k.key } }.count
        BucksCard(onTap: onTap) {
            HStack(spacing: 12) {
                Avatar(systemImage: Studio.vehicleIcon(v.kind), size: 48)
                VStack(alignment: .leading, spacing: 0) {
                    Text(v.model.isEmpty ? vehicleKindLabel(v.kind) : v.model).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted("\(vehicleKindLabel(v.kind)) · \(v.plate)")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Pill("Vehicle", bg: BucksColor.surfaceContainerHigh, fg: BucksColor.onSurfaceVariant)
            }
            HStack(spacing: 6) {
                switch v.status {
                case "ACTIVE": PillGood("Checked · can go online")
                case "SUSPENDED": PillBad("Suspended")
                default: if have < needed { PillWarn("\(have) of \(needed) documents") } else { PillWarn("Documents being checked") }
                }
                if v.ownerId != m.me?.id { PillGrey("You drive it") }
            }.padding(.top, 10)
        }
    }
}
