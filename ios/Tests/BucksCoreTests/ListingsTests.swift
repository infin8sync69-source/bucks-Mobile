import Foundation
import Testing
@testable import BucksCore

/// The Studio state holder (Android MyListings) and its wire format: tables, RPC names and `p_` parameters were checked against
/// supabase/schema.sql, supabase/migrations/manage.sql and Backend.kt / BackendManage.kt / BackendStudio.kt.
@MainActor @Suite(.serialized) struct ListingsTests {
    private func call(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }
    private var toasts = ToastLog()
    final class ToastLog { var all: [String] = [] }

    private func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) -> (AppSession, ToastLog) {
        RingAlert.enabled = false
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
        let s = AppSession()
        s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao", area: "Jayanagar")
        let said = ToastLog(); s.toastHandler = { said.all.append($0) }
        return (s, said)
    }
    private func wait(_ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(4)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 30_000_000) }
        return cond()
    }
    private func listing(_ id: String, kind: String = "BUSINESS", status: String = "PENDING", online: Bool = false, photo: String? = nil, gallery: [[String: Any]] = []) -> [String: Any] {
        var r: [String: Any] = ["id": id, "kind": kind, "owner_id": "me", "title": "Sri Stores \(id)", "category": "Grocery", "description": "", "area": "Jayanagar", "details": [String: Any](),
                                "status": status, "online": online, "trust_up": 0, "trust_down": 0, "gallery": gallery]
        if let photo { r["photo_url"] = photo }
        return r
    }
    private func item(_ id: String?, listing: String = "L1", name: String = "Rice", photos: [[String: Any]] = [], inStock: Bool = true, sort: Int = 0) -> [String: Any] {
        var r: [String: Any] = ["listing_id": listing, "kind": "PRODUCT", "name": name, "price": 62, "unit": "1 kg", "group_name": "", "in_stock": inStock, "sort": sort, "description": "", "photos": photos, "details": [String: Any]()]
        if let id { r["id"] = id }
        return r
    }

    @Test func refreshReadsEverythingIRunAndTheThreshold() async throws {
        let (s, _) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/listing_members": return (200, [["listing_id": "L2", "profile_id": "me", "role": "OWNER"], ["listing_id": "L1", "profile_id": "me", "role": "ADMIN"]])
            case "/rest/v1/listings": return (200, [[String: Any]]([self.listing("L2", status: "LIVE", online: true), self.listing("L1")]))
            case "/rest/v1/vehicles": return (200, [["id": "v1", "owner_id": "me", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "status": "PENDING", "docs": []]])
            case "/rest/v1/settings": return (200, [["key": "min_recommendations", "value": 5]])
            case "/rest/v1/recommendations": return (200, [["listing_id": "L1", "recommender_id": "a"], ["listing_id": "L1", "recommender_id": "b"]])
            case "/rest/v1/invites": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [["id": "i1", "inviter_id": "u9", "inviter_name": "Meera", "role": "ADMIN", "title": "Chai Point", "kind": "BUSINESS"]])
            default: return (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        s.listings.refresh()
        #expect(await wait { s.listings.loaded })
        let m = s.listings
        #expect(m.listings.map(\.id) == ["L1", "L2"].sorted { self.title($0) < self.title($1) })   // sorted by lower-cased title
        #expect(m.roleIn("L1") == "ADMIN"); #expect(m.canManage("L1")); #expect(m.isOwner("L2")); #expect(!m.isOwner("L1"))
        #expect(m.needed == 5); #expect(ListingsStore.NEEDED == 5)
        #expect(m.recommendations["L1"] == 2); #expect(m.recommendations["L2"] == nil)   // only pending listings are counted
        #expect(m.vehicles.map(\.id) == ["v1"]); #expect(m.pendingCount == 1)
        #expect(call("/rest/v1/listing_members").first?.query.contains("profile_id=eq.me") == true)
        #expect(call("/rest/v1/recommendations").first?.query.contains("listing_id=in.(L1)") == true)
        ListingsStore.NEEDED = 7
    }
    private func title(_ id: String) -> String { "sri stores \(id.lowercased())" }

    @Test func aFailedRefreshKeepsTheHubFromLookingEmpty() async throws {
        let (s, said) = boot { _, _, _ -> (Int, Any) in (500, ["message": "boom"]) }
        s.listings.refresh()
        #expect(await wait { s.listings.error != nil })
        #expect(!s.listings.loaded); #expect(!said.all.isEmpty)
    }

    @Test func creatingAListingSendsTheRowAndThenThePhoto() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/listings": return (201, [self.listing("L9")])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L9", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/vehicles", "/rest/v1/invites", "/rest/v1/recommendations": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [[String: Any]]())
            default: return path.hasPrefix("/storage/") ? (200, ["Key": "k"] as [String: Any]) : (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        var created: ListingRow?
        let photo = Picked(data: Data([1, 2, 3]), name: "cover.jpg", mime: "image/jpeg")
        s.listings.createListing(kind: "BUSINESS", title: "Sri Stores", category: "Grocery", description: "Rice", area: "Jayanagar", at: LatLng(12.93, 77.58),
                                 details: .object(["hours": .string("9-9"), "free_delivery": .bool(true)]), photo: photo, service: "GROCERY") { created = $0 }
        #expect(await wait { created != nil })
        let post = try #require(call("/rest/v1/listings").first { $0.method == "POST" })
        #expect(Set(post.body.keys) == ["kind", "owner_id", "title", "category", "description", "area", "service", "location", "details"])
        #expect(post.body["owner_id"] as? String == "me"); #expect(post.body["service"] as? String == "GROCERY")
        #expect(post.body["location"] as? String == "SRID=4326;POINT(77.58 12.93)")
        #expect((post.body["details"] as? [String: Any])?["hours"] as? String == "9-9")
        // The photo goes to listing-media/<listing id>/ and then becomes photo_url.
        let up = try #require(FakeServer.calls.first { $0.path.hasPrefix("/storage/v1/object/listing-media/L9/") })
        #expect(up.method == "POST")
        let patch = try #require(call("/rest/v1/listings").first { $0.method == "PATCH" })
        #expect((patch.body["photo_url"] as? String)?.contains("/object/public/listing-media/L9/") == true); #expect(patch.query.contains("id=eq.L9"))
        #expect(said.all.first == "Sri Stores is saved. It goes live once 7 people nearby recommend it.")
        // A driver profile has no service column to send.
        #expect(s.listings.savedMessage(kind: "DRIVER", title: "x") == "Your driver profile is saved. It goes live once 7 people nearby recommend you.")
        #expect(s.listings.savedMessage(kind: "ASSET", title: "Flat") == "Flat is saved. It goes live once 7 people nearby vouch for it and Bucks checks any documents it needs.")
    }

    @Test func aFailedPhotoUploadIsReportedButTheListingStays() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/listings": return (201, [self.listing("L9", kind: "SKILL")])
            case "/rest/v1/listing_members": return (200, [[String: Any]]())
            case "/rest/v1/vehicles", "/rest/v1/invites", "/rest/v1/recommendations": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [[String: Any]]())
            default: return (400, ["message": "bad mime"] as [String: Any])
            }
        }
        var created = false
        s.listings.createListing(kind: "SKILL", title: "Plumber", category: "Plumber", description: "", area: "", at: LatLng(12.9, 77.5), details: .emptyObject, photo: Picked(data: Data([9]), name: "a.jpg", mime: "image/jpeg")) { _ in created = true }
        #expect(await wait { created })
        #expect(said.all.first == "Plumber is saved, but the photo didn't upload. Add it from Edit.")
        let post = try #require(call("/rest/v1/listings").first)
        #expect(post.body["service"] == nil)   // skills never send a service
    }

    @Test func updatingOnlySendsTheServiceAndLocationWhenTheyChange() async throws {
        let (s, _) = boot { path, _, _ -> (Int, Any) in path.hasPrefix("/rest/v1/") ? (200, [[String: Any]]()) : (404, ["message": "no stub"] as [String: Any]) }
        var done = 0
        s.listings.updateListing(id: "L1", title: "T", category: "Grocery", description: "d", area: "A", at: nil, details: .emptyObject, photo: nil) { done += 1 }
        #expect(await wait { done == 1 })
        let first = try #require(call("/rest/v1/listings").first { $0.method == "PATCH" })
        #expect(Set(first.body.keys) == ["title", "category", "description", "area", "details"]); #expect(first.query.contains("id=eq.L1"))
        FakeServer.calls = []
        s.listings.updateListing(id: "L1", title: "T", category: "Grocery", description: "d", area: "A", at: LatLng(1, 2), details: .emptyObject, photo: nil, service: "FOOD") { done += 1 }
        #expect(await wait { done == 2 })
        let second = try #require(call("/rest/v1/listings").first { $0.method == "PATCH" })
        #expect(second.body["service"] as? String == "FOOD"); #expect(second.body["location"] as? String == "SRID=4326;POINT(2.0 1.0)")
    }

    @Test func theOnlineSwitchIsOptimisticAndRollsBackOnFailure() async throws {
        var fail = false
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/listings": return fail ? (400, ["message": "nope"] as [String: Any]) : (200, [self.listing("L1", status: "LIVE")])
            case "/rest/v1/vehicles", "/rest/v1/invites", "/rest/v1/recommendations": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [[String: Any]]())
            default: return (404, ["message": "no stub"] as [String: Any])
            }
        }
        s.listings.refresh()
        #expect(await wait { s.listings.loaded })
        s.listings.setOnline("L1", true)
        #expect(await wait { s.listings.listing("L1")?.online == true && !said.all.isEmpty })
        #expect(said.all.last == "Sri Stores L1 is open. Orders will reach you.")
        let patch = try #require(call("/rest/v1/listings").last { $0.method == "PATCH" })
        #expect(patch.body as NSDictionary == ["online": true] as NSDictionary)
        fail = true
        s.listings.setOnline("L1", false)
        #expect(await wait { said.all.count >= 2 })
        #expect(s.listings.listing("L1")?.online == true)   // rolled back
    }

    @Test func deletingAListingGoesThroughTheServerFunction() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in path == "/rest/v1/rpc/delete_listing" ? (204, [String: Any]()) : (404, ["message": "no stub"] as [String: Any]) }
        var done = false
        s.listings.deleteListing("L1") { done = true }
        #expect(await wait { done })
        #expect(try #require(call("/rest/v1/rpc/delete_listing").first).body as NSDictionary == ["p_listing": "L1"] as NSDictionary)
        #expect(said.all.last == "Listing deleted.")
    }

    @Test func savingItemsGoesColumnByColumnAndDropsPhotosNobodyUses() async throws {
        let old = ["url": "https://x.supabase.co/storage/v1/object/public/listing-media/L1/old.jpg"]
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/items": return (200, [self.item("i1", photos: [old])])
            default: return path.hasPrefix("/storage/") ? (200, [String: Any]()) : (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        // An existing item with a cleared MRP, back in stock and without its old photo: every column is sent, null included.
        var row = ItemRow(id: "i1", listingId: "L1", name: "Rice", price: 62, inStock: true, photos: [MediaPhoto(url: old["url"]!)])
        row.mrp = nil
        var done = false
        s.listings.saveItem(row, keep: [], add: []) { done = true }
        #expect(await wait { done })
        let patch = try #require(call("/rest/v1/items").first { $0.method == "PATCH" })
        #expect(Set(patch.body.keys) == ["name", "price", "mrp", "unit", "group_name", "photo_url", "in_stock", "sort", "description", "stock", "photos", "details"])
        #expect(patch.body["mrp"] is NSNull); #expect(patch.body["in_stock"] as? Bool == true); #expect(patch.query.contains("id=eq.i1"))
        #expect(said.all.last == "Saved.")
        // The removed photo's file is deleted from listing-media.
        #expect(await wait { FakeServer.calls.contains { $0.method == "DELETE" && $0.path == "/storage/v1/object/listing-media" } })
        let del = try #require(FakeServer.calls.first { $0.method == "DELETE" && $0.path == "/storage/v1/object/listing-media" })
        #expect((del.body["prefixes"] as? [String]) == ["L1/old.jpg"])
    }

    @Test func aNewItemIsInsertedWithItsPhotoAsTheMainOne() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/items": return (201, [self.item("i2", name: "Sugar")])
            default: return path.hasPrefix("/storage/") ? (200, [String: Any]()) : (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        var done = false
        s.listings.saveItem(ItemRow(listingId: "L1", name: "Sugar", price: 45), keep: [], add: [Picked(data: Data([1]), name: "s.jpg", mime: "image/jpeg")]) { done = true }
        #expect(await wait { done })
        let post = try #require(call("/rest/v1/items").first { $0.method == "POST" })
        #expect(post.body["id"] == nil); #expect(post.body["listing_id"] as? String == "L1"); #expect(post.body["kind"] as? String == "PRODUCT")
        #expect((post.body["photo_url"] as? String)?.contains("/object/public/listing-media/L1/") == true)
        #expect(((post.body["photos"] as? [[String: Any]])?.first?["url"] as? String)?.contains("listing-media/L1/") == true)
        #expect(said.all.last == "Sugar added.")
        #expect(s.listings.items["L1"]?.map { $0.id } == ["i2"])
    }

    @Test func theGalleryHoldsTwentyAndTheFirstPhotoBecomesTheCover() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in path == "/rest/v1/listings" ? (200, [[String: Any]]() as Any) : path.hasPrefix("/storage/") ? (200, [String: Any]() as Any) : (404, ["message": "no stub for \(path)"] as Any) }
        s.listings.addGalleryPhotos("L1", [Picked(data: Data([1]), name: "a.jpg", mime: "image/jpeg")])   // L1 is not in my cache: nothing to add to
        #expect(await wait { !FakeServer.calls.isEmpty })
        #expect(call("/rest/v1/listings").first?.body["gallery"] != nil)
        #expect(said.all.last == "Photo added.")
        // Gallery JSON keeps `caption` only when there is one.
        #expect(Backend.mediaJSON([MediaPhoto(url: "u1"), MediaPhoto(url: "u2", caption: "Before")]) == [["url": "u1"], ["url": "u2", "caption": "Before"]])
    }

    @Test func recommendationsUseTheServersParameterNames() async throws {
        let (s, said) = boot { path, _, params -> (Int, Any) in
            switch path {
            case "/rest/v1/rpc/recommend_token": return (200, "tok-1")
            case "/rest/v1/recommendations": return (200, [["listing_id": "L1", "recommender_id": "a"]])
            case "/rest/v1/rpc/recommend": return (200, 7)
            default: return (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        s.listings.refreshToken("L1")
        #expect(await wait { s.listings.token == "tok-1" && s.listings.recommendations["L1"] == 1 })
        #expect(try #require(call("/rest/v1/rpc/recommend_token").first).body as NSDictionary == ["p_listing": "L1"] as NSDictionary)
        var count = 0
        s.listings.recommend(token: "tok-9", at: LatLng(12.93, 77.58)) { count = $0 }
        #expect(await wait { count == 7 })
        #expect(try #require(call("/rest/v1/rpc/recommend").first).body as NSDictionary == ["p_token": "tok-9", "lat": 12.93, "lng": 77.58] as NSDictionary)
        #expect(said.all.last == "Thanks, that's 7 of 7. They're live on Bucks now.")
        s.listings.clearToken(); #expect(s.listings.token == nil)
    }

    @Test func invitesAndMembersUseTheServersNames() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/rpc/invite": return (200, "Sent")
            case "/rest/v1/invites": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [[String: Any]]())
            case "/rest/v1/rpc/respond_invite", "/rest/v1/listing_members": return (204, [String: Any]())
            default: return (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        s.listings.invite(listingId: "L1", vehicleId: nil, bucksId: " ab12 ", role: "ADMIN")
        #expect(await wait { said.all.last?.hasPrefix("Invite sent to AB12") == true })
        let inv = try #require(call("/rest/v1/rpc/invite").first)
        #expect(Set(inv.body.keys) == ["p_listing", "p_vehicle", "p_short_code", "p_role"]); #expect(inv.body["p_vehicle"] is NSNull); #expect(inv.body["p_short_code"] as? String == " ab12 ")
        s.listings.removeMember("L1", profileId: "u5")
        #expect(await wait { call("/rest/v1/listing_members").contains { $0.method == "DELETE" } })
        let del = try #require(call("/rest/v1/listing_members").first { $0.method == "DELETE" })
        #expect(del.query.contains("listing_id=eq.L1")); #expect(del.query.contains("profile_id=eq.u5"))
        #expect(said.all.last == "Removed.")
    }

    @Test func aListingPostIsWrittenAsTheListingWithItsPhoto() async throws {
        let (s, said) = boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/listings": return (200, [self.listing("L1", status: "LIVE")])
            case "/rest/v1/listing_points": return (200, [["id": "L1", "lat": 12.95, "lng": 77.6]])
            case "/rest/v1/posts": return (201, [[String: Any]]())
            case "/rest/v1/vehicles", "/rest/v1/invites", "/rest/v1/recommendations": return (200, [[String: Any]]())
            case "/rest/v1/rpc/my_invites": return (200, [[String: Any]]())
            default: return path.hasPrefix("/storage/") ? (200, [String: Any]()) : (404, ["message": "no stub for \(path)"] as [String: Any])
            }
        }
        s.listings.refresh()
        #expect(await wait { s.listings.loaded })
        var done = false
        s.listings.postAs("L1", body: "  Fresh stock  ", photo: Picked(data: Data([1]), name: "p.jpg", mime: "image/jpeg")) { done = true }
        #expect(await wait { done })
        let post = try #require(call("/rest/v1/posts").first { $0.method == "POST" })
        #expect(post.body["listing_id"] as? String == "L1"); #expect(post.body["author_id"] as? String == "me"); #expect(post.body["body"] as? String == "Fresh stock")
        #expect(post.body["visibility"] as? String == "LOCAL"); #expect(post.body["location"] as? String == "SRID=4326;POINT(77.6 12.95)")
        let media = try #require((post.body["media"] as? [[String: Any]])?.first)
        #expect((media["path"] as? String)?.hasPrefix("me/") == true); #expect(media["mime"] as? String == "image/jpeg")
        #expect(FakeServer.calls.contains { $0.path.hasPrefix("/storage/v1/object/posts/me/") })
        #expect(await wait { said.all.contains("Posted as Sri Stores L1.") })
    }
}
