import SwiftUI
import BucksCore

/// Create or edit a BUSINESS, SKILL, ASSET or DRIVER listing. Fields differ by `kind`; kind-specific values go into listings.details.
/// The location is where the phone is when the listing is created (so create it at the shop); on edit it only moves if the owner asks.
struct ListingEditScreen: View {
    var id: String?
    var kind: String
    var service: String?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let m = session.listings
        let existing = id.flatMap { m.listing($0) }
        Group {
            if id != nil && existing == nil {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 0) {
                        BucksTopBar(title: "Edit \(Studio.kindLabel(kind).lowercased())", onBack: { router.pop() })
                        if m.loaded {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Listing not found").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted("It may have been deleted, or you're no longer part of it.").padding(.top, 4)
                                SmallButton("Back", tonal: true) { router.pop() }.padding(.top, 14)
                            }.padding(Gutter)
                        } else if let err = m.error { ListingsLoadError(message: err) { m.refresh() }.padding(Gutter) }
                        else { CenteredLoading() }
                    }
                }
            } else {
                ListingForm(kind: kind, existing: existing, initialService: service).id(existing?.id ?? "new")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { if !m.loaded { m.refresh() } }
    }
}

private func limited(_ b: Binding<String>, _ n: Int) -> Binding<String> { Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.prefix(n)) }) }
private func digits(_ b: Binding<String>, _ n: Int) -> Binding<String> { Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.filter(\.isNumber).prefix(n)) }) }

private struct ListingForm: View {
    let kind: String
    let existing: ListingRow?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    @State private var title: String
    @State private var category: String
    /// Which Services tile a business belongs to; it decides the documents it needs. Fixed once the listing is live.
    @State private var service: String
    @State private var description: String
    @State private var area: String
    @State private var hours: String
    @State private var freeDelivery: Bool
    @State private var radius: String
    @State private var cod: Bool
    // E-commerce: ship anywhere in India by courier (customers far away can only order this way).
    @State private var ships: Bool
    @State private var shipFee: String
    @State private var freeAbove: String
    @State private var dispatchDays: String
    @State private var level: String
    @State private var rate: String
    @State private var languages: Set<String>
    @State private var vehicleKind: String
    @State private var model: String
    // Assets: what it is, what the owner wants (sell / rent / lease / PG), the price and the facts buyers ask first.
    @State private var mode: String
    @State private var price: String
    @State private var priceUnit: String
    @State private var deposit: String
    @State private var areaSqft: String
    @State private var bedrooms: String
    @State private var furnishing: String
    @State private var availableFrom: String
    @State private var year: String
    @State private var kmDriven: String
    @State private var negotiable: Bool
    @State private var photo: Picked?
    @State private var picking = false
    @State private var moveHere: Bool
    @State private var confirmDelete = false
    @State private var areaSeeded = false

