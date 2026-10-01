#if os(macOS)
import Foundation
import BucksCore

/// A small in-process stand-in for the Bucks Supabase project: enough of the schema's RPCs and views for the taxi flow to run end to end.
/// A rider's request is "answered" by a simulated driver on a timeline; a driver sees a simulated open request once online.
final class FakeSupabase: URLProtocol, @unchecked Sendable {
    // MARK: state
    nonisolated(unsafe) static var profileName = ""
    nonisolated(unsafe) static var profileArea = ""
    nonisolated(unsafe) static var upi: String? = "upi://pay?pa=ravi@okaxis&pn=Ravi%20Kumar"
    nonisolated(unsafe) static var vehicles: [[String: Any]] = [
        ["id": "v1", "owner_id": "me", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "status": "ACTIVE", "docs": [["kind": "RC", "path": "me/rc.jpg"]]],
        ["id": "v2", "owner_id": "me", "kind": "CAB", "model": "Maruti Dzire", "plate": "KA01MN4567", "status": "PENDING", "docs": []],
    ]
    private static let lock = NSLock()
    /// Per-area fake endpoints (FakeSupabase+<Area>.swift add themselves here before the built-in routes are tried).
    nonisolated(unsafe) static var areaHandlers: [(String, String, String, [String: Any]) -> (Int, Any)?] = []
    private static let home = (lat: 12.9279, lng: 77.5836)

    /// The rider's task, advanced by the simulated driver.
    struct Ride { var id = "t-rider"; var created = Date(); var kind = "AUTO"; var km = 5.2; var fare = 82; var pickupLabel = ""; var dropLabel = ""; var dropLat = 12.9757; var dropLng = 77.6063
                  var status = "SEARCHING"; var paidWith: String?; var cancelled = false }
    nonisolated(unsafe) static var ride: Ride?
    /// The driver's task: a simulated customer.
    struct Job { var id = "t-driver"; var status = "SEARCHING"; var driverId: String?; var attempts = 0; var completedAt: Date?; var paid = false }
    nonisolated(unsafe) static var job: Job?
    nonisolated(unsafe) static var driverOnlineSince: Date?

