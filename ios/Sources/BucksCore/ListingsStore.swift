import Foundation
import Observation

/// The listing-side calls the store needs that are not shared with another area; kept here so they cannot clash with other `Backend` extensions.
enum ListingsAPI {
    static var db: Backend { Backend.shared }

    static func myListings(me: String) async throws -> [ListingRow] {
        let ids = try await db.select("listing_members", filters: [.eq("profile_id", me)]) as [MemberRow]
        if ids.isEmpty { return [] }
        return try await db.select("listings", filters: [.isIn("id", ids.map(\.listingId))])
    }
    static func createListing(me: String, kind: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JSONValue, service: String?) async throws -> ListingRow {
        var body: [String: Any?] = ["kind": kind, "owner_id": me, "title": title, "category": category, "description": description, "area": area, "details": details.any]
        if let service { body["service"] = service }
        if let at { body["location"] = Backend.point(at) }
        return try await db.insert("listings", body)
    }
    /// `service` is only sent when it changes (the server refuses a change once the listing is live); `at` nil keeps the saved location.
    static func updateListing(id: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JSONValue, service: String?) async throws {
        var body: [String: Any?] = ["title": title, "category": category, "description": description, "area": area, "details": details.any]
        if let at { body["location"] = Backend.point(at) }
        if let service { body["service"] = service }
        try await db.update("listings", body, filters: [.eq("id", id)])
    }
    static func setOnline(id: String, online: Bool) async throws { try await db.update("listings", ["online": online], filters: [.eq("id", id)]) }
    static func members(listingId: String) async throws -> [MemberRow] { try await db.select("listing_members", filters: [.eq("listing_id", listingId)]) }
    static func removeMember(listingId: String, profileId: String) async throws {
        try await db.delete("listing_members", filters: [.eq("listing_id", listingId), .eq("profile_id", profileId)])
    }
    static func items(listingId: String) async throws -> [ItemRow] { try await db.select("items", filters: [.eq("listing_id", listingId)], order: "sort") }
    static func insertItem(_ item: ItemRow) async throws -> ItemRow { try await db.insert("items", item.body) }
    static func deleteItem(id: String) async throws { try await db.delete("items", filters: [.eq("id", id)]) }
    static func listingPosts(listingId: String) async throws -> [PostRow] { try await db.select("posts", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false) }
    static func reviews(listingId: String) async throws -> [ReviewRow] { try await db.select("reviews", filters: [.eq("listing_id", listingId)], order: "created_at", ascending: false) }
    static func invite(listingId: String?, vehicleId: String?, bucksId: String, role: String) async throws -> String {
        try await db.rpc("invite", ["p_listing": listingId, "p_vehicle": vehicleId, "p_short_code": bucksId, "p_role": role])
    }
    static func myInvites() async throws -> [InviteRow] { try await db.select("invites", filters: [.eq("status", "PENDING")]) }
    static func recommendToken(listingId: String) async throws -> String { try await db.rpc("recommend_token", ["p_listing": listingId]) }
    static func recommend(token: String, at: LatLng) async throws -> Int { try await db.rpc("recommend", ["p_token": token, "lat": at.lat, "lng": at.lng]) }
}

