import Foundation

/// The validity of a Bucks ID card: a year from when it was issued (profiles.id_issued_at, studio.sql).
/// `renewable` opens in the last 30 days; an `expired` card can't be used by others to sync until it's renewed.
public struct BucksIdCardInfo: Hashable, Sendable {
    public var issued: Date
    public var till: Date
    public var daysLeft: Int
    public var expired: Bool { daysLeft < 0 }
    public var renewable: Bool { daysLeft <= 30 }
    public var validFrom: String { Self.format(issued) }
    public var validTill: String { Self.format(till) }

    private static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC") ?? .gmt; return c }
    private static func format(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM yyyy"; return f.string(from: d)
    }

    /// The card for an `id_issued_at` timestamp; nil when it is missing or unreadable. `today` is a moment on the person's calendar day.
    public static func of(_ iso: String?, today: Date = Date(), timeZone: TimeZone = .current) -> BucksIdCardInfo? {
        guard let iso, !iso.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // The calendar date as written (the offset's own date), which is what OffsetDateTime.toLocalDate gives.
        let parts = String(iso.prefix(10)).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let issued = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        guard let till = utc.date(byAdding: .year, value: 1, to: issued) else { return nil }
        var local = Calendar(identifier: .gregorian); local.timeZone = timeZone
        let t = local.dateComponents([.year, .month, .day], from: today)
        guard let todayUTC = utc.date(from: t) else { return nil }
        let days = utc.dateComponents([.day], from: todayUTC, to: till).day ?? 0
        return BucksIdCardInfo(issued: issued, till: till, daysLeft: days)
    }
}

/// How a person is vouched for (data/Identity.kt). The Account tab lists every level with a tick for the ones reached.
public enum VerificationLevel: String, CaseIterable, Sendable {
    case phone = "PHONE", device = "DEVICE", document = "DOCUMENT", community = "COMMUNITY"
    public var label: String {
        switch self { case .phone: "Phone verified"; case .device: "Genuine device"; case .document: "ID verified"; case .community: "Community vouched" }
    }
    public var detail: String {
        switch self {
        case .phone: "One mobile number is bound to this key"
        case .device: "Play Integrity / key attestation passed"
        case .document: "Driving licence or vehicle RC checked via DigiLocker partner"
        case .community: "10+ completed, well-rated transactions"
        }
    }
}

/// Reading a Bucks ID aloud.
public enum BucksIdCode {
    /// "H6VF YWYF": the 8-character ID split for reading aloud.
    public static func pretty(_ code: String) -> String {
        let u = Array(code.uppercased()); return stride(from: 0, to: u.count, by: 4).map { String(u[$0..<min($0 + 4, u.count)]) }.joined(separator: " ")
    }
}

/// "@asha_k": a handle made from a name (ProfileScreens.kt handleOf).
public func accountHandle(_ name: String) -> String {
    let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var out = ""; var gap = false
    for ch in lower { if ch.isASCII, ch.isLetter || ch.isNumber { if gap, !out.isEmpty { out += "_" }; gap = false; out.append(ch) } else { gap = true } }
    return "@" + out
}

/// "1.5 MB" / "12 KB" / "300 B" (ProfileTabs.kt humanBytes).
public func accountHumanBytes(_ n: Int) -> String {
    n >= 1_048_576 ? String(format: "%.1f MB", Double(n) / 1_048_576) : n >= 1024 ? "\(n / 1024) KB" : "\(n) B"
}
