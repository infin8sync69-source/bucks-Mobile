import Foundation

// Showcase documents (migration showcase_docs.sql; port of data/BackendDocs.kt): what a business, NGO or institution shows on its profile.
// Not the compliance documents Bucks staff check for go-live (BackendDocs.swift / BackendServices.swift, table listing_documents).
// Every call goes through a server function that decides who may see what: PUBLIC to anyone signed in, ON_REQUEST after the owner
// approves, PRIVATE to the team only.

private extension KeyedDecodingContainer {
    func str(_ k: Key, _ d: String = "") -> String { (try? decodeIfPresent(String.self, forKey: k)) ?? d }
    func opt(_ k: Key) -> String? { (try? decodeIfPresent(String.self, forKey: k)) ?? nil }
    func int(_ k: Key, _ d: Int = 0) -> Int { (try? decodeIfPresent(Int.self, forKey: k)) ?? d }
    func optInt(_ k: Key) -> Int? { (try? decodeIfPresent(Int.self, forKey: k)) ?? nil }
    func bool(_ k: Key, _ d: Bool = false) -> Bool { (try? decodeIfPresent(Bool.self, forKey: k)) ?? d }
}

/// A document on a profile as I see it: `canOpen` says whether I may read the file now, `myRequest` where my access request stands.
public struct ShowcaseDoc: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var kind: String
    public var title: String
    public var issuer: String
    public var number: String
    public var registry: String?
    public var mime: String
    public var sizeBytes: Int
    public var visibility: String
    public var expiresOn: String?
    public var bucksChecked: Bool
    public var checksUp: Int
    public var checksDown: Int
    public var sort: Int
    public var createdAt: String
    public var canOpen: Bool
    /// PENDING, APPROVED or DECLINED when I asked to see it; nil when I haven't (or it lapsed).
    public var myRequest: String?
    /// My opinion once I opened it: 1 looks genuine, -1 doesn't look right, nil none.
    public var myCheck: Int?
    /// For the team only: requests waiting for an answer.
    public var pendingRequests: Int

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        listingId = c.str(.listingId); kind = c.str(.kind, "OTHER"); title = c.str(.title); issuer = c.str(.issuer); number = c.str(.number)
        registry = c.opt(.registry); mime = c.str(.mime); sizeBytes = c.int(.sizeBytes); visibility = c.str(.visibility, "ON_REQUEST")
        expiresOn = c.opt(.expiresOn); bucksChecked = c.bool(.bucksChecked); checksUp = c.int(.checksUp); checksDown = c.int(.checksDown)
        sort = c.int(.sort); createdAt = c.str(.createdAt); canOpen = c.bool(.canOpen); myRequest = c.opt(.myRequest); myCheck = c.optInt(.myCheck)
        pendingRequests = c.int(.pendingRequests)
    }
    private enum K: String, CodingKey {
        case id, listingId, kind, title, issuer, number, registry, mime, sizeBytes, visibility, expiresOn, bucksChecked, checksUp, checksDown, sort, createdAt, canOpen, myRequest, myCheck, pendingRequests
    }

    public var isPdf: Bool { mime == "application/pdf" }
    /// How many viewers gave an opinion.
    public var checks: Int { checksUp + checksDown }
    /// True once the day it was valid till has passed (compared as yyyy-MM-dd, so no time zone arithmetic).
    public var expired: Bool {
        guard let e = expiresOn, e.count >= 10 else { return false }
        return String(e.prefix(10)) < ShowcaseDoc.todayISO()
    }
    static func todayISO() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// A request to see an ON_REQUEST document, or an approval still running, as the owner or an admin sees it.
public struct DocRequest: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var docId: String
    public var docTitle: String
    public var requesterId: String
    public var requesterName: String
    /// "Has ordered here", "Follows this page" or "No past activity here".
    public var relation: String
    public var message: String
    public var status: String
    public var createdAt: String
    public var expiresAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        docId = c.str(.docId); docTitle = c.str(.docTitle); requesterId = c.str(.requesterId); requesterName = c.str(.requesterName); relation = c.str(.relation)
        message = c.str(.message); status = c.str(.status, "PENDING"); createdAt = c.str(.createdAt); expiresAt = c.str(.expiresAt)
    }
    private enum K: String, CodingKey { case id, docId, docTitle, requesterId, requesterName, relation, message, status, createdAt, expiresAt }
}

