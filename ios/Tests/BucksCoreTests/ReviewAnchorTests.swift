import Foundation
import Testing
@testable import BucksCore

/// A reviewer's number stands at the demo world (ReviewAnchor, supabase/migrations/review_accounts.sql); everyone else keeps their GPS.
/// Part of DispatchTests so it runs serialized with every suite that scripts the shared FakeServer / Backend.shared.
extension DispatchTests {
    private func reviewSession(_ rows: [[String: Any]]) -> AppSession {
        RingAlert.enabled = false
        FakeServer.handler = { (path: String, _: String, _: [String: Any]) -> (Int, Any) in
            if path == "/rest/v1/rpc/review_anchor" { return (200, rows) }
            return (404, ["message": "no stub"])
        }
        FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
        return AppSession()
    }

    @Test func reviewerNumberGetsTheDemoPosition() async throws {
        _ = reviewSession([["lat": 13.003, "lng": 77.745, "label": "Whitefield, Bengaluru"]])
        let a = try #require(try await Backend.shared.reviewAnchor())
        #expect(a.at == LatLng(13.003, 77.745)); #expect(a.label == "Whitefield, Bengaluru")
    }

    @Test func everyoneElseGetsNothing() async throws {
        _ = reviewSession([])
        #expect(try await Backend.shared.reviewAnchor() == nil)
    }

    @Test func impossiblePositionIsIgnored() async throws {
        _ = reviewSession([["lat": 0.0, "lng": 0.0, "label": ""]])
        #expect(try await Backend.shared.reviewAnchor() == nil)
        #expect(!ReviewAnchor(lat: 91, lng: 77, label: "").valid)
        #expect(ReviewAnchor(lat: 12.183, lng: 75.915, label: "").valid)
    }

    @Test func gpsFixesDoNotMoveAReviewer() async {
        let s = reviewSession([])
        let demo = ReviewAnchor(lat: 13.003, lng: 77.745, label: "Whitefield, Bengaluru")
        s.useReviewAnchor(demo)
        #expect(s.here == demo.at); #expect(s.hereKnown); #expect(s.hereLabel == "Whitefield, Bengaluru")
        // Cupertino, and a fake-location app: neither moves the account or blocks booking.
        s.onLocation(LatLng(37.3349, -122.009), mocked: true)
        #expect(s.here == demo.at); #expect(!s.mockLocation)
        #expect(await s.refreshLocation())
    }

    @Test func anOrdinaryAccountFollowsItsGps() {
        let s = reviewSession([])
        s.onLocation(LatLng(12.97, 77.59), mocked: false)
        #expect(s.here == LatLng(12.97, 77.59)); #expect(s.reviewAnchor == nil)
    }
}
