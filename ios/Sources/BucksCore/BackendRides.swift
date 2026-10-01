import Foundation

/// The calls the taxi flow makes, named and shaped as in Backend.kt / BackendDispatch.kt.
extension Backend {
    // MARK: people

    public func ensureProfile(name: String, phone: String?) async throws -> ProfileRow {
        try await rpc("ensure_profile", ["p_name": name, "p_phone": phone])
    }
    /// The columns the API may read from profiles; `home` is withheld, so `select *` would be refused.
    private static let profileColumns = "id,short_code,name,bio,area,photo_url,trust_up,trust_down,id_issued_at"
    public func profiles(_ ids: [String]) async throws -> [ProfileRow] {
        ids.isEmpty ? [] : try await select("profiles", columns: Self.profileColumns, filters: [.isIn("id", ids)])
    }
    public func updateProfile(id: String, name: String, bio: String, area: String, home: LatLng?) async throws {
        var v: [String: Any?] = ["name": name, "bio": bio, "area": area]
        if let home { v["home"] = Backend.point(home) }
        try await update("profiles", v, filters: [.eq("id", id)])
    }

    // MARK: vehicles and presence

    public func myVehicles() async throws -> [VehicleRow] { try await select("vehicles") }
    public func vehicleStats() async throws -> [VehicleStat] { try await select("vehicle_stats") }
    public func setPresence(me: String, vehicleId: String, kind: String, online: Bool, at: LatLng?) async throws {
        var row: [String: Any?] = ["profile_id": me, "vehicle_id": vehicleId, "kind": kind, "online": online]
        if let at { row["location"] = Backend.point(at) }
        try await upsert("driver_presence", row)
    }
    /// Presence off by profile, without needing the vehicle (the presence row is the driver's own).
    public func setOffline(me: String) async throws { try await update("driver_presence", ["online": false], filters: [.eq("profile_id", me)]) }
    public func updateLocation(_ at: LatLng) async throws { try await rpcVoid("update_location", ["lat": at.lat, "lng": at.lng]) }

    // MARK: tasks

    public func requestRide(kind: VehicleKind, from: LatLng, fromLabel: String, to: LatLng, toLabel: String, km: Double, fare: Int) async throws -> TaskRow {
        try await rpc("request_ride", ["p_kind": kind.rawValue, "p_lat": from.lat, "p_lng": from.lng, "p_pickup_label": fromLabel,
                                       "d_lat": to.lat, "d_lng": to.lng, "p_drop_label": toLabel, "p_km": km, "p_fare": fare])
    }
    public func openTasksNear(_ at: LatLng) async throws -> [TaskRow] { try await rpcList("open_tasks_near", ["lat": at.lat, "lng": at.lng]) }
    public func claimTask(_ id: String) async throws -> Bool { try await rpc("claim_task", ["p_task": id]) }
    public func passTask(_ id: String, missed: Bool) async throws { try await rpcVoid("pass_task", ["p_task": id, "p_missed": missed]) }
    public func advanceTask(_ id: String, status: String, pin: String? = nil, paidWith: String? = nil) async throws -> TaskRow {
        try await rpc("advance_task", ["p_task": id, "p_status": status, "p_pin": pin, "p_paid_with": paidWith])
    }
    /// Through the `tasks_geo` view: `tasks.pin` is withheld from the API, so `select *` on the table is refused.
    public func taskGeo(_ id: String) async throws -> TaskGeoRow? { try await selectOne("tasks_geo", filters: [.eq("id", id)]) }
    /// The caller's active task as requester or driver, or nil.
    public func myOpenTask() async throws -> TaskGeoRow? { (try await rpcList("my_open_task") as [TaskGeoRow]).first }
    public func onlineDriversNear(_ at: LatLng, radiusM: Int = 5000) async throws -> [NearDriverRow] {
        try await rpcList("online_drivers_near", ["p_lat": at.lat, "p_lng": at.lng, "radius_m": radiusM])
    }
    public func taskDriver(_ taskId: String) async throws -> TaskDriverRow? { (try await rpcList("task_driver", ["p_task": taskId]) as [TaskDriverRow]).first }
    public func contactFor(_ taskId: String) async throws -> ContactRow? { (try await rpcList("contact_for_task", ["p_task": taskId]) as [ContactRow]).first }
    /// A number from the server's settings table (readable by every signed-in user); nil when missing or unreadable.
    public func settingValue(_ key: String) async throws -> Double? { (try await select("settings", filters: [.eq("key", key)]) as [SettingRow]).first?.value }

    // MARK: reviews, payment link, account

    public func review(listingId: String, taskId: String?, orderId: String?, up: Bool, comment: String) async throws {
        try await rpcVoid("review", ["p_listing": listingId, "p_task": taskId, "p_order": orderId, "p_vote": up ? 1 : -1, "p_comment": comment])
    }
    public func myPaymentLink(me: String) async throws -> String? {
        let row: PrivateRow? = try await selectOne("profile_private", filters: [.eq("profile_id", me)])
        return row?.upiUri.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    public func setPaymentLink(profileId: String, upiUri: String) async throws { try await update("profile_private", ["upi_uri": upiUri], filters: [.eq("profile_id", profileId)]) }
    public func clearPaymentLink(me: String) async throws { try await update("profile_private", ["upi_uri": nil], filters: [.eq("profile_id", me)]) }
    /// Account deletion on the server: presence off, open tasks cancelled or handed back, phone and UPI link deleted, profile anonymised.
    public func deleteMyAccount() async throws { try await rpcVoid("delete_my_account") }
}