    init(kind: String, existing: ListingRow?, initialService: String?) {
        self.kind = kind; self.existing = existing
        let d = existing?.details ?? .emptyObject
        _title = State(initialValue: existing?.title ?? "")
        _category = State(initialValue: existing?.category ?? "")
        _service = State(initialValue: existing?.service.flatMap { businessServices.contains($0) ? $0 : nil } ?? initialService.flatMap { businessServices.contains($0) ? $0 : nil } ?? existing.map { serviceForCategory($0.category) } ?? "FOOD")
        _description = State(initialValue: existing?.description ?? "")
        _area = State(initialValue: "")
        _hours = State(initialValue: d.sStr("hours"))
        _freeDelivery = State(initialValue: d.sBool("free_delivery"))
        _radius = State(initialValue: d.sInt("delivery_radius_km").map(String.init) ?? "3")
        _cod = State(initialValue: d.sBool("cod"))
        _ships = State(initialValue: d.sBool("ships_india"))
        _shipFee = State(initialValue: d.sInt("ship_fee").map(String.init) ?? "")
        _freeAbove = State(initialValue: d.sInt("free_ship_above").map(String.init) ?? "")
        _dispatchDays = State(initialValue: d.sStr("dispatch_days"))
        _level = State(initialValue: d.sStr("level").isEmpty ? "Intermediate" : d.sStr("level"))
        _rate = State(initialValue: d.sStr("rate"))
        _languages = State(initialValue: Set(d.sStrings("languages")))
        _vehicleKind = State(initialValue: d.sStr("vehicle_kind").isEmpty ? "AUTO" : d.sStr("vehicle_kind"))
        _model = State(initialValue: d.sStr("model"))
        _mode = State(initialValue: d.sStr("mode").isEmpty ? "SELL" : d.sStr("mode"))
        func pos(_ k: String) -> String { d.sNum(k).map { Int($0) }.flatMap { $0 > 0 ? String($0) : nil } ?? "" }
        _price = State(initialValue: pos("price"))
        _priceUnit = State(initialValue: d.sStr("price_unit").isEmpty ? "TOTAL" : d.sStr("price_unit"))
        _deposit = State(initialValue: pos("deposit"))
        _areaSqft = State(initialValue: pos("area_sqft"))
        _bedrooms = State(initialValue: d.sInt("bedrooms").map(String.init) ?? "")
        _furnishing = State(initialValue: d.sStr("furnishing"))
        _availableFrom = State(initialValue: d.sStr("available_from"))
        _year = State(initialValue: d.sInt("year").map(String.init) ?? "")
        _kmDriven = State(initialValue: d.sInt("km_driven").map(String.init) ?? "")
        _negotiable = State(initialValue: d.sBool("negotiable"))
        _moveHere = State(initialValue: existing == nil)
    }

