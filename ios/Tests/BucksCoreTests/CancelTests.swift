import Foundation
import Testing
@testable import BucksCore

/// Cancelling a ride with a reason (cancel_task), handing a trip back (release_task) and the stats behind the nudge, against the
/// scripted server of DispatchTests and supabase/migrations/cancellation.sql. A refusal must leave the ride where the server says it is.
private final class DriverWorld { var state = TaskState(); var claimed = false }

extension DispatchTests {
    private func cancelCalls(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }

    /// A rider's ride that the scripted server answers; `cancel` decides what cancel_task does.
    private func bootRider(_ state: @escaping () -> TaskState, cancel: @escaping ([String: Any]) -> (Int, Any)) {
        boot { path, _, params in
            switch path {
            case "/rest/v1/rpc/request_ride": return (200, state().row())
            case "/rest/v1/tasks_geo": return (200, [state().row()])
            case "/rest/v1/rpc/task_driver": return (200, [])
            case "/rest/v1/rpc/contact_for_task": return (200, [])
            case "/rest/v1/rpc/cancel_task": return cancel(params)
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
    }
    private func book(_ d: Dispatch) async -> Bool {
        d.requestRide(kind: .auto, from: host.here, fromLabel: "Jayanagar", dest: Place(name: "MG Road", km: 5.9, at: LatLng(12.9757, 77.6063)), fare: 90)
        return await wait { d.ride != nil }
    }

    @Test func aMatchedRideNeedsAReasonAndNothingIsSentWithoutOne() async throws {
        let box = DriverWorld()
        bootRider({ box.state }, cancel: { _ in box.state.status = "CANCELLED"; return (200, box.state.row()) })
        let d = Dispatch(host: host)
        #expect(await book(d))
        box.state.status = "MATCHED"; box.state.driverId = "d1"
        await d.refreshRide("t1")
        #expect(d.ride?.status == .matched)
        // Refused here: no call, the ride stays.
        let refused = await d.cancelRide()
        #expect(refused == "Choose why you are cancelling.")
        #expect(d.ride?.status == .matched); #expect(cancelCalls("/rest/v1/rpc/cancel_task").isEmpty); #expect(!d.cancelling)
        // With a reason: the server cancels, then the ride goes.
        let done = await d.cancelRide(reason: "DRIVER_FAR", note: "  waited twenty minutes  ")
        #expect(done == nil); #expect(d.ride == nil)
        let body = try #require(cancelCalls("/rest/v1/rpc/cancel_task").first).body
        #expect(body["p_task"] as? String == "t1"); #expect(body["p_reason"] as? String == "DRIVER_FAR"); #expect(body["p_note"] as? String == "waited twenty minutes")
        #expect(box.state.status == "CANCELLED")
    }

    @Test func aRequestNobodyTookCancelsWithoutAReasonAndTheNoteIsCapped() async throws {
        let box = DriverWorld()
        bootRider({ box.state }, cancel: { _ in box.state.status = "CANCELLED"; return (200, box.state.row()) })
        let d = Dispatch(host: host)
        #expect(await book(d)); #expect(d.ride?.status == .searching)
        let done = await d.cancelRide(reason: nil, note: String(repeating: "x", count: 250))
        #expect(done == nil); #expect(d.ride == nil)
        let body = try #require(cancelCalls("/rest/v1/rpc/cancel_task").first).body
        #expect(body["p_reason"] is NSNull)   // sent as JSON null, as Android does
        #expect((body["p_note"] as? String)?.count == 200)
    }

    @Test func aServerRefusalKeepsTheRideAndSaysWhy() async throws {
        let box = DriverWorld(); box.state.status = "MATCHED"; box.state.driverId = "d1"
        bootRider({ box.state }, cancel: { _ in (400, ["message": "unknown reason"]) })
        let d = Dispatch(host: host)
        #expect(await book(d))
        let err = await d.cancelRide(reason: "NOPE")
        #expect(err == "Unknown reason")
        #expect(d.ride?.status == .matched); #expect(!d.cancelling)
        #expect(cancelCalls("/rest/v1/rpc/cancel_task").count == 1)
        // The sheet can try again: a second attempt goes to the server too.
        _ = await d.cancelRide(reason: "NOPE")
        #expect(cancelCalls("/rest/v1/rpc/cancel_task").count == 2); #expect(d.ride != nil)
    }

    @Test func aRideAlreadyCancelledElsewhereCountsAsCancelled() async throws {
        let box = DriverWorld(); box.state.status = "SEARCHING"
        bootRider({ box.state }, cancel: { _ in box.state.status = "CANCELLED"; return (400, ["message": "this ride can no longer be cancelled (it is cancelled)"]) })
        let d = Dispatch(host: host)
        #expect(await book(d))
        let err = await d.cancelRide()
        #expect(err == nil); #expect(d.ride == nil)
    }

    // MARK: driver hands a trip back

    private func bootDriver(_ w: DriverWorld, release: @escaping (DriverWorld, [String: Any]) -> (Int, Any)) {
        boot { path, _, params in
            switch path {
            case "/rest/v1/vehicles": return (200, [["id": "v1", "owner_id": "me", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "status": "ACTIVE"]])
            case "/rest/v1/driver_presence": return (201, [:])
            case "/rest/v1/rpc/open_tasks_near": return (200, w.claimed ? [] : [w.state.row(requester: "u9")])
            case "/rest/v1/tasks_geo": return (200, [w.state.row(requester: "u9")])
            case "/rest/v1/profiles": return (200, [["id": "u9", "short_code": "CU0009", "name": "Meera Shah", "trust_up": 4, "trust_down": 0]])
            case "/rest/v1/rpc/claim_task": w.claimed = true; w.state.status = "MATCHED"; w.state.driverId = "me"; return (200, true)
            case "/rest/v1/rpc/contact_for_task": return (200, [["phone": "9000000001"]])
            case "/rest/v1/rpc/release_task": return release(w, params)
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
    }
    /// Online, ringing, accepted: the driver is on the way to the pick-up and nothing is in flight.
    private func acceptTrip(_ d: Dispatch) async throws {
        #expect(await d.setOnline(true, plate: nil))
        try await d.pollRing()
        d.driverAccept()
        #expect(await wait { d.driverRide?.status == .toPickup && !d.busy })
    }

    @Test func handingATripBackNeedsAReasonAndGoesThroughReleaseTask() async throws {
        let w = DriverWorld()
        bootDriver(w, release: { w, _ in w.state.status = "SEARCHING"; w.state.driverId = nil; return (200, w.state.row(requester: "u9")) })
        let d = Dispatch(host: host)
        try await acceptTrip(d)
        // No reason: refused here, nothing sent, the trip stays.
        let refused = await d.driverCancel(reason: nil)
        #expect(refused == "Choose why you are handing it back.")
        #expect(cancelCalls("/rest/v1/rpc/release_task").isEmpty); #expect(d.driverRide?.status == .toPickup)
        // With a reason: release_task (not advance_task), then the trip is gone from this driver.
        let done = await d.driverCancel(reason: "RIDER_NO_SHOW", note: " not at the gate ")
        #expect(done == nil); #expect(d.driverRide == nil); #expect(!d.handingBack)
        let body = try #require(cancelCalls("/rest/v1/rpc/release_task").first).body
        #expect(body["p_task"] as? String == "t1"); #expect(body["p_reason"] as? String == "RIDER_NO_SHOW"); #expect(body["p_note"] as? String == "not at the gate")
        #expect(cancelCalls("/rest/v1/rpc/advance_task").isEmpty)
        await d.setOnline(false)
    }

    @Test func aRefusedHandBackKeepsTheTripWhereTheServerHasIt() async throws {
        let w = DriverWorld()
        bootDriver(w, release: { w, _ in w.state.status = "IN_PROGRESS"; return (400, ["message": "it can only be handed back before the trip starts (it is in progress)"]) })
        let d = Dispatch(host: host)
        try await acceptTrip(d)
        let err = await d.driverCancel(reason: "UNSAFE")
        #expect(err == "It can only be handed back before the trip starts (it is in progress)")
        #expect(d.driverRide?.status == .inRide); #expect(!d.handingBack)
        // Once the trip has started the screen refuses by itself, without calling the server again.
        let again = await d.driverCancel(reason: "UNSAFE")
        #expect(again == "A trip that has started can't be handed back.")
        #expect(cancelCalls("/rest/v1/rpc/release_task").count == 1)
        await d.setOnline(false)
    }

    // MARK: stats and codes

    @Test func cancelStatsDecodeAndTheReasonCodesAreTheServers() async throws {
        boot { path, _, _ in
            if path == "/rest/v1/rpc/my_cancel_stats" { return (200, ["rider_day": 2, "rider_week": 3, "driver_day": 0, "driver_week": 1]) }
            return (404, ["message": "no stub for \(path)"])
        }
        let st = try await Backend.shared.myCancelStats()
        #expect(st == CancelStats(riderDay: 2, riderWeek: 3, driverDay: 0, driverWeek: 1))
        #expect(CancelReasons.rider.map(\.code) == ["TOO_LONG", "DRIVER_FAR", "DRIVER_ASKED", "PLANS_CHANGED", "BOOKED_BY_MISTAKE", "WRONG_ADDRESS", "OTHER"])
        #expect(CancelReasons.driver.map(\.code) == ["RIDER_NO_SHOW", "RIDER_UNREACHABLE", "RIDER_ASKED", "TOO_FAR", "VEHICLE_ISSUE", "UNSAFE", "OTHER"])
        #expect(CancelReasons.buyer.map(\.code) == ["CHANGED_MIND", "ORDERED_BY_MISTAKE", "WRONG_ADDRESS", "TOO_SLOW", "FOUND_BETTER", "OTHER"])
        #expect(CancelReasons.shop.map(\.code) == ["OUT_OF_STOCK", "CANT_DELIVER", "CUSTOMER_UNREACHABLE", "CUSTOMER_ASKED", "CLOSED", "OTHER"])
        #expect(CancelReasons.shopReject.map(\.code) == ["OUT_OF_STOCK", "CLOSED", "TOO_FAR", "CANT_DELIVER", "OTHER"])
    }
}
