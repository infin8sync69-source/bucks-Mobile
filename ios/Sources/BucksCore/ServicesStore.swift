import Foundation
import Observation

/// One tile of the Services menu. The server decides whether it is open where the customer stands (services_near); this is
/// what only the app needs: the icon, what the supply side is asked to do, and the categories a business of it can pick.
public struct ServiceDef: Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    /// SF Symbol name.
    public var icon: String
    /// Button on the locked sheet that asks providers to join ("Run a restaurant? List it").
    public var joinPrompt: String
    public var joinAction: String
    /// Categories a business of this service can pick (empty for services that are not businesses).
    public var categories: [String] = []
    public var id: String { key }
}

public let serviceCatalog: [ServiceDef] = [
    ServiceDef(key: "TAXI", label: "Taxi", icon: "car.fill", joinPrompt: "Drive a cab?", joinAction: "Add your cab"),
    ServiceDef(key: "AUTO", label: "Auto", icon: "car.side.fill", joinPrompt: "Drive an auto?", joinAction: "Add your auto"),
    ServiceDef(key: "PARCEL", label: "Parcel", icon: "shippingbox.fill", joinPrompt: "Ride a bike?", joinAction: "Add your bike"),
    ServiceDef(key: "FOOD", label: "Food", icon: "fork.knife", joinPrompt: "Run a restaurant?", joinAction: "List it", categories: ["Restaurant", "Bakery", "Cafe", "Sweets", "Cloud kitchen", "Tiffin"]),
    ServiceDef(key: "GROCERY", label: "Grocery", icon: "cart.fill", joinPrompt: "Run a grocery store?", joinAction: "List it", categories: ["Grocery", "Supermarket", "Dairy"]),
    ServiceDef(key: "VEGETABLES", label: "Vegetables", icon: "leaf.fill", joinPrompt: "Sell vegetables or fruit?", joinAction: "List your stall", categories: ["Vegetables", "Fruits"]),
    ServiceDef(key: "MEAT", label: "Meat", icon: "flame.fill", joinPrompt: "Run a meat or fish shop?", joinAction: "List it", categories: ["Chicken", "Mutton", "Fish", "Eggs"]),
    ServiceDef(key: "SHOPPING", label: "Shopping", icon: "bag.fill", joinPrompt: "Run a shop?", joinAction: "List it", categories: ["Electronics", "Mobile repair", "Hardware", "Furniture", "Clothing", "Stationery", "Salon", "Tailor", "Other"]),
    ServiceDef(key: "GIGS", label: "Gigs", icon: "wrench.and.screwdriver.fill", joinPrompt: "Have a skill?", joinAction: "Offer it"),
    ServiceDef(key: "JOBS", label: "Jobs", icon: "briefcase.fill", joinPrompt: "Hiring?", joinAction: "Post a job from your business"),
    ServiceDef(key: "PROPERTIES", label: "Properties", icon: "building.2.fill", joinPrompt: "Have a place to rent or sell?", joinAction: "List it", categories: ["Property owner", "Real estate agent", "Builder"]),
]
public func serviceDef(_ key: String?) -> ServiceDef? { serviceCatalog.first { $0.key == key } }
/// The services a BUSINESS listing can belong to (skills are always Gigs, drivers have none).
public let businessServices = ["FOOD", "GROCERY", "VEGETABLES", "MEAT", "SHOPPING", "PROPERTIES"]
/// Same mapping as service_for_category() on the server, for listings saved before a service was chosen.
public func serviceForCategory(_ category: String?) -> String {
    let c = category?.trimmingCharacters(in: .whitespaces) ?? ""
    return businessServices.first { k in serviceDef(k)?.categories.contains { $0.caseInsensitiveCompare(c) == .orderedSame } ?? false } ?? "SHOPPING"
}

