import Foundation

/// A provider licence (Skills, Taxi, Business) for one listing or vehicle: code, state and VALID TILL (BackendBilling.kt LicenceRow,
/// billing.sql my_licences). Status only: the app never sells a licence or shows its price (App Store 3.1.1 / Play payments policy).
public struct LicenceRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var code: String
    public var listingId: String?
    public var vehicleId: String?
    public var subject: String
    public var planCode: String
    public var planLabel: String
    /// FOUNDING or TRIAL (free period), ACTIVE, GRACE (lapsed, still live) or EXPIRED (paused).
    public var state: String
    public var founding: Bool
    public var validFrom: String?
    public var validTill: String?
    public var graceUntil: String?
    public var foundingBonusUntil: String?
    public var paid: Bool
    /// Chats and orders (pages) or accepted trips (vehicles) in the last 30 days.
    public var enquiries30d: Int

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .licenceId); code = try c.decode(String.self, forKey: .code)
        listingId = try? c.decodeIfPresent(String.self, forKey: .listingId); vehicleId = try? c.decodeIfPresent(String.self, forKey: .vehicleId)
        subject = (try? c.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        planCode = try c.decode(String.self, forKey: .planCode); planLabel = (try? c.decodeIfPresent(String.self, forKey: .planLabel)) ?? planCode
        state = try c.decode(String.self, forKey: .state); founding = (try? c.decodeIfPresent(Bool.self, forKey: .founding)) ?? false
        validFrom = try? c.decodeIfPresent(String.self, forKey: .validFrom); validTill = try? c.decodeIfPresent(String.self, forKey: .validTill)
        graceUntil = try? c.decodeIfPresent(String.self, forKey: .graceUntil)
        foundingBonusUntil = try? c.decodeIfPresent(String.self, forKey: .foundingBonusUntil)
        paid = (try? c.decodeIfPresent(Bool.self, forKey: .paid)) ?? false
        enquiries30d = (try? c.decodeIfPresent(Int.self, forKey: .enquiries30d)) ?? 0
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .licenceId); try c.encode(code, forKey: .code); try c.encodeIfPresent(listingId, forKey: .listingId)
        try c.encodeIfPresent(vehicleId, forKey: .vehicleId); try c.encode(subject, forKey: .subject); try c.encode(planCode, forKey: .planCode)
        try c.encode(planLabel, forKey: .planLabel); try c.encode(state, forKey: .state); try c.encode(founding, forKey: .founding)
        try c.encodeIfPresent(validFrom, forKey: .validFrom); try c.encodeIfPresent(validTill, forKey: .validTill)
        try c.encodeIfPresent(graceUntil, forKey: .graceUntil); try c.encodeIfPresent(foundingBonusUntil, forKey: .foundingBonusUntil)
        try c.encode(paid, forKey: .paid); try c.encode(enquiries30d, forKey: .enquiries30d)
    }
    private enum K: String, CodingKey {
        case licenceId, code, listingId, vehicleId, subject, planCode, planLabel, state, founding, validFrom, validTill, graceUntil, foundingBonusUntil, paid
        case enquiries30d = "enquiriesMonth"
    }

    /// "TX7K Q2MP": two groups of four, easier to read out and type.
    public var prettyCode: String { code.count == 8 ? String(code.prefix(4)) + " " + String(code.suffix(4)) : code }
    public var lapsed: Bool { state == "GRACE" || state == "EXPIRED" }

    private static let ist = TimeZone(identifier: "Asia/Kolkata")!
    private static func parse(_ iso: String?) -> Date? {
        guard let s = iso?.replacingOccurrences(of: " ", with: "T") else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: s)
    }
    /// "10 Apr 2027" in India time, or "–".
    public static func day(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "–" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.timeZone = ist; return f.string(from: d)
    }
    /// Whole days until VALID TILL in India dates (0 on the day itself).
    public var daysLeft: Int {
        guard let d = Self.parse(validTill) else { return 0 }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = Self.ist
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
    }
}

extension Backend {
    /// My licences, one per listing or vehicle that has one (none while billing is switched off on the server).
    public func myLicences() async throws -> [LicenceRow] { try await rpcList("my_licences") }
}
