import SwiftUI
import BucksCore

/// Add or edit one product or service. With no `item` it shows the listing's list instead (Android's ITEM_EDIT convention:
/// nil -> the list, "new" -> add, any other id -> edit that item).
struct ItemEditScreen: View {
    var listing: String
    var item: String?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        if item == nil { ItemsScreen(listingId: listing) } else { editor }
    }

    private var editor: some View {
        let m = session.listings
        let l = m.listing(listing), service = l?.kind == "SKILL"
        let existing = (item != "new") ? item.flatMap { id in m.items[listing]?.first { $0.id == id } } : nil
        return Group {
            if item != "new" && existing == nil {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 0) {
                        BucksTopBar(title: service ? "Edit service" : "Edit product", onBack: { router.pop() })
                        if m.items[listing] != nil {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Not found").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted("This \(service ? "service" : "product") was removed.").padding(.top, 4)
                                SmallButton("Back", tonal: true) { router.pop() }.padding(.top, 14)
                            }.padding(Gutter)
                        } else { CenteredLoading() }
                    }
                }
            } else {
                ItemForm(listingId: listing, service: service, existing: existing).id(existing?.id ?? "new")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: listing) { if !m.loaded { m.refresh() }; if m.items[listing] == nil { m.loadItems(listing) } }
    }
}

/// A listing's products (business) or services (skill), grouped by section, with an inline in-stock switch.
struct ItemsScreen: View {
    let listingId: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let m = session.listings
        let l = m.listing(listingId), service = l?.kind == "SKILL", noun = service ? "service" : "product"
        let rows = m.items[listingId]
        VStack(spacing: 0) {
            ContentColumn {
                VStack(alignment: .leading, spacing: 0) {
                    BucksTopBar(title: service ? "Services" : "Products", onBack: { router.pop() })
                    if let l { Muted(l.title).padding(.horizontal, Gutter) }
                    if let rows {
                        if rows.isEmpty {
                            BucksCard {
                                Text("No \(noun)s yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted(service ? "Add each service with a price, like \"Tap repair · ₹300 per visit\". People see them on your profile and can message you about them."
                                              : "Add what you sell with a price and pack size, like \"Sugar · ₹45 · 1 kg\". Customers search by product name and order from your profile. Use groups to keep long lists tidy: Rice, Dals, Snacks.").padding(.top, 4)
                            }.padding(Gutter)
                        } else { list(m, rows, service: service, noun: noun) }
                    } else { CenteredLoading() }
                    Spacer(minLength: 0)
                }
            }
            PrimaryButton("Add \(noun)") { router.push(.itemEdit(listing: listingId, item: "new")) }.padding(.horizontal, Gutter).padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: listingId) { if !m.loaded { m.refresh() }; m.loadItems(listingId) }
    }

    private func list(_ m: ListingsStore, _ rows: [ItemRow], service: Bool, noun: String) -> some View {
        let grouped = Dictionary(grouping: rows) { $0.groupName.trimmingCharacters(in: .whitespaces) }
        let groups = grouped.keys.sorted { a, b in a.isEmpty != b.isEmpty ? !a.isEmpty : a.lowercased() < b.lowercased() }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.self) { g in
                    SectionTitle(g.isEmpty ? (groups.count > 1 ? "Other" : "All \(noun)s") : g).padding(.horizontal, Gutter).padding(.vertical, 8)
                    ForEach(grouped[g] ?? [], id: \.id) { row in
                        let mrpNote = row.mrp.flatMap { $0 > row.price ? "  (MRP ₹\($0))" : nil } ?? ""
                        ListRow(row.name, subtitle: ["₹\(row.price)\(mrpNote)", row.unit.isEmpty ? nil : row.unit].compactMap { $0 }.joined(separator: " · "), onTap: { router.push(.itemEdit(listing: listingId, item: row.id)) }) {
                            PhotoOrIcon(url: row.photoUrl, systemImage: service ? "wrench.and.screwdriver.fill" : "bag.fill", size: 48)
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 0) {
                                Toggle("", isOn: studioSwitchBinding(row.inStock) { m.setInStock(row, $0) }).labelsHidden().tint(BucksColor.primary)
                                Muted(row.inStock ? (service ? "Available" : "In stock") : (service ? "Paused" : "Out of stock"), align: .trailing)
                            }.fixedSize()
                        }
                        BucksDivider()
                    }
                }
            }.padding(.top, 8).padding(.bottom, 16)
        }
    }
}

private struct ItemForm: View {
    let listingId: String
    let service: Bool
    let existing: ItemRow?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    @State private var name: String
    @State private var description: String
    @State private var price: String
    @State private var mrp: String
    @State private var unit: String
    @State private var group: String
    @State private var inStock: Bool
    @State private var countStock: Bool
    @State private var stock: String
    @State private var pricing: String
    @State private var duration: String
    @State private var brand: String
    /// Photos it already has (older items only have photo_url) and new ones picked here; the first is the main photo.
    @State private var keep: [MediaPhoto]
    @State private var added: [Picked] = []
    @State private var picking = false
    @State private var confirmDelete = false

