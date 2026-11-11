import Foundation

/// My age band and whether a date of birth is on file (social_safety.sql my_safety).
public struct SafetyRow: Codable, Hashable, Sendable {
    public var ageBand: String
    public var birthDateSet: Bool
    public var guardianConsent: Bool?
    public init(ageBand: String = "UNKNOWN", birthDateSet: Bool = false, guardianConsent: Bool? = nil) { self.ageBand = ageBand; self.birthDateSet = birthDateSet; self.guardianConsent = guardianConsent }
}

/// What is being reported. `kind`: POST, COMMENT, MOMENT, MESSAGE, PROFILE, LISTING, REVIEW or JOB. `ownerId` lets the sheet offer "also block".
public struct ReportTarget: Identifiable, Hashable, Sendable {
    public var kind: String
    public var targetId: String
    public var ownerId: String?
    public var ownerName: String
    public var id: String { kind + ":" + targetId }
    public init(kind: String, targetId: String, ownerId: String?, ownerName: String = "") { self.kind = kind; self.targetId = targetId; self.ownerId = ownerId; self.ownerName = ownerName }

    /// Sheet title ("Report this post"); a profile is reported by name.
    public var title: String {
        switch kind {
        case "POST": "Report this post"
        case "COMMENT": "Report this comment"
        case "MOMENT": "Report this moment"
        case "MESSAGE": "Report this message"
        case "LISTING": "Report this page"
        case "REVIEW": "Report this recommendation"
        case "JOB": "Report this job"
        default: ownerName.isEmpty ? "Report this account" : "Report \(ownerName)"
        }
    }
}

/// The reasons the server accepts (social_safety.sql reports.reason), with the words shown for each.
public enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam = "SPAM", harassment = "HARASSMENT", hate = "HATE", nudity = "NUDITY", violence = "VIOLENCE", selfHarm = "SELF_HARM"
    case childSafety = "CHILD_SAFETY", scam = "SCAM", impersonation = "IMPERSONATION", other = "OTHER"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Bullying or harassment"
        case .hate: "Hate speech"
        case .nudity: "Nudity or sexual content"
        case .violence: "Violence"
        case .selfHarm: "Self-harm or suicide"
        case .childSafety: "A child may be at risk"
        case .scam: "Fraud or scam"
        case .impersonation: "Pretending to be someone"
        case .other: "Something else"
        }
    }
    public var hint: String {
        switch self {
        case .spam: "Ads, scam links, repeated posts"
        case .harassment: "Threats, picking on someone, unwanted contact"
        case .hate: "Attacks on people for who they are"
        case .nudity: "Sexual photos, videos or messages"
        case .violence: "Threats, graphic violence, dangerous acts"
        case .selfHarm: "Someone may be at risk"
        case .childSafety: "Grooming, exploitation, a child in danger"
        case .scam: "Asking for money, fake offers"
        case .impersonation: "A fake account of a real person"
        case .other: ""
        }
    }
    /// Someone may be in danger: the sheet shows emergency numbers before anything is sent.
    public var urgent: Bool { self == .selfHarm || self == .childSafety || self == .violence }
}

/// Age and reporting (BackendSafety.kt).
extension Backend {
    /// Nil when signed out.
    public func mySafety() async throws -> SafetyRow? { (try await rpcList("my_safety") as [SafetyRow]).first }
    /// Saves my date of birth (yyyy-MM-dd) once; answers the age band. Refused with BK_NOT_ELIGIBLE below the sign-up age.
    public func setBirthDate(_ isoDate: String) async throws -> String { try await rpc("set_birth_date", ["p_date": isoDate]) }
    /// Files a report for staff review; answers its id. Reporting the same thing twice keeps the first report.
    public func reportContent(kind: String, target: String, reason: String, detail: String) async throws -> String {
        try await rpc("report_content", ["p_kind": kind, "p_target": target, "p_reason": reason, "p_detail": detail])
    }
}
