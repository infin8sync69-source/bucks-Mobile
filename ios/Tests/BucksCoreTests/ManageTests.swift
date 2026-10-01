import Foundation
import Testing
@testable import BucksCore

@Suite struct BucksQrTests {
    @Test func parsesEachPrefix() {
        #expect(BucksQr.parse("bucks:id:h6vfywyf ") == .bucksId("H6VFYWYF"))
        #expect(BucksQr.parse("bucks:rec: tok-1 ") == .recommendation("tok-1"))
        #expect(BucksQr.parse("UPI://pay?pa=a@b") == .upi("UPI://pay?pa=a@b"))
        #expect(BucksQr.parse("hello") == .other("hello"))
    }
    @Test func buildsTheCodesItReads() {
        #expect(BucksQr.forBucksId("abcd2345") == "bucks:id:ABCD2345")
        #expect(BucksQr.forRecommendation("t") == "bucks:rec:t")
    }
    @Test func bucksIdShape() {
        #expect(BucksQr.looksLikeBucksId("h6vfywyf"))
        #expect(BucksQr.looksLikeBucksId(" H6VFYWYF "))
        #expect(!BucksQr.looksLikeBucksId("H6VFYWY"))      // 7
        #expect(!BucksQr.looksLikeBucksId("H6VFYWYI"))     // I is not used
        #expect(!BucksQr.looksLikeBucksId("H6VFYWYU"))     // nor U
    }
}

@MainActor @Suite(.serialized) struct ManageTests {
    private func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) {
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
    }
    private func calls(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }
    private let docRow: [String: Any] = ["doc_type": "FSSAI", "label": "FSSAI licence", "required": true, "public_number": true, "asks_number": true, "has_expiry": true, "status": "MISSING"]

    @Test func documentCallsUseTheServersParameterNames() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/listing_compliance": return (200, [self.docRow])
            case "/rest/v1/rpc/documents_to_review":
                return (200, [["id": "d1", "listing_id": "L1", "listing_title": "Asha's Kitchen", "service": "FOOD", "doc_type": "FSSAI", "label": "FSSAI licence", "path": "me/x.jpg", "uploaded_by": "me"]])
            default: return (204, [:])
            }
        }
        let rows = try await Backend.shared.listingCompliance("L1")
        #expect(rows.first?.docType == "FSSAI"); #expect(rows.first?.required == true); #expect(rows.first?.status == "MISSING")
        #expect(calls("/rest/v1/rpc/listing_compliance").first?.body["p_listing"] as? String == "L1")

        try await Backend.shared.submitDocument(listingId: "L1", type: "FSSAI", path: "me/a.jpg", number: "123", expires: "2027-01-31")
        let sub = try #require(calls("/rest/v1/rpc/submit_document").first)
        #expect(Set(sub.body.keys) == ["p_listing", "p_type", "p_path", "p_number", "p_expires"]); #expect(sub.body["p_expires"] as? String == "2027-01-31")

        try await Backend.shared.deleteDocument(listingId: "L1", type: "FSSAI")
        #expect(Set(calls("/rest/v1/rpc/delete_document")[0].body.keys) == ["p_listing", "p_type"])

        let queue = try await Backend.shared.documentsToReview()
        #expect(queue.first?.listingTitle == "Asha's Kitchen")
        try await Backend.shared.reviewDocument(id: "d1", approve: false, note: "Blurry")
        let rev = try #require(calls("/rest/v1/rpc/review_document").first)
        #expect(Set(rev.body.keys) == ["p_doc", "p_approve", "p_note"]); #expect(rev.body["p_approve"] as? Bool == false)
    }

    @Test func aRejectedSubmitRemovesTheUploadedFile() async throws {
        boot { path, _, _ in
            if path == "/rest/v1/rpc/submit_document" { return (400, ["message": "Number is required"]) }
            return (200, [:])
        }
        let store = ManageStore(); var toasts: [String] = []
        let row = try Backend.decoder.decode(DocRequirement.self, from: JSONSerialization.data(withJSONObject: docRow))
        let ok = await store.submit(listingId: "L1", row: row, file: Picked(data: Data([1, 2, 3]), name: "a.jpg", mime: "image/jpeg"), number: "", expires: nil, me: "me") { toasts.append($0) }
        #expect(!ok); #expect(store.uploading == nil)
        let up = try #require(FakeServer.calls.first { $0.method == "POST" && $0.path.hasPrefix("/storage/v1/object/docs/me/listing-fssai-") })
        #expect(up.path.hasPrefix("/storage/v1/object/docs/me/"))
        #expect(FakeServer.calls.contains { $0.method == "DELETE" && $0.path.hasPrefix("/storage/v1/object/docs") })
        #expect(toasts.count == 1)
    }

    @Test func memberInviteAndRecommendationCalls() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/recommend_token": return (200, "tok-123")
            case "/rest/v1/rpc/recommend": return (200, 4)
            case "/rest/v1/rpc/invite": return (200, "Invite sent")
            case "/rest/v1/recommendations": return (200, [["recommender_id": "a"], ["recommender_id": "b"]])
            case "/rest/v1/settings": return (200, [["key": "min_recommendations", "value": 7]])
            default: return (200, [])
            }
        }
        #expect(try await Backend.shared.recommendToken(listingId: "L1") == "tok-123")
        #expect(calls("/rest/v1/rpc/recommend_token")[0].body["p_listing"] as? String == "L1")
        #expect(try await Backend.shared.recommend(token: "tok-123", lat: 12.9, lng: 77.5) == 4)
        let rec = calls("/rest/v1/rpc/recommend")[0].body
        #expect(Set(rec.keys) == ["p_token", "lat", "lng"]); #expect(rec["lat"] as? Double == 12.9)
        #expect(try await Backend.shared.recommendationTotal(listingId: "L1") == 2)
        #expect(try await Backend.shared.minRecommendationsSetting() == 7)

        try await Backend.shared.inviteToListing(listingId: "L1", bucksId: "H6VFYWYF", role: "STORE_RIDER")
        let inv = calls("/rest/v1/rpc/invite")[0].body
        #expect(Set(inv.keys) == ["p_listing", "p_vehicle", "p_short_code", "p_role"]); #expect(inv["p_vehicle"] is NSNull); #expect(inv["p_role"] as? String == "STORE_RIDER")

        _ = try await Backend.shared.listingMembers(listingId: "L1")
        #expect(calls("/rest/v1/listing_members")[0].query.contains("listing_id=eq.L1"))
        try await Backend.shared.removeListingMember(listingId: "L1", profileId: "u2")
        let del = try #require(calls("/rest/v1/listing_members").first { $0.method == "DELETE" })
        #expect(del.query.contains("listing_id=eq.L1")); #expect(del.query.contains("profile_id=eq.u2"))
    }

    @Test func recommendingToastsTheCountAgainstTheThreshold() async {
        boot { path, _, _ in
            if path == "/rest/v1/rpc/recommend" { return (200, 7) }
            return (200, [])
        }
        let store = ManageStore(); var toasts: [String] = []
        let n = await store.recommend(token: "t", lat: 1, lng: 2) { toasts.append($0) }
        #expect(n == 7); #expect(toasts == ["Thanks, that's 7 of 7. They're live on Bucks now."])
    }
}
