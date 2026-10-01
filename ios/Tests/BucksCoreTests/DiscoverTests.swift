import Foundation
import Testing
@testable import BucksCore

/// Search, the listing profile, sync with a listing, the service tiles and listing documents: what each call puts on the wire (RPC names,
/// `p_` parameters, filters) and how the stores react to answers and failures. Written against supabase/schema.sql, migrations/discover.sql,
/// migrations/services.sql and the Kotlin in Discover.kt, Services.kt, BackendDiscover.kt and BackendServices.kt.
@MainActor @Suite(.serialized) struct DiscoverTests {
    func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) {
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
    }
    func wait(timeout: Double = 4, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 50_000_000) }
        return cond()
    }
    private func call(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }
    private func session() -> (AppSession, Toasts) {
        let s = AppSession(); let t = Toasts(); s.toastHandler = { t.lines.append($0) }
        s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        return (s, t)
    }
    final class Toasts { var lines: [String] = [] }

    private func hit(_ id: String, kind: String = "BUSINESS") -> [String: Any] {
        ["id": id, "kind": kind, "title": "Fresh Mart", "category": "Grocery", "description": "", "area": "Jayanagar", "online": true, "trust_up": 4, "trust_down": 1, "details": [String: Any](), "distance_m": 650.0, "min_price": 5]
    }
    private func listingJSON(_ id: String = "L1", kind: String = "BUSINESS") -> [String: Any] {
        ["id": id, "kind": kind, "owner_id": "o1", "title": "Fresh Mart", "category": "Grocery", "area": "Jayanagar", "status": "LIVE", "online": true, "details": ["hours": "9 to 9"]]
    }

    // MARK: search

    @Test func searchSendsOnlyTheFiltersThatAreSet() async throws {
        let (s, _) = session()
        boot { path, _, _ in
            if path == "/rest/v1/rpc/search_listings" { return (200, [self.hit("L1")]) }
            return (404, ["message": "no stub"])
        }
        let d = s.discover
        d.query = "  sugar "; d.search()
        #expect(await wait { d.searched })
        let first = try #require(call("/rest/v1/rpc/search_listings").first)
        #expect(Set(first.body.keys) == ["q", "lat", "lng", "radius_m"])
        #expect(first.body["q"] as? String == "sugar"); #expect(first.body["radius_m"] as? Int == 10_000)
        #expect(d.results.map(\.id) == ["L1"])

        // A service tile limits the search to that service and uses its own radius; the kind chip clears.
        d.useService("FOOD", radiusM: 4_000)
        #expect(d.radiusKm == 10); #expect(d.query == ""); #expect(d.kind == .all)
        d.selectKind(.shops)
        #expect(await wait { call("/rest/v1/rpc/search_listings").count == 2 })
        let shops = call("/rest/v1/rpc/search_listings").last
        #expect(shops?.body["kinds"] as? [String] == ["BUSINESS"]); #expect(shops?.body["services"] as? [String] == ["FOOD"])
    }

    @Test func radiusChipsWidenOneStepAtATime() {
        let (s, _) = session()
        boot { _, _, _ in (200, []) }
        let d = s.discover
        #expect(d.widerRadius == 25)
        d.setRadius(3); #expect(d.widerRadius == 10)
        d.setRadius(25); #expect(d.widerRadius == nil)
        d.useService("PROPERTIES", radiusM: 20_000); #expect(d.radiusKm == 25)
        d.useService("PROPERTIES", radiusM: 99_000); #expect(d.radiusKm == 25)   // wider than every chip: the widest
    }

    @Test func aPendingQueryIsHandedOverOnce() {
        let (s, _) = session()
        s.discover.pendingQuery = "  tap repair "
        #expect(s.discover.takePendingQuery() == "tap repair"); #expect(s.discover.takePendingQuery() == nil)
    }

    // MARK: the profile

    @Test func openLoadsTheWholeProfileAndDegradesPartByPart() async throws {
        let (s, _) = session()
        boot { path, query, _ in
            switch path {
            case "/rest/v1/listings": return (200, [self.listingJSON()])
            case "/rest/v1/items": return (200, [["id": "i1", "listing_id": "L1", "kind": "PRODUCT", "name": "Sugar", "price": 48, "sort": 1]])
            case "/rest/v1/reviews": return (500, ["message": "boom"])                        // a failing part is empty, not fatal
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "me", "role": "OWNER"]])
            case "/rest/v1/rpc/listing_counts": return (200, [["recommendations": 9, "syncs": 3, "members": 1, "open_jobs": 2]])
            case "/rest/v1/listing_points": return (200, [["id": "L1", "lat": 12.93, "lng": 77.58]])
            case "/rest/v1/rpc/search_listings": return (200, [self.hit("L1"), self.hit("L2"), self.hit("L3")])
            case "/rest/v1/listing_syncs": return (200, [["profile_id": "me", "listing_id": "L1"]])
            case "/rest/v1/profiles": return (200, [["id": "o1", "name": "Meena"]])
            default: return (404, ["message": "no stub \(path) \(query)"])
            }
        }
        let d = s.discover
        d.open("L1")
        #expect(await wait { d.profiles["L1"] != nil })
        let p = try #require(d.profiles["L1"])
        #expect(p.mine); #expect(p.myRole == "OWNER"); #expect(p.synced)
        #expect(p.recommendations == 9); #expect(p.syncs == 3); #expect(p.openJobs == 2)
        #expect(p.products.map(\.name) == ["Sugar"]); #expect(p.reviews.isEmpty)
        // "More grocery nearby" never lists the shop itself.
        #expect(p.similar.map(\.id) == ["L2", "L3"])
        #expect(try #require(call("/rest/v1/rpc/listing_counts").first).body["p_listing"] as? String == "L1")
        #expect(call("/rest/v1/items").first?.query.contains("listing_id=eq.L1") == true)
        #expect(call("/rest/v1/rpc/search_listings").contains { $0.body["radius_m"] as? Int == 5_000 && $0.body["kinds"] as? [String] == ["BUSINESS"] })
        #expect(d.loading.isEmpty)
    }

    @Test func openFallsBackToPlainTablesWhenTheCountsFunctionIsMissing() async throws {
        let (s, _) = session()
        boot { path, _, _ in
            switch path {
            case "/rest/v1/listings": return (200, [self.listingJSON()])
            case "/rest/v1/rpc/listing_counts": return (404, ["message": "function not found"])
            case "/rest/v1/recommendations": return (200, [["recommender_id": "a"], ["recommender_id": "b"]])
            case "/rest/v1/listing_syncs": return (200, [["profile_id": "x", "listing_id": "L1"]])
            case "/rest/v1/jobs": return (200, [["id": "j1", "listing_id": "L1", "title": "Cashier", "open": true], ["id": "j2", "listing_id": "L1", "title": "Packer", "open": false]])
            case "/rest/v1/listing_members": return (200, [["listing_id": "L1", "profile_id": "o1", "role": "OWNER"], ["listing_id": "L1", "profile_id": "o2", "role": "ADMIN"]])
            default: return (200, [])
            }
        }
        s.discover.open("L1")
        #expect(await wait { s.discover.profiles["L1"] != nil })
        let p = try #require(s.discover.profiles["L1"])
        #expect(p.recommendations == 2); #expect(p.syncs == 1); #expect(p.members == 2); #expect(p.openJobs == 1); #expect(!p.mine)
    }

    @Test func aMissingListingAndAFailedLoadAreToldApart() async {
        let (s, t) = session()
        boot { _, _, _ in (200, [Any]()) }
        s.discover.open("gone")
        #expect(await wait { s.discover.missing.contains("gone") })
        #expect(s.discover.profiles["gone"] == nil); #expect(!s.discover.failed.contains("gone"))

        boot { path, _, _ in
            if path == "/rest/v1/listings" { return (503, ["message": "down"]) }
            return (200, [Any]())
        }
        s.discover.open("L9")
        #expect(await wait { s.discover.failed.contains("L9") })
        #expect(!s.discover.loading.contains("L9")); #expect(t.lines.last == "Couldn't reach Bucks. Check your connection and try again.")
    }

    // MARK: sync with a listing

    @Test func syncAndUnsyncUseTheListingSyncsTable() async throws {
        let (s, t) = session()
        boot { path, _, _ in
            switch path {
            case "/rest/v1/listings": return (200, [self.listingJSON()])
            default: return (200, [])
            }
        }
        let d = s.discover
        d.open("L1"); #expect(await wait { d.profiles["L1"] != nil })
        d.syncListing("L1", on: true)
        #expect(await wait { d.isSynced("L1") })
        let ins = try #require(call("/rest/v1/listing_syncs").first(where: { $0.method == "POST" }))
        #expect(Set(ins.body.keys) == ["profile_id", "listing_id"]); #expect(ins.body["profile_id"] as? String == "me"); #expect(ins.body["listing_id"] as? String == "L1")
        #expect(d.profiles["L1"]?.synced == true); #expect(t.lines.last == "Synced with Fresh Mart. Their posts now show in your feed.")
        // Syncing again does nothing.
        d.syncListing("L1", on: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(call("/rest/v1/listing_syncs").filter { $0.method == "POST" }.count == 1)

        d.syncListing("L1", on: false)
        #expect(await wait { !d.isSynced("L1") })
        let del = try #require(call("/rest/v1/listing_syncs").first(where: { $0.method == "DELETE" }))
        #expect(del.query.contains("profile_id=eq.me")); #expect(del.query.contains("listing_id=eq.L1"))
        #expect(t.lines.last == "Unsynced from Fresh Mart.")
    }

    @Test func signingOutClearsEverythingPersonal() async {
        let (s, _) = session()
        boot { path, _, _ in
            if path == "/rest/v1/listings" { return (200, [self.listingJSON()]) }
            return (200, [Any]())
        }
        let d = s.discover
        d.open("L1"); #expect(await wait { d.profiles["L1"] != nil })
        d.query = "x"; d.pendingQuery = "y"
        d.signedOut()
        #expect(d.profiles.isEmpty); #expect(d.query == ""); #expect(d.pendingQuery == ""); #expect(d.mySyncs.isEmpty); #expect(!d.searched)
    }

    // MARK: messaging a listing

    @Test func messagingAListingOpensTheChatAndSendsTheFirstLine() async throws {
        let (s, _) = session()
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/start_listing_chat": return (200, "c-77")
            case "/rest/v1/messages": return (201, [:])
            default: return (200, [])
            }
        }
        var opened: String?
        s.discover.startListingChat("L1", firstLine: "  Hi, are you free?  ") { opened = $0 }
        #expect(await wait { opened != nil })
        #expect(opened == "c-77")
        #expect(call("/rest/v1/rpc/start_listing_chat").first?.body as NSDictionary? == ["p_listing": "L1"] as NSDictionary)
        let msg = try #require(call("/rest/v1/messages").first)
        #expect(msg.body["conversation_id"] as? String == "c-77"); #expect(msg.body["sender_id"] as? String == "me"); #expect(msg.body["body"] as? String == "Hi, are you free?")
        // The buttons come back on once the chat is open.
        #expect(await wait { !s.discover.chatStarting })
    }

    @Test func aFailedChatStartShowsTheServersSentenceAndReenablesTheButtons() async {
        let (s, t) = session()
        boot { _, _, _ in (400, ["message": "you can't message this listing"]) }
        var opened = false
        s.discover.startListingChat("L1") { _ in opened = true }
        #expect(await wait { !t.lines.isEmpty })
        #expect(t.lines.last == "You can't message this listing"); #expect(!opened); #expect(!s.discover.chatStarting)
    }

    // MARK: services

    @Test func serviceStatesAreReadAroundMeAndInterestToggles() async throws {
        let (s, t) = session()
        var mine = false
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/services_near":
                return (200, [["key": "FOOD", "label": "Food", "mode": "AUTO", "state": "LOCKED", "supply": 3, "min_supply": 10, "online": 0, "min_online": 2, "supply_noun": "restaurants", "radius_m": 3000, "delivery": true, "delivery_now": false, "interested": 4, "mine": mine],
                              ["key": "TAXI", "label": "Taxi", "state": "QUIET"]])
            case "/rest/v1/rpc/toggle_service_interest": mine.toggle(); return (200, mine)
            default: return (404, ["message": "no stub"])
            }
        }
        let sv = s.services
        sv.refresh()
        #expect(await wait { sv.loaded })
        let near = try #require(call("/rest/v1/rpc/services_near").first)
        #expect(Set(near.body.keys) == ["lat", "lng"])
        #expect(sv.state("FOOD")?.usable == false); #expect(sv.state("TAXI")?.usable == true); #expect(sv.openCount == 1)
        #expect(sv.state("FOOD")?.radiusKm == "3 km")

        sv.toggleInterest("FOOD")
        #expect(await wait { sv.state("FOOD")?.mine == true })
        let tog = try #require(call("/rest/v1/rpc/toggle_service_interest").first)
        #expect(Set(tog.body.keys) == ["p_service", "lat", "lng"]); #expect(tog.body["p_service"] as? String == "FOOD")
        #expect(sv.state("FOOD")?.interested == 5); #expect(t.lines.last == "We'll let you know when Food opens near you.")
        sv.toggleInterest("FOOD")
        #expect(await wait { sv.state("FOOD")?.mine == false })
        #expect(sv.state("FOOD")?.interested == 4); #expect(t.lines.last == "You won't get a note about Food.")
    }

    @Test func aFailedServicesReadLocksEveryTile() async {
        let (s, _) = session()
        boot { _, _, _ in (503, ["message": "down"]) }
        s.services.refresh()
        #expect(await wait { s.services.error != nil })
        #expect(s.services.rows.count == serviceCatalog.count); #expect(s.services.rows.allSatisfy { $0.state == "LOCKED" })
    }

    @Test func aDocumentIsUploadedThenSubmittedAndRolledBackWhenRefused() async throws {
        let (s, t) = session()
        var refuse = false
        boot { path, _, _ in
            switch path {
            case let p where p.hasPrefix("/storage/v1/object/docs/"): return (200, ["Key": "ok"])
            case "/storage/v1/object/docs": return (200, [])
            case "/rest/v1/rpc/submit_document": return refuse ? (400, ["message": "that FSSAI number isn't valid"]) : (200, [:])
            case "/rest/v1/rpc/listing_compliance": return (200, [["doc_type": "FSSAI", "label": "FSSAI licence", "status": "PENDING", "path": "me/new.pdf"]])
            default: return (404, ["message": "no stub \(path)"])
            }
        }
        let row = try Backend.decoder.decode(ComplianceRow.self, from: Data(#"{"doc_type":"FSSAI","label":"FSSAI licence","status":"MISSING"}"#.utf8))
        let file = Picked(data: Data([1, 2, 3]), name: "licence.pdf", mime: "application/pdf")
        var done = false
        s.services.submit("L1", row: row, file: file, number: " 123 ", expires: "2027-03-12") { done = true }
        #expect(await wait { done })
        let uploadPath = FakeServer.calls.first(where: { $0.path.hasPrefix("/storage/v1/object/docs/me/listing-fssai-") })?.path ?? ""
        let up = try #require(call(uploadPath).first)
        #expect(up.method == "POST")
        let sub = try #require(call("/rest/v1/rpc/submit_document").first)
        #expect(Set(sub.body.keys) == ["p_listing", "p_type", "p_path", "p_number", "p_expires"])
        #expect(sub.body["p_type"] as? String == "FSSAI"); #expect(sub.body["p_number"] as? String == "123"); #expect(sub.body["p_expires"] as? String == "2027-03-12")
        #expect((sub.body["p_path"] as? String)?.hasPrefix("me/listing-fssai-") == true)
        #expect(t.lines.last == "FSSAI licence sent. Bucks checks documents within two working days.")
        #expect(s.services.uploading == nil); #expect(s.services.compliance["L1"]?.first?.status == "PENDING")

        // A refused submit removes the file again and tells the person why.
        refuse = true; FakeServer.calls = []
        s.services.submit("L1", row: row, file: file, number: "bad", expires: nil)
        #expect(await wait { FakeServer.calls.contains { $0.method == "DELETE" && $0.path == "/storage/v1/object/docs" } })
        #expect(t.lines.last == "That FSSAI number isn't valid"); #expect(s.services.uploading == nil)
    }

    @Test func staffReviewCallsTheReviewFunctionAndDropsTheItem() async throws {
        let (s, t) = session()
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/documents_to_review": return (200, [["id": "d1", "listing_id": "L1", "listing_title": "Fresh Mart", "doc_type": "FSSAI", "label": "FSSAI licence", "path": "u/x.pdf", "uploaded_by": "u"]])
            case "/rest/v1/rpc/review_document": return (200, "LIVE")
            case "/rest/v1/rpc/is_staff": return (200, true)
            default: return (404, ["message": "no stub"])
            }
        }
        s.services.checkStaff(); #expect(await wait { s.services.isStaff })
        s.services.loadReviewQueue(); #expect(await wait { s.services.reviewLoaded })
        let item = try #require(s.services.reviewQueue.first)
        s.services.review(item, approve: false, note: "blurry")
        #expect(await wait { s.services.reviewQueue.isEmpty })
        let r = try #require(call("/rest/v1/rpc/review_document").first)
        #expect(Set(r.body.keys) == ["p_doc", "p_approve", "p_note"]); #expect(r.body["p_approve"] as? Bool == false); #expect(r.body["p_note"] as? String == "blurry")
        #expect(t.lines.last == "Rejected. They'll see your reason.")
    }

    // MARK: pure helpers

    @Test func labelsDistancesAndDetailsReadLikeAndroid() throws {
        #expect(kindLabel("BUSINESS") == "Shop"); #expect(kindLabel("SKILL") == "Pro"); #expect(kindLabel("DRIVER") == "Driver"); #expect(kindLabel("ASSET") == "Asset")
        #expect(formatDistance(650) == "650 m"); #expect(formatDistance(1234) == "1.2 km"); #expect(formatDistance(999.6) == "1000 m")
        let det = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"rate":" ₹300/hr ","free_delivery":true,"year":2019,"blank":"  ","gone":"null","languages":["Kannada"," Hindi ",""],"csv":"a, b ,,c","vehicle_kind":"auto"}"#.utf8))
        #expect(det.str("rate") == "₹300/hr"); #expect(det.str("free_delivery") == "true"); #expect(det.str("year") == "2019")
        #expect(det.str("blank") == nil); #expect(det.str("gone") == nil); #expect(det.str("missing") == nil)
        #expect(det.list("languages") == ["Kannada", "Hindi"]); #expect(det.list("csv") == ["a", "b", "c"]); #expect(det.list("nothing") == [])
        #expect(driverKind(det) == .auto); #expect(driverKind(.emptyObject, category: "Cab taxi") == .cab); #expect(driverKind(.emptyObject) == nil)
        #expect(proRate(det, minPrice: 50) == "₹300/hr"); #expect(proRate(.emptyObject, minPrice: 50) == "From ₹50"); #expect(proRate(.emptyObject, minPrice: nil) == "Rate on request")
    }

    @Test func serviceCatalogMapsCategoriesLikeTheServer() {
        #expect(serviceCatalog.map(\.key) == ["TAXI", "AUTO", "PARCEL", "FOOD", "GROCERY", "VEGETABLES", "MEAT", "SHOPPING", "GIGS", "JOBS", "PROPERTIES"])
        #expect(serviceForCategory("bakery") == "FOOD"); #expect(serviceForCategory(" Dairy ") == "GROCERY"); #expect(serviceForCategory("Fish") == "MEAT")
        #expect(serviceForCategory("Something else") == "SHOPPING"); #expect(serviceForCategory(nil) == "SHOPPING")
        #expect(serviceDef("JOBS")?.joinAction == "Post a job from your business"); #expect(serviceDef("nope") == nil)
        var stateLocked = ServiceState(key: "X", label: "X"); #expect(!stateLocked.usable)
        stateLocked.state = "OPEN"; #expect(stateLocked.usable); stateLocked.radiusM = 1500; #expect(stateLocked.radiusKm == "1.5 km")
    }
}
