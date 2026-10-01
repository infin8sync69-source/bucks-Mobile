import SwiftUI
import BucksCore

/// The universal public profile of a listing: the same header for a shop, a pro and a driver, then tabs by kind.
/// BUSINESS: Products, Jobs, About, Reviews. SKILL: Services, Feed, About, Reviews. DRIVER: About, Reviews, plus Book.
struct ListingProfileScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var tab: String?

    private var d: DiscoverStore { session.discover }

    init(id: String) { self.id = id }

    var body: some View {
        Group {
            if let p = d.profiles[id] { profile(p) } else { ProfilePlaceholder(id: id) }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .task(id: id) { d.open(id) }
        // Commerce: asks "Start a new cart?" when an item from a second shop is added.
        .cartSwitchDialog()
    }

    private func tabs(_ l: ListingRow) -> [(key: String, label: String)] {
        let photos = !l.gallery.isEmpty
        switch l.kind {
        case "BUSINESS": return [("products", "Products")] + (photos ? [("photos", "Photos")] : []) + [("feed", "Feed"), ("jobs", "Jobs"), ("about", "About"), ("reviews", "Reviews")]
        case "SKILL": return [("services", "Services")] + (photos ? [("photos", "Portfolio")] : []) + [("feed", "Feed"), ("about", "About"), ("reviews", "Reviews")]
        case "ASSET": return [("about", "Details")] + (photos ? [("photos", "Photos")] : []) + [("reviews", "Reviews")]
        default: return [("about", "About")] + (photos ? [("photos", "Photos")] : []) + [("reviews", "Reviews")]
        }
    }

    private func profile(_ p: ListingProfile) -> some View {
        let l = p.listing
        let tabs = tabs(l)
        let current = tabs.contains { $0.key == tab } ? (tab ?? tabs[0].key) : tabs[0].key
        let cartCount = session.commerce.count
        return GeometryReader { geo in ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    ProfileCover(listing: l, top: geo.safeAreaInsets.top, onBack: { router.pop() }, shareText: shareText(l))
                    ProfileHeader(profile: p, cartHere: cartCount > 0 && session.commerce.shop?.id == id, shareText: shareText(l), onMessage: message, onBook: { startRide(session, router, kind: $0) }, onCart: { router.push(.cart) })
                    TabStrip(tabs: tabs, current: current) { tab = $0 }
                    switch current {
                    case "products": ProductsTab(profile: p, onMessage: message); Spacer().frame(height: cartCount > 0 ? 96 : 24)
                    case "jobs": JobsTab(profile: p) { router.push(.listingJobs(id)) }
                    case "services": ServicesTab(profile: p) { line in session.discover.startListingChat(id, firstLine: line) { router.push(.chat($0)) } }
                    case "feed": FeedTab(profile: p)
                    case "photos": GalleryTab(listing: l)
                    case "about": AboutTab(profile: p, onOpenListing: { router.push(.listing($0)) }).task(id: l.id) { session.services.loadBadges(l.id) }
                    case "reviews": ReviewsTab(profile: p)
                    default: EmptyView()
                    }
                    Spacer().frame(height: 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            if l.kind == "BUSINESS" && l.online && cartCount > 0 && current == "products" {
                DarkButton("View cart · \(plural(cartCount, "item"))") { router.push(.cart) }.padding(Gutter)
            }
        } }
    }

    private func message() { d.startListingChat(id) { router.push(.chat($0)) } }

    private func shareText(_ l: ListingRow) -> String {
        let extra = [l.category, l.area].filter { !$0.isEmpty }.joined(separator: ", ")
        return "\(l.title) on Bucks" + (extra.isEmpty ? "" : " · \(extra)") + ". Open Bucks and search \"\(l.title)\"."
    }
}

/// While the profile loads, when the listing isn't there (missing), or when the load itself failed (offline, server error).
private struct ProfilePlaceholder: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    var body: some View {
        let d: DiscoverStore = session.discover
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Listing", onBack: { router.pop() })
                VStack(spacing: 0) {
                    if d.missing.contains(id) {
                        notice(icon: "magnifyingglass", title: "This listing isn't available", detail: "It may have been removed, or it isn't live yet. A listing goes live once 7 people nearby recommend it in person.")
                    } else if d.failed.contains(id) {
                        notice(icon: "icloud.slash", title: "Couldn't load this listing", detail: "Check your connection and try again.")
                    } else {
                        BucksLoader()
                        Muted("Loading…").padding(.top, 12)
                    }
                }.frame(maxWidth: .infinity).padding(Gutter).padding(.top, 48)
            }.frame(maxHeight: .infinity, alignment: .top)
        }
    }
    @ViewBuilder private func notice(icon: String, title: String, detail: String) -> some View {
        Image(systemName: icon).font(.system(size: 36)).foregroundStyle(BucksColor.onSurfaceVariant)
        Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 12)
        Muted(detail, align: .center).padding(.top, 6)
        SmallButton("Try again", tonal: true) { session.discover.open(id) }.fixedSize().padding(.top, 14)
        Button { router.pop() } label: { Text("Back").bucks(.labelLarge).foregroundStyle(BucksColor.primary).padding(12) }.buttonStyle(.plain)
    }
}

