import Foundation
import Observation

/// State behind the documents, staff review, members and recommendation screens (the parts of Android's `Services` and `MyListings` they use).
@MainActor @Observable
public final class ManageStore {
    /// Recommendations a listing needs (settings.min_recommendations); 7 until the setting is read.
    public private(set) var needed = 7
    public private(set) var listings: [String: ListingRow] = [:]
    public private(set) var compliance: [String: [DocRequirement]] = [:]
    /// Document type uploading right now, for the spinner on its row.
    public private(set) var uploading: String?
    public private(set) var recommendations: [String: Int] = [:]
    /// The current recommendation token while the QR screen is open.
    public private(set) var token: String?
    public private(set) var reviewQueue: [ReviewDoc] = []
    public private(set) var reviewLoaded = false
    public private(set) var members: [String: [MemberRow]] = [:]
    public private(set) var sentInvites: [String: [SentInviteRow]] = [:]
    public private(set) var names: [String: String] = [:]
    public static let maxFileBytes = 10 * 1024 * 1024

    public init() {}

    private func fail(_ e: Error, _ toast: (String) -> Void) { if !(e is CancellationError) { toast(friendlyError(e)) } }

    // MARK: listing
    public func loadNeeded() async {
        if let n = (try? await Backend.shared.minRecommendationsSetting()) ?? nil, n > 0 { needed = n }
    }
    public func loadListing(_ id: String) async {
        if let l: ListingRow = try? await Backend.shared.selectOne("listings", filters: [.eq("id", id)]) { listings[id] = l }
        await loadNeeded()
        if let n = try? await Backend.shared.recommendationTotal(listingId: id) { recommendations[id] = n }
    }

    // MARK: documents
    public func loadCompliance(_ id: String, toast: (String) -> Void) async {
        do { compliance[id] = try await Backend.shared.listingCompliance(id) } catch let e { fail(e, toast) }
    }

