import Foundation
import Testing
@testable import BucksCore

@Suite struct DecodingTests {
    @Test func taskGeoRowDecodesSnakeCaseWithDefaults() throws {
        let json = #"""
        {"id":"t1","type":"RIDE","requester_id":"u1","vehicle_kind":"AUTO","km":5.2,"fare":82,"pin":"4321","status":"MATCHED","driver_id":"d1",
         "pickup_lat":12.93,"pickup_lng":77.62,"drop_lat":12.97,"drop_lng":77.59,"driver_lat":12.94,"driver_lng":77.61,"pin_attempts":2,
         "status_at":"2026-09-30T10:15:20.123456+00:00"}
        """#
        let t = try Backend.decoder.decode(TaskGeoRow.self, from: Data(json.utf8))
        #expect(t.id == "t1"); #expect(t.driverId == "d1"); #expect(t.pinAttempts == 2); #expect(t.pickupLabel == "")
        #expect(t.driverAt == LatLng(12.94, 77.61)); #expect(t.pickup == LatLng(12.93, 77.62)); #expect(!t.isDelivery); #expect(t.collect == nil)
    }
    @Test func vehicleRowDefaultsToPending() throws {
        let v = try Backend.decoder.decode(VehicleRow.self, from: Data(#"{"id":"v1","owner_id":"u1","kind":"AUTO","plate":"KA05AB1234"}"#.utf8))
        #expect(v.status == "PENDING"); #expect(v.model == ""); #expect(v.vehicleKind == .auto)
    }
    @Test func profileRowAndScalarRpcDecoding() throws {
        let p = try Backend.decoder.decode(ProfileRow.self, from: Data(#"{"id":"u1","short_code":"AB12CD","trust_up":3}"#.utf8))
        #expect(p.shortCode == "AB12CD"); #expect(p.trust.pct == 100); #expect(p.name == "")
        #expect(try Backend.decoder.decode(Bool.self, from: Data("true".utf8)) == true)
    }
    @Test func secondsSinceParsesPostgrestTimestamps() {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        let s = secondsSince(f.string(from: Date().addingTimeInterval(-10))) ?? -1
        #expect(abs(s - 10) <= 2)
        #expect(secondsSince("2020-01-01 10:00:00.123456+00:00") != nil)
        #expect(secondsSince("not a date") == nil)
    }
}

@Suite struct HelperTests {
    @Test func friendlyErrorUsesTheServersSentence() {
        let e = BackendError.http(status: 400, body: #"{"code":"P0001","message":"cannot go from SEARCHING to PAID","details":null}"#)
        #expect(friendlyError(e) == "Cannot go from SEARCHING to PAID")
        #expect(isServerRefusal(e)); #expect(!isTransportError(e))
    }
    @Test func transientStatusesAreTransport() {
        for s in [401, 408, 429, 500, 503] { #expect(isTransportError(BackendError.http(status: s, body: "")), "\(s)") }
        #expect(friendlyError(BackendError.transport("offline")) == "Couldn't reach Bucks. Check your connection and try again.")
    }
    @Test func upiLinkKeepsPayeeAndSetsAmount() {
        let link = upiPayLink(base: "upi://pay?pa=ravi@okaxis&pn=Ravi%20K&am=1&tn=old", amountRupees: 82, note: "Bucks ride")
        let c = URLComponents(string: link)!
        #expect(c.scheme == "upi"); #expect(c.host == "pay")
        let q = Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(q["pa"] == "ravi@okaxis"); #expect(q["am"] == "82.00"); #expect(q["cu"] == "INR"); #expect(q["tn"] == "Bucks ride")
        #expect(upiPayee(link)?.name == "Ravi K"); #expect(upiPayee(link)?.address == "ravi@okaxis")
        #expect(upiPayee("upi://pay?am=5") == nil)
    }
    @Test func payWords() { #expect(payWord("CASH") == "cash"); #expect(payWord(nil) == "cash or UPI"); #expect(payWord("UPI") == "UPI"); #expect(isCash("Cash")) }
    @Test func geo() {
        #expect(Geo.distanceKm(Geo.center, Geo.center) < 0.001)
        #expect(abs(Geo.distanceKm(LatLng(12.9279, 77.5836), LatLng(12.9757, 77.6063)) - 5.9) < 0.3)
        #expect(Geo.nearestArea(LatLng(12.9352, 77.6245)) == "Koramangala")
    }
    @Test func jwtRoleClaim() {
        func token(_ payload: String) -> String { "h." + Data(payload.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + ".s" }
        #expect(JWT.hasRole(token(#"{"role":"authenticated"}"#))); #expect(!JWT.hasRole(token(#"{"sub":"x"}"#))); #expect(!JWT.hasRole("garbage"))
    }
}