/// Cover band (primary gradient), back and share on top, the photo or initials overlapping the bottom edge.
private struct ProfileCover: View {
    let listing: ListingRow
    /// The status bar's height: the band runs under it.
    let top: CGFloat
    var onBack: () -> Void
    let shareText: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [BucksColor.primary, BucksColor.onPrimaryContainer], startPoint: .topLeading, endPoint: .bottomTrailing)
                // The first gallery photo fills the band, darkened at the top so back and share stay readable.
                if let g = listing.gallery.first, let url = URL(string: g.url) {
                    RemotePhoto(url: url) { Color.clear }.frame(maxWidth: .infinity).frame(height: 140 + top).clipped()
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom).frame(height: 140 + top)
                }
            }
            .frame(height: 140 + top).frame(maxHeight: .infinity, alignment: .top).clipped()
            HStack {
                coverButton("chevron.left", "Back", onBack)
                Spacer()
                ShareLink(item: shareText) { coverIcon("square.and.arrow.up") }.buttonStyle(.plain).accessibilityLabel("Share")
            }.padding(8).padding(.top, top).frame(maxHeight: .infinity, alignment: .top)
            ZStack {
                Circle().fill(BucksColor.primaryContainer)
                if let url = Backend.shared.listingPhoto(listing.photoUrl) {
                    RemotePhoto(url: url) { initialsFace }.clipShape(Circle())
                } else { initialsFace }
            }
            .padding(4).background(Circle().fill(BucksColor.surface)).frame(width: 96, height: 96).padding(.leading, Gutter)
        }
        .frame(height: 170 + top)
        .accessibilityElement(children: .contain)
    }
    private var initialsFace: some View {
        Text(initials(listing.title).isEmpty ? "?" : initials(listing.title)).bucks(.headlineMedium).foregroundStyle(BucksColor.onPrimaryContainer)
    }
    private func coverIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 20, weight: .semibold)).foregroundStyle(BucksColor.onPrimary).frame(width: 48, height: 48).contentShape(Rectangle())
    }
    private func coverButton(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { coverIcon(name) }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Name, badges, status line, trust, counts and the action row (Message, Sync, Share, Directions, cart) or the Book / Enquire button.
private struct ProfileHeader: View {
    let profile: ListingProfile
    let cartHere: Bool
    let shareText: String
    var onMessage: () -> Void
    var onBook: (VehicleKind) -> Void
    var onCart: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let p = profile, l = p.listing
        let d: DiscoverStore = session.discover
        let vk = l.kind == "DRIVER" ? driverKind(l.details, category: l.category) : nil
        let distance = p.at.map { formatDistance(Geo.distanceKm(session.here, $0) * 1000) }
        let synced = d.isSynced(l.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(l.title).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                if l.status == "LIVE" { Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(BucksColor.primary).accessibilityLabel("Verified by locals") }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                KindBadge(kind: l.kind)
                if !l.category.isEmpty { Muted(l.category, maxLines: 1) }
                switch l.status { case "PENDING": PillWarn("Not live yet"); case "SUSPENDED": PillBad("Suspended"); default: EmptyView() }
            }.padding(.top, 6)
            HStack(spacing: 6) {
                OnlineDot(online: l.online)
                Muted([onlineText(l.kind, l.online), distance.map { "\($0) away" }, l.area.isEmpty ? nil : l.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
            }.padding(.top, 6)
            if l.kind == "ASSET" {
                Text(assetPriceLine(l.details)).bucks(.titleLarge).fontWeight(.semibold).foregroundStyle(BucksColor.primary).padding(.top, 8)
            }
            HStack { TrustBadge(up: l.trustUp, down: l.trustDown); Spacer(minLength: 0) }.padding(.top, 10)
            Muted(["\(p.recommendations) in-person recommendations", "\(p.syncs) synced", p.members > 1 ? "team of \(p.members)" : nil].compactMap { $0 }.joined(separator: " · ")).padding(.top, 6)
            if p.mine {
                Notice("This is your listing. Edit it, its products and its team from Menu > Bucks Pro.").padding(.top, 12)
            } else {
                HStack(spacing: 8) {
                    Button(action: onMessage) {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill").font(.system(size: 16))
                            Text("Message").bucks(.labelLarge).lineLimit(1)
                        }
                        .foregroundStyle(BucksColor.onPrimary).padding(.horizontal, 12).frame(minWidth: 0, maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primary)).opacity(d.chatStarting ? 0.4 : 1)
                    }.buttonStyle(.plain).disabled(d.chatStarting)
                    SyncButton(synced: synced, busy: d.syncing.contains(l.id)) { d.syncListing(l.id, on: !synced) }
                    ShareLink(item: shareText) { HeaderIconFace(systemImage: "square.and.arrow.up") }.buttonStyle(.plain).accessibilityLabel("Share")
                    if let at = p.at { HeaderIcon(systemImage: "mappin.and.ellipse", label: "Directions") { openMapsTo(router, name: l.title, detail: l.area, at: at) } }
                    if l.kind == "BUSINESS" && cartHere && l.online {
                        HeaderIcon(systemImage: "cart.fill", label: "Order", on: true, action: onCart)
                            .overlay(alignment: .topTrailing) { Text("\(session.commerce.count)").bucks(.labelSmall).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(BucksColor.error)).offset(x: 6, y: -6) }
                    }
                }.padding(.top, 12)
            }
            if l.kind == "ASSET" && !p.mine {
                PrimaryButton(l.details.str("mode") == "SELL" ? "Enquire about buying" : "Enquire about renting", enabled: !d.chatStarting) {
                    d.startListingChat(l.id, firstLine: "Hi, I'm interested in \(l.title). Is it still available?") { router.push(.chat($0)) }
                }.padding(.top, 12)
            }
            if l.kind == "DRIVER" && !p.mine {
                if let vk, vk.carriesPassengers {
                    PrimaryButton("Book a \(vk.label.lowercased())") { onBook(vk) }.padding(.top, 12)
                    Muted("Bucks rings the nearest online \(vk.label.lowercased()) rider, so it may not be \(l.title.split(separator: " ").first.map(String.init) ?? l.title). Pay after the trip, cash or UPI.").padding(.top, 6)
                } else {
                    Notice("Bike riders carry parcels only, never passengers. Order from a shop nearby and a rider delivers it.").padding(.top, 12)
                }
            }
        }
        .padding(.horizontal, Gutter).padding(.vertical, 8)
    }
}