    init(listingId: String, service: Bool, existing: ItemRow?) {
        self.listingId = listingId; self.service = service; self.existing = existing
        let d = existing?.details ?? .emptyObject
        _name = State(initialValue: existing?.name ?? "")
        _description = State(initialValue: existing?.description ?? "")
        _price = State(initialValue: existing.map { String($0.price) } ?? "")
        _mrp = State(initialValue: existing?.mrp.map(String.init) ?? "")
        _unit = State(initialValue: existing?.unit ?? "")
        _group = State(initialValue: existing?.groupName ?? "")
        _inStock = State(initialValue: existing?.inStock ?? true)
        _countStock = State(initialValue: existing?.stock != nil)
        _stock = State(initialValue: existing?.stock.map(String.init) ?? "")
        _pricing = State(initialValue: d.sStr("pricing").isEmpty ? "FIXED" : d.sStr("pricing"))
        _duration = State(initialValue: d.sStr("duration"))
        _brand = State(initialValue: d.sStr("brand"))
        let own = existing?.photos ?? []
        _keep = State(initialValue: !own.isEmpty ? own : (existing?.photoUrl).flatMap { $0.isEmpty ? nil : [MediaPhoto(url: $0)] } ?? [])
    }

    private var m: ListingsStore { session.listings }
    private var noun: String { service ? "service" : "product" }

