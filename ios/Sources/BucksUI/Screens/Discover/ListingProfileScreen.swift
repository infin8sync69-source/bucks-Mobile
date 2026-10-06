import SwiftUI
import BucksCore

/// The universal public profile of a listing: the same header for a shop, a pro and a driver, then tabs by kind.
/// BUSINESS: Feed, About, Products, Jobs, Reviews (opens on Products when it has any). SKILL: Services, Portfolio, Feed, About, Reviews.
/// DRIVER: About, Photos, Reviews, plus Book. Anyone but the owner can recommend or not recommend it with a comment.
struct ListingProfileScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var tab: String?
    /// Recommend (1) / not recommend (-1) tapped: the comment sheet is open with that vote.
    @State private var rateVote: Int?

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
        // A business reads like a page: what it posts, who it is (photos live in About), what it sells, who it hires, what people say.
        case "BUSINESS": return [("feed", "Feed"), ("about", "About"), ("products", "Products"), ("jobs", "Jobs"), ("reviews", "Reviews")]
        case "SKILL": return [("services", "Services")] + (photos ? [("photos", "Portfolio")] : []) + [("feed", "Feed"), ("about", "About"), ("reviews", "Reviews")]
        case "ASSET": return [("about", "Details")] + (photos ? [("photos", "Photos")] : []) + [("reviews", "Reviews")]
        default: return [("about", "About")] + (photos ? [("photos", "Photos")] : []) + [("reviews", "Reviews")]
        }
    }

    private func profile(_ p: ListingProfile) -> some View {
        let l = p.listing
        let tabs = tabs(l)
        // A shop with products opens on them; the Feed is often still empty.
        let initial = l.kind == "BUSINESS" && !p.products.isEmpty ? "products" : tabs[0].key
        let current = tabs.contains { $0.key == tab } ? (tab ?? initial) : initial
        let cartCount = session.commerce.count
        let myDirect = p.reviews.first { $0.authorId == session.me?.id && !$0.verified }
        return GeometryReader { geo in ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    ProfileCover(listing: l, top: geo.safeAreaInsets.top, onBack: { router.pop() }, shareText: shareText(l))
                    ProfileHeader(profile: p, cartHere: cartCount > 0, myVote: myDirect?.vote, shareText: shareText(l), onMessage: message, onBook: { startRide(session, router, kind: $0) },
                                  onCart: { router.push(.cart) }, onTab: { tab = $0 }, onRate: { rateVote = $0 })
                    TabStrip(tabs: tabs, current: current) { tab = $0 }
                    switch current {
                    case "products": StoreProducts(profile: p, onMessage: message, onCart: { router.push(.cart) }); Spacer().frame(height: cartCount > 0 ? 96 : 24)
                    case "jobs": JobsTab(profile: p) { router.push(.listingJobs(id)) }
                    case "services": ServicesTab(profile: p) { line in session.discover.startListingChat(id, firstLine: line) { router.push(.chat($0)) } }
                    case "feed": FeedTab(profile: p)
                    case "photos": GalleryTab(listing: l)
                    case "about":
                        AboutTab(profile: p, onOpenListing: { router.push(.listing($0)) }).task(id: l.id) { session.services.loadBadges(l.id) }
                        ShowcaseDocsSection(listingId: l.id, team: p.myRole == "OWNER" || p.myRole == "ADMIN", onManage: { router.push(.showcaseDocs(id)) })
                        if l.kind == "BUSINESS" && !l.gallery.isEmpty {
                            SectionTitle("Photos").padding(.horizontal, Gutter).padding(.top, 8)
                            GalleryTab(listing: l)
                        }
                    case "reviews": ReviewsTab(profile: p, mine: myDirect) { rateVote = $0 }
                    default: EmptyView()
                    }
                    Spacer().frame(height: 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: Binding(get: { rateVote != nil }, set: { if !$0 { rateVote = nil } })) {
                RecommendSheet(listing: l, mine: myDirect, initial: rateVote ?? 1) { rateVote = nil; tab = "reviews"; d.open(id) }
            }
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
                if !d.missing.contains(id) && !d.failed.contains(id) { ProfileSkeleton() } else { VStack(spacing: 0) {
                    if d.missing.contains(id) {
                        notice(icon: "magnifyingglass", title: "This listing isn't available", detail: "It may have been removed, or it isn't live yet. A listing goes live once 7 people nearby recommend it in person.")
                    } else if d.failed.contains(id) {
                        notice(icon: "icloud.slash", title: "Couldn't load this listing", detail: "Check your connection and try again.")
                    }
                }.frame(maxWidth: .infinity).padding(Gutter).padding(.top, 48) }
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
    /// My own direct recommendation of this listing (1 / -1), if I gave one.
    let myVote: Int?
    let shareText: String
    var onMessage: () -> Void
    var onBook: (VehicleKind) -> Void
    var onCart: () -> Void
    var onTab: (String) -> Void
    var onRate: (Int) -> Void
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
            StatsRow(stats: stats(p)).padding(.top, 10)
            ShowcaseDocsChip(listingId: l.id) { onTab("about") }
            if !p.mine {
                HStack(spacing: 8) {
                    RateButton(up: true, mine: myVote == 1) { onRate(1) }
                    RateButton(up: false, mine: myVote == -1) { onRate(-1) }
                }.padding(.top, 10)
            }
            if !p.mine && l.kind == "BUSINESS" {
                Muted(synced ? "You're synced: \(l.title)'s posts show in your Feed and you'll get a notification when they post." : "Sync to see \(l.title)'s posts in your Feed and get notified.").padding(.top, 6)
            }
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

    private func stats(_ p: ListingProfile) -> [StatsRow.Stat] {
        let l = p.listing
        var out = [StatsRow.Stat(n: p.syncs, label: "Synced", go: nil)]
        if l.kind == "BUSINESS" && !p.products.isEmpty { out.append(StatsRow.Stat(n: p.products.count, label: "Products", go: { onTab("products") })) }
        out.append(StatsRow.Stat(n: l.trustUp, label: "Recommendations", go: { onTab("reviews") }))
        if p.members > 1 { out.append(StatsRow.Stat(n: p.members, label: "Team", go: nil)) }
        return out
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

/// Numbers under the name: synced, products, recommendations (opens Reviews) and team size. A stat with an action is tappable.
private struct StatsRow: View {
    struct Stat { var n: Int; var label: String; var go: (() -> Void)? }
    let stats: [Stat]
    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                if let go = s.go {
                    Button(action: go) { face(s).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("\(s.n) \(s.label)").accessibilityHint("See \(s.label)")
                } else { face(s).accessibilityElement(children: .ignore).accessibilityLabel("\(s.n) \(s.label)") }
            }
            Spacer(minLength: 0)
        }
    }
    private func face(_ s: Stat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.n.formatted()).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted(s.label, maxLines: 1).fixedSize()
        }
    }
}

