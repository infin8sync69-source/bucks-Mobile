import Foundation
import Testing
@testable import BucksCore

/// A scripted Supabase: answers the PostgREST/RPC calls the dispatch engine makes from a small in-memory task.
final class FakeServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((String, String, [String: Any]) -> (Int, Any))?
    nonisolated(unsafe) static var log: [String] = []
    /// "METHOD /path" -> the Prefer header of that request (how a write is meant to behave: merge-duplicates, return=minimal, ...).
    nonisolated(unsafe) static var prefer: [String: String] = [:]
    /// Every request in order: method, path, query string and JSON body.
    nonisolated(unsafe) static var calls: [(method: String, path: String, query: String, body: [String: Any])] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = Data()
        if let s = request.httpBodyStream { s.open(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); while s.hasBytesAvailable { let n = s.read(buf, maxLength: 4096); if n <= 0 { break }; body.append(buf, count: n) }; buf.deallocate(); s.close() }
        else if let b = request.httpBody { body = b }
        let params = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let path = request.url!.path, query = request.url!.query ?? ""
        Self.log.append("\(request.httpMethod ?? "") \(path)")
        Self.prefer["\(request.httpMethod ?? "") \(path)"] = request.value(forHTTPHeaderField: "Prefer") ?? ""
        Self.calls.append((request.httpMethod ?? "", path, query, params))
        let (status, json) = Self.handler?(path, query, params) ?? (404, ["message": "no stub"])
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])) ?? Data()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class FakeIdentity: IdentityProvider, @unchecked Sendable {
    var uid: String? { "me" }
    func idToken(forceRefresh: Bool) async throws -> String? { "h." + Data(#"{"role":"authenticated"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") + ".s" }
}

@MainActor final class MockHost: DispatchHost {
    var me: ProfileRow? = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
    var here = LatLng(12.9279, 77.5836)
    var hereKnown = true
    var names: [String: String] = [:]
    var toasts: [String] = []
    func toast(_ message: String) { toasts.append(message) }
}

/// Mutable server state for one task.
struct TaskState {
    var status = "SEARCHING", driverId: String? = nil, pinAttempts = 0, paidWith: String? = nil
    func row(requester: String = "me") -> [String: Any] {
        var r: [String: Any] = ["id": "t1", "type": "RIDE", "requester_id": requester, "vehicle_kind": "AUTO", "pickup_label": "Jayanagar", "drop_label": "MG Road", "km": 5.2, "fare": 82, "pin": "4321",
                                "status": status, "created_at": "2026-09-30T10:00:00+00:00", "status_at": "2026-09-30T10:00:00+00:00", "pin_attempts": pinAttempts,
                                "pickup_lat": 12.9279, "pickup_lng": 77.5836, "drop_lat": 12.9757, "drop_lng": 77.6063]
        if let d = driverId { r["driver_id"] = d; r["driver_lat"] = 12.93; r["driver_lng"] = 77.59 }
        if let p = paidWith { r["paid_with"] = p }
        return r
    }
}

@MainActor @Suite(.serialized) struct DispatchTests {
    let host = MockHost()

    func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) {
        RingAlert.enabled = false
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
    }
    func wait(_ what: String = "", timeout: Double = 4, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 50_000_000) }
        return cond()
    }

    @Test func riderFollowsTheTaskToMatchedAndCancelsServerFirst() async throws {
        var state = TaskState()
        boot { path, _, params in
            switch path {
            case "/rest/v1/rpc/request_ride": return (200, state.row())
            case "/rest/v1/tasks_geo": return (200, [state.row()])
            case "/rest/v1/rpc/task_driver": return (200, [["profile_id": "d1", "name": "Ravi Kumar", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "up": 12, "down": 1, "listing_id": "L1"]])
            case "/rest/v1/rpc/contact_for_task": return (200, [["phone": "9845012345"]])
            case "/rest/v1/rpc/cancel_task":
                state.status = "CANCELLED"
                return (200, state.row())
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let d = Dispatch(host: host)
        d.requestRide(kind: .auto, from: host.here, fromLabel: "Jayanagar", dest: Place(name: "MG Road", km: 5.9, at: LatLng(12.9757, 77.6063)), fare: 90)
        #expect(await wait { d.ride != nil })
        // The server's fare and distance replace the estimate (contract C3).
        #expect(d.ride?.fare == 82); #expect(d.ride?.dest.km == 5.2); #expect(d.ride?.pin == "4321")
        state.status = "MATCHED"; state.driverId = "d1"
        await d.refreshRide("t1")
        #expect(d.ride?.status == .matched)
        #expect(d.ride?.driver?.name == "Ravi Kumar"); #expect(d.ride?.driver?.plate == "KA05AB1234"); #expect(d.ride?.driver?.phone == "9845012345")
        #expect((d.ride?.etaMin ?? -1) >= 0)
        let err = await d.cancelRide(reason: "PLANS_CHANGED")
        #expect(err == nil); #expect(d.ride == nil)
        #expect(state.status == "CANCELLED")
    }

    @Test func cancelRefusedWhenTripAlreadyStarted() async throws {
        var state = TaskState(); state.status = "MATCHED"; state.driverId = "d1"
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/request_ride": return (200, state.row())
            case "/rest/v1/tasks_geo": return (200, [state.row()])
            case "/rest/v1/rpc/task_driver": return (200, [])
            case "/rest/v1/rpc/contact_for_task": return (200, [])
            case "/rest/v1/rpc/cancel_task": state.status = "IN_PROGRESS"; return (400, ["message": "this ride can no longer be cancelled (it is in progress)"])
            default: return (404, ["message": "no stub"])
            }
        }
        let d = Dispatch(host: host)
        d.requestRide(kind: .auto, from: host.here, fromLabel: "Jayanagar", dest: Place(name: "MG Road", km: 5.9, at: LatLng(12.9757, 77.6063)), fare: 90)
        #expect(await wait { d.ride != nil })
        let err = await d.cancelRide(reason: "TOO_LONG")
        #expect(err == "Your trip has already started, so it can't be cancelled here.")
        #expect(d.ride?.status == .inRide)
    }

    @Test func rideRefusesTooShortTripsBeforeCallingTheServer() async throws {
        boot { _, _, _ in (500, ["message": "should not be called"]) }
        let d = Dispatch(host: host)
        d.requestRide(kind: .auto, from: host.here, fromLabel: "x", dest: Place(name: "Next door", km: 0.1, at: host.here), fare: 30)
        d.requestRide(kind: .bike, from: host.here, fromLabel: "x", dest: Place(name: "Far", km: 5, at: host.here), fare: 60)
        #expect(host.toasts == ["That's too close for a ride. Pick a destination at least 200 m away.", "Bikes carry goods only. Choose an auto or a cab."])
        #expect(FakeServer.log.isEmpty)
    }

    @Test func driverRingsAcceptsEntersPinAndCollects() async throws {
        var state = TaskState()
        var claimed = false
        boot { path, _, params in
            switch path {
            case "/rest/v1/vehicles": return (200, [["id": "v1", "owner_id": "me", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "status": "ACTIVE"]])
            case "/rest/v1/driver_presence": return (201, [:])
            case "/rest/v1/rpc/open_tasks_near": return (200, claimed ? [] : [state.row(requester: "u9")])
            case "/rest/v1/tasks_geo": return (200, [state.row(requester: "u9")])
            case "/rest/v1/profiles": return (200, [["id": "u9", "short_code": "CU0009", "name": "Meera Shah", "trust_up": 4, "trust_down": 0]])
            case "/rest/v1/rpc/claim_task": claimed = true; state.status = "MATCHED"; state.driverId = "me"; return (200, true)
            case "/rest/v1/rpc/contact_for_task": return (200, [["phone": "9000000001"]])
            case "/rest/v1/rpc/advance_task":
                let to = params["p_status"] as? String ?? ""
                if to == "IN_PROGRESS" { if (params["p_pin"] as? String) == "4321" { state.status = "IN_PROGRESS" } else { state.pinAttempts += 1 } }
                else { state.status = to }
                return (200, state.row(requester: "u9"))
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let d = Dispatch(host: host)
        #expect(await d.setOnline(true, plate: nil)); #expect(d.online); #expect(d.vehicle?.plate == "KA05AB1234")
        try await d.pollRing()
        #expect(d.driverRide?.status == .ringing); #expect(d.driverRide?.customer == "Meera Shah"); #expect(d.driverRide?.fare == 82); #expect(d.driverRide?.secondsLeft == 15)
        d.driverAccept()
        #expect(await wait { d.driverRide?.status == .toPickup })
        d.driverNext()
        #expect(await wait { d.driverRide?.status == .arrived })
        d.driverNext(pin: "0000")
        #expect(await wait { d.driverRide?.pinAttempts == 1 })
        #expect(d.driverRide?.status == .arrived)
        #expect(host.toasts.last == "That PIN doesn't match. 4 tries left.")
        d.driverNext(pin: "4321")
        #expect(await wait { d.driverRide?.status == .inRide })
        d.driverNext()
        #expect(await wait { d.driverRide?.status == .done })
        #expect(d.driverPaid(method: "CASH")); #expect(d.driverRide?.status == .rate); #expect(!d.driverPaid(method: "CASH"))
        d.closeTrip(); #expect(d.driverRide == nil)
        await d.setOnline(false)
        #expect(!d.online)
    }

    @Test func goingOnlineNeedsAnActiveVehicle() async throws {
        boot { path, _, _ in
            if path == "/rest/v1/vehicles" { return (200, [["id": "v1", "owner_id": "me", "kind": "AUTO", "plate": "KA05AB1234", "status": "PENDING"]]) }
            return (404, ["message": "no stub"])
        }
        let d = Dispatch(host: host)
        #expect(await d.setOnline(true, plate: nil) == false)
        #expect(host.toasts.last == "Bucks is still checking your vehicle. You can go online once it's active.")
    }
}
