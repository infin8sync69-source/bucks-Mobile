import Foundation
import Testing
@testable import BucksCore

/// Search measurement (DiscoveryLog.swift, the port of DiscoveryLog.kt): what log_discovery receives, and that nothing is kept or sent
/// for anyone but an adult with usage statistics on. Written against supabase/migrations/discovery_log.sql, whose checks accept whole
/// numbers and plain decimals only.
@MainActor @Suite(.serialized) struct DiscoveryLogTests {
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
    private func calls(_ path: String) -> Int { FakeServer.calls.filter { $0.path == path }.count }
    /// Every event log_discovery received, in order.
    private func sent() -> [[String: Any]] {
        FakeServer.calls.filter { $0.path == "/rest/v1/rpc/log_discovery" }.flatMap { $0.body["p_events"] as? [[String: Any]] ?? [] }
    }
    private func hit(_ id: String) -> [String: Any] {
        ["id": id, "kind": "BUSINESS", "title": "Fresh Mart", "category": "Grocery", "description": "", "area": "Jayanagar", "online": true, "trust_up": 4, "trust_down": 1, "details": [String: Any](), "distance_m": 650.0]
    }
    private func session() -> AppSession {
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao"); return s
    }
    private func stub(band: String = "ADULT") {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/search_listings": return (200, [self.hit("L1"), self.hit("L2")])
            case "/rest/v1/rpc/log_discovery", "/rest/v1/rpc/discovery_forget_me": return (200, 1)
            case "/rest/v1/rpc/set_birth_date": return (200, band)
            default: return (404, ["message": "no stub"])
            }
        }
    }

    @Test func aSearchWhatWasShownTheResultOpenedAndWhatWasDoneNext() async throws {
        let s = session(); stub()
        let log = DiscoveryLog.shared
        log.configure(band: "ADULT", optedIn: true)
        defer { log.configure(band: "UNKNOWN", optedIn: false) }
        let d = s.discover
        d.query = "  sugar "; d.search()
        #expect(await wait { d.searched && !d.searching })
        d.opened("L2")
        log.acted("SHARE", listingId: "L2")
        log.acted("MESSAGE", listingId: "L1")   // a page that wasn't the one opened from search: not sent
        #expect(log.pending.count == 4)
        log.flush()
        #expect(log.pending.isEmpty)
        #expect(await wait { sent().count == 4 })
        let e = sent()
        #expect(e.map { $0["t"] as? String } == ["QUERY", "IMPRESSION", "OPEN", "SHARE"])

        let q = e[0], qid = try #require(q["id"] as? String)
        #expect(qid == qid.lowercased()); #expect(UUID(uuidString: qid) != nil); #expect(d.lastQueryId == qid)
        #expect(q["surface"] as? String == "SEARCH"); #expect(q["q"] as? String == "sugar")
        #expect(q["radius_m"] as? Int == 10_000); #expect(q["n"] as? Int == 2); #expect(q["ranker"] as? String == "v1")
        #expect((q["ms"] as? Int).map { $0 >= 0 } == true)
        #expect(q["filters"] as? [String: String] == ["kind": "ALL"])
        #expect((q["app"] as? String)?.hasPrefix("ios ") == true)
        #expect(abs((q["lat"] as? Double ?? 0) - s.here.lat) < 0.000_001); #expect(abs((q["lng"] as? Double ?? 0) - s.here.lng) < 0.000_001)
        #expect((q["at"] as? String)?.hasPrefix("20") == true)

        #expect(e[1]["query_id"] as? String == qid); #expect(e[1]["subject_type"] as? String == "LISTING"); #expect(e[1]["ids"] as? [String] == ["L1", "L2"])
        #expect(e[2]["query_id"] as? String == qid); #expect(e[2]["subject_id"] as? String == "L2"); #expect(e[2]["position"] as? Int == 1)
        #expect(e[3]["query_id"] as? String == qid); #expect(e[3]["subject_id"] as? String == "L2"); #expect(!e[3].keys.contains("position"))
    }

    @Test func aServiceTileWithNoWordsIsTheServicesSurface() async throws {
        let s = session(); stub()
        let log = DiscoveryLog.shared
        log.configure(band: "ADULT", optedIn: true)
        defer { log.configure(band: "UNKNOWN", optedIn: false) }
        let d = s.discover
        d.useService("FOOD", radiusM: 4_000); d.search()
        #expect(await wait { d.searched && !d.searching })
        log.flush()
        #expect(await wait { sent().count == 2 })
        let q = try #require(sent().first)
        #expect(q["surface"] as? String == "SERVICES"); #expect(q["q"] is NSNull)
        #expect(q["filters"] as? [String: String] == ["kind": "ALL", "service": "FOOD"])
    }

    /// A ↑ or ↓ given to a page (DiscoveryLog.voted, as in DiscoveryLog.kt): tied to the search the page was opened from in the last
    /// 30 minutes, sent without a search otherwise; a removed review (0) sends nothing.
    @Test func aVoteIsTheOutcomeOfTheSearchThePageCameFrom() async throws {
        let s = session(); stub()
        let log = DiscoveryLog.shared
        log.configure(band: "ADULT", optedIn: true)
        defer { log.configure(band: "UNKNOWN", optedIn: false) }
        let d = s.discover
        d.query = "sugar"; d.search()
        #expect(await wait { d.searched && !d.searching })
        d.opened("L1")
        let qid = try #require(d.lastQueryId)
        #expect(log.queryFor("L1") == qid); #expect(log.queryFor("L2") == nil)
        log.voted("L1", vote: 1, queryId: log.queryFor("L1"))
        log.voted("L2", vote: -1, queryId: log.queryFor("L2"))
        log.voted("L1", vote: 0, queryId: qid)
        log.flush()
        #expect(await wait { sent().count == 5 })   // QUERY, IMPRESSION, OPEN and the two votes
        let votes = sent().filter { $0["t"] as? String == "VOTE" }
        #expect(votes.count == 2)
        #expect(votes.first?["query_id"] as? String == qid); #expect(votes.first?["subject_id"] as? String == "L1")
        #expect(votes.first?["subject_type"] as? String == "LISTING"); #expect(votes.first?["detail"] as? String == "UP")
        #expect(votes.last?.keys.contains("query_id") == false); #expect(votes.last?["subject_id"] as? String == "L2"); #expect(votes.last?["detail"] as? String == "DOWN")
    }

    /// The checks of log_discovery: a coordinate is at most 3 digits, a point and at most 12 decimals (discovery_num); a count is digits
    /// only (discovery_int). A Double written by JSONSerialization can carry 15 decimals or more and would fail the first.
    @Test func coordinatesAndCountsPassTheServersChecks() throws {
        let e: DiscoveryLog.Event = ["lat": DiscoveryLog.coordinate(12.971598765432101), "lng": DiscoveryLog.coordinate(-77.594562987654321),
                                     "n": .int(3), "nowhere": DiscoveryLog.coordinate(.nan)]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: DiscoveryLog.wire(e), options: [.sortedKeys]), as: UTF8.self)
        func value(_ key: String) -> String? {
            guard let r = text.range(of: "\"\(key)\":[^,}]*", options: .regularExpression) else { return nil }
            return String(text[r].dropFirst(key.count + 3))
        }
        let decimal = try NSRegularExpression(pattern: #"^-?\d{1,3}(\.\d{1,12})?$"#)
        for key in ["lat", "lng"] {
            let v = try #require(value(key))
            #expect(decimal.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) != nil, "\(key) went out as \(v)")
        }
        #expect(value("lat").flatMap { Double($0) } == 12.971599); #expect(value("lng").flatMap { Double($0) } == -77.594563)
        #expect(value("n") == "3"); #expect(value("nowhere") == "null")
    }

    @Test func nothingIsKeptOrSentForUnderEighteensUnknownAgesOrWithTheSwitchOff() async {
        let s = session(); stub()
        let log = DiscoveryLog.shared
        defer { log.configure(band: "UNKNOWN", optedIn: false) }
        let d = s.discover
        var searches = 0
        for (band, optedIn) in [("TEEN", true), ("CHILD", true), ("UNKNOWN", true), ("ADULT", false)] {
            log.configure(band: band, optedIn: optedIn)
            #expect(!log.on)
            d.query = "sugar"; d.search(); searches += 1
            #expect(await wait { calls("/rest/v1/rpc/search_listings") == searches && !d.searching })
            d.opened("L1"); log.acted("SHARE", listingId: "L1")
            #expect(log.pending.isEmpty); #expect(d.lastQueryId == nil)
        }
        log.flush()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sent().isEmpty)
    }

    @Test func theAgeBandFromTheServerTurnsItOnOnlyForAdults() async {
        let s = session()
        let log = DiscoveryLog.shared
        defer { log.configure(band: "UNKNOWN", optedIn: false) }
        stub(band: "TEEN")
        #expect(await s.setBirthDate("2010-05-01") == nil)
        #expect(s.ageBand == "TEEN"); #expect(!log.on)
        stub(band: "ADULT")
        #expect(await s.setBirthDate("1990-05-01") == nil)
        #expect(s.ageBand == "ADULT"); #expect(log.on == Prefs.shared.shareUsage)
    }

    @Test func switchingUsageStatisticsOffDeletesWhatWasKept() async {
        let s = session(); stub()
        let log = DiscoveryLog.shared
        log.configure(band: "ADULT", optedIn: true)
        defer { log.configure(band: "UNKNOWN", optedIn: false); s.setShareUsage(true); UserDefaults.standard.removeObject(forKey: "shareUsage") }
        log.search(log.newId(), surface: "SEARCH", q: "sugar", at: LatLng(12.93, 77.58), radiusM: 3_000, filters: ["kind": "ALL"], n: 0, ms: 90)
        #expect(log.pending.count == 1)
        s.setShareUsage(false)
        #expect(!Prefs.shared.shareUsage); #expect(!log.on); #expect(log.pending.isEmpty)
        #expect(await wait { calls("/rest/v1/rpc/discovery_forget_me") == 1 })
        log.flush()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(sent().isEmpty)
    }
}