/// Service unlocking and listing documents. Same shape as the other stores: observable state plus actions that report every failure as a toast.
@MainActor @Observable
public final class ServicesStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    /// Every service in menu order, as seen from where I am.
    public private(set) var rows: [ServiceState] = []
    public private(set) var loaded = false
    public private(set) var error: String?
    /// Listing id -> documents its service asks for.
    public private(set) var compliance: [String: [ComplianceRow]] = [:]
    /// Listing id -> verified documents shown on its public profile.
    public private(set) var badges: [String: [BadgeRow]] = [:]
    /// Document type uploading right now, for the spinner on its row.
    public private(set) var uploading: String?
    public private(set) var isStaff = false
    public private(set) var reviewQueue: [ReviewItem] = []
    public private(set) var reviewLoaded = false

    private func go(_ block: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { session.toast(friendly(error)) }
        }
    }
    /// A refusal carries our own sentence; anything else is a connection problem.
    private func friendly(_ e: Error) -> String { isServerRefusal(e) ? friendlyError(e) : "Couldn't reach Bucks. Check your connection and try again." }

    public func state(_ key: String) -> ServiceState? { rows.first { $0.key == key } }
    /// How many services are usable here.
    public var openCount: Int { serviceCatalog.filter { state($0.key)?.usable == true }.count }

    /// Re-reads every service's state around where I am.
    public func refresh() {
        guard session.cloud else { return }
        let at = session.here
        Task { @MainActor in
            do { rows = try await Backend.shared.servicesNear(at); loaded = true; error = nil }
            catch is CancellationError {}
            catch { self.error = friendly(error); if rows.isEmpty { rows = serviceCatalog.map { ServiceState(key: $0.key, label: $0.label, state: "LOCKED") } } }
        }
    }

    public func toggleInterest(_ key: String) {
        go { [self] in
            let on = try await Backend.shared.toggleServiceInterest(key, at: session.here)
            rows = rows.map { r in
                guard r.key == key else { return r }
                var n = r; n.mine = on; n.interested = max(0, r.interested + (on ? 1 : -1)); return n
            }
            let label = serviceDef(key)?.label ?? "it"
            session.toast(on ? "We'll let you know when \(label) opens near you." : "You won't get a note about \(label).")
        }
    }

    // MARK: listing documents

    public func loadCompliance(_ listingId: String) { go { [self] in compliance[listingId] = try await Backend.shared.listingCompliance(listingId) } }
    public func loadBadges(_ listingId: String) { go { [self] in badges[listingId] = try await Backend.shared.listingBadges(listingId) } }

    /// Uploads `file` to my private docs folder, then asks the server to record it (submit_document checks the number, expiry
    /// and service). A rejected submit removes the uploaded file again; a replaced document's old file is removed after.
    public func submit(_ listingId: String, row: ComplianceRow, file: Picked, number: String, expires: String?, onDone: @escaping () -> Void = {}) {
        go { [self] in
            guard let me = session.me?.id else { return }
            uploading = row.docType
            defer { uploading = nil }
            let path = "\(me)/listing-\(row.docType.lowercased())-\(file.objectName())"
            try await Backend.shared.upload(bucket: "docs", path: path, data: file.data, contentType: file.mime)
            do { try await Backend.shared.submitDocument(listingId: listingId, type: row.docType, path: path, number: number.trimmingCharacters(in: .whitespacesAndNewlines), expires: expires) }
            catch { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [path]); throw error }
            if let old = row.path, old != path, old.hasPrefix("\(me)/") { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [old]) }
            session.toast("\(row.label) sent. Bucks checks documents within two working days.")
            compliance[listingId] = try await Backend.shared.listingCompliance(listingId)
            onDone()
        }
    }

    public func remove(_ listingId: String, row: ComplianceRow) {
        go { [self] in
            try await Backend.shared.deleteDocument(listingId: listingId, type: row.docType)
            if let me = session.me?.id, let p = row.path, p.hasPrefix("\(me)/") { try? await Backend.shared.deleteObjects(bucket: "docs", paths: [p]) }
            compliance[listingId] = try await Backend.shared.listingCompliance(listingId)
            session.toast("\(row.label) removed.")
        }
    }

    // MARK: Bucks staff: document review

    public func checkStaff() {
        guard session.cloud else { return }
        Task { @MainActor in isStaff = (try? await Backend.shared.isStaff()) ?? false }
    }
    public func loadReviewQueue() { go { [self] in reviewQueue = try await Backend.shared.documentsToReview(); reviewLoaded = true } }
    public func review(_ item: ReviewItem, approve: Bool, note: String) {
        go { [self] in
            try await Backend.shared.reviewDocument(id: item.id, approve: approve, note: note)
            reviewQueue.removeAll { $0.id == item.id }
            session.toast(approve ? "\(item.label) for \(item.listingTitle) approved." : "Rejected. They'll see your reason.")
        }
    }

    /// The next account on this phone starts clean.
    public func signedOut() {
        rows = []; loaded = false; error = nil
        compliance = [:]; badges = [:]; isStaff = false; reviewQueue = []; reviewLoaded = false
    }
}
