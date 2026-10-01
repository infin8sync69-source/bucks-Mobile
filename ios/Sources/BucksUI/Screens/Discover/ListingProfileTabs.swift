import SwiftUI
import BucksCore

// The tabs of ListingProfileScreen (ports of ProductsTab, JobsTab, ServicesTab, FeedTab, AboutTab, ReviewsTab and GalleryTab).

// MARK: - BUSINESS: Products and Jobs

struct ProductsTab: View {
    let profile: ListingProfile
    var onMessage: () -> Void
    @Environment(AppSession.self) private var session
    @State private var open: ItemRow?

    var body: some View {
        let p = profile, items = p.products
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Muted(p.mine ? "No products yet. Add them from Menu > Bucks Pro." : "\(p.listing.title) hasn't listed products yet. Message them to ask what's in stock.")
                if !p.mine { SmallButton("Message", tonal: true, action: onMessage).fixedSize().padding(.top, 12) }
            }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // A closed shop (switched off by its owner) takes no orders: the server refuses them, so nothing can be added.
            let shopOpen = p.listing.online
            let groups = grouped(items)
            VStack(alignment: .leading, spacing: 0) {
                if !shopOpen && !p.mine { Notice("\(p.listing.title) is closed now. You can order once they open again.").padding(.top, 12) }
                ForEach(groups, id: \.name) { g in
                    SectionTitle(g.name).padding(.top, 14).padding(.bottom, 2)
                    ForEach(Array(g.items.enumerated()), id: \.offset) { i, item in
                        if i > 0 { BucksDivider() }
                        ProductRow(item: item, qty: session.commerce.qty(item.id ?? ""), canAdd: !p.mine && shopOpen, onOpen: { open = item }) { delta in session.commerce.add(p.listing, item, delta) }
                    }
                }
            }
            .padding(.horizontal, Gutter).padding(.vertical, 4)
            .sheet(item: $open) { item in
                ItemSheet(item: item, qty: session.commerce.qty(item.id ?? ""), canAdd: !p.mine && shopOpen && item.inStock) { delta in session.commerce.add(p.listing, item, delta) }
            }
        }
    }

    /// Products by group name (a blank group is "Products"), in the order the groups first appear.
    private func grouped(_ items: [ItemRow]) -> [(name: String, items: [ItemRow])] {
        var order: [String] = [], map: [String: [ItemRow]] = [:]
        for i in items {
            let n = i.groupName.trimmingCharacters(in: .whitespaces).isEmpty ? "Products" : i.groupName
            if map[n] == nil { order.append(n) }
            map[n, default: []].append(i)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

/// One product: photo when it has one, name, unit, price with the MRP struck through when higher; out of stock is greyed and can't be added.
private struct ProductRow: View {
    let item: ItemRow
    let qty: Int
    let canAdd: Bool
    var onOpen: () -> Void
    var onAdd: (Int) -> Void

    var body: some View {
        let dim = item.inStock ? 1.0 : 0.45
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    if let url = Backend.shared.listingPhoto(item.photos.first?.url ?? item.photoUrl) {
                        RemotePhoto(url: url) { Color.clear }.frame(width: 52, height: 52).background(BucksColor.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous)).opacity(dim)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                        if !item.unit.isEmpty { Muted(item.unit, maxLines: 1) }
                        if !item.description.isEmpty { Muted(item.description, maxLines: 1) }
                        if let s = item.stock, (1...5).contains(s), item.inStock { Text("Only \(s) left").bucks(.labelSmall).foregroundStyle(BucksColor.warn) }
                        HStack(spacing: 6) {
                            Text(rupeesGrouped(item.price)).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                            if let mrp = item.mrp, mrp > item.price { Text(rupeesGrouped(mrp)).bucks(.labelSmall).strikethrough().foregroundStyle(BucksColor.onSurfaceVariant) }
                        }.padding(.top, 2)
                    }.opacity(dim).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !item.inStock { PillGrey("Out of stock").padding(.leading, 12) } else if canAdd { AddStepper(qty: qty, onAdd: onAdd).padding(.leading, 12) }
        }.padding(.vertical, 10)
    }
}

/// A product's own page as a sheet: its photos, description, price, stock and the add button.
private struct ItemSheet: View {
    let item: ItemRow
    let qty: Int
    let canAdd: Bool
    var onAdd: (Int) -> Void

