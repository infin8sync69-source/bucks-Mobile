import Foundation

/// The public pages the app links to (docs/legal, published by GitHub Pages) and the contact details Help shows (ui/social/Legal.kt).
/// The support address and the grievance officer come from the build: the SUPPORT_EMAIL and GRIEVANCE_OFFICER secrets reach Info.plist
/// (SupportEmail, GrievanceOfficer) through Config/Secrets.xcconfig and are set at launch. A build without them leaves both empty, and Help
/// then points to the grievance page, which carries the contacts.
public enum Legal {
    public enum Page: String, CaseIterable, Sendable {
        case privacy, terms, grievance
        case guidelines = "community-guidelines"
        case childSafety = "child-safety"
        case deleteAccount = "delete-account"
    }

    /// Where docs/legal is published (Android's default LEGAL_BASE_URL).
    public static let base = "https://infin8sync69-source.github.io/bucks-Mobile/legal/"
    public static func url(_ page: Page) -> URL { URL(string: base + page.rawValue)! }

    /// The support address, set at launch from Info.plist (SupportEmail). Empty: Help has no address to write to.
    nonisolated(unsafe) public static var supportEmail = ""
    /// The grievance officer as one line (name and how to reach them), set at launch from Info.plist (GrievanceOfficer).
    nonisolated(unsafe) public static var grievanceOfficer = ""

    /// A mail to support with the subject and, under the message, the app's version and build, so a reply can say whether a fix has shipped
    /// (Legal.emailSupport on Android). Nil without an address.
    public static func supportMail(subject: String) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "", build = info["CFBundleVersion"] as? String ?? ""
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let system = "iOS"
        #else
        let system = "macOS"   // the preview harness and the tests
        #endif
        return mailto(supportEmail, subject: subject, body: "\n\n---\nBucks \(version) (\(build)) · \(system) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }

    /// mailto:address?subject=…&body=…, with the subject and body percent-encoded (spaces as %20, as mail apps expect). Nil for an empty address.
    public static func mailto(_ address: String, subject: String, body: String) -> URL? {
        let to = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, let addr = to.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "mailto:\(addr)?subject=\(encoded(subject))&body=\(encoded(body))")
    }

    /// Only unreserved characters stay as they are, so an &, =, + or line break in the text can't change the link.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static func encoded(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
}
