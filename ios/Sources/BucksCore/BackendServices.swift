import Foundation

// Service unlocking and listing documents (supabase/migrations/services.sql, docs/SERVICES_UNLOCK.md). Port of data/BackendServices.kt.

/// One service as seen from where the customer stands (services_near). `state`: SOON (switched off), LOCKED (not enough
/// checked providers within `radiusM`), QUIET (unlocked, too few online right now), OPEN.
public struct ServiceState: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var mode: String
    public var state: String
    public var supply: Int
    public var minSupply: Int
    public var online: Int
    public var minOnline: Int
    public var supplyNoun: String
    public var radiusM: Int
    public var delivery: Bool
    public var deliveryNow: Bool
    public var interested: Int
    public var mine: Bool
    public var id: String { key }
    public init(key: String, label: String, mode: String = "AUTO", state: String = "LOCKED", supply: Int = 0, minSupply: Int = 0, online: Int = 0, minOnline: Int = 0,
                supplyNoun: String = "", radiusM: Int = 0, delivery: Bool = false, deliveryNow: Bool = false, interested: Int = 0, mine: Bool = false) {
        self.key = key; self.label = label; self.mode = mode; self.state = state; self.supply = supply; self.minSupply = minSupply; self.online = online; self.minOnline = minOnline
        self.supplyNoun = supplyNoun; self.radiusM = radiusM; self.delivery = delivery; self.deliveryNow = deliveryNow; self.interested = interested; self.mine = mine
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        key = try c.decode(String.self, forKey: .key); label = try c.decode(String.self, forKey: .label)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? "AUTO"; state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "LOCKED"
        supply = (try? c.decodeIfPresent(Int.self, forKey: .supply)) ?? 0; minSupply = (try? c.decodeIfPresent(Int.self, forKey: .minSupply)) ?? 0
        online = (try? c.decodeIfPresent(Int.self, forKey: .online)) ?? 0; minOnline = (try? c.decodeIfPresent(Int.self, forKey: .minOnline)) ?? 0
        supplyNoun = (try? c.decodeIfPresent(String.self, forKey: .supplyNoun)) ?? ""; radiusM = (try? c.decodeIfPresent(Int.self, forKey: .radiusM)) ?? 0
        delivery = (try? c.decodeIfPresent(Bool.self, forKey: .delivery)) ?? false; deliveryNow = (try? c.decodeIfPresent(Bool.self, forKey: .deliveryNow)) ?? false
        interested = (try? c.decodeIfPresent(Int.self, forKey: .interested)) ?? 0; mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
    private enum K: String, CodingKey { case key, label, mode, state, supply, minSupply, online, minOnline, supplyNoun, radiusM, delivery, deliveryNow, interested, mine }
    public var usable: Bool { state == "OPEN" || state == "QUIET" }
    /// "3 km" or "1.5 km".
    public var radiusKm: String { radiusM % 1000 == 0 ? "\(radiusM / 1000) km" : String(format: "%.1f km", Double(radiusM) / 1000) }
}

/// A document the listing's service asks for and where it stands (listing_compliance). status: MISSING, PENDING, VERIFIED, REJECTED, EXPIRED.
public struct ComplianceRow: Codable, Hashable, Sendable, Identifiable {
    public var docType: String
    public var label: String
    public var hint: String
    public var required: Bool
    public var publicNumber: Bool
    public var asksNumber: Bool
    public var hasExpiry: Bool
    public var status: String
    public var number: String
    public var expiresOn: String?
    public var note: String
    public var path: String?
    public var id: String { docType }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func s(_ k: K, _ def: String = "") -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? def }
        func b(_ k: K, _ def: Bool) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? def }
        docType = try c.decode(String.self, forKey: .docType); label = try c.decode(String.self, forKey: .label); hint = s(.hint); required = b(.required, false)
        publicNumber = b(.publicNumber, false); asksNumber = b(.asksNumber, true); hasExpiry = b(.hasExpiry, false); status = s(.status, "MISSING"); number = s(.number)
        expiresOn = (try? c.decodeIfPresent(String.self, forKey: .expiresOn)) ?? nil; note = s(.note); path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? nil
    }
    private enum K: String, CodingKey { case docType, label, hint, required, publicNumber, asksNumber, hasExpiry, status, number, expiresOn, note, path }
}

/// A verified, in-date document shown on a public profile (listing_badges); `number` is blank unless the law wants it shown.
public struct BadgeRow: Codable, Hashable, Sendable, Identifiable {
    public var docType: String
    public var label: String
    public var number: String
    public var expiresOn: String?
    public var id: String { docType }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        docType = try c.decode(String.self, forKey: .docType); label = try c.decode(String.self, forKey: .label)
        number = (try? c.decodeIfPresent(String.self, forKey: .number)) ?? ""; expiresOn = (try? c.decodeIfPresent(String.self, forKey: .expiresOn)) ?? nil
    }
    private enum K: String, CodingKey { case docType, label, number, expiresOn }
}

/// A document waiting for Bucks staff (documents_to_review).
public struct ReviewItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String
    public var listingTitle: String
    public var service: String?
    public var docType: String
    public var label: String
    public var number: String
    public var expiresOn: String?
    public var path: String
    public var uploadedBy: String
    public var createdAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func s(_ k: K) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        id = try c.decode(String.self, forKey: .id); listingId = try c.decode(String.self, forKey: .listingId); listingTitle = s(.listingTitle)
        service = (try? c.decodeIfPresent(String.self, forKey: .service)) ?? nil; docType = try c.decode(String.self, forKey: .docType); label = s(.label); number = s(.number)
        expiresOn = (try? c.decodeIfPresent(String.self, forKey: .expiresOn)) ?? nil; path = try c.decode(String.self, forKey: .path)
        uploadedBy = try c.decode(String.self, forKey: .uploadedBy); createdAt = s(.createdAt)
    }
    private enum K: String, CodingKey { case id, listingId, listingTitle, service, docType, label, number, expiresOn, path, uploadedBy, createdAt }
}

extension Backend {
    public func servicesNear(_ at: LatLng) async throws -> [ServiceState] { try await rpcList("services_near", ["lat": at.lat, "lng": at.lng]) }
    /// True when I am now on the "notify me" list for `key`, false when I just left it.
    public func toggleServiceInterest(_ key: String, at: LatLng) async throws -> Bool {
        try await rpc("toggle_service_interest", ["p_service": key, "lat": at.lat, "lng": at.lng])
    }
    public func listingCompliance(_ listingId: String) async throws -> [ComplianceRow] { try await rpcList("listing_compliance", ["p_listing": listingId]) }
    public func listingBadges(_ listingId: String) async throws -> [BadgeRow] { try await rpcList("listing_badges", ["p_listing": listingId]) }
    /// `expires`: yyyy-MM-dd or nil. The file must already be uploaded to docs/<my id>/.
    public func submitDocument(listingId: String, type: String, path: String, number: String, expires: String?) async throws {
        try await rpcVoid("submit_document", ["p_listing": listingId, "p_type": type, "p_path": path, "p_number": number, "p_expires": expires])
    }
    public func deleteDocument(listingId: String, type: String) async throws { try await rpcVoid("delete_document", ["p_listing": listingId, "p_type": type]) }
    public func isStaff() async throws -> Bool { try await rpc("is_staff") }
    public func documentsToReview() async throws -> [ReviewItem] { try await rpcList("documents_to_review") }
    public func reviewDocument(id: String, approve: Bool, note: String) async throws {
        try await rpcVoid("review_document", ["p_doc": id, "p_approve": approve, "p_note": note])
    }
}
