import Foundation

/// The delivery time a shop promises its customers, chosen in the listing form (and changed there any time): one preset in
/// details.delivery_time, and an optional preferred time of day in details.delivery_slot ("6 pm to 9 pm"). It is the shop's own
/// promise, shown as "usually": nothing on the server enforces it, and a Bucks delivery agent still has to be free to carry the order.
/// Port of ui/DeliveryTimes.kt; same keys and words.
public enum DeliveryTime: String, CaseIterable, Sendable {
    case min10 = "10M", min30 = "30M", hour1 = "1H", hour2 = "2H", sameDay = "SAME_DAY", hour24 = "24H", day2 = "2D"

    public var label: String {
        switch self {
        case .min10: "Within 10 min"; case .min30: "Within 30 min"; case .hour1: "Within 1 hour"; case .hour2: "Within 2 hours"
        case .sameDay: "Same day"; case .hour24: "Within 24 hours"; case .day2: "Within 2 days"
        }
    }

    public static let slotMax = 40
    /// The preset a shop chose, or nil (not set, or a key this version doesn't know).
    public static func of(_ details: JSONValue) -> DeliveryTime? {
        guard case .string(let s)? = details["delivery_time"] else { return nil }
        return DeliveryTime(rawValue: s.trimmingCharacters(in: .whitespaces))
    }
    public static func slotOf(_ details: JSONValue) -> String? {
        guard case .string(let s)? = details["delivery_slot"] else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(slotMax))
    }
    /// "Within 30 min · preferred 6 pm to 9 pm", or nil when the shop set neither.
    public static func summary(_ details: JSONValue) -> String? {
        let parts = [of(details)?.label, slotOf(details).map { "preferred \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
