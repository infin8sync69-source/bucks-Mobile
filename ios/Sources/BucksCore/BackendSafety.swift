import Foundation

/// My age band and whether a date of birth is on file (social_safety.sql my_safety).
public struct SafetyRow: Codable, Hashable, Sendable {
    public var ageBand: String
    public var birthDateSet: Bool
    public var guardianConsent: Bool?
    public init(ageBand: String = "UNKNOWN", birthDateSet: Bool = false, guardianConsent: Bool? = nil) { self.ageBand = ageBand; self.birthDateSet = birthDateSet; self.guardianConsent = guardianConsent }
}

/// A person in search results (search_people): by name, or exactly by Bucks ID.
public struct PersonHit: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shortCode: String
    public var area: String
    /// People we are both synced with.
    public var mutual: Int
    public var synced: Bool
    enum CodingKeys: String, CodingKey { case id, name, shortCode, area, mutual, synced }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        shortCode = (try? c.decodeIfPresent(String.self, forKey: .shortCode)) ?? ""; area = (try? c.decodeIfPresent(String.self, forKey: .area)) ?? ""
        mutual = (try? c.decodeIfPresent(Int.self, forKey: .mutual)) ?? 0; synced = (try? c.decodeIfPresent(Bool.self, forKey: .synced)) ?? false
    }
    public init(id: String, name: String, shortCode: String, area: String = "", mutual: Int = 0, synced: Bool = false) {
        self.id = id; self.name = name; self.shortCode = shortCode; self.area = area; self.mutual = mutual; self.synced = synced
    }
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
    /// A parent or guardian's consent for an under-18 account (relation PARENT or GUARDIAN; phone with +91). Until it is recorded the
    /// server refuses the account's posts, messages and orders.
    public func recordGuardianConsent(name: String, phone: String, relation: String) async throws {
        try await rpcVoid("record_guardian_consent", ["p_name": name, "p_phone": phone, "p_relation": relation])
    }
    /// My gender, private to me (profile_private): WOMAN, MAN, NON_BINARY, UNSAID or nil.
    public func setGender(id: String, code: String?) async throws { try await update("profile_private", ["gender": code], filters: [.eq("profile_id", id)]) }
    /// People by name, or exactly by Bucks ID (send the bare code, see `peopleQuery`).
    public func searchPeople(_ q: String) async throws -> [PersonHit] { try await rpcList("search_people", ["q": q]) }
    /// One person's posts that I'm allowed to see, newest first.
    public func postsBy(_ author: String) async throws -> [FeedRow] { try await rpcList("posts_by", ["p_author": author]) }
    /// Files a report for staff review; answers its id. Reporting the same thing twice keeps the first report.
    public func reportContent(kind: String, target: String, reason: String, detail: String) async throws -> String {
        try await rpc("report_content", ["p_kind": kind, "p_target": target, "p_reason": reason, "p_detail": detail])
    }
}