    var body: some View {
        let urls = item.photos.compactMap { Backend.shared.listingPhoto($0.url) }
        let photos = urls.isEmpty ? [Backend.shared.listingPhoto(item.photoUrl)].compactMap { $0 } : urls
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos, id: \.self) { u in
                                RemotePhoto(url: u) { Color.clear }.frame(width: photos.count == 1 ? 280 : 220, height: photos.count == 1 ? 280 : 220)
                                    .background(BucksColor.surfaceContainer).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                            }
                        }
                    }.padding(.bottom, 12)
                }
                Text(item.name).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted([item.unit.isEmpty ? nil : item.unit, item.details.str("brand"), item.groupName.isEmpty ? nil : item.groupName].compactMap { $0 }.joined(separator: " · "))
                HStack(spacing: 8) {
                    Text(inr(item.price)).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
                    if let mrp = item.mrp, mrp > item.price {
                        Text(inr(mrp)).bucks(.bodyMedium).strikethrough().foregroundStyle(BucksColor.onSurfaceVariant)
                        PillGood("\((mrp - item.price) * 100 / mrp)% off")
                    }
                }.padding(.top, 8)
                if !item.inStock { PillGrey("Out of stock") }
                else if let s = item.stock, s <= 5 { Text("Only \(s) left").bucks(.labelLarge).foregroundStyle(BucksColor.warn) }
                if !item.description.isEmpty { Text(item.description).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 12) }
                if canAdd { HStack { Spacer(); AddStepper(qty: qty, onAdd: onAdd) }.padding(.top, 16) }
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

struct JobsTab: View {
    let profile: ListingProfile
    var onJobs: () -> Void
    var body: some View {
        let p = profile
        VStack(alignment: .leading, spacing: 0) {
            BucksCard(onTap: onJobs) {
                HStack(spacing: 12) {
                    Image(systemName: "briefcase.fill").font(.system(size: 19)).foregroundStyle(BucksColor.onPrimaryContainer).frame(width: 44, height: 44).background(Circle().fill(BucksColor.primaryContainer))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Open jobs at \(p.listing.title)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(p.openJobs > 0 ? "\(plural(p.openJobs, "opening")) right now. Apply with your skill profile." : "See openings here and apply with your skill profile.")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant)
                }
            }
            if p.mine { Muted("Post a job and manage applications from Menu > Bucks Pro.").padding(.top, 10) }
        }.padding(Gutter)
    }
}

// MARK: - SKILL: Services and Feed

