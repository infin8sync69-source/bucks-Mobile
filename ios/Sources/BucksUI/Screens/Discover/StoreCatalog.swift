import SwiftUI
import BucksCore

/*
 * The Products tab of a shop (StoreCatalog.kt): what a shopper needs to find and buy something in a catalogue of hundreds.
 *  - Categories down the left (thumbnail and name), "All" first; searching looks across every category.
 *  - One search box, Sort and Filter (in stock, on sale, price band) with the result count read out as it changes.
 *  - Products, not variants: a product with options (Small / Regular / Set) is one card ("From ₹1,500", "3 options") that opens a sheet
 *    to pick the option; a plain product adds straight from the card and turns into a - / + stepper.
 *  - 24 at a time with "Show more", so a 300-item shop opens fast.
 */

private let catalogPage = 24

private enum CatalogSort: Int, CaseIterable {
    case featured, rec, low, high, name
    var label: String {
        switch self { case .featured: "Featured"; case .rec: "Most recommended"; case .low: "Price: low to high"; case .high: "Price: high to low"; case .name: "Name: A to Z" }
    }
}
private let priceBands: [(label: String, range: ClosedRange<Int>)] = [("Any price", 0...Int.max), ("Under ₹1,000", 0...999), ("₹1,000 to ₹3,000", 1000...3000),
                                                                     ("₹3,000 to ₹10,000", 3001...10_000), ("Above ₹10,000", 10_001...Int.max)]

private func rs(_ n: Int) -> String { rupeesGrouped(n) }

/// Shopify-sized photos: a small file for a card, a big one for the sheet. Other hosts are used as they are.
private func sized(_ url: String?, _ width: Int) -> URL? {
    guard let u = Backend.shared.listingPhoto(url) else { return nil }
    let s = u.absoluteString
    guard s.contains("cdn.shopify.com") else { return u }
    return URL(string: s + (s.contains("?") ? "&" : "?") + "width=\(width)") ?? u
}
private func photosOf(_ i: ItemRow) -> [String] {
    let p = i.photos.map(\.url)
    return p.isEmpty ? [i.photoUrl].compactMap { $0 }.filter { !$0.isEmpty } : p
}
private func optionLabel(_ i: ItemRow) -> String { i.details.str("variant") ?? (i.unit.isEmpty ? i.name : i.unit) }

/// One product as the shopper sees it: its options (variants) together, in the store's order.
struct CatalogProduct: Identifiable {
    let key: String
    let title: String
    let group: String
    let options: [ItemRow]
    var id: String { key }
    let photos: [String]
    let from: Int
    let to: Int
    let anyInStock: Bool
    /// The biggest discount among the options, in percent; nil when nothing is marked down.
    let off: Int?
    private let text: String

    init(key: String, title: String, group: String, options: [ItemRow]) {
        self.key = key; self.title = title; self.group = group; self.options = options
        var seen = Set<String>()
        photos = Array(options.flatMap(photosOf).filter { seen.insert($0).inserted }.prefix(8))
        from = options.map(\.price).min() ?? 0; to = options.map(\.price).max() ?? 0
        anyInStock = options.contains { $0.inStock }
        let offs = options.compactMap { o -> Int? in guard let m = o.mrp, m > o.price else { return nil }; return Int(Double(m - o.price) * 100 / Double(m)) }
        off = offs.max().flatMap { $0 >= 1 ? $0 : nil }
        let about = options.first?.description ?? ""
        text = ([title, group] + options.map { optionLabel($0) + " " + ($0.details.str("sku") ?? "") } + [about]).joined(separator: " ").lowercased()
    }
    var multi: Bool { options.count > 1 }
    func matches(_ q: String) -> Bool { q.lowercased().split(separator: " ").allSatisfy { text.contains($0) } }
}

/// Items grouped into products by details.product_id (else the item itself), in first-appearance order.
private func productsOf(_ items: [ItemRow]) -> [CatalogProduct] {
    var order: [String] = [], groups: [String: [ItemRow]] = [:]
    for i in items {
        let k = i.details.str("product_id") ?? i.id ?? i.name
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(i)
    }
    return order.compactMap { k in
        guard let os = groups[k], let first = os.first else { return nil }
        let g = first.groupName.trimmingCharacters(in: .whitespaces)
        return CatalogProduct(key: k, title: first.details.str("product") ?? first.name, group: g.isEmpty ? "Products" : g, options: os)
    }
}

