import SwiftUI
import BucksCore
import ImageIO
import UniformTypeIdentifiers

// Vocabulary, formatting and the go-live checklist shared by the Studio screens (ports of StudioCommon.kt and ManageCommon.kt).

enum Studio {
    /// Every category a business can pick, across its service. Pharmacy is left out on purpose: selling medicines online needs its own licensing.
    static let skillCategories = ["Plumber", "Electrician", "Tutor", "Doctor", "Carpenter", "Painter", "Cleaner", "Driver", "Designer", "Software developer", "Other"]
    static let languages = ["Kannada", "English", "Hindi", "Tamil", "Telugu", "Malayalam", "Urdu"]
    static let levels = ["Amateur", "Intermediate", "Expert"]
    static let units = ["1 kg", "500 g", "1 piece", "1 plate", "1 litre", "per hour", "per visit", "per day"]
    static let vehicleKinds: [(key: String, label: String)] = [("AUTO", "Auto"), ("CAB", "Cab"), ("BIKE", "Bike (delivery only)")]
    /// How a service is priced; stored in items.details.pricing and shown next to the price.
    static let servicePricing: [(key: String, label: String)] = [("FIXED", "Fixed price"), ("HOURLY", "Per hour"), ("VISIT", "Per visit"), ("FROM", "Starting from"), ("QUOTE", "On quote")]

    /// Asset types. The property ones (studio.sql asset_service) belong to Properties and need the owner's ID checked.
    static let assetTypes = ["House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space", "Vehicle", "Equipment", "Other"]
    static let propertyTypes: Set<String> = ["House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space"]
    static let residentialTypes: Set<String> = ["House", "Flat", "Villa", "PG / Room"]
    /// Listing mode: what the owner wants to do with the asset.
    static let assetModes: [(key: String, label: String)] = [("SELL", "Sell"), ("RENT", "Rent"), ("LEASE", "Lease"), ("PG", "PG / Hostel")]
    static let priceUnits: [(key: String, label: String)] = [("TOTAL", "Total"), ("MONTH", "per month"), ("YEAR", "per year"), ("DAY", "per day")]
    static let furnishing = ["Unfurnished", "Semi-furnished", "Furnished"]

    /// Local recommendations a listing needs before it goes live.
    @MainActor static var needed: Int { ListingsStore.NEEDED }

    static func kindLabel(_ kind: String) -> String {
        switch kind { case "BUSINESS": "Business"; case "SKILL": "Skill"; case "DRIVER": "Driver"; case "ASSET": "Asset"; default: "Listing" }
    }
    /// What a listing's online switch means to its owner.
    static func onlineLabel(_ kind: String, _ on: Bool) -> String {
        switch kind {
        case "BUSINESS": on ? "Open for orders" : "Closed"
        case "SKILL": on ? "Taking requests" : "Not taking requests"
        case "ASSET": on ? "Available" : "Not available"
        default: on ? "Available" : "Unavailable"
        }
    }
    static func roleLabel(_ role: String, vehicle: Bool) -> String {
        switch role { case "OWNER": "Owner"; case "ADMIN": vehicle ? "Driver" : "Admin"; case "STORE_RIDER": "Store rider"; default: role }
    }
    static func roleExplain(_ role: String, vehicle: Bool) -> String {
        switch role {
        case "OWNER": "Can do everything, including deleting it."
        case "ADMIN": vehicle ? "Can go online with this vehicle and take rides or deliveries." : "Runs it with you: edits details, products, accepts orders and posts jobs. Cannot delete it or invite people."
        case "STORE_RIDER": "Delivers your orders. Cash-on-delivery orders go only to store riders."
        default: ""
        }
    }
    static func assetModeLabel(_ m: String) -> String {
        assetModes.first { $0.key == m }?.label ?? (m.isEmpty ? m : m.prefix(1).uppercased() + m.lowercased().dropFirst())
    }

    // MARK: icons (SF Symbols)

