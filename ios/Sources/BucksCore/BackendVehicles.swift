import Foundation

// Vehicle management calls (port of data/BackendManage.kt, vehicle part). Rows are protected by row-level security:
// an owner sees and changes their vehicles, a driver they invited sees them.

/// One uploaded vehicle document (kind RC, INSURANCE, DL, PERMIT or PUC) at `path` in the private "docs" bucket.
public struct VehicleDoc: Hashable, Sendable {
    public var kind: String
    public var path: String
    public init(kind: String, path: String) { self.kind = kind; self.path = path }
}

/// A document slot: what it is, whether Bucks needs it before the vehicle can go online, and how to photograph it.
public struct VehicleDocKind: Hashable, Sendable {
    public var key: String, label: String, required: Bool, hint: String
}

/// The documents asked for a vehicle kind (BIKE, AUTO, CAB).
public func vehicleDocKinds(_ vehicleKind: String) -> [VehicleDocKind] {
    let bike = vehicleKind == "BIKE"
    return [
        VehicleDocKind(key: "RC", label: "Registration certificate (RC)", required: true, hint: "Both sides, with the number plate readable."),
        VehicleDocKind(key: "INSURANCE", label: "Insurance", required: true, hint: "The current policy page showing the vehicle number and dates."),
        VehicleDocKind(key: "DL", label: "Driving licence", required: true, hint: "Your licence, both sides. Drivers you invite add theirs from their own phone."),
        VehicleDocKind(key: "PERMIT", label: "Permit", required: !bike, hint: bike ? "Only if you carry goods commercially." : "Contract carriage or auto permit for passengers."),
        VehicleDocKind(key: "PUC", label: "Pollution certificate (PUC)", required: false, hint: "Valid PUC. Not needed for electric vehicles."),
    ]
}

public struct VehicleMemberRow: Codable, Hashable, Sendable {
    public var vehicleId: String
    public var profileId: String
    public var role: String
}

/// A vehicle row with its `docs` column (a JSON array of {kind, path}; plain path strings are read as kind DOC).
private struct VehicleWithDocsRow: Decodable {
    var row: VehicleRow
    var docs: [VehicleDoc]
    private struct Entry: Decodable {
        var kind: String?, path: String?
        init(from d: Decoder) throws {
            if let single = try? d.singleValueContainer(), let s = try? single.decode(String.self) { kind = "DOC"; path = s; return }
            // Anything else in the list (null, a number, an object without a path) is skipped; it must not discard the other documents.
            guard let c = try? d.container(keyedBy: Keys.self) else { return }
            kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil; path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? nil
        }
        private enum Keys: String, CodingKey { case kind, path }
    }
    private enum Keys: String, CodingKey { case docs }
    init(from d: Decoder) throws {
        row = try VehicleRow(from: d)
        let c = try d.container(keyedBy: Keys.self)
        let entries = (try? c.decodeIfPresent([Entry].self, forKey: .docs)) ?? nil
        docs = (entries ?? []).compactMap { e in
            guard let p = e.path, !p.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return VehicleDoc(kind: e.kind ?? "DOC", path: p)
        }
    }
}

public extension Backend {
    /// Vehicles I own or drive, and their documents, from one read so the edit form never sees a vehicle without its documents.
    func myVehiclesWithDocs() async throws -> (vehicles: [VehicleRow], docs: [String: [VehicleDoc]]) {
        let rows: [VehicleWithDocsRow] = try await select("vehicles")
        var docs: [String: [VehicleDoc]] = [:]
        for r in rows { docs[r.row.id] = r.docs }
        return (rows.map(\.row), docs)
    }
    func addVehicle(me: String, kind: String, model: String, plate: String) async throws -> VehicleRow {
        try await insert("vehicles", ["owner_id": me, "kind": kind, "model": model, "plate": Self.cleanPlate(plate)])
    }
    func setVehicleDocs(id: String, docs: [VehicleDoc]) async throws {
        try await update("vehicles", ["docs": Self.docsJSON(docs)], filters: [.eq("id", id)])
    }
    func updateVehicleDetails(id: String, kind: String, model: String, plate: String, docs: [VehicleDoc]) async throws {
        try await update("vehicles", ["kind": kind, "model": model, "plate": Self.cleanPlate(plate), "docs": Self.docsJSON(docs)], filters: [.eq("id", id)])
    }
    func deleteVehicle(id: String) async throws { try await delete("vehicles", filters: [.eq("id", id)]) }
    func vehicleMembers(vehicleId: String) async throws -> [VehicleMemberRow] {
        try await select("vehicle_members", filters: [.eq("vehicle_id", vehicleId)])
    }
    func removeVehicleMember(vehicleId: String, profileId: String) async throws {
        try await delete("vehicle_members", filters: [.eq("vehicle_id", vehicleId), .eq("profile_id", profileId)])
    }