    /// Uploads the file to my private docs folder, then asks the server to record it (it checks number, expiry and service).
    /// A rejected submit removes the uploaded file again; a replaced document's old file is removed after.
    public func submit(listingId: String, row: DocRequirement, file: Picked, number: String, expires: String?, me: String, toast: (String) -> Void) async -> Bool {
        uploading = row.docType; defer { uploading = nil }
        let path = "\(me)/listing-\(row.docType.lowercased())-\(file.objectName())"
        do {
            try await Backend.shared.upload(bucket: "docs", path: path, data: file.data, contentType: file.mime)
            do { try await Backend.shared.submitDocument(listingId: listingId, type: row.docType, path: path, number: number.trimmingCharacters(in: .whitespaces), expires: expires) }
            catch let e { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [path]); throw e }
            if let old = row.path, old != path, old.hasPrefix("\(me)/") { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [old]) }
            toast("\(row.label) sent. Bucks checks documents within two working days.")
            compliance[listingId] = try await Backend.shared.listingCompliance(listingId)
            return true
        } catch let e { fail(e, toast); return false }
    }

    public func remove(listingId: String, row: DocRequirement, me: String?, toast: (String) -> Void) async {
        do {
            try await Backend.shared.deleteDocument(listingId: listingId, type: row.docType)
            if let me, let p = row.path, p.hasPrefix("\(me)/") { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [p]) }
            compliance[listingId] = try await Backend.shared.listingCompliance(listingId)
            toast("\(row.label) removed.")
        } catch let e { fail(e, toast) }
    }

    // MARK: staff review
    public func loadReviewQueue(toast: (String) -> Void) async {
        do { reviewQueue = try await Backend.shared.documentsToReview(); reviewLoaded = true } catch let e { fail(e, toast) }
    }
    public func review(_ item: ReviewDoc, approve: Bool, note: String, toast: (String) -> Void) async {
        do {
            try await Backend.shared.reviewDocument(id: item.id, approve: approve, note: note)
            reviewQueue.removeAll { $0.id == item.id }
            toast(approve ? "\(item.label) for \(item.listingTitle) approved." : "Rejected. They'll see your reason.")
        } catch let e { fail(e, toast) }
    }

    // MARK: members and invites
    public func loadMembers(_ listingId: String, me: String?, toast: (String) -> Void) async {
        do {
            let rows = try await Backend.shared.listingMembers(listingId: listingId)
            let sent = (try? await Backend.shared.pendingListingInvites(listingId: listingId)) ?? []
            await loadNames(rows.map(\.profileId) + sent.map(\.inviteeId))
            members[listingId] = rows
            sentInvites[listingId] = sent
        } catch let e { if members[listingId] == nil { members[listingId] = [] }; fail(e, toast) }
    }
    private func loadNames(_ ids: [String]) async {
        let missing = Array(Set(ids)).filter { names[$0] == nil }
        guard !missing.isEmpty, let ps = try? await Backend.shared.profiles(missing) else { return }
        for p in ps { names[p.id] = p.name }
    }
    public func invite(listingId: String, bucksId: String, role: String, toast: (String) -> Void) async -> Bool {
        do {
            try await Backend.shared.inviteToListing(listingId: listingId, bucksId: bucksId, role: role)
            toast("Invite sent to \(bucksId.trimmingCharacters(in: .whitespaces).uppercased()). They'll see it under Invites.")
            sentInvites[listingId] = (try? await Backend.shared.pendingListingInvites(listingId: listingId)) ?? sentInvites[listingId]
            await loadNames((sentInvites[listingId] ?? []).map(\.inviteeId))
            return true
        } catch let e { fail(e, toast); return false }
    }
    public func revoke(listingId: String, invite: SentInviteRow, toast: (String) -> Void) async {
        do {
            try await Backend.shared.revokeInvite(id: invite.id)
            sentInvites[listingId]?.removeAll { $0.id == invite.id }
            toast("Invite cancelled.")
        } catch let e { fail(e, toast) }
    }
    /// Returns true when it was me who left.
    public func removeMember(listingId: String, profileId: String, me: String?, toast: (String) -> Void) async -> Bool {
        do {
            try await Backend.shared.removeListingMember(listingId: listingId, profileId: profileId)
            members[listingId]?.removeAll { $0.profileId == profileId }
            toast(profileId == me ? "You left." : "Removed.")
            return profileId == me
        } catch let e { fail(e, toast); return false }
    }

    // MARK: recommendations
    /// A fresh token (valid 2 minutes) and the current count; the QR screen calls this every 90 seconds.
    public func refreshToken(_ listingId: String, toast: (String) -> Void) async {
        do {
            token = try await Backend.shared.recommendToken(listingId: listingId)
            recommendations[listingId] = try await Backend.shared.recommendationTotal(listingId: listingId)
            if (recommendations[listingId] ?? 0) >= needed, listings[listingId]?.status == "PENDING" { await loadListing(listingId) }
        } catch let e { fail(e, toast) }
    }
    /// Count and status only (the live count while the QR screen stays open).
    public func refreshCount(_ listingId: String) async {
        guard let n = try? await Backend.shared.recommendationTotal(listingId: listingId) else { return }
        recommendations[listingId] = n
        if n >= needed, listings[listingId]?.status == "PENDING" { await loadListing(listingId) }
    }
    public func clearToken() { token = nil }

    /// Scanned someone's code in person at a real fix: the server checks distance, account age and position, and returns the new count.
    public func recommend(token: String, lat: Double, lng: Double, toast: (String) -> Void) async -> Int? {
        do {
            let n = try await Backend.shared.recommend(token: token, lat: lat, lng: lng)
            toast(n >= needed ? "Thanks, that's \(n) of \(needed). They're live on Bucks now." : "Thanks, that's \(n) of \(needed).")
            return n
        } catch let e { fail(e, toast); return nil }
    }

    /// The next account on this phone starts clean.
    public func reset() {
        listings = [:]; compliance = [:]; uploading = nil; recommendations = [:]; token = nil; reviewQueue = []; reviewLoaded = false
        members = [:]; sentInvites = [:]; names = [:]
    }
}