struct StoreProducts: View {
    let profile: ListingProfile
    var onMessage: () -> Void
    var onCart: () -> Void
    @Environment(AppSession.self) private var session
    @State private var query = ""
    @State private var cat: String?
    @State private var sort: CatalogSort = .featured
    @State private var inStockOnly = false
    @State private var onSaleOnly = false
    @State private var band = 0
    @State private var shown = catalogPage
    @State private var filterSheet = false
    @State private var open: CatalogProduct?
    @State private var ratings: [String: RatingSummary] = [:]

    var body: some View {
        let p = profile, listing = p.listing
        if p.products.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Muted(p.mine ? "No products yet. Add them from Menu > Bucks Pro." : "\(listing.title) hasn't listed products yet. Message them to ask what's in stock.")
                if !p.mine { SmallButton("Message", tonal: true, action: onMessage).fixedSize().padding(.top, 12) }
            }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            catalogue(p)
        }
    }

    private struct FilterKey: Hashable { var cat: String?; var query: String; var sort: Int; var stock: Bool; var sale: Bool; var band: Int }

    private func catalogue(_ p: ListingProfile) -> some View {
        let listing = p.listing
        let canAdd = !p.mine && listing.online
        let all = productsOf(p.products)
        var catOrder: [String] = [], catCount: [String: Int] = [:], catPhoto: [String: String] = [:]
        for pr in all {
            if catCount[pr.group] == nil { catOrder.append(pr.group) }
            catCount[pr.group, default: 0] += 1
            if catPhoto[pr.group] == nil, let ph = pr.photos.first { catPhoto[pr.group] = ph }
        }
        let filtersOn = (inStockOnly ? 1 : 0) + (onSaleOnly ? 1 : 0) + (band != 0 ? 1 : 0)
        let result = filtered(all)
        let rail = catOrder.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            if !listing.online && !p.mine { Notice("\(listing.title) is closed now. You can order once they open again.").padding(.horizontal, Gutter).padding(.vertical, 4) }
            searchField(listing.title).padding(.horizontal, Gutter)
            HStack(spacing: 8) {
                Menu {
                    ForEach(CatalogSort.allCases, id: \.self) { s in
                        Button { sort = s } label: { if sort == s { Label(s.label, systemImage: "checkmark") } else { Text(s.label) } }
                    }
                } label: { toolPill("arrow.up.arrow.down", "Sort") }
                .accessibilityLabel("Sort: \(sort.label)")
                Button { filterSheet = true } label: { toolPill("slider.horizontal.3", filtersOn > 0 ? "Filter (\(filtersOn))" : "Filter") }
                    .buttonStyle(.plain).accessibilityLabel(filtersOn > 0 ? "Filter, \(filtersOn) on" : "Filter")
                Spacer(minLength: 0)
                Text(result.count == 1 ? "1 product" : "\(result.count) products").bucks(.labelMedium).foregroundStyle(BucksColor.onSurfaceVariant)
                    .accessibilityLabel("\(result.count) products shown")
            }.padding(.horizontal, Gutter).padding(.vertical, 8)
            HStack(alignment: .top, spacing: 0) {
                if rail {
                    VStack(spacing: 0) {
                        CategoryTab(name: "All", count: all.count, photo: catOrder.lazy.compactMap { catPhoto[$0] }.first, selected: query.isEmpty && cat == nil) { cat = nil; query = "" }
                        ForEach(catOrder, id: \.self) { g in
                            CategoryTab(name: g, count: catCount[g] ?? 0, photo: catPhoto[g], selected: query.isEmpty && cat == g) { cat = g; query = "" }
                        }
                    }.frame(width: 80).padding(.bottom, 8)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(!query.trimmingCharacters(in: .whitespaces).isEmpty ? "Results for “\(query.trimmingCharacters(in: .whitespaces))”" : cat ?? "All products")
                        .bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.bottom, 8).accessibilityAddTraits(.isHeader)
                    if result.isEmpty {
                        VStack(spacing: 0) {
                            Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundStyle(BucksColor.onSurfaceVariant)
                            Text("Nothing matches").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10)
                            Muted(filtersOn > 0 ? "Try removing a filter." : "Try another word, or pick a category.", align: .center).padding(.top, 4)
                            if filtersOn > 0 || !query.isEmpty {
                                SmallButton("Clear filters and search", tonal: true) { query = ""; inStockOnly = false; onSaleOnly = false; band = 0 }.fixedSize().padding(.top, 12)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        let page = Array(result.prefix(shown))
                        ForEach(Array(stride(from: 0, to: page.count, by: 2)), id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                ProductCard(product: page[i], listing: listing, rating: ratings[page[i].key], canAdd: canAdd) { open = page[i] }
                                if i + 1 < page.count {
                                    ProductCard(product: page[i + 1], listing: listing, rating: ratings[page[i + 1].key], canAdd: canAdd) { open = page[i + 1] }
                                } else { Color.clear.frame(maxWidth: .infinity) }
                            }.padding(.bottom, 8)
                        }
                        if result.count > shown { GhostButton("Show more · \(result.count - shown) left") { shown += catalogPage } }
                    }
                }.padding(.leading, rail ? 6 : Gutter).padding(.trailing, Gutter)
            }
        }
        .padding(.top, 8)
        .task(id: listing.id) { await loadRatings(listing.id) }
        .onChange(of: FilterKey(cat: cat, query: query, sort: sort.rawValue, stock: inStockOnly, sale: onSaleOnly, band: band)) { _, _ in shown = catalogPage }
        .sheet(item: $open) { pr in
            ProductSheet(product: pr, listing: listing, rating: ratings[pr.key], canAdd: canAdd, isOwner: p.mine,
                         onRated: { Task { await loadRatings(listing.id) } }, onCart: { open = nil; onCart() })
        }
        .sheet(isPresented: $filterSheet) { filterPanel(count: result.count) }
    }

    private func filtered(_ all: [CatalogProduct]) -> [CatalogProduct] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let range = priceBands[band].range
        let l = all.filter { pr in
            (!q.isEmpty || cat == nil || pr.group == cat) && (q.isEmpty || pr.matches(q)) &&
            (!inStockOnly || pr.anyInStock) && (!onSaleOnly || pr.off != nil) && (band == 0 || pr.options.contains { range.contains($0.price) })
        }
        switch sort {
        case .featured: return l
        case .rec: return l.sorted { a, b in
            let pa = ratings[a.key]?.percent ?? -1, pb = ratings[b.key]?.percent ?? -1
            return pa != pb ? pa > pb : (ratings[a.key]?.votes ?? 0) > (ratings[b.key]?.votes ?? 0)
        }
        case .low: return l.sorted { $0.from < $1.from }
        case .high: return l.sorted { $0.from > $1.from }
        case .name: return l.sorted { $0.title.lowercased() < $1.title.lowercased() }
        }
    }

    /// Recommend / not-recommend counts for every product in one call; the cards show the share that recommend.
    private func loadRatings(_ listingId: String) async {
        let rows = (try? await Backend.shared.productRatings(listingId)) ?? []
        ratings = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func searchField(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(BucksColor.onSurfaceVariant)
            TextField("Search \(title)", text: Binding(get: { query }, set: { query = String($0.prefix(60)) }))
                .font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface).submitLabel(.search).autocorrectionDisabled()
                .accessibilityLabel("Search \(title)")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, 2).frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
    }

    private func toolPill(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16))
            Text(label).bucks(.labelLarge).lineLimit(1)
        }
        .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 12).frame(minHeight: 48)
        .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func filterPanel(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filter").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).accessibilityAddTraits(.isHeader)
            Toggle("In stock only", isOn: $inStockOnly).font(.bucks(.bodyLarge)).tint(BucksColor.primary).frame(minHeight: 56)
            Toggle("On sale", isOn: $onSaleOnly).font(.bucks(.bodyLarge)).tint(BucksColor.primary).frame(minHeight: 56)
            FieldLabel("Price").padding(.top, 8)
            FlowLayout(spacing: 8) {
                ForEach(priceBands.indices, id: \.self) { i in BucksChip(priceBands[i].label, selected: band == i) { band = i } }
            }
            HStack(spacing: 10) {
                GhostButton("Reset") { inStockOnly = false; onSaleOnly = false; band = 0 }
                PrimaryButton("Show \(count) products") { filterSheet = false }
            }.padding(.top, 20)
        }
        .padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        .presentationDetents([.medium])
        .background(BucksColor.surface.ignoresSafeArea())
    }
}

