import Foundation

// Calls for managing my own listings (port of data/BackendManage.kt; the vehicle half lives in BackendVehicles.swift).

public extension Backend {
    /// listing id -> my role (OWNER, ADMIN, STORE_RIDER) for every listing I help run.
    func myRoles(me: String) async throws -> [String: String] {
        let rows: [MemberRow] = try await select("listing_members", filters: [.eq("profile_id", me)])
        return Dictionary(rows.map { ($0.listingId, $0.role) }, uniquingKeysWith: { _, last in last })
    }
    func setListingPhoto(id: String, url: String?) async throws {
        try await update("listings", ["photo_url": url], filters: [.eq("id", id)])
    }
    /// Deletes a listing through delete_listing() (manage.sql): outright when it never took an order, otherwise it is emptied and kept
    /// hidden so buyers keep their order history. Raises a plain sentence while an order is still open.
    func removeListing(id: String) async throws { try await rpcVoid("delete_listing", ["p_listing": id]) }
    /// Saves an existing product or service column by column, so "back in stock" or a cleared MRP, unit or group always reaches the server.
    func updateItem(_ item: ItemRow) async throws -> ItemRow {
        guard let id = item.id else { throw BackendError.decoding("updateItem needs a saved item") }
        let values: [String: Any?] = [
            "name": item.name, "price": item.price, "mrp": item.mrp, "unit": item.unit, "group_name": item.groupName,
            "photo_url": item.photoUrl, "in_stock": item.inStock, "sort": item.sort,
            "description": item.description, "stock": item.stock, "photos": Self.mediaJSON(item.photos), "details": item.details.any,
        ]
        guard let saved = try await update("items", values, filters: [.eq("id", id)], returning: ItemRow.self) else { throw BackendError.decoding("items: empty update result") }
        return saved
    }
    /// How many neighbours have recommended each listing (the community cap counts these).
    func recommendationCounts(_ listingIds: [String]) async throws -> [String: Int] {
        if listingIds.isEmpty { return [:] }
        struct Row: Decodable { var listingId: String }
        let rows: [Row] = try await select("recommendations", columns: "listing_id,recommender_id", filters: [.isIn("listing_id", listingIds)])
        return rows.reduce(into: [:]) { $0[$1.listingId, default: 0] += 1 }
    }
    /// Removes files from a bucket (documents of a deleted vehicle). Row-level security still applies.
    func deleteFiles(bucket: String, paths: [String]) async throws { if !paths.isEmpty { try await deleteObjects(bucket: bucket, paths: paths) } }
}