    private var m: ListingsStore { session.listings }
    private var fix: LatLng? { session.hereKnown ? session.here : nil }
    private var owner: Bool { existing == nil || m.isOwner(existing?.id ?? "") }
    private var serviceLocked: Bool { existing != nil && existing?.status != "PENDING" }
    private var driverTitle: String {
        let n = session.me?.name ?? ""
        return "\(n.isEmpty ? "Driver" : n) - \(vehicleKindLabel(vehicleKind))"
    }
    private var screenTitle: String {
        if existing == nil {
            switch kind { case "BUSINESS": return "Add a business"; case "SKILL": return "Add a skill"; case "ASSET": return "List an asset"; default: return "Your driver profile" }
        }
        return "Edit \(Studio.kindLabel(kind).lowercased())"
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentColumn {
                VStack(spacing: 0) {
                    BucksTopBar(title: screenTitle, onBack: { router.pop() })
                    if m.busy { StudioBusyBar() }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            switch kind {
                            case "BUSINESS": business
                            case "SKILL": skill
                            case "ASSET": asset
                            default: driver
                            }
                            PhotoField(label: kind == "BUSINESS" || kind == "ASSET" ? "Cover photo" : "Profile photo", url: existing?.photoUrl, preview: photo,
                                       systemImage: kind == "BUSINESS" ? "storefront.fill" : kind == "ASSET" ? Studio.assetIcon(category) : "person.fill",
                                       onPick: { picking = true }, onClear: { photo = nil })
                            FieldLabel("Location")
                            locationNote
                        }.padding(.horizontal, Gutter).padding(.top, 8).padding(.bottom, 16)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                PrimaryButton(m.busy ? "Saving…" : existing == nil ? "Save" : "Save changes", enabled: !m.busy && (existing != nil || fix != nil)) { save() }
                if let existing, kind != "DRIVER", m.canManage(existing.id) {
                    SmallButton("Documents for Bucks to check", tonal: true) { router.push(.listingDocs(existing.id)) }.padding(.bottom, 6)
                }
                if existing != nil && owner { BadButton("Delete this \(Studio.kindLabel(kind).lowercased())") { confirmDelete = true }.padding(.top, 4) }
            }.padding(.horizontal, Gutter).padding(.vertical, 12)
        }
        .onAppear { if !areaSeeded { areaSeeded = true; if area.isEmpty { area = initialArea } } }
        .bucksPhotoPicker(isPresented: $picking, maxCount: 1) { files in
            guard let first = files.first else { return }
            if let ok = StudioPhoto.asListingPhoto(first) { photo = ok } else { session.toast("Couldn't read that image. Try a JPG or PNG photo.") }
        }
        .bucksConfirm(isPresented: $confirmDelete, title: "Delete \(existing?.title ?? "")?", message: "Its products, members, recommendations and reviews go with it. Orders customers already placed stay in their history. This can't be undone.", confirmTitle: "Delete", destructive: true) {
            if let existing { m.deleteListing(existing.id) { router.pop() } }
        }
    }

    private var initialArea: String {
        if let a = existing?.area, !a.isEmpty { return a }
        if let a = session.me?.area.split(separator: ",").first.map({ String($0).trimmingCharacters(in: .whitespaces) }), !a.isEmpty { return a }
        return areaOf(session.hereLabel) ?? ""
    }

    // MARK: kind sections

    @ViewBuilder private var business: some View {
        BucksField(limited($title, 80), label: "Business name", placeholder: "Sri Lakshmi Stores")
        FieldLabel("Service")
        FlowChips(businessServices.compactMap { serviceDef($0)?.label }, selected: [serviceDef(service)?.label ?? ""]) { picked in
            if serviceLocked { session.toast("A live listing can't move to another service. Ask Bucks support.") }
            else if let key = businessServices.first(where: { serviceDef($0)?.label == picked }) {
                service = key
                if !(serviceDef(key)?.categories.contains(category) ?? false) { category = "" }
            }
        }
        Muted(serviceLocked ? "Customers find you under \(serviceDef(service)?.label ?? ""). It can't change while you're live." : "Where customers find you in Services. It decides the documents Bucks checks.").padding(.top, 6).padding(.bottom, 12)
        FieldLabel("Category"); FlowChips(serviceDef(service)?.categories ?? [], selected: [category]) { category = $0 }
        Spacer().frame(height: 14)
        BucksField(limited($description, 600), label: "About the business", placeholder: "What you sell, what you're known for", singleLine: false, minLines: 3)
        BucksField(limited($hours, 80), label: "Opening hours", placeholder: "9 am - 9 pm, closed Sundays")
        BucksField(limited($area, 60), label: "Area", placeholder: "Jayanagar")
        SectionTitle("Delivery and payment").padding(.top, 6).padding(.bottom, 4)
        SwitchRow(title: "Free delivery", detail: "You pay the rider's fee instead of the customer.", isOn: $freeDelivery)
        BucksField(digits($radius, 2), label: "Delivery radius (km)", placeholder: "3", keyboard: .number)
        SwitchRow(title: "Cash on delivery", detail: "With your own store riders, or with the courier on shipped orders. You collect the cash.", isOn: $cod)
        SectionTitle("Ship across India").padding(.top, 14).padding(.bottom, 4)
        SwitchRow(title: "Ship by courier", detail: "Customers anywhere can find you and order. You accept, pack, hand it to a courier and enter the tracking number.", isOn: $ships)
        if ships {
            BucksField(digits($shipFee, 5), label: "Shipping fee (₹)", placeholder: "99, or 0 for free shipping", keyboard: .number)
            BucksField(digits($freeAbove, 6), label: "Free shipping above (₹)", placeholder: "1999, or leave empty for none", keyboard: .number)
            BucksField(limited($dispatchDays, 30), label: "Ships in (days)", placeholder: "2 to 4")
            Muted("Buyers pay the items and the shipping to you (UPI, or cash on delivery if you turned it on). You have 24 hours to accept each order.").padding(.bottom, 8)
        }
    }

    @ViewBuilder private var skill: some View {
        BucksField(limited($title, 80), label: "Skill", placeholder: "Plumber, Maths tutor, Wedding photographer")
        FieldLabel("Category"); FlowChips(Studio.skillCategories, selected: [category]) { category = $0 }
        Spacer().frame(height: 14)
        FieldLabel("Experience"); HStack(spacing: 8) { ForEach(Studio.levels, id: \.self) { l in BucksChip(l, selected: level == l) { level = l } } }
        Spacer().frame(height: 14)
        BucksField(limited($rate, 60), label: "Rate", placeholder: "₹300 per visit + parts")
        FieldLabel("Languages you speak"); FlowChips(Studio.languages, selected: languages) { toggleLanguage($0) }
        Spacer().frame(height: 14)
        BucksField(limited($description, 600), label: "About your work", placeholder: "Years of experience, what you specialise in", singleLine: false, minLines: 3)
        BucksField(limited($area, 60), label: "Area you work in", placeholder: "Jayanagar")
    }

    private var assetTitleHint: String {
        switch category {
        case "Vehicle": "Honda Activa 2019, single owner"
        case "Plot / Land": "30x40 plot near Kanakapura Road"
        case "Shop", "Office", "Commercial space": "Ground-floor shop on 11th Main"
        default: "2BHK flat in 4th Block, east facing"
        }
    }

    @ViewBuilder private var asset: some View {
        FieldLabel("What is it?")
        FlowChips(Studio.assetTypes, selected: [category]) { category = $0 }
        Muted(Studio.propertyTypes.contains(category) ? "Property: Bucks checks the owner's ID (and RERA for builders) before it goes live. Files stay private." : "Vehicles and equipment need no documents to go live.").padding(.top, 6).padding(.bottom, 14)
        FieldLabel("You want to")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Studio.assetModes.filter { $0.key != "PG" || Studio.residentialTypes.contains(category) }, id: \.key) { k in
                    BucksChip(k.label, selected: mode == k.key) {
                        mode = k.key
                        priceUnit = k.key == "SELL" ? "TOTAL" : k.key == "LEASE" ? "YEAR" : "MONTH"
                    }
                }
            }
        }
        Spacer().frame(height: 14)
        BucksField(limited($title, 80), label: "Title", placeholder: assetTitleHint)
        HStack(alignment: .top, spacing: 10) {
            BucksField(digits($price, 10), label: mode == "SELL" ? "Price (₹)" : "Rent (₹)", placeholder: mode == "SELL" ? "4500000" : "28000", keyboard: .number)
            if mode != "SELL" { BucksField(digits($deposit, 10), label: "Deposit (₹)", placeholder: "150000", keyboard: .number) }
        }
        Group {
            if let p = Int(price), p > 0 {
                let unit = Studio.priceUnits.first { $0.key == priceUnit }?.label
                Muted(Studio.rupees(p) + (unit.flatMap { $0 != "Total" ? " \($0)" : nil } ?? ""))
            } else { Muted("Leave the price empty to show \"Price on request\".") }
        }.padding(.bottom, 6)
        ChipRow(Studio.priceUnits.map(\.label), selected: Studio.priceUnits.first { $0.key == priceUnit }?.label) { picked in
            if let k = Studio.priceUnits.first(where: { $0.label == picked }) { priceUnit = k.key }
        }.padding(.bottom, 6)
        SwitchRow(title: "Price is negotiable", detail: nil, isOn: $negotiable)
        SectionTitle("Details").padding(.top, 8).padding(.bottom, 4)
        if category == "Vehicle" {
            HStack(alignment: .top, spacing: 10) {
                BucksField(digits($year, 4), label: "Year", placeholder: "2019", keyboard: .number)
                BucksField(digits($kmDriven, 7), label: "Km driven", placeholder: "18000", keyboard: .number)
            }
        } else if category != "Equipment" && category != "Other" {
            HStack(alignment: .top, spacing: 10) {
                BucksField(digits($areaSqft, 7), label: "Size (sq ft)", placeholder: "1100", keyboard: .number)
                if Studio.residentialTypes.contains(category) { BucksField(digits($bedrooms, 2), label: "Bedrooms", placeholder: "2", keyboard: .number) }
            }
        }
        if Studio.residentialTypes.contains(category) || ["Office", "Shop", "Commercial space"].contains(category) {
            FieldLabel("Furnishing")
            ChipRow(Studio.furnishing, selected: furnishing.isEmpty ? nil : furnishing) { furnishing = furnishing == $0 ? "" : $0 }.padding(.bottom, 14)
        }
        if mode != "SELL" { BucksField(limited($availableFrom, 40), label: "Available from", placeholder: "Immediately, or 1 November") }
        BucksField(limited($description, 600), label: "Description", placeholder: "Condition, what's included, nearby landmarks, who it suits", singleLine: false, minLines: 3)
        BucksField(limited($area, 60), label: "Area / locality", placeholder: "Jayanagar 4th Block")
        Muted("Add more photos from the listing's Photos tab after saving.").padding(.bottom, 10)
    }

    @ViewBuilder private var driver: some View {
        BucksCard(padding: 12) {
            Muted("Shown to riders as")
            Text(driverTitle).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
        }.padding(.bottom, 14)
        FieldLabel("What you drive")
        HStack(spacing: 8) { ForEach(Studio.vehicleKinds, id: \.key) { k in BucksChip(k.label, selected: vehicleKind == k.key, systemImage: Studio.vehicleIcon(k.key)) { vehicleKind = k.key } } }
        Muted(vehicleKind == "BIKE" ? "Bikes carry parcels and food, never passengers." : "Rides and deliveries. Add the vehicle itself under Vehicles; it goes online after Bucks checks its documents.").padding(.top, 6).padding(.bottom, 14)
        BucksField(limited($model, 60), label: "Vehicle model", placeholder: "Bajaj RE, Maruti Dzire")
        FieldLabel("Languages you speak"); FlowChips(Studio.languages, selected: languages) { toggleLanguage($0) }
        Spacer().frame(height: 14)
        BucksField(limited($description, 600), label: "About you", placeholder: "Years driving, areas you know well", singleLine: false, minLines: 3)
        BucksField(limited($area, 60), label: "Home area", placeholder: "Jayanagar")
    }

    @ViewBuilder private var locationNote: some View {
        let near = areaOf(session.hereLabel)
        if existing == nil, fix != nil {
            Muted("Saved as where you are now: near \(near ?? "your current location"). People within 3 km of this spot can recommend you, so create it " + (kind == "ASSET" ? "at the property or where the asset is kept." : "at your shop or where you usually work."))
        } else if existing == nil {
            Notice(session.locationGranted ? "Waiting for your location… Bucks saves the listing where you are, so create it at your shop or where you usually work."
                                           : "Turn on location so Bucks can save where your shop is. Neighbours within 3 km of that spot can recommend you, so create it at your shop or where you usually work.")
        } else if fix != nil {
            SwitchRow(title: "Move to where I am now", detail: "Near \(near ?? "your current location"). Leave off if you're not at the shop.", isOn: $moveHere)
        } else {
            Muted(session.locationGranted ? "Stays where it is. Waiting for your location before it can move to where you are now." : "Stays where it is. Turn on location to move it to where you are now.")
        }
    }

    private func toggleLanguage(_ l: String) { if languages.contains(l) { languages.remove(l) } else { languages.insert(l) } }

    // MARK: save

    private func buildDetails() -> JSONValue {
        var d: [String: JSONValue] = existing?.details.object ?? [:]   // keep anything other features stored
        let langs = JSONValue.array(Studio.languages.filter { languages.contains($0) }.map { .string($0) } + languages.filter { !Studio.languages.contains($0) }.sorted().map { .string($0) })
        switch kind {
        case "BUSINESS":
            d["hours"] = .string(hours.trimmingCharacters(in: .whitespaces)); d["free_delivery"] = .bool(freeDelivery)
            d["delivery_radius_km"] = .number(Double(Int(radius) ?? 0)); d["cod"] = .bool(cod)
            d["ships_india"] = .bool(ships)
            if ships {
                d["ship_fee"] = .number(Double(Int(shipFee) ?? 0)); d["free_ship_above"] = .number(Double(Int(freeAbove) ?? 0))
                d["dispatch_days"] = .string(dispatchDays.trimmingCharacters(in: .whitespaces))
            }
        case "SKILL":
            d["level"] = .string(level); d["rate"] = .string(rate.trimmingCharacters(in: .whitespaces)); d["languages"] = langs
        case "ASSET":
            d["mode"] = .string(mode); d["price"] = .number(Double(Int(price) ?? 0)); d["price_unit"] = .string(priceUnit); d["negotiable"] = .bool(negotiable)
            // Blank facts are removed, not saved as empty: the profile only shows what the owner filled in.
            for (k, v) in [("deposit", deposit), ("area_sqft", areaSqft), ("bedrooms", bedrooms), ("year", year), ("km_driven", kmDriven)] {
                if let n = Int(v), n > 0 { d[k] = .number(Double(n)) } else { d.removeValue(forKey: k) }
            }
            for (k, v) in [("furnishing", furnishing), ("available_from", availableFrom)] {
                if !v.trimmingCharacters(in: .whitespaces).isEmpty { d[k] = .string(v.trimmingCharacters(in: .whitespaces)) } else { d.removeValue(forKey: k) }
            }
        default:
            d["vehicle_kind"] = .string(vehicleKind); d["model"] = .string(model.trimmingCharacters(in: .whitespaces)); d["languages"] = langs
        }
        return .object(d)
    }

    private func save() {
        let t = kind == "DRIVER" ? driverTitle : title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            switch kind { case "SKILL": session.toast("Name the skill, like Plumber or Maths tutor."); case "ASSET": session.toast("Give it a title, like 2BHK flat in 4th Block."); default: session.toast("Add the business name.") }
            return
        }
        if kind != "DRIVER" && category.isEmpty { session.toast(kind == "ASSET" ? "Pick what it is: house, flat, shop, vehicle…" : "Pick a category so people can find you."); return }
        if kind == "ASSET" && !price.isEmpty && Int(price) == nil { session.toast("Enter the price in rupees, numbers only."); return }
        if kind == "ASSET" && !year.isEmpty && !(1950...2100).contains(Int(year) ?? 0) { session.toast("Enter the year it was made, like 2019."); return }
        if kind == "BUSINESS" && !(1...50).contains(Int(radius) ?? 0) { session.toast("Delivery radius should be between 1 and 50 km."); return }
        let details = buildDetails()
        let cat = kind == "DRIVER" ? vehicleKindLabel(vehicleKind) : category
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines), areaText = area.trimmingCharacters(in: .whitespaces)
        if let existing {
            let newService: String? = kind == "BUSINESS" && service != existing.service && !serviceLocked ? service : nil
            m.updateListing(id: existing.id, title: t, category: cat, description: desc, area: areaText, at: moveHere ? fix : nil, details: details, photo: photo, service: newService) { router.pop() }
        } else {
            guard let at = fix else { session.toast("Turn on location so Bucks can save where your shop is."); return }
            // A new listing opens its dashboard (with the go-live checklist) in place of the empty "Add" form.
            m.createListing(kind: kind, title: t, category: cat, description: desc, area: areaText, at: at, details: details, photo: photo, service: kind == "BUSINESS" ? service : nil) { row in
                if case .listingEdit? = router.path.last { router.path.removeLast() }
                router.push(.studio(row.id))
            }
        }
    }
}