    static func vehicleIcon(_ kind: String) -> String { vehicleSymbol(kind) }
    static func categoryIcon(_ c: String) -> String {
        switch c.lowercased() {
        case "restaurant", "bakery": "fork.knife"
        case "grocery": "basket.fill"
        case "vegetables": "leaf.fill"
        case "plumber": "wrench.fill"
        case "electrician": "bolt.fill"
        case "doctor", "nurse", "pharmacy": "cross.case.fill"
        case "gym trainer", "yoga instructor": "dumbbell.fill"
        case "photographer", "videographer": "camera.fill"
        case "software developer", "data analyst": "chevron.left.forwardslash.chevron.right"
        case "it firm", "design agency", "ux designer": "paintbrush.pointed.fill"
        case "taxi": "car.fill"
        case "electronics", "mobile repair": "desktopcomputer"
        case "furniture", "hardware": "chair.lounge.fill"
        case "clothing", "tailor": "tshirt.fill"
        case "salon", "beautician": "scissors"
        default: "wrench.and.screwdriver.fill"
        }
    }
    static func assetIcon(_ type: String) -> String {
        switch type {
        case "House", "Villa": "house.fill"
        case "Flat", "PG / Room": "building.2.fill"
        case "Plot / Land": "mappin.and.ellipse"
        case "Shop", "Commercial space": "storefront.fill"
        case "Office": "briefcase.fill"
        case "Warehouse": "shippingbox.fill"
        case "Vehicle": "car.fill"
        case "Equipment": "wrench.and.screwdriver.fill"
        default: "building.2.fill"
        }
    }
    static func listingIcon(_ kind: String, _ category: String) -> String {
        switch kind {
        case "DRIVER": "car.fill"
        case "BUSINESS": categoryIcon(category) == "wrench.and.screwdriver.fill" ? "storefront.fill" : categoryIcon(category)
        case "ASSET": assetIcon(category)
        default: categoryIcon(category)
        }
    }
    static func icon(_ l: ListingRow) -> String { l.kind == "ASSET" ? assetIcon(l.category) : listingIcon(l.kind, l.category) }

    // MARK: money