    // MARK: URLProtocol
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = Data()
        if let s = request.httpBodyStream { s.open(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 8192); while s.hasBytesAvailable { let n = s.read(buf, maxLength: 8192); if n <= 0 { break }; body.append(buf, count: n) }; buf.deallocate(); s.close() }
        else if let b = request.httpBody { body = b }
        let params = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        Self.lock.lock()
        let (status, json) = Self.handle(method: request.httpMethod ?? "GET", path: request.url!.path, query: request.url!.query ?? "", params: params)
        Self.lock.unlock()
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])) ?? Data()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    // MARK: rows
    static var profile: [String: Any] { ["id": "me", "short_code": "AS4821", "name": profileName, "bio": "", "area": profileArea, "trust_up": 5, "trust_down": 0] }
    static let driverRow: [String: Any] = ["profile_id": "d1", "name": "Ravi Kumar", "kind": "AUTO", "model": "Bajaj RE", "plate": "KA05AB1234", "up": 41, "down": 2, "listing_id": "L1"]

    static func rideGeo(_ r: Ride) -> [String: Any] {
        let age = Date().timeIntervalSince(r.created)
        var status = r.status
        if !r.cancelled && status != "PAID" && status != "COMPLETED" {
            // The simulated driver: accepts at 4 s, arrives at 12 s, starts at 20 s, finishes at 34 s.
            if r.status == "SEARCHING" && age >= 4 { status = "MATCHED" }
            if age >= 12 && status == "MATCHED" { status = "ARRIVED" }
            if age >= 20 && status == "ARRIVED" { status = "IN_PROGRESS" }
            if age >= 34 && status == "IN_PROGRESS" { status = "COMPLETED" }
        }
        ride?.status = status
        var row: [String: Any] = ["id": r.id, "type": "RIDE", "requester_id": "me", "vehicle_kind": r.kind, "pickup_label": r.pickupLabel, "drop_label": r.dropLabel, "km": r.km, "fare": r.fare, "pin": "4321",
                                  "status": r.cancelled ? "CANCELLED" : status, "created_at": iso(r.created), "status_at": iso(Date()),
                                  "pickup_lat": home.lat, "pickup_lng": home.lng, "drop_lat": r.dropLat, "drop_lng": r.dropLng, "pin_attempts": 0]
        if status != "SEARCHING" {
            row["driver_id"] = "d1"
            let t = min(1.0, max(0, (age - 4) / 8)); row["driver_lat"] = home.lat + 0.012 * (1 - t); row["driver_lng"] = home.lng + 0.01 * (1 - t)
            if status == "IN_PROGRESS" { let p = min(1.0, (age - 20) / 14); row["driver_lat"] = home.lat + (r.dropLat - home.lat) * p; row["driver_lng"] = home.lng + (r.dropLng - home.lng) * p }
            if status == "COMPLETED" || status == "PAID" { row["driver_lat"] = r.dropLat; row["driver_lng"] = r.dropLng }
        }
        if let p = r.paidWith { row["paid_with"] = p }
        return row
    }
    static func jobGeo(_ j: Job) -> [String: Any] {
        var status = j.status
        if status == "COMPLETED", !j.paid, let c = j.completedAt, Date().timeIntervalSince(c) > 6 { job?.paid = true }
        if job?.paid == true, status == "COMPLETED" { status = "PAID" }
        var row: [String: Any] = ["id": j.id, "type": "RIDE", "requester_id": "u9", "vehicle_kind": "AUTO", "pickup_label": "Indiranagar 100 ft Rd", "drop_label": "MG Road", "km": 3.4, "fare": 61, "pin": "",
                                  "status": status, "created_at": iso(Date()), "status_at": iso(Date()), "pickup_lat": home.lat + 0.004, "pickup_lng": home.lng + 0.004, "drop_lat": 12.9757, "drop_lng": 77.6063, "pin_attempts": j.attempts]
        if let d = j.driverId { row["driver_id"] = d }
        if status == "PAID" { row["paid_with"] = "UPI" }
        return row
    }
    static func iso(_ d: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: d) }

    // MARK: routing
    static func handle(method: String, path: String, query: String, params: [String: Any]) -> (Int, Any) {
        func filter(_ col: String) -> String? { query.components(separatedBy: "&").first { $0.hasPrefix(col + "=eq.") }.map { String($0.dropFirst(col.count + 4)) } }
        if path.hasPrefix("/storage/") { return (200, ["Key": "ok", "signedURL": "/object/sign/docs/x?token=1"]) }
        if path.hasPrefix("/functions/") { return (200, [:]) }
        for h in areaHandlers { if let r = h(method, path, query, params) { return r } }
        switch (method, path) {
        case ("POST", "/rest/v1/rpc/ensure_profile"): if profileName.isEmpty, let n = params["p_name"] as? String { profileName = n }; return (200, profile)
        case (_, "/rest/v1/profiles"):
            if method == "PATCH" { profileName = params["name"] as? String ?? profileName; profileArea = params["area"] as? String ?? profileArea; return (204, [:]) }
            if let ids = query.range(of: "id=in."), query[ids.upperBound...].contains("u9") { return (200, [["id": "u9", "short_code": "CU0009", "name": "Meera Shah", "trust_up": 4, "trust_down": 0]]) }
            return (200, [profile])
        case ("GET", "/rest/v1/settings"): return (200, [["key": "ring_window_seconds", "value": 180]])
        case ("GET", "/rest/v1/vehicles"): return (200, vehicles)
        case ("POST", "/rest/v1/vehicles"):
            var v = params; v["id"] = "v\(vehicles.count + 1)"; v["status"] = "PENDING"; v["docs"] = []; vehicles.append(v); return (201, [v])
        case ("PATCH", "/rest/v1/vehicles"): return (204, [:])
        case ("DELETE", "/rest/v1/vehicles"): return (204, [:])
        case ("GET", "/rest/v1/vehicle_stats"): return (200, [["vehicle_id": "v1", "plate": "KA05AB1234", "model": "Bajaj RE", "kind": "AUTO", "accepted": 18, "rejected": 3, "completed": 17, "km": 96.4, "earnings": 2140]])
        case ("GET", "/rest/v1/vehicle_members"): return (200, [["vehicle_id": "v1", "profile_id": "me", "role": "OWNER"]])
        case ("GET", "/rest/v1/invites"): return (200, [])
        case ("POST", "/rest/v1/driver_presence"), ("PATCH", "/rest/v1/driver_presence"):
            if method == "POST" { if params["online"] as? Bool == true { if driverOnlineSince == nil { driverOnlineSince = Date() } } else { driverOnlineSince = nil; job = nil } }
            return (204, [:])
        case ("POST", "/rest/v1/rpc/update_location"): return (204, [:])
        case ("GET", "/rest/v1/profile_private"): return (200, [["profile_id": "me", "upi_uri": upi as Any? ?? NSNull()]])
        case ("PATCH", "/rest/v1/profile_private"): upi = params["upi_uri"] as? String; return (204, [:])
        case ("POST", "/rest/v1/rpc/online_drivers_near"):
            return (200, [["profile_id": "d1", "kind": "AUTO", "lat": home.lat + 0.006, "lng": home.lng - 0.004, "name": "Ravi Kumar", "model": "Bajaj RE", "plate": "KA05AB1234", "up": 41, "down": 2],
                          ["profile_id": "d2", "kind": "AUTO", "lat": home.lat - 0.008, "lng": home.lng + 0.006, "name": "Imran S", "model": "TVS King", "plate": "KA03CD9876", "up": 12, "down": 0],
                          ["profile_id": "d3", "kind": "CAB", "lat": home.lat + 0.01, "lng": home.lng + 0.012, "name": "Divya N", "model": "Maruti Dzire", "plate": "KA01XY1122", "up": 77, "down": 3]])
        // ---- rider
        case ("POST", "/rest/v1/rpc/request_ride"):
            var r = Ride(); r.kind = params["p_kind"] as? String ?? "AUTO"; r.km = params["p_km"] as? Double ?? 5.2; r.fare = params["p_fare"] as? Int ?? 82
            r.pickupLabel = params["p_pickup_label"] as? String ?? ""; r.dropLabel = params["p_drop_label"] as? String ?? ""; r.dropLat = params["d_lat"] as? Double ?? r.dropLat; r.dropLng = params["d_lng"] as? Double ?? r.dropLng
            ride = r
            return (200, taskRow(from: rideGeo(r)))
        case ("GET", "/rest/v1/tasks_geo"):
            let id = filter("id")
            if id == ride?.id, let r = ride { return (200, [rideGeo(r)]) }
            if id == job?.id, let j = job { return (200, [jobGeo(j)]) }
            return (200, [])
        case ("POST", "/rest/v1/rpc/my_open_task"):
            if let r = ride, !r.cancelled, r.status != "PAID" { return (200, [rideGeo(r)]) }
            if let j = job, j.driverId != nil, !j.paid { return (200, [jobGeo(j)]) }
            return (200, [])
        case ("POST", "/rest/v1/rpc/task_driver"): return (200, [driverRow])
        case ("POST", "/rest/v1/rpc/contact_for_task"): return (200, [["phone": "9845012345", "upi_uri": upi as Any? ?? NSNull()]])
        case ("POST", "/rest/v1/rpc/review"): return (204, [:])
        // ---- driver
        case ("POST", "/rest/v1/rpc/open_tasks_near"):
            if let since = driverOnlineSince, Date().timeIntervalSince(since) > 4, job == nil || job?.status == "SEARCHING" { if job == nil { job = Job() }; return (200, [taskRow(from: jobGeo(job!))]) }
            return (200, [])
        case ("POST", "/rest/v1/rpc/claim_task"): job?.status = "MATCHED"; job?.driverId = "me"; return (200, true)
        case ("POST", "/rest/v1/rpc/pass_task"): job = nil; return (204, [:])
        case ("POST", "/rest/v1/rpc/advance_task"):
            let id = params["p_task"] as? String, to = params["p_status"] as? String ?? ""
            if id == ride?.id {
                if to == "CANCELLED" { ride?.cancelled = true } else if to == "PAID" { ride?.status = "PAID"; ride?.paidWith = params["p_paid_with"] as? String } else if to == "NO_DRIVER" { ride?.status = "NO_DRIVER" }
                return (200, taskRow(from: rideGeo(ride!)))
            }
            if id == job?.id {
                switch to {
                case "ARRIVED": job?.status = "ARRIVED"
                case "IN_PROGRESS": if (params["p_pin"] as? String) == "4321" { job?.status = "IN_PROGRESS" } else { job?.attempts += 1 }
                case "COMPLETED": job?.status = "COMPLETED"; job?.completedAt = Date()
                case "SEARCHING": job = Job()
                default: break }
                return (200, taskRow(from: jobGeo(job ?? Job())))
            }
            return (400, ["message": "unknown task"])
        default: return (404, ["message": "fake: no route for \(method) \(path)"])
        }
    }
    /// The plain `tasks` row (no coordinates).
    static func taskRow(from geo: [String: Any]) -> [String: Any] {
        var r = geo; for k in ["pickup_lat", "pickup_lng", "drop_lat", "drop_lng", "driver_lat", "driver_lng"] { r.removeValue(forKey: k) }; return r
    }
}
#endif