/// Who opened which document (owner and admins only).
public struct DocView: Decodable, Hashable, Sendable, Identifiable {
    public var docTitle: String
    public var viewerId: String
    public var viewerName: String
    public var lastAt: String
    public var times: Int
    public var id: String { viewerId + "|" + docTitle }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        docTitle = c.str(.docTitle); viewerId = c.str(.viewerId); viewerName = c.str(.viewerName); lastAt = c.str(.lastAt); times = c.int(.times, 1)
    }
    private enum K: String, CodingKey { case docTitle, viewerId, viewerName, lastAt, times }
}

/// Where an opened document's file is in the docs bucket (the owner's folder).
public struct OpenedDoc: Decodable, Hashable, Sendable {
    public var path: String
    public var mime: String
    public var title: String
    public var expiresOn: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        path = try c.decode(String.self, forKey: .path)
        mime = c.str(.mime); title = c.str(.title); expiresOn = c.opt(.expiresOn)
    }
    private enum K: String, CodingKey { case path, mime, title, expiresOn }
}

/// The kinds a profile can show. "Other" lets the owner name it; the others suggest a name.
public enum ShowcaseKinds {
    public static let all: [(key: String, label: String, hint: String)] = [
        ("REGISTRATION", "Registration", "Company, society, trust or NGO registration"),
        ("LICENCE", "Licence", "Trade licence, FSSAI, RERA or a professional licence"),
        ("TAX", "Tax", "GST, 12A / 80G or other tax registration"),
        ("CERTIFICATE", "Certificate", "Quality, training or safety certificate"),
        ("AFFILIATION", "Affiliation", "Board, university or association"),
        ("AWARD", "Award", "Awards and recognition"),
        ("REPORT", "Report", "Annual or audited report"),
        ("BROCHURE", "Brochure", "Brochure, catalogue or price list"),
        ("OTHER", "Other", "Anything else; you choose the name"),
    ]
    public static func label(_ kind: String) -> String { all.first { $0.key == kind }?.label ?? "Document" }
    public static func hint(_ kind: String) -> String { all.first { $0.key == kind }?.hint ?? "" }
    /// Documents that usually carry a registration number the public can look up.
    public static func hasNumber(_ kind: String) -> Bool { ["REGISTRATION", "LICENCE", "TAX"].contains(kind) }
    /// Safe to show to everyone by default; the rest start as "on request".
    public static func defaultVisibility(_ kind: String) -> String { ["CERTIFICATE", "AFFILIATION", "AWARD", "REPORT", "BROCHURE"].contains(kind) ? "PUBLIC" : "ON_REQUEST" }
}

/// Official registries a number can be checked against; the app opens the registry's own search, it does not check for you.
public enum Registries {
    public static let all: [(key: String, label: String)] = [("GST", "GST"), ("FSSAI", "FSSAI"), ("MCA", "Company (MCA)")]
    public static func url(_ registry: String?) -> String? {
        switch registry {
        case "GST": return "https://services.gst.gov.in/services/searchtp"
        case "FSSAI": return "https://foscos.fssai.gov.in/"
        case "MCA": return "https://www.mca.gov.in/"
        default: return nil
        }
    }
}

public extension Backend {
    private static let showcaseSession = Backend.makeSession()

    // MARK: reading

    /// The documents I may see on a profile (the team sees them all; everyone else PUBLIC and ON_REQUEST ones of a live profile).
    func showcaseDocs(_ listingId: String) async throws -> [ShowcaseDoc] { try await rpcList("showcase_docs", ["p_listing": listingId]) }

    /// Requests waiting, and approvals still running, for the owner or an admin to act on.
    func docRequestsFor(_ listingId: String) async throws -> [DocRequest] { try await rpcList("doc_requests_for", ["p_listing": listingId]) }

    /// The last 50 people who opened a document of this profile (owner and admins).
    func docViewLog(_ listingId: String) async throws -> [DocView] { try await rpcList("doc_view_log", ["p_listing": listingId]) }

    // MARK: owner: add, edit, remove