struct ServicesTab: View {
    let profile: ListingProfile
    var onRequest: (String) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        let p = profile, l = p.listing, services = p.services, first = l.title.split(separator: " ").first.map(String.init) ?? l.title
        let busy = session.discover.chatStarting
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "indianrupeesign.circle").font(.system(size: 18)).foregroundStyle(BucksColor.onSurfaceVariant)
                Text(proRate(l.details, minPrice: services.map(\.price).min())).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            }
            if services.isEmpty {
                Muted(p.mine ? "No services listed yet. Add them from Menu > Bucks Pro." : "No services listed yet. Describe what you need; \(first) confirms the price before starting.").padding(.top, 8)
                if !p.mine { PrimaryButton("Request a visit", enabled: !busy) { onRequest("Hi, I need help with \(l.category.trimmingCharacters(in: .whitespaces).isEmpty ? "a job" : l.category.lowercased()). Are you available?") }.padding(.top, 14) }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(services.enumerated()), id: \.offset) { i, s in
                        if i > 0 { BucksDivider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                                Muted(servicePrice(s), maxLines: 1)
                                if !s.description.isEmpty { Muted(s.description, maxLines: 2) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if !p.mine {
                                SmallButton("Request", tonal: true, enabled: !busy) { onRequest("Hi, I'd like to request: \(s.name) (₹\(s.price)\(s.unit.isEmpty ? "" : " " + s.unit)). When are you free?") }.fixedSize()
                            }
                        }.padding(.vertical, 10)
                    }
                }.padding(.top, 8)
                if !p.mine { Notice("Request opens a chat with \(first), who confirms the price before starting.").padding(.top, 14) }
            }
        }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Starting from ₹500 · per visit · about 1 hour", or "Price on quote".
    private func servicePrice(_ s: ItemRow) -> String {
        let pricing = s.details.str("pricing") ?? "FIXED"
        let money: String
        if pricing == "QUOTE" && s.price == 0 { money = "Price on quote" }
        else if pricing == "FROM" { money = "From \(inr(s.price))" }
        else if pricing == "QUOTE" { money = "Usually \(inr(s.price))" }
        else { money = inr(s.price) }
        let unit = !s.unit.isEmpty ? s.unit : (pricing == "HOURLY" ? "per hour" : pricing == "VISIT" ? "per visit" : nil)
        return [money, unit, s.details.str("duration").map { "about \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}

struct FeedTab: View {
    let profile: ListingProfile
    @Environment(AppSession.self) private var session
    var body: some View {
        let p = profile
        if p.posts.isEmpty {
            Muted(p.mine ? "No posts yet. Post as \(p.listing.title) from the feed." : "\(p.listing.title) hasn't posted yet. Sync to see their posts in your feed when they do.").padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) { ForEach(p.posts) { post in ListingPost(post: post, title: p.listing.title); BucksDivider() } }
        }
    }
}

/// A listing's post, laid out like the feed: who and when, text, the first photo, and its counts.
private struct ListingPost: View {
    let post: PostRow
    let title: String
    @Environment(AppSession.self) private var session
    var body: some View {
        let who = session.social.nameOf(post.authorId)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Avatar(initials: initials(title).isEmpty ? "?" : initials(title), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted([who == "…" ? nil : who, discoverAgo(post.createdAt)].compactMap { $0 }.joined(separator: " · "))
                }
            }
            if !post.body.isEmpty { Text(post.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10) }
            if let path = post.media.first?["path"]?.string, !path.isEmpty {
                SignedImage(bucket: "posts", path: path).frame(maxWidth: .infinity).frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous)).padding(.top, 10)
            }
            HStack(spacing: 14) {
                count("arrow.up", post.up); count("arrow.down", post.down); count("bubble.left", post.comments)
            }.padding(.top, 10)
        }.padding(.horizontal, Gutter).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func count(_ icon: String, _ n: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(BucksColor.onSurfaceVariant)
            Text("\(n)").bucks(.labelLarge).foregroundStyle(BucksColor.onSurfaceVariant)
        }
    }
}

// MARK: - About and Reviews (every kind)

/// Details keys the About tab renders with a proper label; everything else gets a generic row.
private let knownDetails: Set<String> = ["hours", "free_delivery", "delivery_radius_km", "delivery_radius_m", "rate", "level", "languages", "vehicle_kind", "vehicle", "kind", "model", "bio",
                                         "cod", "mode", "price", "price_unit", "deposit", "area_sqft", "bedrooms", "furnishing", "available_from", "year", "km_driven", "negotiable"]