private struct SyncButton: View {
    let synced: Bool; let busy: Bool; var action: () -> Void
    var body: some View {
        let c = synced ? BucksColor.onPrimaryContainer : BucksColor.onSurface
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small).tint(c).frame(width: 18, height: 18) } else { Image(systemName: synced ? "checkmark" : "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .semibold)).foregroundStyle(c) }
                Text(synced ? "Synced" : "Sync").bucks(.labelLarge).foregroundStyle(c).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(minWidth: 0, maxWidth: .infinity).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(synced ? BucksColor.primaryContainer : BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy)
    }
}

/// 44pt tonal icon button for the header's secondary actions; `on` tints it.
private struct HeaderIconFace: View {
    let systemImage: String; var on = false
    var body: some View {
        Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(on ? BucksColor.onPrimaryContainer : BucksColor.onSurface)
            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(on ? BucksColor.primaryContainer : BucksColor.surfaceContainer)).contentShape(Rectangle())
    }
}
private struct HeaderIcon: View {
    let systemImage: String; let label: String; var on = false; var action: () -> Void
    var body: some View { Button(action: action) { HeaderIconFace(systemImage: systemImage, on: on) }.buttonStyle(.plain).accessibilityLabel(label) }
}

/// Equal-width tabs with a 3 pt indicator under the selected one.
private struct TabStrip: View {
    let tabs: [(key: String, label: String)]
    let current: String
    var onSelect: (String) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.key) { t in
                let on = t.key == current
                Button { onSelect(t.key) } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(t.label).bucks(.titleSmall).fontWeight(on ? .semibold : .regular).foregroundStyle(on ? BucksColor.onSurface : BucksColor.onSurfaceVariant).lineLimit(1).padding(.horizontal, 4)
                        Spacer(minLength: 0)
                        Rectangle().fill(on ? BucksColor.primary : .clear).frame(height: 3)
                    }.frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(BucksColor.surface).overlay(alignment: .bottom) { Rectangle().fill(BucksColor.outline).frame(height: 1) }
    }
}
