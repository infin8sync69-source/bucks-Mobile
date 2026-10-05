import Foundation

// The compliance/review rows and their RPCs live in BackendServices.swift (ComplianceRow, ReviewItem, listingCompliance, submitDocument, ...).
public typealias DocRequirement = ComplianceRow
public typealias ReviewDoc = ReviewItem

private struct RecommenderRow: Decodable { var recommenderId: String }
private struct SettingValue: Decodable { var value: Double }

/// Documents, staff review, members, invites and in-person recommendations (BackendManage / BackendStudio / BackendServices / Backend.kt).
public extension Backend {
    // MARK: members and invites
    func listingMembers(listingId: String) async throws -> [MemberRow] { try await select("listing_members", filters: [.eq("listing_id", listingId)]) }
    func removeListingMember(listingId: String, profileId: String) async throws {
        try await delete("listing_members", filters: [.eq("listing_id", listingId), .eq("profile_id", profileId)])
    }
    /// Invites a person to help run a listing (ADMIN or STORE_RIDER); the server answers with a sentence, or raises one.
    @discardableResult func inviteToListing(listingId: String, bucksId: String, role: String) async throws -> String {
        try await rpc("invite", ["p_listing": listingId, "p_vehicle": nil, "p_short_code": bucksId, "p_role": role])
    }
    /// Invites I sent for this listing that nobody has answered yet.
    func pendingListingInvites(listingId: String) async throws -> [SentInviteRow] {
        try await select("invites", columns: "id,invitee_id,role", filters: [.eq("listing_id", listingId), .eq("status", "PENDING")])
    }

    // MARK: recommendations
    func recommendToken(listingId: String) async throws -> String { try await rpc("recommend_token", ["p_listing": listingId]) }
    /// Returns the listing's recommendation count after this one; it goes live at the threshold.
    func recommend(token: String, lat: Double, lng: Double) async throws -> Int { try await rpc("recommend", ["p_token": token, "lat": lat, "lng": lng]) }
    func recommendationTotal(listingId: String) async throws -> Int {
        let rows: [RecommenderRow] = try await select("recommendations", columns: "recommender_id", filters: [.eq("listing_id", listingId)])
        return rows.count
    }
    /// How many in-person recommendations take a listing live (`settings.min_recommendations`); nil when it can't be read.
    func minRecommendationsSetting() async throws -> Int? {
        let rows: [SettingValue] = try await select("settings", columns: "key,value", filters: [.eq("key", "min_recommendations")])
        return rows.first.map { Int($0.value) }
    }
}
