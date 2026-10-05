import Foundation

/// Where sign-in comes from. Sign-in stays with Firebase: every request carries the Firebase ID token, which Supabase verifies,
/// so row-level security sees the same person. The iOS app implements this on top of FirebaseAuth.
public protocol IdentityProvider: AnyObject, Sendable {
    /// The signed-in Firebase uid, or nil when signed out.
    var uid: String? { get }
    /// A Firebase ID token for the signed-in user (the cached one unless `forceRefresh`), or nil when signed out.
    func idToken(forceRefresh: Bool) async throws -> String?
}

public struct BackendConfig: Sendable {
    public var url: String
    public var anonKey: String
    public init(url: String, anonKey: String) { self.url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/")); self.anonKey = anonKey }
    public var isComplete: Bool { !url.isEmpty && !anonKey.isEmpty }
}

/// One PostgREST filter, e.g. `.eq("id", x)` becomes `id=eq.x`.
public struct Filter: Sendable {
    public var column: String
    public var expression: String
    public static func eq(_ column: String, _ value: String) -> Filter { Filter(column: column, expression: "eq.\(value)") }
    public static func isIn(_ column: String, _ values: [String]) -> Filter { Filter(column: column, expression: "in.(\(values.joined(separator: ",")))") }
    public static func raw(_ column: String, _ expression: String) -> Filter { Filter(column: column, expression: expression) }
}

/// Supabase data layer (schema: supabase/schema.sql) over plain PostgREST HTTP, the same calls the Android app makes.
public final class Backend: @unchecked Sendable {
    public static let shared = Backend()
    private init() {}

    /// Internal: Realtime builds its socket URL from it.
    var config: BackendConfig?
    private var identity: IdentityProvider?
    private let roleClaim = RoleClaim()
    private var session: URLSession = Backend.makeSession()
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20; c.timeoutIntervalForResource = 60; c.waitsForConnectivity = false
        if let protocolClasses { c.protocolClasses = protocolClasses }
        return URLSession(configuration: c)
    }

    /// Call once at launch. Until then (or without Firebase) `enabled` is false.
    public func configure(_ config: BackendConfig, identity: IdentityProvider?) { self.config = config; self.identity = identity }
    /// Tests: route every request through the given URLProtocol classes instead of the network.
    public func useProtocolClasses(_ classes: [AnyClass]) { session = Backend.makeSession(protocolClasses: classes); RealtimeHub.live = false }
    public var enabled: Bool { (config?.isComplete ?? false) && identity != nil }
    public var uid: String? { identity?.uid }

    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()

    /// Postgres geography input: PostGIS reads this text form directly.
    public static func point(_ p: LatLng) -> String { "SRID=4326;POINT(\(p.lng) \(p.lat))" }

    // MARK: - HTTP

    private func cfg() throws -> BackendConfig { guard let c = config, c.isComplete else { throw BackendError.notSignedIn }; return c }