    /// Uploads one document to docs/<my id>/ and returns its reference.
    func uploadVehicleDoc(me: String, kind: String, data: Data, fileExtension: String, contentType: String) async throws -> VehicleDoc {
        let ext = fileExtension.isEmpty ? "bin" : fileExtension.lowercased()
        let path = "\(me)/vehicle-\(kind.lowercased())-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()).\(ext)"
        try await upload(bucket: "docs", path: path, data: data, contentType: contentType)
        return VehicleDoc(kind: kind, path: path)
    }

    private static func cleanPlate(_ plate: String) -> String { plate.uppercased().replacingOccurrences(of: " ", with: "") }
    private static func docsJSON(_ docs: [VehicleDoc]) -> [[String: String]] { docs.map { ["kind": $0.kind, "path": $0.path] } }
}

/// An invite I sent for a vehicle (waiting for the answer).
public struct SentInviteRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var inviteeId: String
    public var role: String
}

public extension Backend {
    /// Invites I sent for this vehicle that nobody has answered yet.
    func pendingVehicleInvites(vehicleId: String) async throws -> [SentInviteRow] {
        try await select("invites", columns: "id,invitee_id,role", filters: [.eq("vehicle_id", vehicleId), .eq("status", "PENDING")])
    }
    /// Sends a driver invite to a Bucks ID; the server answers with a sentence, or raises one.
    @discardableResult func inviteDriver(vehicleId: String, bucksId: String) async throws -> String {
        try await rpc("invite", ["p_listing": nil, "p_vehicle": vehicleId, "p_short_code": bucksId, "p_role": "ADMIN"])
    }
    func revokeInvite(id: String) async throws { try await update("invites", ["status": "REVOKED"], filters: [.eq("id", id)]) }
}


/// An invite addressed to me, with the inviter's name and what it is for (from `my_invites()`). kind: BUSINESS / SKILL / DRIVER / VEHICLE.
public struct InviteForMe: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listingId: String?
    public var vehicleId: String?
    public var inviterId: String
    public var inviterName: String
    public var role: String
    public var title: String
    public var kind: String
    public var createdAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); listingId = try c.decodeIfPresent(String.self, forKey: .listingId); vehicleId = try c.decodeIfPresent(String.self, forKey: .vehicleId)
        inviterId = try c.decode(String.self, forKey: .inviterId); inviterName = try c.decodeIfPresent(String.self, forKey: .inviterName) ?? ""; role = try c.decode(String.self, forKey: .role)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""; kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""; createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
    private enum Keys: String, CodingKey { case id, listingId, vehicleId, inviterId, inviterName, role, title, kind, createdAt }
}

public extension Backend {
    /// Invites waiting for my answer.
    func invitesForMe() async throws -> [InviteForMe] { try await rpcList("my_invites") }
    func respondInvite(id: String, accept: Bool) async throws { try await rpcVoid("respond_invite", ["p_invite": id, "p_accept": accept]) }
    /// Deleting an account: every file in my private docs folder (listing and vehicle documents).
    func deleteMyDocFiles(me: String) async throws {
        let names = try await listObjects(bucket: "docs", folder: me).map { "\(me)/\($0)" }
        if !names.isEmpty { try await deleteObjects(bucket: "docs", paths: names) }
    }
}