    /// 150000 -> "₹1,50,000" (Indian grouping).
    static func rupees(_ n: Int) -> String {
        let s = String(abs(n))
        var grouped = s
        if s.count > 3 {
            let head = Array(s.dropLast(3)), tail = String(s.suffix(3))
            var parts: [String] = []
            var i = head.count
            while i > 0 { let start = max(0, i - 2); parts.append(String(head[start..<i])); i = start }
            grouped = parts.reversed().joined(separator: ",") + "," + tail
        }
        return (n < 0 ? "-₹" : "₹") + grouped
    }
    /// "Rent · ₹28,000 per month" for an asset's details; "Price on request" when it has none.
    static func assetPriceLine(_ d: JSONValue) -> String {
        let mode = d.sStr("mode"), price = d.sNum("price").map { Int($0) }
        let unit = priceUnits.first { $0.key == (d.sStr("price_unit").isEmpty ? "TOTAL" : d.sStr("price_unit")) }?.label ?? ""
        let money = (price == nil || price == 0) ? "Price on request" : rupees(price ?? 0) + (!unit.isEmpty && unit != "Total" ? " \(unit)" : "")
        return [mode.isEmpty ? nil : assetModeLabel(mode), money].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: time

    /// "2m", "3h", "Yesterday", "12 Mar" from an ISO timestamp.
    static func ago(_ iso: String) -> String {
        guard let t = parseISO(iso) else { return "" }
        let s = max(0, Int(Date().timeIntervalSince(t)))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 172800 { return "Yesterday" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"; return f.string(from: t)
    }
    private static func parseISO(_ iso: String) -> Date? {
        var s = iso.replacingOccurrences(of: " ", with: "T")
        if !(s.hasSuffix("Z") || s.contains("+") || s.dropFirst(10).contains("-")) { s += "Z" }
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        return b.date(from: s)
    }

    static func trustPct(_ up: Int, _ down: Int) -> String { up + down == 0 ? "–" : "\((up * 100) / (up + down))%" }
}

// MARK: details helpers (listings.details is a jsonb object)

extension JSONValue {
    /// The text of a primitive value ("" when absent), as Kotlin's `contentOrNull`.
    func sStr(_ k: String) -> String {
        switch self[k] {
        case .string(let s)?: return s
        case .number(let n)?: return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b)?: return b ? "true" : "false"
        default: return ""
        }
    }
    func sBool(_ k: String) -> Bool {
        switch self[k] { case .bool(let b)?: b; case .string(let s)?: s.lowercased() == "true"; default: false }
    }
    func sInt(_ k: String) -> Int? {
        switch self[k] {
        case .number(let n)?: return n.rounded() == n ? Int(n) : nil
        case .string(let s)?: return Int(s)
        default: return nil
        }
    }
    func sNum(_ k: String) -> Double? {
        switch self[k] { case .number(let n)?: n; case .string(let s)?: Double(s); default: nil }
    }
    func sStrings(_ k: String) -> [String] { (self[k]?.array ?? []).compactMap(\.string) }
}

// MARK: go-live checklist

/// One step towards going live. `required` steps are what the server checks; the others make the listing worth finding.
struct GoLiveStep {
    var title: String, detail: String, done: Bool, required: Bool
    var waiting = false
    var action: String?
    /// EDIT, PHOTOS, ITEMS, VEHICLES, DOCS or RECOMMEND.
    var target: String
}

extension Studio {
    /// The go-live checklist for `l`. `items` and `compliance` are nil while loading (the step shows as not done yet).
    @MainActor static func goLiveSteps(_ l: ListingRow, items: [ItemRow]?, compliance: [ComplianceRow]?, recs: Int, hasVehicle: Bool) -> [GoLiveStep] {
        var steps: [GoLiveStep] = []
        let detailsDone = l.description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 && (l.kind != "ASSET" || (l.details.sNum("price") ?? 0) > 0)
        steps.append(GoLiveStep(title: "Describe it", detail: l.kind == "ASSET" ? "A few lines and the price, so people know what they're looking at." : "A few lines about what you do, so people pick you.", done: detailsDone, required: false, action: "Edit", target: "EDIT"))
        let photos = !(l.photoUrl ?? "").isEmpty || !l.gallery.isEmpty
        let photoDetail: String
        switch l.kind { case "SKILL": photoDetail = "Photos of jobs you've done build trust fast."; case "ASSET": photoDetail = "Listings with 4+ photos get far more enquiries."; default: photoDetail = "A cover photo and a few of the place or products." }
        steps.append(GoLiveStep(title: l.kind == "SKILL" ? "Show your work" : "Add photos", detail: photoDetail, done: photos, required: false, action: "Add", target: "PHOTOS"))
        let hasItems = !(items ?? []).isEmpty
        switch l.kind {
        case "BUSINESS": steps.append(GoLiveStep(title: "Add products", detail: "Put in what you sell with prices, so customers can order.", done: hasItems, required: false, action: "Add", target: "ITEMS"))
        case "SKILL": steps.append(GoLiveStep(title: "Add services and prices", detail: "\"Tap repair · ₹300 per visit\". People request from this list.", done: hasItems, required: false, action: "Add", target: "ITEMS"))
        case "DRIVER": steps.append(GoLiveStep(title: "Add your vehicle", detail: "With its RC, insurance and your licence. Bucks checks them before you can go online.", done: hasVehicle, required: true, action: "Open", target: "VEHICLES"))
        default: break
        }
        let needs = (compliance ?? []).filter(\.required)
        if l.kind != "DRIVER" && (compliance == nil || !needs.isEmpty) {
            let verified = needs.filter { $0.status == "VERIFIED" }.count, pending = needs.filter { $0.status == "PENDING" }.count
            let toUpload = needs.count - verified - pending
            let detail: String
            if compliance == nil { detail = "Checking what's needed…" }
            else if verified == needs.count { detail = "All \(needs.count) required document\(needs.count == 1 ? "" : "s") checked by Bucks." }
            else if pending > 0 && verified + pending == needs.count { detail = "Uploaded. Bucks is checking them." }
            else { detail = "\(toUpload) required document\(toUpload == 1 ? "" : "s") to upload. Only Bucks sees the files." }
            steps.append(GoLiveStep(title: "Documents", detail: detail, done: compliance != nil && verified == needs.count, required: true, waiting: pending > 0 && verified + pending == needs.count, action: "Upload", target: "DOCS"))
        }
        steps.append(GoLiveStep(title: "Get recommended", detail: "\(recs) of \(needed) people nearby have recommended you in person.", done: recs >= needed, required: true, action: "Show code", target: "RECOMMEND"))
        return steps
    }
}

// MARK: photos

enum StudioPhoto {
    /// A listing or product photo as JPEG. Picked photos arrive re-encoded already, but the listing-media bucket only takes JPEG, PNG and WebP,
    /// so a GIF's first frame is re-encoded here; nil when it cannot be decoded.
    static func asListingPhoto(_ p: Picked) -> Picked? {
        guard p.mime == "image/gif" else { return p }
        guard let src = CGImageSourceCreateWithData(p.data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Picked(data: out as Data, name: ((p.name as NSString).deletingPathExtension) + ".jpg", mime: "image/jpeg")
    }
    static func image(_ p: Picked) -> Image? {
        guard let src = CGImageSourceCreateWithData(p.data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}