    var body: some View {
        let existingGroups = Array(Set((m.items[listingId] ?? []).map { $0.groupName.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        VStack(spacing: 0) {
            ContentColumn {
                VStack(spacing: 0) {
                    BucksTopBar(title: existing == nil ? "Add \(noun)" : "Edit \(noun)", onBack: { router.pop() })
                    if m.busy { StudioBusyBar() }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Photos first: they sell the item.
                            FieldLabel("Photos (up to 8, the first is the main one)")
                            photoStrip.padding(.bottom, 14)
                            BucksField($name.limited(80), label: service ? "Service" : "Product name", placeholder: service ? "Tap repair" : "Sona masoori rice")
                            BucksField($description.limited(1000), label: "Description (optional)", placeholder: service ? "What's included, what isn't, how long it takes" : "Size, material, taste, what's in the box", singleLine: false, minLines: 2)
                            if service {
                                FieldLabel("Pricing")
                                ChipRow(Studio.servicePricing.map(\.label), selected: Studio.servicePricing.first { $0.key == pricing }?.label) { picked in
                                    if let k = Studio.servicePricing.first(where: { $0.label == picked }) { pricing = k.key }
                                }.padding(.bottom, 12)
                            }
                            HStack(alignment: .top, spacing: 10) {
                                BucksField($price.digits(7), label: service && pricing == "QUOTE" ? "Typical price (₹, optional)" : "Price (₹)", placeholder: "45", keyboard: .number)
                                if !service { BucksField($mrp.digits(7), label: "MRP (₹, optional)", placeholder: "50", keyboard: .number) }
                            }
                            if !service, (Int(mrp) ?? 0) > (Int(price) ?? 0), !price.isEmpty { Muted("Customers see the discount: ₹\(price) instead of ₹\(mrp).").padding(.bottom, 10) }
                            BucksField($unit.limited(30), label: service ? "Charged per" : "Pack size or unit", placeholder: service ? "per visit" : "1 kg")
                            ChipRow(service ? Studio.units.filter { $0.hasPrefix("per") } : Studio.units.filter { !$0.hasPrefix("per") }, selected: unit.isEmpty ? nil : unit) { unit = $0 }.padding(.bottom, 14)
                            if service { BucksField($duration.limited(40), label: "Takes about (optional)", placeholder: "1 hour, 2 days") }
                            else { BucksField($brand.limited(40), label: "Brand (optional)", placeholder: "Aashirvaad, Nandini") }
                            BucksField($group.limited(40), label: service ? "Group (optional)" : "Group or section (optional)", placeholder: service ? "Repairs" : "Rice and grains")
                            if !existingGroups.isEmpty { ChipRow(existingGroups, selected: group.trimmingCharacters(in: .whitespaces).isEmpty ? nil : group.trimmingCharacters(in: .whitespaces)) { group = $0 }.padding(.bottom, 14) }
                            SectionTitle("Availability").padding(.top, 4).padding(.bottom, 2)
                            SwitchRow(title: service ? "Available now" : "In stock", detail: service ? "Switch off when you can't take this work for a while." : "Out-of-stock products stay on your profile but can't be ordered.", isOn: $inStock)
                            if !service {
                                SwitchRow(title: "Count stock", detail: "Bucks takes each order off the count and stops orders at 0. Cancelled orders go back.", isOn: $countStock)
                                if countStock { BucksField($stock.digits(6), label: "How many you have", placeholder: "25", keyboard: .number) }
                            }
                        }.padding(.horizontal, Gutter).padding(.top, 8).padding(.bottom, 16)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                PrimaryButton(m.busy ? "Saving…" : existing == nil ? "Add \(noun)" : "Save changes", enabled: !m.busy) { save() }
                if existing != nil { BadButton("Remove this \(noun)") { confirmDelete = true }.padding(.top, 4) }
            }.padding(.horizontal, Gutter).padding(.vertical, 12)
        }
        .bucksPhotoPicker(isPresented: $picking, maxCount: 8) { files in
            let room = max(0, 8 - keep.count - added.count)
            if files.count > room { session.toast("Up to 8 photos per \(noun).") }
            added.append(contentsOf: files.prefix(room).compactMap(StudioPhoto.asListingPhoto))
        }
        .bucksConfirm(isPresented: $confirmDelete, title: "Remove \(existing?.name ?? "")?", message: "It disappears from your profile and search. Orders already placed aren't affected.", confirmTitle: "Remove", destructive: true) {
            if let existing { m.deleteItem(existing) { router.pop() } }
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(keep.enumerated()), id: \.element.url) { i, ph in
                    ItemPhotoThumb(isMain: i == 0, onMain: i == 0 ? nil : { keep.remove(at: i); keep.insert(ph, at: 0) }, onRemove: { keep.remove(at: i) }) { StudioRemoteImage(url: ph.url) }
                }
                ForEach(Array(added.enumerated()), id: \.offset) { i, p in
                    ItemPhotoThumb(isMain: keep.isEmpty && i == 0, onMain: nil, onRemove: { added.remove(at: i) }) { StudioPickedImage(picked: p) }
                }
                if keep.count + added.count < 8 {
                    Button { picking = true } label: {
                        VStack(spacing: 0) { Image(systemName: "camera.fill").foregroundStyle(BucksColor.primary); Text("Add").font(.bucks(.labelSmall)).foregroundStyle(BucksColor.onSurface) }
                            .frame(width: 84, height: 84)
                            .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces), p = Int(price), mp = Int(mrp), st = Int(stock)
        if n.isEmpty { session.toast("Give the \(noun) a name."); return }
        if p == nil && !(service && pricing == "QUOTE") { session.toast("Enter the price in rupees."); return }
        if let mp, let p, mp < p { session.toast("MRP should be the same as or more than the selling price."); return }
        if countStock && st == nil { session.toast("Enter how many you have, or switch off stock counting."); return }
        var d = existing?.details.object ?? [:]
        for k in ["pricing", "duration", "brand"] { d.removeValue(forKey: k) }
        if service {
            d["pricing"] = .string(pricing)
            if !duration.trimmingCharacters(in: .whitespaces).isEmpty { d["duration"] = .string(duration.trimmingCharacters(in: .whitespaces)) }
        } else if !brand.trimmingCharacters(in: .whitespaces).isEmpty { d["brand"] = .string(brand.trimmingCharacters(in: .whitespaces)) }
        let row = ItemRow(id: existing?.id, listingId: listingId, kind: service ? "SERVICE" : "PRODUCT", name: n, price: p ?? 0, mrp: service ? nil : mp, unit: unit.trimmingCharacters(in: .whitespaces),
                          groupName: group.trimmingCharacters(in: .whitespaces), photoUrl: existing?.photoUrl, inStock: inStock, sort: existing?.sort ?? (m.items[listingId] ?? []).count,
                          description: description.trimmingCharacters(in: .whitespacesAndNewlines), stock: countStock ? st : nil, photos: existing?.photos ?? [], details: .object(d))
        m.saveItem(row, keep: keep, add: added) { router.pop() }
    }
}

/// One photo in the item form: "Main" on the first, tap another to make it main, x to take it out.
private struct ItemPhotoThumb<Image_: View>: View {
    let isMain: Bool
    let onMain: (() -> Void)?
    let onRemove: () -> Void
    @ViewBuilder let image: () -> Image_
    var body: some View {
        image().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
            .overlay(alignment: .bottomLeading) { if isMain { Pill("Main", bg: BucksColor.primary, fg: BucksColor.onPrimary).padding(4) } }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(Color.black.opacity(0.5))) }
                    .buttonStyle(.plain).padding(2).accessibilityLabel("Remove photo")
            }
            .contentShape(Rectangle()).onTapGesture { if !isMain { onMain?() } }
    }
}

private extension Binding where Value == String {
    func limited(_ n: Int) -> Binding<String> { Binding(get: { wrappedValue }, set: { wrappedValue = String($0.prefix(n)) }) }
    func digits(_ n: Int) -> Binding<String> { Binding(get: { wrappedValue }, set: { wrappedValue = String($0.filter(\.isNumber).prefix(n)) }) }
}