struct AboutTab: View {
    let profile: ListingProfile
    var onOpenListing: (String) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        let p = profile, l = p.listing, det = l.details
        let vk = l.kind == "DRIVER" ? driverKind(det, category: l.category) : nil
        let distance = p.at.map { formatDistance(Geo.distanceKm(session.here, $0) * 1000) }
        let badges = session.services.badges[l.id] ?? []
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if !l.description.isEmpty { Text(l.description).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface) } else { Muted("No description yet.") }
                let area = [l.area.isEmpty ? nil : l.area, distance.map { "\($0) from you" }].compactMap { $0 }.joined(separator: " · ")
                AboutRow(icon: "mappin.and.ellipse", label: "Area", value: area.isEmpty ? "Not shared" : area)
                if !l.category.isEmpty { AboutRow(icon: "square.grid.2x2", label: "Category", value: l.category) }
                kindRows(p, vk)
                // Anything else the owner filled in, as a labelled row: "delivery_note" -> "Delivery note".
                ForEach(extraKeys(det), id: \.self) { k in
                    if let v = det.str(k) {
                        AboutRow(icon: "info.circle", label: k.replacingOccurrences(of: "_", with: " ").prefix(1).uppercased() + k.replacingOccurrences(of: "_", with: " ").dropFirst(), value: v == "true" ? "Yes" : v == "false" ? "No" : v)
                    }
                }
                // Checked documents: a tick for each, with the number only where the law wants customers to see it (FSSAI, GST, RERA).
                // The files themselves are private to the owner and Bucks.
                ForEach(badges) { b in
                    AboutRow(icon: "checkmark.shield", label: b.label, value: [b.number.isEmpty ? nil : b.number, "checked by Bucks", b.expiresOn.map { "valid till \(humanDate($0))" }].compactMap { $0 }.joined(separator: " · "))
                }
                AboutRow(icon: "checkmark.seal", label: "Status", value: status(p))
            }.padding(Gutter)
            if !p.similar.isEmpty {
                Rectangle().fill(BucksColor.surfaceContainer).frame(height: 8)
                SectionTitle("More \((l.category.isEmpty ? kindLabel(l.kind) + "s" : l.category).lowercased()) nearby").padding(.init(top: 16, leading: Gutter, bottom: 4, trailing: Gutter))
                ForEach(p.similar) { h in
                    ListRow(h.title, subtitle: [formatDistance(h.distanceM), h.area.isEmpty ? nil : h.area, onlineText(h.kind, h.online)].compactMap { $0 }.joined(separator: " · "), onTap: { onOpenListing(h.id) },
                            leading: { ListingPhoto(url: Backend.shared.listingPhoto(h.photoUrl), title: h.title, size: 40) },
                            trailing: { TrustBadge(up: h.trustUp, down: h.trustDown, compact: true) })
                    BucksDivider()
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ p: ListingProfile) -> String {
        switch p.listing.status {
        case "LIVE": "Live: \(p.recommendations) people nearby recommended it in person"
        case "PENDING": "Not live yet: \(p.recommendations) of \(ListingsStore.NEEDED) recommendations"
        default: "Suspended"
        }
    }

    private func extraKeys(_ det: JSONValue) -> [String] {
        (det.object ?? [:]).filter { k, v in
            if knownDetails.contains(k) { return false }
            switch v { case .string, .number, .bool: return true; default: return false }
        }.keys.sorted()
    }

    @ViewBuilder private func kindRows(_ p: ListingProfile, _ vk: VehicleKind?) -> some View {
        let l = p.listing, det = l.details
        switch l.kind {
        case "BUSINESS":
            if let v = det.str("hours") { AboutRow(icon: "clock", label: "Hours", value: v) }
            if let v = det.str("free_delivery") { AboutRow(icon: "shippingbox", label: "Delivery", value: v == "true" ? "Free delivery" : "Delivery charged") }
            if let v = det.str("delivery_radius_km").map({ "\($0) km" }) ?? det.str("delivery_radius_m").flatMap(Double.init).map(formatDistance) { AboutRow(icon: "location", label: "Delivers within", value: v) }
        case "SKILL":
            AboutRow(icon: "indianrupeesign.circle", label: "Rate", value: proRate(det, minPrice: p.services.map(\.price).min()))
            if let v = det.str("level") { AboutRow(icon: "rosette", label: "Experience", value: v.lowercased().prefix(1).uppercased() + v.lowercased().dropFirst()) }
            if !det.list("languages").isEmpty { AboutRow(icon: "globe", label: "Languages", value: det.list("languages").joined(separator: ", ")) }
        case "ASSET":
            AboutRow(icon: "building.2", label: "Listing", value: assetPriceLine(det))
            if let v = det.str("deposit").flatMap(Double.init), v > 0 { AboutRow(icon: "indianrupeesign.circle", label: "Deposit", value: inr(Int(v))) }
            if let v = det.str("area_sqft") { AboutRow(icon: "square.grid.2x2", label: "Size", value: "\(v) sq ft") }
            if let v = det.str("bedrooms") { AboutRow(icon: "house", label: "Bedrooms", value: v) }
            if let v = det.str("furnishing") { AboutRow(icon: "bed.double", label: "Furnishing", value: v) }
            if let v = det.str("available_from") { AboutRow(icon: "calendar", label: "Available from", value: v) }
            if let v = det.str("year") { AboutRow(icon: "calendar", label: "Year", value: v) }
            if let v = det.str("km_driven") { AboutRow(icon: "car", label: "Driven", value: "\(v) km") }
            if det.str("negotiable") == "true" { AboutRow(icon: "indianrupeesign.circle", label: "Price", value: "Negotiable") }
        case "DRIVER":
            AboutRow(icon: vk?.systemImage ?? "car", label: "Vehicle", value: [vk?.label, det.str("model")].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Not shared")
            if let vk { AboutRow(icon: "indianrupeesign.circle", label: "Fare", value: "₹\(vk.farePerKm) per km, plus ₹20 base fare" + (vk.carriesPassengers ? "" : " · parcels only")) }
            if !det.list("languages").isEmpty { AboutRow(icon: "globe", label: "Languages", value: det.list("languages").joined(separator: ", ")) }
            if let v = det.str("bio") { AboutRow(icon: "person", label: "About", value: v) }
        default: EmptyView()
        }
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

private struct AboutRow: View {
    let icon: String; let label: String; let value: String
    init(icon: String, label: String, value: String) { self.icon = icon; self.label = label; self.value = value }
    init<S: StringProtocol>(icon: String, label: S, value: String) { self.icon = icon; self.label = String(label); self.value = value }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).bucks(.labelSmall).foregroundStyle(BucksColor.onSurfaceVariant)
                Text(value).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
            }
            Spacer(minLength: 0)
        }.padding(.top, 16).accessibilityElement(children: .combine)
    }
}