    /// Uploads `data` to my own folder of the private docs bucket and returns the path to give `addShowcaseDoc`.
    func uploadShowcaseFile(me: String, data: Data, mime: String) async throws -> String {
        let ext: String
        switch mime { case "application/pdf": ext = "pdf"; case "image/png": ext = "png"; case "image/webp": ext = "webp"; default: ext = "jpg" }
        let path = "\(me)/showcase-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()).\(ext)"
        try await upload(bucket: "docs", path: path, data: data, contentType: mime)
        return path
    }

    /// Returns the new document's id. `expires` is yyyy-MM-dd.
    @discardableResult
    func addShowcaseDoc(listingId: String, kind: String, title: String, issuer: String, number: String, registry: String?, path: String, mime: String, size: Int, visibility: String, expires: String?) async throws -> String {
        try await rpc("add_showcase_doc", [
            "p_listing": listingId, "p_kind": kind, "p_title": title, "p_issuer": issuer, "p_number": number, "p_registry": registry,
            "p_path": path, "p_mime": mime, "p_size": size, "p_visibility": visibility, "p_expires": expires,
        ])
    }

    func updateShowcaseDoc(_ docId: String, title: String, issuer: String, number: String, registry: String?, visibility: String, expires: String?) async throws {
        try await rpcVoid("update_showcase_doc", [
            "p_doc": docId, "p_title": title, "p_issuer": issuer, "p_number": number, "p_registry": registry, "p_visibility": visibility, "p_expires": expires,
        ])
    }

    /// Removes the document and returns its file path; call `removeShowcaseFile` with it. (Server function delete_showcase_doc.)
    func removeShowcaseDoc(_ docId: String) async throws -> String { try await rpc("delete_showcase_doc", ["p_doc": docId]) }

    /// Best effort: only the person who uploaded a file may remove it from storage.
    func removeShowcaseFile(_ path: String) async { _ = try? await deleteFiles(bucket: "docs", paths: [path]) }

    // MARK: viewer: ask, open, say whether it looks genuine

    /// Asks the owner to share an ON_REQUEST document. Returns PENDING, or APPROVED when I already have access.
    func requestDocAccess(_ docId: String, message: String) async throws -> String {
        try await rpc("request_doc_access", ["p_doc": docId, "p_message": message])
    }

    /// Owner or admin: approve (for `days`, default 30) or decline. Returns APPROVED or DECLINED.
    @discardableResult
    func decideDocRequest(_ requestId: String, approve: Bool, days: Int = 30) async throws -> String {
        try await rpc("decide_doc_request", ["p_req": requestId, "p_approve": approve, "p_days": days])
    }

    func revokeDocAccess(_ requestId: String) async throws { try await rpcVoid("revoke_doc_access", ["p_req": requestId]) }

    /// Checks I may read it, notes that I looked, and returns where the file is. Then `downloadShowcaseFile`.
    func openShowcaseDoc(_ docId: String) async throws -> OpenedDoc { try await rpc("open_showcase_doc", ["p_doc": docId]) }

    /// Reads the file with my own sign-in (not a signed link), so the storage rules decide again: an approval that was revoked stops working here.
    func downloadShowcaseFile(path: String) async throws -> Data {
        guard let c = config, c.isComplete else { throw BackendError.notSignedIn }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "\(c.url)/storage/v1/object/authenticated/docs/\(encoded)") else { throw BackendError.decoding("file path") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(c.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + ((await accessToken()) ?? c.anonKey), forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await Backend.showcaseSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw BackendError.transport("no response") }
            guard (200...299).contains(http.statusCode) else { throw BackendError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self)) }
            return data
        } catch let e as BackendError { throw e }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw BackendError.transport(error.localizedDescription) }
    }

    /// "Looks genuine" (1) or "doesn't look right" (-1) after opening a document, with an optional comment. A viewer signal only; never Bucks verification.
    func checkShowcaseDoc(_ docId: String, vote: Int, comment: String) async throws {
        try await rpcVoid("check_showcase_doc", ["p_doc": docId, "p_vote": vote, "p_comment": comment])
    }
    func clearShowcaseCheck(_ docId: String) async throws { try await rpcVoid("clear_showcase_check", ["p_doc": docId]) }
}