/// One category down the left: a round thumbnail, its name and how many products; the selected one has a bar on its right edge.
private struct CategoryTab: View {
    let name: String; let count: Int; let photo: String?; let selected: Bool; let action: () -> Void
    var body: some View {
        let c = selected ? BucksColor.primary : BucksColor.onSurfaceVariant
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(BucksColor.surfaceContainer)
                        if let u = sized(photo, 150) { ShimmerImage(url: u).clipShape(Circle()) } else { Image(systemName: "storefront").foregroundStyle(c) }
                    }
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(selected ? BucksColor.primary : .clear, lineWidth: 2))
                    Text(name).font(.bucks(.labelSmall)).fontWeight(selected ? .semibold : .regular).foregroundStyle(c)
                        .multilineTextAlignment(.center).lineLimit(2).padding(.top, 4)
                }.frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
                Rectangle().fill(selected ? BucksColor.primary : .clear).frame(width: 3)
            }.frame(minHeight: 88).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count) products").accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A product card: photo, name, price (with the marked-down price struck through), then Add / a stepper / Choose / Sold out.
private struct ProductCard: View {
    let product: CatalogProduct; let listing: ListingRow; let rating: RatingSummary?; let canAdd: Bool; let onOpen: () -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        let pr = product, one = pr.options[0]
        let qty = pr.options.reduce(0) { $0 + session.commerce.qty($1.id ?? "") }
        let dim = pr.anyInStock ? 1.0 : 0.5
        let price = pr.multi && pr.from != pr.to ? "From \(rs(pr.from))" : rs(pr.from)
        let say = [pr.title, price, pr.multi ? "\(pr.options.count) options" : nil, pr.off.map { "\($0) percent off" }, pr.anyInStock ? nil : "sold out",
                   rating?.percent.map { "\($0) percent recommend, \(rating!.votes) \(rating!.votes == 1 ? "vote" : "votes")" }, qty > 0 ? "\(qty) in your cart" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .top) {
                        Color.clear.aspectRatio(1, contentMode: .fit).overlay {
                            if let u = sized(pr.photos.first, 400) { ShimmerImage(url: u) }
                            else { ZStack { BucksColor.surfaceContainer; Image(systemName: "photo").foregroundStyle(BucksColor.onSurfaceVariant) } }
                        }.clipped().opacity(dim)
                        HStack {
                            if let off = pr.off {
                                Text("\(off)% off").bucks(.labelSmall).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BucksColor.good))
                            }
                            Spacer()
                            if qty > 0 {
                                Text("\(qty)").bucks(.labelSmall).foregroundStyle(BucksColor.onPrimary).padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(BucksColor.primary))
                            }
                        }.padding(6)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pr.title).bucks(.bodyMedium).fontWeight(.medium).foregroundStyle(BucksColor.onSurface).lineLimit(2).multilineTextAlignment(.leading).opacity(dim)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(price).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).opacity(dim)
                            if !pr.multi, let mrp = one.mrp, mrp > one.price { Text(rs(mrp)).bucks(.labelSmall).strikethrough().foregroundStyle(BucksColor.onSurfaceVariant) }
                        }.padding(.top, 4)
                        if let r = rating, let pct = r.percent {
                            let tone = pct >= 50 ? BucksColor.good : BucksColor.bad
                            HStack(spacing: 2) {
                                Image(systemName: pct >= 50 ? "arrow.up" : "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(tone)
                                Text("\(pct)%").bucks(.labelMedium).foregroundStyle(tone)
                                Text(" (\(r.votes))").bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant).lineLimit(1)
                            }.padding(.top, 2)
                        }
                        if pr.multi { Muted("\(pr.options.count) options", maxLines: 1).padding(.top, 2) }
                    }.padding(.horizontal, 8).padding(.top, 8)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Group {
                if !pr.anyInStock { PillGrey("Sold out") }
                else if !canAdd { EmptyView() }
                else if pr.multi {
                    Button(action: onOpen) {
                        Text(qty > 0 ? "In cart · Change" : "Choose").bucks(.labelLarge).foregroundStyle(BucksColor.primary).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
                    }.buttonStyle(.plain)
                } else { AddStepper(qty: qty) { d in session.commerce.add(listing, one, d) } }
            }.padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
        .accessibilityElement(children: .combine).accessibilityLabel(say)
    }
}

