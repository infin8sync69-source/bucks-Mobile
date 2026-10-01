import SwiftUI
import BucksCore

// Small pieces shared by the discover screens (ports of the helpers in ListingCard.kt and ListingProfileScreen.kt).

/// "Open now" for a shop, "Available now" for a pro, "Online now" for a driver, and their opposites.
func onlineText(_ kind: String, _ online: Bool) -> String {
    switch kind {
    case "BUSINESS": online ? "Open now" : "Closed now"
    case "SKILL": online ? "Available now" : "Not available right now"
    case "ASSET": online ? "Available" : "Not available now"
    default: online ? "Online now" : "Offline"
    }
}

func kindIcon(_ kind: String) -> String {
    switch kind { case "BUSINESS": "storefront.fill"; case "SKILL": "wrench.and.screwdriver.fill"; case "ASSET": "building.2.fill"; default: "car.fill" }
}

/// Shop / Pro / Driver pill with its icon.
struct KindBadge: View {
    let kind: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kindIcon(kind)).font(.system(size: 10)).foregroundStyle(BucksColor.onPrimaryContainer)
            Text(kindLabel(kind)).bucks(.labelSmall).foregroundStyle(BucksColor.onPrimaryContainer).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(BucksColor.primaryContainer))
    }
}

/// Green when open / available / online, grey otherwise.
struct OnlineDot: View {
    let online: Bool
    var body: some View { Circle().fill(online ? BucksColor.good : BucksColor.outline).frame(width: 8, height: 8) }
}

/// A photo from a URL, cropped to fill its frame; `placeholder` shows while it loads or when it fails.
struct RemotePhoto<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                case .failure: placeholder()
                default: BucksColor.surfaceContainerHigh
                }
            }
        } else { placeholder() }
    }
}

/// The listing's photo in a circle, or its initials when it has none.
struct ListingPhoto: View {
    let url: URL?
    let title: String
    var size: CGFloat = 44
    var body: some View {
        if let url {
            RemotePhoto(url: url) { Avatar(initials: initials(title), size: size) }
                .frame(width: size, height: size).background(BucksColor.surfaceContainerHigh).clipShape(Circle())
        } else { Avatar(initials: initials(title), size: size) }
    }
}

/// "₹1,50,000" (Indian grouping), as the Studio screens write prices.
func inr(_ n: Int) -> String {
    let digits = String(abs(n))
    var grouped = digits
    if digits.count > 3 {
        var head = String(digits.dropLast(3)), parts: [String] = []
        while head.count > 2 { parts.insert(String(head.suffix(2)), at: 0); head = String(head.dropLast(2)) }
        if !head.isEmpty { parts.insert(head, at: 0) }
        grouped = parts.joined(separator: ",") + "," + digits.suffix(3)
    }
    return (n < 0 ? "-₹" : "₹") + grouped
}
/// "₹1,200" with plain thousands grouping, as the product rows write prices.
func rupeesGrouped(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal
    return "₹" + (f.string(from: NSNumber(value: n)) ?? String(n))
}

/// "Rent · ₹28,000 per month" for an asset's details; "Price on request" when it has none.
func assetPriceLine(_ d: JSONValue) -> String {
    let mode = d.str("mode") ?? ""
    let price = d.str("price").flatMap(Double.init).map { Int($0) }
    let units = ["TOTAL": "Total", "MONTH": "per month", "YEAR": "per year", "DAY": "per day"]
    let unit = units[d.str("price_unit") ?? "TOTAL"] ?? ""
    let money = (price == nil || price == 0) ? "Price on request" : inr(price ?? 0) + (!unit.isEmpty && unit != "Total" ? " \(unit)" : "")
    let modes = ["SELL": "Sell", "RENT": "Rent", "LEASE": "Lease", "PG": "PG / Hostel"]
    let label = modes[mode] ?? (mode.isEmpty ? "" : mode.lowercased().prefix(1).uppercased() + mode.lowercased().dropFirst())
    return [mode.isEmpty ? nil : label, money].compactMap { $0 }.joined(separator: " · ")
}

/// "2027-03-12" -> "12 Mar 2027"; anything unparseable comes back unchanged.
func humanDate(_ iso: String) -> String {
    let p = DateFormatter(); p.locale = Locale(identifier: "en_US_POSIX"); p.dateFormat = "yyyy-MM-dd"
    guard let d = p.date(from: String(iso.prefix(10))) else { return iso }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}

/// "2m", "3h", "Yesterday", "12 Mar" from an ISO timestamp.
func discoverAgo(_ iso: String) -> String {
    var t = iso.replacingOccurrences(of: " ", with: "T")
    if !(t.hasSuffix("Z") || t.contains("+")) { t += "Z" }
    let plain = ISO8601DateFormatter(), frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = frac.date(from: t) ?? plain.date(from: t) else { return "" }
    let s = max(0, Int(Date().timeIntervalSince(date)))
    switch s {
    case ..<60: return "now"
    case ..<3600: return "\(s / 60)m"
    case ..<86400: return "\(s / 3600)h"
    case ..<172800: return "Yesterday"
    default: let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"; return f.string(from: date)
    }
}

/// Starts a ride of `kind` from the Services tab, a driver profile or the search banner: Android's `ride()` after `setRideKind`.
@MainActor func startRide(_ session: AppSession, _ router: Router, kind: VehicleKind) {
    session.setRideKind(kind); session.startRide(); router.push(.destination)
}

/// Where a query typed on Home or Services goes: "jobs" opens jobs near me, anything else is searched.
@MainActor func openQuery(_ session: AppSession, _ router: Router, _ q: String) {
    session.discover.useService(nil)
    if q == "jobs" { router.push(.jobsNear) } else { session.discover.pendingQuery = q; router.push(.search) }
}

/// A plural such as "1 item" / "3 items".
func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : (many ?? one + "s"))" }

/// SmallButton that fills the width it is given (Android's `SmallButton(Modifier.fillMaxWidth())` / `weight(1f)`).
struct WideSmallButton: View {
    let title: String
    var tonal = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.bucks(.labelMedium)).lineLimit(1).padding(.horizontal, 14).frame(minHeight: 38).frame(maxWidth: .infinity)
                .foregroundStyle(tonal ? BucksColor.onSecondaryContainer : BucksColor.onPrimary)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(tonal ? BucksColor.secondaryContainer : BucksColor.primary))
                .padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