/// Recommend / not recommend button; filled when it is my current vote.
struct RateButton: View {
    let up: Bool; let mine: Bool; let action: () -> Void
    var body: some View {
        let c = up ? BucksColor.good : BucksColor.bad
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 15, weight: .semibold))
                Text(up ? "Recommend" : "Not recommend").bucks(.labelLarge).lineLimit(1)
            }
            .foregroundStyle(c).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(mine ? c.opacity(0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(mine ? .isSelected : [])
    }
}

/// Comment box that opens on a recommend / not recommend tap; the vote and comment land in the Reviews tab. Works for shops, pros, assets and drivers.
private struct RecommendSheet: View {
    let listing: ListingRow
    let mine: ReviewRow?
    let initial: Int
    var onDone: () -> Void
    @Environment(AppSession.self) private var session
    @State private var vote = 1
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(mine != nil ? "Your recommendation for \(listing.title)" : "Recommend \(listing.title)?").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("Your vote and comment are shown in Reviews for everyone.").padding(.top, 4)
                HStack(spacing: 8) {
                    RateButton(up: true, mine: vote == 1) { vote = 1 }
                    RateButton(up: false, mine: vote == -1) { vote = -1 }
                }.padding(.top, 14)
                BucksField(Binding(get: { text }, set: { text = String($0.prefix(500)) }), placeholder: vote > 0 ? "What did you like? (optional)" : "What went wrong? (optional)", singleLine: false, minLines: 3)
                    .padding(.top, 12)
                HStack { Spacer(); Muted("\(text.count)/500").fixedSize() }.padding(.top, -10)
                HStack(spacing: 8) {
                    SmallButton(busy ? "Sending…" : mine != nil ? "Update" : "Submit", enabled: !busy) { submit() }.fixedSize()
                    if mine != nil {
                        Button("Remove mine") { remove() }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.bad).frame(minHeight: 48).disabled(busy)
                    }
                }.padding(.top, 8)
            }.padding(Gutter).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { vote = initial; text = mine?.comment ?? "" }
    }

    private func submit() {
        Task {
            busy = true; defer { busy = false }
            do { try await Backend.shared.rateListing(listing.id, vote: vote, comment: text.trimmingCharacters(in: .whitespacesAndNewlines)); session.toast("Thanks, your review is posted."); onDone() }
            catch { session.toast(friendlyError(error)) }
        }
    }
    private func remove() {
        Task {
            busy = true; defer { busy = false }
            do { try await Backend.shared.clearListingRating(listing.id); session.toast("Your review was removed."); onDone() }
            catch { session.toast(friendlyError(error)) }
        }
    }
}
