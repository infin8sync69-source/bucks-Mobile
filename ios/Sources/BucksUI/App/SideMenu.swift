import SwiftUI
import BucksCore

/// The "Bucks Pro" menu (Android's navigation drawer): my Bucks ID, my listings with their online switches, the driver's vehicle switch,
/// invites, orders, jobs, recommendations, maps, account settings and logout. Slides in over a scrim.
struct SideMenu: View {
    @Binding var isOpen: Bool
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    private var m: ListingsStore { session.listings }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { close() }.accessibilityHidden(true)
            panel.transition(.move(edge: .leading))
                .gesture(DragGesture(minimumDistance: 20).onEnded { v in if v.translation.width < -60 { close() } })
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
        .task { if session.me != nil { m.refresh() } }
    }

    /// Android highlights the home entry on the hub, a listing dashboard or form, the vehicle form and the vehicles list.
    private var onProHome: Bool {
        switch router.path.last {
        case .myListings?, .studio?, .listingEdit?, .vehicleEdit?, .vehicles?: true
        default: false
        }
    }

    /// Android highlights "Bucks Pro home" on the hub, a listing dashboard and the vehicle screens.
    private var managingListings: Bool {
        guard let last = router.path.last else { return false }
        switch last { case .myListings, .studio, .vehicles: return true; default: return false }
    }

    private func close() { withAnimation(.easeOut(duration: 0.25)) { isOpen = false } }
    private func go(_ r: Route) { close(); router.push(r) }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView { VStack(alignment: .leading, spacing: 0) { header; idSection; listingsSection; BucksDivider(); linksSection } }
            BucksDivider()
            footer
        }
        .frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomTrailingRadius: BucksRadius.large, topTrailingRadius: BucksRadius.large, style: .continuous).fill(BucksColor.surface).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("Bucks Pro").font(.bucks(.titleLarge)).fontWeight(.semibold).foregroundStyle(BucksColor.primary).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(BucksColor.primary).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Close menu")
        }.padding(.leading, 20).padding(.trailing, 8).padding(.top, 20).padding(.bottom, 8)
    }

    @ViewBuilder private var idSection: some View { if let me = session.me { idCard(me) } }

    private var sortedListings: [ListingRow] {
        m.listings.sorted { a, b in
            if (a.status == "LIVE") != (b.status == "LIVE") { return a.status == "LIVE" }
            return a.title.lowercased() < b.title.lowercased()
        }
    }

    private var listingsSection: some View {
        VStack(spacing: 1) {
            item("square.grid.2x2", "Bucks Pro home", selected: onProHome) { go(.myListings) }
            ForEach(sortedListings) { listingRow($0) }
            if let v = session.dispatch.cloudVehicle { vehicleRow(v) }
            item("plus", "Create a listing") { go(.myListings) }
        }.padding(12)
    }

    private var linksSection: some View {
        VStack(spacing: 1) {
            item("envelope", m.pendingCount > 0 ? "Invites (\(m.pendingCount))" : "Invites", selected: router.path.last == .invites) { go(.invites) }
            item("bag", "My orders", selected: router.path.last == .myOrders) { go(.myOrders) }
            item("briefcase", "Jobs and applications", selected: router.path.last == .myApplications) { go(.myApplications) }
            item("qrcode.viewfinder", "Recommend a local", selected: router.path.last == .recommendScan) { go(.recommendScan) }
        }.padding(12)
    }

    private var footer: some View {
        VStack(spacing: 1) {
            item("mappin.and.ellipse", "Maps & directions", selected: router.path.last == .maps) { go(.maps) }
            item("gearshape", "Account settings") { close(); router.select(.account, accountTab: "settings") }
            item("rectangle.portrait.and.arrow.right", "Logout") { close(); Task { await session.logout() } }
        }.padding(12)
    }

    /// Bucks ID: a mini card that opens the full card with QR and barcode.
    private func idCard(_ me: ProfileRow) -> some View {
        let info = BucksIdCardInfo.of(me.idIssuedAt)
        let line: String = {
            guard let info else { return "Tap to show your card" }
            if info.expired { return "Expired · tap to renew" }
            if info.renewable { return "Renew soon · valid till \(info.validTill)" }
            return "Valid till \(info.validTill)"
        }()
        return Button { go(.bucksId) } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode").font(.system(size: 22)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bucks ID  \(BucksIdCode.pretty(me.shortCode))").font(.bucks(.titleSmall)).foregroundStyle(.white)
                    Text(line).font(.bucks(.bodySmall)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.white)
            }
            .padding(14)
            .background(LinearGradient(colors: [Color(hex: 0x811FF0), Color(hex: 0x4A0AA6)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).padding(.horizontal, 12).accessibilityLabel("Bucks ID, show card")
    }

    /// Quick access: a listing I run, one tap to its dashboard, and the switch right here when it's live.
    private func listingRow(_ l: ListingRow) -> some View {
        let status: String = l.status == "LIVE" ? Studio.onlineLabel(l.kind, l.online) : (l.status == "SUSPENDED" ? "Suspended" : "\(Studio.kindLabel(l.kind)) · not live yet")
        return HStack(spacing: 12) {
            Button { go(.studio(l.id)) } label: {
                HStack(spacing: 12) {
                    PhotoOrIcon(url: l.photoUrl ?? l.gallery.first?.url, systemImage: Studio.icon(l), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Text(status).font(.bucks(.bodySmall)).foregroundStyle(BucksColor.onSurfaceVariant).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if l.status == "LIVE" && m.canManage(l.id) {
                ListingSwitch(Binding(get: { l.online }, set: { m.setOnline(l.id, $0) }))
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Quick switch for my checked vehicle, so a driver can go online from anywhere (Android's `ListingCard` in the drawer).
    private func vehicleRow(_ v: VehicleRow) -> some View {
        let kind = v.vehicleKind
        let online = Binding(get: { session.dispatch.online }, set: { on in
            Task { let ok = await session.setOnline(on, plate: v.plate); if ok && on { close(); router.select(.home) } }
        })
        return ListingCard(title: v.model.isEmpty ? vehicleKindLabel(v.kind) : v.model, pill: vehicleKindLabel(v.kind), online: online, onEdit: { go(.vehicleEdit(v.id)) },
                           thumb: { ListingThumb(systemImage: kind.systemImage, size: 44) }, details: { Muted(v.plate) })
            .padding(.vertical, 4)
    }

    private func item(_ icon: String, _ label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Text(label).font(.bucks(.bodyLarge))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? BucksColor.onPrimaryContainer : BucksColor.onSurfaceVariant)
            .padding(.horizontal, 16).frame(height: 52).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(selected ? BucksColor.primaryContainer : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
