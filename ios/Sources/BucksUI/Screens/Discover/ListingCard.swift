import SwiftUI
import BucksCore

/// The one card every search result uses, whatever its kind: photo or initials, title, kind badge, category,
/// distance, open/online dot, trust, and one line that says what matters for that kind
/// (the matched item and the shop's starting price for a shop, the rate for a pro, the vehicle and fare for a driver).
/// Tapping opens the listing profile unless `onTap` says otherwise.
struct DiscoverListingCard: View {
    @Environment(Router.self) private var router
    private let card: Model
    private let onTap: (() -> Void)?

    init(hit: SearchHit, onTap: (() -> Void)? = nil) {
        card = Model(id: hit.id, kind: hit.kind, title: hit.title, category: hit.category, area: hit.area, online: hit.online, photoUrl: hit.photoUrl, distanceM: hit.distanceM,
                     ships: hit.details.str("ships_india") == "true" || hit.details["ships_india"]?.bool == true, trust: Trust(up: hit.trustUp, down: hit.trustDown), line: Self.kindLine(kind: hit.kind, details: hit.details, category: hit.category, description: hit.description, matchedItem: hit.matchedItem, minPrice: hit.minPrice))
        self.onTap = onTap
    }
    /// From a full listing row (no distance or price known).
    init(listing l: ListingRow, onTap: (() -> Void)? = nil) {
        card = Model(id: l.id, kind: l.kind, title: l.title, category: l.category, area: l.area, online: l.online, photoUrl: l.photoUrl, distanceM: nil, ships: false,
                     trust: Trust(up: l.trustUp, down: l.trustDown), line: Self.kindLine(kind: l.kind, details: l.details, category: l.category, description: l.description, matchedItem: nil, minPrice: nil))
        self.onTap = onTap
    }

    private struct Model { var id, kind, title, category, area: String; var online: Bool; var photoUrl: String?; var distanceM: Double?; var ships: Bool; var trust: Trust; var line: String }
    /// A store that ships shows "Ships across India" instead of a distance that means nothing to a buyer far away.
    private var where_: String? {
        guard let m = card.distanceM else { return nil }
        return card.ships && m > 25_000 ? "Ships across India" : formatDistance(m)
    }

    var body: some View {
        BucksCard(onTap: { if let onTap { onTap() } else { router.push(.listing(card.id)) } }, padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                ListingPhoto(url: Backend.shared.listingPhoto(card.photoUrl), title: card.title, size: 56)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(card.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        KindBadge(kind: card.kind).fixedSize()
                        Spacer(minLength: 0)
                    }
                    Muted([card.category.isEmpty ? nil : card.category, where_, card.area.isEmpty ? nil : card.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    HStack(spacing: 6) { OnlineDot(online: card.online); Muted(onlineText(card.kind, card.online), maxLines: 1) }.padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Text(card.line).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                TrustBadge(up: card.trust.up, down: card.trust.down, compact: true)
            }.padding(.top, 10)
        }
    }

    /// The kind-specific line of a result card. For a shop, matched_item is the product whose name matched the query while
    /// min_price is the cheapest in-stock product of the whole shop (search_listings), so the two are never joined as one price:
    /// "Sells Sugar · products from ₹5", not "Sugar · from ₹5".
    static func kindLine(kind: String, details: JSONValue, category: String, description: String, matchedItem: String?, minPrice: Int?) -> String {
        switch kind {
        case "BUSINESS":
            if let m = matchedItem { return "Sells \(m)" + (minPrice.map { " · products from ₹\($0)" } ?? "") }
            if let p = minPrice { return "Products from ₹\(p)" }
            return "No products listed yet · message to ask"
        case "SKILL": return [matchedItem, proRate(details, minPrice: minPrice)].compactMap { $0 }.joined(separator: " · ")
        case "DRIVER":
            guard let k = driverKind(details, category: category) else { return "Driver" }
            return ["\(k.label) · ₹\(k.farePerKm)/km", details.str("model")].compactMap { $0 }.joined(separator: " · ")
        default: return String(description.prefix(80))
        }
    }
}