/// Everything an owner does with their own listings: businesses, skills and the driver profile, their products and services,
/// vehicles with documents, admins and store riders, and the recommendation QR that takes a listing live.
/// Port of the Android `MyListings`: observable state plus actions that run in the background and toast any failure.
@MainActor @Observable
public final class ListingsStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    /// Local recommendations a listing needs before it goes live: settings.min_recommendations, read on every refresh (7 until then).
    public nonisolated(unsafe) static var NEEDED = 7
    public private(set) var needed = 7

    public var me: ProfileRow? { session.me }

    /// Listings I own or help run.
    public private(set) var listings: [ListingRow] = []
    /// listing id -> my role in it: OWNER, ADMIN or STORE_RIDER.
    public private(set) var roles: [String: String] = [:]
    /// Vehicles I own or drive.
    public private(set) var vehicles: [VehicleRow] = []
    public private(set) var vehicleDocs: [String: [VehicleDoc]] = [:]
    /// listing id -> its products or services, loaded per listing.
    public private(set) var items: [String: [ItemRow]] = [:]
    public private(set) var members: [String: [MemberRow]] = [:]
    public private(set) var vehicleMembers: [String: [VehicleMemberRow]] = [:]
    /// listing id -> how many people nearby have recommended it.
    public private(set) var recommendations: [String: Int] = [:]
    /// listing id -> its own posts (the listing's feed), newest first.
    public private(set) var posts: [String: [PostRow]] = [:]
    /// listing id -> customer reviews, newest first.
    public private(set) var reviews: [String: [ReviewRow]] = [:]
    /// listing id -> recommendations, syncs, team size and open jobs.
    public private(set) var counts: [String: ListingCounts] = [:]
    /// listing id -> the documents its service asks for (for the go-live checklist); absent while loading.
    public private(set) var compliance: [String: [ComplianceRow]] = [:]
    /// Invites waiting for my answer.
    public private(set) var invites: [InviteForMe] = []
    /// Invites I sent that are still pending.
    public private(set) var sentInvites: [InviteRow] = []
    public private(set) var stats: [VehicleStat] = []
    /// The current recommendation token while the QR screen is open.
    public private(set) var token: String?
    public private(set) var loading = false
    /// True once a refresh succeeded (empty states only show after that). A failed refresh leaves it false and sets `error`.
    public private(set) var loaded = false
    /// Why the last refresh failed (no network, expired session); the hub shows it with a Retry instead of an empty state.
    public private(set) var error: String?
    /// True while a photo or document is uploading or a save is in flight.
    public private(set) var busy = false
    public var pendingCount: Int { invites.count }
    /// The account the cached lists belong to.
    @ObservationIgnored private var ownerId: String?

    public func listing(_ id: String) -> ListingRow? { listings.first { $0.id == id } }
    public func vehicle(_ id: String) -> VehicleRow? { vehicles.first { $0.id == id } }
    public func roleIn(_ listingId: String) -> String? {
        if let r = roles[listingId] { return r }
        if let l = listing(listingId), l.ownerId == me?.id { return "OWNER" }
        return nil
    }
    public func isOwner(_ listingId: String) -> Bool { roleIn(listingId) == "OWNER" }
    public func canManage(_ listingId: String) -> Bool { let r = roleIn(listingId); return r == "OWNER" || r == "ADMIN" }
    public func ownsVehicle(_ vehicleId: String) -> Bool { vehicle(vehicleId)?.ownerId == me?.id }
    public func driverProfile() -> ListingRow? { listings.first { $0.kind == "DRIVER" && $0.ownerId == me?.id } }
    public func nameOf(_ id: String) -> String { session.names[id] ?? "…" }

    @discardableResult
    private func go(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
        }
    }

    private func namesFor(_ ids: [String]) async {
        let missing = Array(Set(ids.filter { session.names[$0] == nil }))
        if missing.isEmpty { return }
        if let rows = try? await Backend.shared.profiles(missing) { for r in rows { session.names[r.id] = r.name } }
    }

    /// Sign-out and account deletion: the next account on this phone starts with nothing of mine.
    public func signedOut() {
        listings = []; roles = [:]; vehicles = []; vehicleDocs = [:]
        items = [:]; members = [:]; vehicleMembers = [:]; recommendations = [:]; posts = [:]; reviews = [:]; counts = [:]; compliance = [:]
        invites = []; sentInvites = []; stats = []; token = nil
        loading = false; loaded = false; error = nil; busy = false; ownerId = nil
    }

    // MARK: loading

    /// Loads everything I run. Vehicles and their documents come from one read and land together, so the edit form never sees a vehicle without its documents.
    @discardableResult
    public func refresh() -> Task<Void, Never> {
        go { [self] in
            guard let p = me else { return }
            if ownerId != nil && ownerId != p.id { signedOut() }
            loading = true; defer { loading = false }
            do {
                let ls = try await ListingsAPI.myListings(me: p.id).sorted { $0.title.lowercased() < $1.title.lowercased() }
                let rs = try await Backend.shared.myRoles(me: p.id)
                let (vs, docs) = try await Backend.shared.myVehiclesWithDocs()
                if let n = try? await Backend.shared.minRecommendations(), n > 0 { needed = n; Self.NEEDED = n }
                if me?.id != p.id { return }   // signed out (or someone else signed in) while this was loading
                ownerId = p.id
                listings = ls; roles = rs
                vehicleDocs = docs; vehicles = vs.sorted { $0.model.lowercased() < $1.model.lowercased() }
                try await loadRecommendations(); try await loadInvites()
                error = nil; loaded = true
            } catch is CancellationError { throw CancellationError() } catch { self.error = friendlyError(error); throw error }
        }
    }
    private func loadRecommendations() async throws {
        let pending = listings.filter { $0.status == "PENDING" }.map(\.id)
        let found = try await Backend.shared.recommendationCounts(pending)
        for id in pending { recommendations[id] = found[id] ?? 0 }
    }
    private func loadInvites() async throws {
        guard let p = me else { return }
        let raw = try await ListingsAPI.myInvites()
        sentInvites = raw.filter { $0.inviterId == p.id }
        await namesFor(sentInvites.map(\.inviteeId))
        // my_invites() adds names the invitee could not read otherwise; without it (migration not applied yet) fall back to bare rows.
        if let full = try? await Backend.shared.invitesForMe() { invites = full; return }
        let mine = raw.filter { $0.inviteeId == p.id }
        await namesFor(mine.map(\.inviterId))
        invites = mine.map { i in InviteForMe.fallback(i, inviterName: nameOf(i.inviterId)) }
    }
    public func refreshInvites() { go { [self] in try await loadInvites() } }
    public func refreshStats() { go { [self] in stats = try await Backend.shared.vehicleStats().sorted { $0.plate < $1.plate } } }
    public func loadItems(_ listingId: String) { go { [self] in items[listingId] = try await ListingsAPI.items(listingId: listingId) } }
    public func loadMembers(_ listingId: String) {
        go { [self] in let rows = try await ListingsAPI.members(listingId: listingId); await namesFor(rows.map(\.profileId)); members[listingId] = rows }
    }
    public func loadVehicleMembers(_ vehicleId: String) {
        go { [self] in let rows = try await Backend.shared.vehicleMembers(vehicleId: vehicleId); await namesFor(rows.map(\.profileId)); vehicleMembers[vehicleId] = rows }
    }
    public func loadAllVehicleMembers() {
        go { [self] in
            for v in vehicles { vehicleMembers[v.id] = try await Backend.shared.vehicleMembers(vehicleId: v.id) }
            await namesFor(vehicleMembers.values.flatMap { $0 }.map(\.profileId))
        }
    }
    public func loadCompliance(_ listingId: String) { go { [self] in compliance[listingId] = try await Backend.shared.listingCompliance(listingId) } }

    // MARK: listings

    private func uploadListingPhoto(_ listingId: String, _ photo: Picked) async throws -> String {
        let url = try await Backend.shared.uploadListingMedia(listingId: listingId, photo: photo)
        return url
    }
    public func savedMessage(kind: String, title: String) -> String {
        switch kind {
        case "BUSINESS": "\(title) is saved. It goes live once \(needed) people nearby recommend it."
        case "SKILL": "\(title) is saved. It goes live once \(needed) people nearby recommend you."
        case "ASSET": "\(title) is saved. It goes live once \(needed) people nearby vouch for it and Bucks checks any documents it needs."
        default: "Your driver profile is saved. It goes live once \(needed) people nearby recommend you."
        }
    }
    /// Creates a listing at `at`, a real location fix (the form only offers Save once it has one; the map's default centre would place the shop
    /// in Jayanagar and nobody at the real shop could recommend it). The photo, if any, goes to listing-media/<listing id>/ afterwards; the listing
    /// exists by then, so a failed upload is reported, not retried through the form, or Save again would create a second listing.
    public func createListing(kind: String, title: String, category: String, description: String, area: String, at: LatLng, details: JSONValue, photo: Picked?, service: String? = nil, onDone: @escaping (ListingRow) -> Void) {
        go { [self] in
            guard let p = me else { return }
            busy = true; defer { busy = false }
            var row = try await ListingsAPI.createListing(me: p.id, kind: kind, title: title, category: category, description: description, area: area, at: at, details: details, service: service)
            var photoFailed = false
            if let photo {
                do { let url = try await uploadListingPhoto(row.id, photo); try await Backend.shared.setListingPhoto(id: row.id, url: url); row.photoUrl = url } catch { photoFailed = true }
            }
            session.toast(photoFailed ? "\(kind == "DRIVER" ? "Your driver profile" : title) is saved, but the photo didn't upload. Add it from Edit." : savedMessage(kind: kind, title: title))
            refresh(); onDone(row)
        }
    }
    /// `at` nil keeps the saved location.
    public func updateListing(id: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JSONValue, photo: Picked?, service: String? = nil, onDone: @escaping () -> Void) {
        go { [self] in
            busy = true; defer { busy = false }
            try await ListingsAPI.updateListing(id: id, title: title, category: category, description: description, area: area, at: at, details: details, service: service)
            if let photo { try await Backend.shared.setListingPhoto(id: id, url: try await uploadListingPhoto(id, photo)) }
            session.toast("Saved."); refresh(); onDone()
        }
    }
    /// delete_listing() keeps a hidden row behind past orders and refuses while an order is open; either way the listing leaves my hub.
    public func deleteListing(_ id: String, onDone: @escaping () -> Void) {
        go { [self] in
            let l = listing(id); try await Backend.shared.removeListing(id: id)
            listings.removeAll { $0.id == id }; session.toast("\(l?.title ?? "Listing") deleted."); onDone()
        }
    }
    public func setOnline(_ id: String, _ on: Bool) {
        go { [self] in
            guard let l = listing(id) else { return }
            patch(id) { $0.online = on }
            do { try await ListingsAPI.setOnline(id: id, online: on) } catch { patch(id) { $0.online = !on }; throw error }
            switch l.kind {
            case "BUSINESS": session.toast(on ? "\(l.title) is open. Orders will reach you." : "\(l.title) is closed. No orders until you open again.")
            case "SKILL": session.toast(on ? "\(l.title) is online. Requests will reach you." : "\(l.title) is offline.")
            case "ASSET": session.toast(on ? "\(l.title) is shown as available." : "\(l.title) is marked not available. It stays on your profile.")
            default: session.toast(on ? "You're shown as available." : "You're shown as unavailable.")
            }
        }
    }
    private func patch(_ id: String, _ change: (inout ListingRow) -> Void) {
        listings = listings.map { var l = $0; if l.id == id { change(&l) }; return l }
    }

    // MARK: products and services

    /// Saves a product or service with its photos: `keep` are photos it already had (in order), `add` new ones to upload.
    /// The first photo becomes photo_url, which search and older app versions show. Photos taken out are deleted afterwards.
    public func saveItem(_ item: ItemRow, keep: [MediaPhoto], add: [Picked], onDone: @escaping () -> Void) {
        go { [self] in
            busy = true; defer { busy = false }
            var uploaded: [MediaPhoto] = []
            for p in add { uploaded.append(MediaPhoto(url: try await Backend.shared.uploadListingMedia(listingId: item.listingId, photo: p))) }
            let photos = Array((keep + uploaded).prefix(8))
            var row = item; row.photos = photos; row.photoUrl = photos.first?.url
            // Photos taken out are deleted, unless a copy of this item (Duplicate) still shows them.
            let usedElsewhere = Set((items[item.listingId] ?? []).filter { $0.id != item.id }.flatMap { $0.photos.map(\.url) })
            let dropped = item.photos.map(\.url).filter { u in !photos.contains { $0.url == u } && !usedElsewhere.contains(u) }
            // Existing items go column by column (updateItem): a whole-row update drops default values, so "back in stock" or a cleared MRP would never reach the server.
            let saved = row.id == nil ? try await ListingsAPI.insertItem(row) : try await Backend.shared.updateItem(row)
            items[item.listingId] = sortedItems(((items[item.listingId] ?? []).filter { $0.id != saved.id }) + [saved])
            session.toast(item.id == nil ? "\(saved.name) added." : "Saved."); onDone()
            if !dropped.isEmpty { try? await Backend.shared.deleteListingMedia(urls: dropped) }
        }
    }
    private func sortedItems(_ rows: [ItemRow]) -> [ItemRow] {
        rows.sorted { $0.sort != $1.sort ? $0.sort < $1.sort : $0.name.lowercased() < $1.name.lowercased() }
    }
    /// A copy of `item` named "<name> (copy)", out of stock until the owner checks it, with the same photos.
    public func duplicateItem(_ item: ItemRow) {
        go { [self] in
            var copy = item; copy.id = nil; copy.name = String("\(item.name) (copy)".prefix(80)); copy.inStock = false; copy.sort = (items[item.listingId] ?? []).count
            let saved = try await ListingsAPI.insertItem(copy)
            items[item.listingId] = (items[item.listingId] ?? []) + [saved]; session.toast("Copied. Edit it and switch it on when it's ready.")
        }
    }
    public func setInStock(_ item: ItemRow, _ on: Bool) {
        go { [self] in
            guard let id = item.id else { return }
            @MainActor func set(_ v: Bool) { items[item.listingId] = (items[item.listingId] ?? []).map { var r = $0; if r.id == id { r.inStock = v }; return r } }
            set(on)
            var changed = item; changed.inStock = on
            do { _ = try await Backend.shared.updateItem(changed) } catch { set(!on); throw error }
        }
    }
    public func deleteItem(_ item: ItemRow, onDone: @escaping () -> Void) {
        go { [self] in
            guard let id = item.id else { return }
            try await ListingsAPI.deleteItem(id: id); items[item.listingId] = (items[item.listingId] ?? []).filter { $0.id != id }
            session.toast("\(item.name) removed."); onDone()
            // Photos shared with a copy of this item stay; only files no other item uses are deleted.
            let stillUsed = Set((items[item.listingId] ?? []).flatMap { $0.photos.map(\.url) })
            let gone = item.photos.map(\.url).filter { !stillUsed.contains($0) }
            if !gone.isEmpty { try? await Backend.shared.deleteListingMedia(urls: gone) }
        }
    }

    // MARK: gallery (photos, portfolio)

    private func galleryOf(_ listingId: String) -> [MediaPhoto] { listing(listingId)?.gallery ?? [] }
    private func saveGallery(_ listingId: String, _ g: [MediaPhoto]) async throws {
        try await Backend.shared.setGallery(listingId: listingId, photos: g); patch(listingId) { $0.gallery = g }
    }
    /// Uploads `photos` and adds them to the end of the gallery (20 at most). The first photo of an empty listing also becomes its cover.
    public func addGalleryPhotos(_ listingId: String, _ photos: [Picked]) {
        go { [self] in
            busy = true; defer { busy = false }
            let room = 20 - galleryOf(listingId).count
            if room <= 0 { session.toast("The gallery holds 20 photos. Remove one to add another."); return }
            var added: [MediaPhoto] = []
            for p in photos.prefix(room) { added.append(MediaPhoto(url: try await Backend.shared.uploadListingMedia(listingId: listingId, photo: p))) }
            try await saveGallery(listingId, galleryOf(listingId) + added)
            if (listing(listingId)?.photoUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty, let first = added.first { try await setCoverNow(listingId, first.url) }
            session.toast(photos.count > room ? "Added \(room). The gallery holds 20 photos." : added.count == 1 ? "Photo added." : "\(added.count) photos added.")
        }
    }
    public func removeGalleryPhoto(_ listingId: String, url: String) {
        go { [self] in
            try await saveGallery(listingId, galleryOf(listingId).filter { $0.url != url })
            if listing(listingId)?.photoUrl != url { try? await Backend.shared.deleteListingMedia(urls: [url]) }
            session.toast("Photo removed.")
        }
    }
    public func setCaption(_ listingId: String, url: String, caption: String) {
        go { [self] in
            let c = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            try await saveGallery(listingId, galleryOf(listingId).map { var p = $0; if p.url == url { p.caption = c }; return p }); session.toast("Caption saved.")
        }
    }
    /// Moves a photo one place towards the start (-1) or the end (+1).
    public func moveGalleryPhoto(_ listingId: String, url: String, by: Int) {
        go { [self] in
            var g = galleryOf(listingId)
            guard let i = g.firstIndex(where: { $0.url == url }) else { return }
            let j = i + by
            if !g.indices.contains(j) { return }
            g.insert(g.remove(at: i), at: j); try await saveGallery(listingId, g)
        }
    }
    private func setCoverNow(_ listingId: String, _ url: String) async throws {
        try await Backend.shared.setListingPhoto(id: listingId, url: url); patch(listingId) { $0.photoUrl = url }
    }
    public func setCover(_ listingId: String, url: String) { go { [self] in try await setCoverNow(listingId, url); session.toast("Cover photo changed.") } }

    // MARK: the listing's feed, reviews and numbers

    public func loadPosts(_ listingId: String) {
        go { [self] in let rows = try await ListingsAPI.listingPosts(listingId: listingId); await namesFor(rows.map(\.authorId)); posts[listingId] = rows }
    }
    /// Posts as the listing: shown on its profile and, to people nearby and those synced with it, in the feed.
    public func postAs(_ listingId: String, body: String, photo: Picked?, onDone: @escaping () -> Void) {
        go { [self] in
            guard let p = me, let l = listing(listingId) else { return }
            busy = true; defer { busy = false }
            var media: [(path: String, mime: String)] = []
            if let f = photo {
                let path = "\(p.id)/\(f.objectName())"
                try await Backend.shared.upload(bucket: "posts", path: path, data: f.data, contentType: f.mime); media = [(path, f.mime)]
            }
            let at = ((try? await Backend.shared.listingPoint(listingId)) ?? nil) ?? (session.hereKnown ? session.here : nil)
            try await Backend.shared.post(me: p.id, body: body.trimmingCharacters(in: .whitespacesAndNewlines), media: media, visibility: "LOCAL", at: at, area: l.area, listingId: listingId)
            session.toast("Posted as \(l.title)."); onDone(); posts[listingId] = try await ListingsAPI.listingPosts(listingId: listingId)
        }
    }
    public func deletePost(_ post: PostRow) {
        go { [self] in
            try await Backend.shared.deletePost(post.id)
            if let lid = post.listingId { posts[lid] = (posts[lid] ?? []).filter { $0.id != post.id } }
            session.toast("Post deleted.")
        }
    }
    public func loadReviews(_ listingId: String) {
        go { [self] in let rows = try await ListingsAPI.reviews(listingId: listingId); await namesFor(rows.map(\.authorId)); reviews[listingId] = rows }
    }
    public func loadCounts(_ listingId: String) {
        go { [self] in if let c = try await Backend.shared.listingCounts(listingId) { counts[listingId] = c; recommendations[listingId] = c.recommendations } }
    }

    // MARK: admins, store riders and drivers

    public func invite(listingId: String?, vehicleId: String?, bucksId: String, role: String) {
        go { [self] in
            _ = try await ListingsAPI.invite(listingId: listingId, vehicleId: vehicleId, bucksId: bucksId, role: role)
            session.toast("Invite sent to \(bucksId.trimmingCharacters(in: .whitespaces).uppercased()). They'll see it under Invites."); try await loadInvites()
        }
    }
    public func revokeInvite(_ id: String) {
        go { [self] in try await Backend.shared.revokeInvite(id: id); sentInvites.removeAll { $0.id == id }; session.toast("Invite cancelled.") }
    }
    public func respondInvite(_ inv: InviteForMe, accept: Bool) {
        go { [self] in
            try await Backend.shared.respondInvite(id: inv.id, accept: accept); invites.removeAll { $0.id == inv.id }
            session.toast(accept ? "Done. \(inv.title) is now under My listings." : "Declined."); if accept { refresh() }
        }
    }
    public func removeMember(_ listingId: String, profileId: String) {
        go { [self] in
            try await ListingsAPI.removeMember(listingId: listingId, profileId: profileId); members[listingId] = (members[listingId] ?? []).filter { $0.profileId != profileId }
            if profileId == me?.id { session.toast("You left."); refresh() } else { session.toast("Removed.") }
        }
    }
    public func removeVehicleMember(_ vehicleId: String, profileId: String) {
        go { [self] in
            try await Backend.shared.removeVehicleMember(vehicleId: vehicleId, profileId: profileId); vehicleMembers[vehicleId] = (vehicleMembers[vehicleId] ?? []).filter { $0.profileId != profileId }
            if profileId == me?.id { session.toast("You left."); refresh() } else { session.toast("Removed.") }
        }
    }

    // MARK: community cap: recommendations

    /// A fresh token (valid 2 minutes) and the current count; the QR screen calls this every 90 seconds.
    public func refreshToken(_ listingId: String) {
        go { [self] in
            token = try await ListingsAPI.recommendToken(listingId: listingId)
            recommendations[listingId] = try await Backend.shared.recommendationCounts([listingId])[listingId] ?? 0
            if (recommendations[listingId] ?? 0) >= needed && listing(listingId)?.status == "PENDING" { refresh() }
        }
    }
    public func clearToken() { token = nil }
    /// Scanned someone's code in person at `at`, a real location fix: the server checks distance, account age and position, and returns the new count.
    /// The scanner only opens with a fix; the map's default centre must never be sent, or a photo of the code would count as "in person".
    public func recommend(token: String, at: LatLng, onDone: @escaping (Int) -> Void) {
        go { [self] in
            let n = try await ListingsAPI.recommend(token: token, at: at)
            session.toast(n >= needed ? "Thanks, that's \(n) of \(needed). They're live on Bucks now." : "Thanks, that's \(n) of \(needed)."); onDone(n)
        }
    }
}

extension InviteForMe {
    /// An invite built from a bare `invites` row, for servers that don't have my_invites() yet.
    static func fallback(_ i: InviteRow, inviterName: String) -> InviteForMe {
        InviteForMe(id: i.id, listingId: i.listingId, vehicleId: i.vehicleId, inviterId: i.inviterId, inviterName: inviterName, role: i.role,
                    title: i.listingId != nil ? "A listing" : "A vehicle", kind: i.listingId != nil ? "LISTING" : "VEHICLE", createdAt: "")
    }
    init(id: String, listingId: String?, vehicleId: String?, inviterId: String, inviterName: String, role: String, title: String, kind: String, createdAt: String) {
        self.id = id; self.listingId = listingId; self.vehicleId = vehicleId; self.inviterId = inviterId; self.inviterName = inviterName
        self.role = role; self.title = title; self.kind = kind; self.createdAt = createdAt
    }
}