    /// Supabase only accepts a Firebase token that carries role=authenticated. The claim is set by the claim-role Supabase function.
    /// The token cached at sign-in predates it, so a fresh one is fetched until the claim is there; after that the cache is used as normal.
    func accessToken() async -> String? {
        guard let identity, identity.uid != nil, let cached = (try? await identity.idToken(forceRefresh: false)) ?? nil else { return nil }
        if JWT.hasRole(cached) { return cached }
        guard let c = config else { return cached }
        return await roleClaim.token(identity: identity, cached: cached, config: c, session: session)
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        let c = try cfg()
        var comps = URLComponents(string: c.url + path)!
        if !query.isEmpty {
            // PostgREST filters carry '+' and ':' (timestamps) that URLQueryItem leaves alone; encode them ourselves.
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=#"))
            comps.percentEncodedQuery = query.map { "\($0.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.name)=\(($0.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(c.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + ((await accessToken()) ?? c.anonKey), forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw BackendError.transport("no response") }
            guard (200...299).contains(http.statusCode) else { throw BackendError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self)) }
            return data
        } catch let e as BackendError { throw e }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw BackendError.transport(error.localizedDescription) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw BackendError.decoding("\(T.self): \(error)") }
    }

    private static func json(_ params: [String: Any?]) -> Data {
        var o: [String: Any] = [:]
        for (k, v) in params { o[k] = v ?? NSNull() }
        return (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    }

    // MARK: - Tables

    public func select<T: Decodable>(_ table: String, columns: String = "*", filters: [Filter] = [], order: String? = nil, ascending: Bool = true, limit: Int? = nil) async throws -> [T] {
        var q = [URLQueryItem(name: "select", value: columns)] + filters.map { URLQueryItem(name: $0.column, value: $0.expression) }
        if let order { q.append(URLQueryItem(name: "order", value: "\(order).\(ascending ? "asc" : "desc")")) }
        if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try decode([T].self, try await request("GET", "/rest/v1/\(table)", query: q))
    }
    public func selectOne<T: Decodable>(_ table: String, columns: String = "*", filters: [Filter] = []) async throws -> T? {
        let rows: [T] = try await select(table, columns: columns, filters: filters, limit: 1); return rows.first
    }
    /// Inserts a row and returns it.
    public func insert<T: Decodable>(_ table: String, _ row: [String: Any?]) async throws -> T {
        let data = try await request("POST", "/rest/v1/\(table)", body: Self.json(row), headers: ["Prefer": "return=representation"])
        guard let first = try decode([T].self, data).first else { throw BackendError.decoding("\(table): empty insert result") }
        return first
    }
    public func insertVoid(_ table: String, _ row: [String: Any?]) async throws {
        _ = try await request("POST", "/rest/v1/\(table)", body: Self.json(row), headers: ["Prefer": "return=minimal"])
    }
    public func update(_ table: String, _ values: [String: Any?], filters: [Filter]) async throws {
        _ = try await request("PATCH", "/rest/v1/\(table)", query: filters.map { URLQueryItem(name: $0.column, value: $0.expression) }, body: Self.json(values), headers: ["Prefer": "return=minimal"])
    }
    public func update<T: Decodable>(_ table: String, _ values: [String: Any?], filters: [Filter], returning: T.Type) async throws -> T? {
        let data = try await request("PATCH", "/rest/v1/\(table)", query: filters.map { URLQueryItem(name: $0.column, value: $0.expression) }, body: Self.json(values), headers: ["Prefer": "return=representation"])
        return try decode([T].self, data).first
    }
    public func upsert(_ table: String, _ row: [String: Any?]) async throws {
        _ = try await request("POST", "/rest/v1/\(table)", body: Self.json(row), headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }
    public func delete(_ table: String, filters: [Filter]) async throws {
        _ = try await request("DELETE", "/rest/v1/\(table)", query: filters.map { URLQueryItem(name: $0.column, value: $0.expression) }, headers: ["Prefer": "return=minimal"])
    }

    // MARK: - Functions

    /// A function that returns one row or one scalar.
    public func rpc<T: Decodable>(_ name: String, _ params: [String: Any?] = [:]) async throws -> T {
        try decode(T.self, try await request("POST", "/rest/v1/rpc/\(name)", body: Self.json(params)))
    }
    /// A set-returning function.
    public func rpcList<T: Decodable>(_ name: String, _ params: [String: Any?] = [:]) async throws -> [T] {
        try decode([T].self, try await request("POST", "/rest/v1/rpc/\(name)", body: Self.json(params)))
    }
    public func rpcVoid(_ name: String, _ params: [String: Any?] = [:]) async throws {
        _ = try await request("POST", "/rest/v1/rpc/\(name)", body: Self.json(params))
    }

    // MARK: - Storage

    /// Uploads to a bucket; the first folder decides who may read it (see the storage policies in schema.sql).
    public func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        let c = try cfg()
        var req = URLRequest(url: URL(string: "\(c.url)/storage/v1/object/\(bucket)/\(path)")!)
        req.httpMethod = "POST"; req.httpBody = data
        req.setValue(c.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + ((await accessToken()) ?? c.anonKey), forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type"); req.setValue("false", forHTTPHeaderField: "x-upsert")
        do {
            let (body, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw BackendError.transport("no response") }
            guard (200...299).contains(http.statusCode) else { throw BackendError.http(status: http.statusCode, body: String(decoding: body, as: UTF8.self)) }
        } catch let e as BackendError { throw e } catch is CancellationError { throw CancellationError() } catch { throw BackendError.transport(error.localizedDescription) }
    }
    public func signedURL(bucket: String, path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        let c = try cfg()
        struct Signed: Decodable { var signedURL: String }
        let data = try await request("POST", "/storage/v1/object/sign/\(bucket)/\(path)", body: Self.json(["expiresIn": seconds]))
        let s: Signed = try decode(Signed.self, data)
        let rel = s.signedURL.hasPrefix("/") ? s.signedURL : "/" + s.signedURL
        guard let u = URL(string: c.url + "/storage/v1" + rel) else { throw BackendError.decoding("signed url") }
        return u
    }
    /// Deletes files from a bucket (the caller's own folder; the storage policies decide).
    public func deleteObjects(bucket: String, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await request("DELETE", "/storage/v1/object/\(bucket)", body: Self.json(["prefixes": paths]))
    }
    /// The names of the files directly inside `folder` of a bucket (what the caller's storage policies let them list).
    public func listObjects(bucket: String, folder: String) async throws -> [String] {
        struct Entry: Decodable { var name: String? }
        var names: [String] = []
        var offset = 0
        while true {
            let data = try await request("POST", "/storage/v1/object/list/\(bucket)", body: Self.json(["prefix": folder, "limit": 100, "offset": offset]))
            let page = try decode([Entry].self, data).compactMap(\.name)
            names += page; offset += 100
            if page.count < 100 { return names }
        }
    }
    public func publicURL(bucket: String, path: String) -> URL? { config.flatMap { URL(string: "\($0.url)/storage/v1/object/public/\(bucket)/\(path)") } }
}

// MARK: - Role claim

enum JWT {
    /// True when the token's payload carries a `role` claim.
    static func hasRole(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return o["role"] != nil
    }
}

/// A token for an account whose cached token has no role claim yet. One caller at a time asks for the claim. A failed ask is
/// retried after a growing pause (5 s, doubling to 60 s), not on every request; while it waits, requests go out with the cached
/// token (Supabase answers 401 at once and the caller retries) instead of each burning seconds on forced token refreshes.
actor RoleClaim {
    private var claimUid: String?
    private var failures = 0
    private var retryAt: TimeInterval = 0

    func token(identity: IdentityProvider, cached: String, config: BackendConfig, session: URLSession) async -> String? {
        let uid = identity.uid
        if claimUid != uid { claimUid = uid; failures = 0; retryAt = 0 }
        // A request that waited its turn may find the claim already in.
        if let t = (try? await identity.idToken(forceRefresh: false)) ?? nil, JWT.hasRole(t) { return t }
        let now = ProcessInfo.processInfo.systemUptime
        if now < retryAt { return cached }
        do {
            if (200...299).contains(try await requestClaim(cached, config, session)) {
                // The new claim can take a moment to reach a refreshed token; without it Supabase answers 401.
                var fresh = (try? await identity.idToken(forceRefresh: true)) ?? nil
                for _ in 0..<3 where !(fresh.map(JWT.hasRole) ?? false) {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    fresh = (try? await identity.idToken(forceRefresh: true)) ?? nil
                }
                if let f = fresh, JWT.hasRole(f) { failures = 0; retryAt = 0; return f }
            }
        } catch is CancellationError { return cached } catch {}
        failures += 1
        retryAt = ProcessInfo.processInfo.systemUptime + min(60, 5 * pow(2, Double(min(failures - 1, 4))))
        return cached
    }

    /// Asks the claim-role Supabase function to mark this Firebase user as authenticated. Plain HTTP on purpose: going through
    /// Backend would ask for a token again and loop.
    private func requestClaim(_ firebaseToken: String, _ c: BackendConfig, _ session: URLSession) async throws -> Int {
        var req = URLRequest(url: URL(string: "\(c.url)/functions/v1/claim-role")!)
        req.httpMethod = "POST"; req.httpBody = Data("{}".utf8); req.timeoutInterval = 15
        req.setValue(c.anonKey, forHTTPHeaderField: "apikey"); req.setValue(firebaseToken, forHTTPHeaderField: "x-firebase-token"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode ?? 0
    }
}