/// The product page in a sheet: photos, price, the option chips, description, add to cart, then what people say with recommend / not recommend.
private struct ProductSheet: View {
    let product: CatalogProduct; let listing: ListingRow; let rating: RatingSummary?; let canAdd: Bool; let isOwner: Bool
    var onRated: () -> Void
    var onCart: () -> Void
    @Environment(AppSession.self) private var session
    @State private var pick: String?
    /// The catalogue carries one photo and no description; the full row (all photos, description) is fetched for the option being looked at.
    @State private var full: ItemRow?
    @State private var fullFailed = false

    var body: some View {
        let pr = product
        let item = pr.options.first { $0.id == (pick ?? defaultPick) } ?? pr.options[0]
        var seen = Set<String>()
        let photos = Array(((full.map(photosOf) ?? photosOf(item)) + pr.photos).filter { seen.insert($0).inserted }.prefix(8))
        let about = cleanAbout(full?.description ?? "", title: pr.title)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { i, u in
                                ShimmerImage(url: sized(u, 900)).frame(width: photos.count == 1 ? 300 : 240, height: photos.count == 1 ? 300 : 240)
                                    .clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                                    .accessibilityLabel("\(pr.title), photo \(i + 1) of \(photos.count)")
                            }
                            if full == nil && !fullFailed { ForEach(0..<2, id: \.self) { _ in SkeletonBox(radius: BucksRadius.medium).frame(width: 240, height: 240) } }
                        }
                    }.padding(.bottom, 12)
                }
                Text(pr.title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).accessibilityAddTraits(.isHeader)
                let sub = [pr.group == "Products" ? nil : pr.group, item.details.str("vendor")].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Muted(sub) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rs(item.price)).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
                    if let mrp = item.mrp, mrp > item.price {
                        Text(rs(mrp)).bucks(.bodyMedium).strikethrough().foregroundStyle(BucksColor.onSurfaceVariant)
                        Text("\(Int(Double(mrp - item.price) * 100 / Double(mrp)))% off").bucks(.labelLarge).foregroundStyle(BucksColor.good)
                    }
                }.padding(.top, 8)
                if let r = rating, let pct = r.percent { Muted("\(pct)% recommend · \(r.votes) \(r.votes == 1 ? "vote" : "votes")").padding(.top, 2) }
                if pr.multi {
                    FieldLabel("Choose an option").padding(.top, 14)
                    FlowLayout(spacing: 8) {
                        ForEach(pr.options, id: \.self) { o in
                            BucksChip(optionLabel(o) + " · " + rs(o.price) + (o.inStock ? "" : " · sold out"), selected: o.id == item.id) { pick = o.id }
                        }
                    }
                }
                if !item.inStock { PillGrey("Sold out").padding(.top, 8) }
                else if let s = item.stock, s <= 5 { Text("Only \(s) left").bucks(.labelLarge).foregroundStyle(BucksColor.warn).padding(.top, 8) }
                if !about.isEmpty { Text(about).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 12) }
                else if full == nil && !fullFailed { SkeletonLines(lines: 4).padding(.top, 14) }
                if canAdd && item.inStock {
                    let qty = session.commerce.qty(item.id ?? "")
                    HStack {
                        Text(qty > 0 ? "In your cart" : "Add to cart").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                        AddStepper(qty: qty) { d in session.commerce.add(listing, item, d) }
                    }.padding(.top, 16)
                }
                if session.commerce.count > 0 {
                    DarkButton("View cart · \(plural(session.commerce.count, "item"))", action: onCart).padding(.top, 14)
                }
                ProductFeedback(listing: listing, product: pr, rating: rating, isOwner: isOwner, onRated: onRated)
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .task(id: item.id) {
            full = nil; fullFailed = false
            guard let id = item.id else { fullFailed = true; return }
            let r = try? await Backend.shared.itemById(id)
            if Task.isCancelled { return }
            full = r ?? nil; fullFailed = full == nil
        }
    }

    private var defaultPick: String? { product.options.first { $0.inStock }?.id ?? product.options.first?.id }

    /// The description without the title the shop repeats at its start.
    private func cleanAbout(_ s: String, title: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix(title) { t = String(t.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return t
    }
}

/// Recommend or not recommend a product, with an optional comment, and what others wrote. One rating per person, changeable and removable.
private struct ProductFeedback: View {
    let listing: ListingRow; let product: CatalogProduct; let rating: RatingSummary?; let isOwner: Bool
    var onRated: () -> Void
    @Environment(AppSession.self) private var session
    @State private var draft = 0
    @State private var text = ""
    @State private var busy = false
    @State private var comments: [ProductComment]?
    @State private var more = false

    var body: some View {
        let mine = rating?.mine
        VStack(alignment: .leading, spacing: 0) {
            BucksDivider().padding(.top, 20)
            Text("What people say").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 16).accessibilityAddTraits(.isHeader)
            Muted(rating?.percent.map { "\($0)% recommend this · \(rating!.up) recommend, \(rating!.down) don't" } ?? "No ratings yet. Be the first.").padding(.top, 2)
            if let pct = rating?.percent {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BucksColor.bad.opacity(0.35))
                        Capsule().fill(BucksColor.good).frame(width: g.size.width * CGFloat(pct) / 100)
                    }
                }.frame(height: 6).padding(.top, 8).accessibilityHidden(true)
            }
            if isOwner {
                Muted("This is your product. Customers' feedback and comments show here, and you get a notification for each comment.").padding(.top, 10)
            } else {
                HStack(spacing: 8) {
                    voteButton(1, "Recommend", "arrow.up", mine: mine)
                    voteButton(-1, "Not recommend", "arrow.down", mine: mine)
                }.padding(.top, 12)
                if draft != 0 || mine != nil {
                    BucksField(Binding(get: { text }, set: { text = String($0.prefix(500)) }), placeholder: "Add a comment (optional)", singleLine: false, minLines: 2).padding(.top, 10)
                    HStack(spacing: 8) {
                        SmallButton(busy ? "Sending…" : mine != nil ? "Update my feedback" : "Post feedback", enabled: !busy && (draft != 0 || !text.trimmingCharacters(in: .whitespaces).isEmpty)) { submit(mine) }
                            .fixedSize()
                        if mine != nil {
                            Button("Remove mine") { remove() }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary).frame(minHeight: 44).disabled(busy)
                        }
                        Spacer()
                        Muted("\(text.count)/500").fixedSize()
                    }
                }
            }
            commentList
        }
        .task(id: product.key) { await load() }
    }

    private func voteButton(_ v: Int, _ label: String, _ icon: String, mine: Int?) -> some View {
        let on = draft == v || (draft == 0 && mine == v)
        let tone = v == 1 ? BucksColor.good : BucksColor.bad
        return Button { draft = draft == v ? 0 : v } label: {
            HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)); Text(label).bucks(.labelLarge).lineLimit(1) }
                .foregroundStyle(on ? tone : BucksColor.onSurface).frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(on ? tone.opacity(0.15) : .clear))
                .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(on ? tone : BucksColor.outline, lineWidth: on ? 2 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var commentList: some View {
        if let list = comments {
            if list.isEmpty { Muted("No comments yet.").padding(.top, 12) }
            else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, c in
                        let who = c.name.isEmpty ? "Someone" : c.name
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(initials: initials(who), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(who).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                                    Image(systemName: c.vote == 1 ? "arrow.up" : "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(c.vote == 1 ? BucksColor.good : BucksColor.bad)
                                    Muted("· " + discoverAgo(c.updatedAt), maxLines: 1)
                                }
                                Text(c.comment).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(who), \(c.vote == 1 ? "recommends" : "does not recommend"), \(discoverAgo(c.updatedAt)). \(c.comment)")
                    }
                }.padding(.top, 12)
                if more, let last = list.last { GhostButton("Show more comments") { Task { await load(before: last.updatedAt) } }.padding(.top, 12) }
            }
        } else {
            VStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { _ in HStack(alignment: .top, spacing: 10) { SkeletonBox(radius: 18).frame(width: 36, height: 36); SkeletonLines(lines: 2) } }
            }.padding(.top, 14)
        }
    }

    private func load(before: String? = nil) async {
        let page = (try? await Backend.shared.productComments(listingId: listing.id, key: product.key, before: before)) ?? []
        comments = before == nil ? page : (comments ?? []) + page
        more = page.count >= 20
    }

    private func submit(_ mine: Int?) {
        let vote = draft != 0 ? draft : (mine ?? 1)
        Task {
            busy = true; defer { busy = false }
            do {
                try await Backend.shared.rateProduct(listingId: listing.id, key: product.key, vote: vote, comment: text.trimmingCharacters(in: .whitespacesAndNewlines))
                session.toast("Thanks, your feedback is posted."); draft = 0; text = ""; onRated(); await load()
            } catch { session.toast(friendlyError(error)) }
        }
    }

    private func remove() {
        Task {
            busy = true; defer { busy = false }
            do {
                try await Backend.shared.clearProductRating(listingId: listing.id, key: product.key)
                session.toast("Your rating was removed."); draft = 0; text = ""; onRated(); await load()
            } catch { session.toast(friendlyError(error)) }
        }
    }
}
