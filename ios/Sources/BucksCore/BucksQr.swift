import Foundation

/// QR codes Bucks shows and reads. The prefix says what a scanned code is for (Android's `BucksQr`).
public enum BucksQr {
    public enum Scanned: Equatable, Sendable {
        case bucksId(String), recommendation(String), upi(String), other(String)
    }
    private static let idPrefix = "bucks:id:", recPrefix = "bucks:rec:"

    public static func forBucksId(_ code: String) -> String { idPrefix + code.uppercased() }
    public static func forRecommendation(_ token: String) -> String { recPrefix + token }

    public static func parse(_ raw: String) -> Scanned {
        if raw.hasPrefix(idPrefix) { return .bucksId(String(raw.dropFirst(idPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
        if raw.hasPrefix(recPrefix) { return .recommendation(String(raw.dropFirst(recPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        if raw.lowercased().hasPrefix("upi://pay") { return .upi(raw) }
        return .other(raw)
    }

    /// A typed Bucks ID: 8 characters, no I/L/O/U, case-insensitive.
    public static func looksLikeBucksId(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return t.count == 8 && t.allSatisfy { "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains($0) }
    }
}
