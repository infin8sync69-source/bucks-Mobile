import Foundation
import Testing
@testable import BucksCore

/// The Account area's logic: stored preferences, the Bucks ID card's validity, and what its calls put on the wire.
extension DispatchTests {
    private func accountCalls(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }

    @Test func prefsPersistAndFallBackToDefaults() {
        let suite = "bucks.prefs.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = Prefs(defaults: d)
        #expect(p.theme == .system); #expect(p.textSize == .normal); #expect(p.mediaDownload == .wifi)
        #expect(!p.reduceMotion); #expect(!p.dataSaver); #expect(p.language == "en"); #expect(p.forcedDark == nil); #expect(p.textScale == 1)
        p.chooseTheme(.dark); p.chooseTextSize(.huge); p.chooseMediaDownload(.never); p.enableReduceMotion(true); p.enableDataSaver(true); p.chooseLanguage("kn")
        let q = Prefs(defaults: d)
        #expect(q.theme == .dark); #expect(q.forcedDark == true); #expect(q.textSize == .huge); #expect(q.textScale == 1.3)
        #expect(q.mediaDownload == .never); #expect(q.reduceMotion); #expect(q.dataSaver); #expect(q.language == "kn")
        d.set("garbage", forKey: "theme")
        #expect(Prefs(defaults: d).theme == .system)
        #expect(Prefs.TextSize.small.scale == 0.9); #expect(Prefs.TextSize.large.scale == 1.15)
    }

    @Test func bucksIdCardIsValidForAYear() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        let utc = TimeZone(identifier: "UTC")!
        let fresh = try #require(BucksIdCardInfo.of("2026-03-01T10:20:30.123456+00:00", today: day(2026, 3, 11), timeZone: utc))
        #expect(fresh.validFrom == "1 Mar 2026"); #expect(fresh.validTill == "1 Mar 2027"); #expect(fresh.daysLeft == 355)
        #expect(!fresh.expired); #expect(!fresh.renewable)
        let soon = try #require(BucksIdCardInfo.of("2026-03-01T00:00:00Z", today: day(2027, 2, 1), timeZone: utc))
        #expect(soon.daysLeft == 28); #expect(soon.renewable); #expect(!soon.expired)
        let last = try #require(BucksIdCardInfo.of("2026-03-01", today: day(2027, 3, 1), timeZone: utc))
        #expect(last.daysLeft == 0); #expect(!last.expired); #expect(last.renewable)
        let gone = try #require(BucksIdCardInfo.of("2026-03-01", today: day(2027, 3, 3), timeZone: utc))
        #expect(gone.daysLeft == -2); #expect(gone.expired)
        #expect(BucksIdCardInfo.of(nil) == nil); #expect(BucksIdCardInfo.of("  ") == nil); #expect(BucksIdCardInfo.of("soon") == nil)
    }

    @Test func verificationLevelsAndIdHelpers() {
        #expect(VerificationLevel.allCases.map(\.label) == ["Phone verified", "Genuine device", "ID verified", "Community vouched"])
        #expect(VerificationLevel.document.detail == "Driving licence or vehicle RC checked via DigiLocker partner")
        #expect(BucksIdCode.pretty("h6vfywyf") == "H6VF YWYF")
        #expect(accountHandle("  Asha K. ") == "@asha_k"); #expect(accountHumanBytes(2_621_440) == "2.5 MB"); #expect(accountHumanBytes(2048) == "2 KB"); #expect(accountHumanBytes(12) == "12 B")
    }

    @Test func renewingTheBucksIdCallsTheServerFunction() async throws {
        boot { path, _, _ in
            if path == "/rest/v1/rpc/renew_bucks_id" { return (200, "2026-09-30T08:00:00+00:00") }
            return (404, ["message": "no stub for \(path)"])
        }
        let issued = try await Backend.shared.renewBucksIdCard()
        #expect(issued == "2026-09-30T08:00:00+00:00")
        let c = try #require(accountCalls("/rest/v1/rpc/renew_bucks_id").first)
        #expect(c.method == "POST"); #expect(c.body.isEmpty)
    }

    @Test func accountReadsAskForMyRowsOnly() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/posts", "/rest/v1/messages", "/rest/v1/orders", "/rest/v1/tasks", "/rest/v1/syncs", "/rest/v1/post_votes": return (200, [])
            case "/rest/v1/recommendations", "/rest/v1/reviews": return (200, [])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        _ = try await Backend.shared.accountMyPosts(me: "me")
        let posts = try #require(accountCalls("/rest/v1/posts").first)
        #expect(posts.query.contains("author_id=eq.me")); #expect(posts.query.contains("deleted_at=is.null")); #expect(posts.query.contains("order=created_at.desc")); #expect(posts.query.contains("limit=60"))
        _ = try await Backend.shared.accountChatFiles()
        let files = try #require(accountCalls("/rest/v1/messages").first)
        #expect(files.query.contains("attachment=not.is.null")); #expect(files.query.contains("deleted_at=is.null"))
        _ = try await Backend.shared.accountMyOrders(me: "me")
        #expect(accountCalls("/rest/v1/orders").first?.query.contains("buyer_id=eq.me") == true)
        _ = try await Backend.shared.accountMyRides(me: "me")
        let rides = try #require(accountCalls("/rest/v1/tasks").first)
        #expect(rides.query.contains("requester_id=eq.me")); #expect(rides.query.contains("type=eq.RIDE"))
        _ = try await Backend.shared.accountRecommendationsIGave(me: "me")
        #expect(accountCalls("/rest/v1/recommendations").first?.query.contains("recommender_id=eq.me") == true)
        _ = try await Backend.shared.accountReviewsIWrote(me: "me")
        let rv = try #require(accountCalls("/rest/v1/reviews").first)
        #expect(rv.query.contains("author_id=eq.me")); #expect(rv.query.contains("limit=40"))
    }

    @Test func votingUpsertsAndTakingItBackDeletes() async throws {
        boot { path, _, _ in
            if path == "/rest/v1/post_votes" { return (201, [String: Any]()) }
            return (404, ["message": "no stub"])
        }
        try await Backend.shared.accountVote(postId: "p1", me: "me", vote: 1)
        let up = try #require(accountCalls("/rest/v1/post_votes").first)
        #expect(up.method == "POST"); #expect(FakeServer.prefer["POST /rest/v1/post_votes"]?.contains("resolution=merge-duplicates") == true)
        #expect(up.body["post_id"] as? String == "p1"); #expect(up.body["profile_id"] as? String == "me"); #expect(up.body["vote"] as? Int == 1)
        try await Backend.shared.accountVote(postId: "p1", me: "me", vote: 0)
        let del = try #require(accountCalls("/rest/v1/post_votes").last)
        #expect(del.method == "DELETE"); #expect(del.query.contains("post_id=eq.p1")); #expect(del.query.contains("profile_id=eq.me"))
    }
}