struct ReviewsTab: View {
    let profile: ListingProfile
    @Environment(AppSession.self) private var session
    var body: some View {
        let p = profile
        VStack(alignment: .leading, spacing: 0) {
            HStack { TrustBadge(up: p.listing.trustUp, down: p.listing.trustDown); Spacer(minLength: 0) }
            Notice(p.mine ? "Reviews come only from customers after a completed order or trip. Nobody can add or remove them by hand."
                   : "Reviews come only from completed orders and trips. After yours, leave one from that order or trip page.").padding(.top, 12)
            if p.reviews.isEmpty {
                Muted(p.mine ? "No reviews yet. They arrive as customers complete orders or trips." : "No reviews yet. Order or book here first; then you can leave the first one.").padding(.vertical, 16)
            }
            ForEach(p.reviews) { r in
                let up = r.vote > 0, name = session.social.nameOf(r.authorId)
                HStack(alignment: .top, spacing: 12) {
                    Avatar(initials: initials(name).isEmpty ? "?" : initials(name), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text(name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                            Muted("  \(discoverAgo(r.createdAt))")
                        }
                        Text(r.comment).bucks(.bodySmall).foregroundStyle(BucksColor.onSurface).padding(.top, 2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(up ? BucksColor.good : BucksColor.bad)
                            .accessibilityLabel(up ? "Recommends" : "Doesn't recommend")
                        if up { PillGood("Recommends") } else { PillBad("Doesn't recommend") }
                    }
                }.padding(.vertical, 14)
                BucksDivider()
            }
        }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gallery

/// A listing's photos (portfolio for a pro) in a grid; tap for full size with the caption.
struct GalleryTab: View {
    let listing: ListingRow
    @State private var open: Int?

    var body: some View {
        let g = listing.gallery
        VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: g.count, by: 3)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(start..<min(start + 3, g.count), id: \.self) { i in
                        Button { open = i } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit).overlay { RemotePhoto(url: URL(string: g[i].url)) { Color.clear } }
                                .background(BucksColor.surfaceContainer).clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
                        }.buttonStyle(.plain).accessibilityLabel(g[i].caption.isEmpty ? "Photo \(i + 1)" : g[i].caption)
                    }
                    ForEach(0..<(3 - min(3, g.count - start)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .padding(Gutter)
        .bucksFullScreenCover(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
            if let i = open, g.indices.contains(i) { PhotoViewer(photos: g, index: i, onIndex: { open = $0 }, onClose: { open = nil }) }
        }
    }
}

private struct PhotoViewer: View {
    let photos: [MediaPhoto]
    let index: Int
    var onIndex: (Int) -> Void
    var onClose: () -> Void

    var body: some View {
        let ph = photos[index]
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 48, height: 48) }.buttonStyle(.plain).accessibilityLabel("Close")
                Text("\(index + 1) of \(photos.count)").bucks(.labelLarge).foregroundStyle(.white)
                Spacer()
            }
            ZStack {
                RemotePhoto(url: URL(string: ph.url), contentMode: .fit) { Color.clear }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    if index > 0 { arrow("chevron.left", "Previous") { onIndex(index - 1) } }
                    Spacer()
                    if index < photos.count - 1 { arrow("chevron.right", "Next") { onIndex(index + 1) } }
                }
            }
            if !ph.caption.isEmpty { Text(ph.caption).bucks(.bodyMedium).foregroundStyle(.white).padding(Gutter).frame(maxWidth: .infinity, alignment: .leading) }
        }.background(Color.black.ignoresSafeArea())
    }
    private func arrow(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 48, height: 48).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
