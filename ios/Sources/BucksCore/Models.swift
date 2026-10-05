import Foundation

// Rows are named as in supabase/schema.sql; the JSON decoder maps snake_case keys to camelCase properties.
// Every row decodes missing optional columns to the same defaults the Kotlin data classes use.

public enum VehicleKind: String, CaseIterable, Codable, Sendable {
    case bike = "BIKE", auto = "AUTO", cab = "CAB"
    public var label: String { switch self { case .bike: "Bike"; case .auto: "Auto"; case .cab: "Cab" } }
    public var farePerKm: Int { switch self { case .bike: 8; case .auto: 12; case .cab: 18 } }
    /// Bikes carry goods only (pick-up and delivery), never passengers.
    public var carriesPassengers: Bool { self != .bike }
    public var maxPassengers: Int { switch self { case .bike: 1; case .auto: 3; case .cab: 4 } }
    public var systemImage: String { switch self { case .bike: "bicycle"; case .auto: "car.side"; case .cab: "car.fill" } }
    public static var passenger: [VehicleKind] { allCases.filter(\.carriesPassengers) }
    /// Unknown server values fall back to an auto, as Android does.
    public init(serverValue: String) { self = VehicleKind(rawValue: serverValue) ?? .auto }
}

public struct Trust: Hashable, Sendable {
    public var up: Int, down: Int
    public init(up: Int, down: Int) { self.up = up; self.down = down }
    public var total: Int { up + down }
    public var pct: Int? { total == 0 ? nil : up * 100 / total }
}

public struct ProfileRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var shortCode: String
    public var name: String
    public var bio: String
    public var area: String
    public var photoUrl: String?
    public var trustUp: Int
    public var trustDown: Int
    /// When the current Bucks ID card was issued; valid for a year.
    public var idIssuedAt: String?
    public init(id: String, shortCode: String, name: String = "", bio: String = "", area: String = "", photoUrl: String? = nil, trustUp: Int = 0, trustDown: Int = 0, idIssuedAt: String? = nil) {
        self.id = id; self.shortCode = shortCode; self.name = name; self.bio = bio; self.area = area; self.photoUrl = photoUrl; self.trustUp = trustUp; self.trustDown = trustDown; self.idIssuedAt = idIssuedAt
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); shortCode = try c.decodeIfPresent(String.self, forKey: .shortCode) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""; bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""; area = try c.decodeIfPresent(String.self, forKey: .area) ?? ""
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl); trustUp = try c.decodeIfPresent(Int.self, forKey: .trustUp) ?? 0; trustDown = try c.decodeIfPresent(Int.self, forKey: .trustDown) ?? 0
        idIssuedAt = try c.decodeIfPresent(String.self, forKey: .idIssuedAt)
    }
    private enum Keys: String, CodingKey { case id, shortCode, name, bio, area, photoUrl, trustUp, trustDown, idIssuedAt }
    public var trust: Trust { Trust(up: trustUp, down: trustDown) }
}

public struct VehicleRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ownerId: String
    public var kind: String
    public var model: String
    public var plate: String
    /// PENDING until staff approve the documents and enough locals recommend, then ACTIVE (or SUSPENDED).
    public var status: String
    public init(id: String, ownerId: String, kind: String, model: String = "", plate: String, status: String = "PENDING") {
        self.id = id; self.ownerId = ownerId; self.kind = kind; self.model = model; self.plate = plate; self.status = status
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); ownerId = try c.decode(String.self, forKey: .ownerId); kind = try c.decode(String.self, forKey: .kind)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""; plate = try c.decode(String.self, forKey: .plate); status = try c.decodeIfPresent(String.self, forKey: .status) ?? "PENDING"
    }
    private enum Keys: String, CodingKey { case id, ownerId, kind, model, plate, status }
    public var vehicleKind: VehicleKind { VehicleKind(serverValue: kind) }
}

public struct VehicleStat: Codable, Hashable, Sendable, Identifiable {
    public var vehicleId: String
    public var plate: String
    public var model: String
    public var kind: String
    public var accepted: Int
    public var rejected: Int
    public var completed: Int
    public var km: Double
    public var earnings: Int
    public var id: String { vehicleId }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        vehicleId = try c.decode(String.self, forKey: .vehicleId); plate = try c.decode(String.self, forKey: .plate); model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        kind = try c.decode(String.self, forKey: .kind); accepted = try c.decodeIfPresent(Int.self, forKey: .accepted) ?? 0; rejected = try c.decodeIfPresent(Int.self, forKey: .rejected) ?? 0
        completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0; km = try c.decodeIfPresent(Double.self, forKey: .km) ?? 0; earnings = try c.decodeIfPresent(Int.self, forKey: .earnings) ?? 0
    }
    private enum Keys: String, CodingKey { case vehicleId, plate, model, kind, accepted, rejected, completed, km, earnings }
}

/// A task (ride or delivery) as the plain table row; `pin` is withheld from the table, so reads go through `tasks_geo` ([TaskGeoRow]).
public struct TaskRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var requesterId: String
    public var orderId: String?
    public var vehicleKind: String
    public var pickupLabel: String
    public var dropLabel: String
    public var km: Double
    public var fare: Int
    public var pin: String
    public var status: String
    public var driverId: String?
    public var paidWith: String?
    /// Wrong PINs the driver has tried (5 lock the trip); 0 until the server counts them.
    public var pinAttempts: Int
    public var createdAt: String
    public var statusAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); type = try c.decode(String.self, forKey: .type); requesterId = try c.decode(String.self, forKey: .requesterId)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId); vehicleKind = try c.decode(String.self, forKey: .vehicleKind)
        pickupLabel = try c.decodeIfPresent(String.self, forKey: .pickupLabel) ?? ""; dropLabel = try c.decodeIfPresent(String.self, forKey: .dropLabel) ?? ""
        km = try c.decodeIfPresent(Double.self, forKey: .km) ?? 0; fare = try c.decodeIfPresent(Int.self, forKey: .fare) ?? 0; pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? ""
        status = try c.decode(String.self, forKey: .status); driverId = try c.decodeIfPresent(String.self, forKey: .driverId); paidWith = try c.decodeIfPresent(String.self, forKey: .paidWith)
        pinAttempts = try c.decodeIfPresent(Int.self, forKey: .pinAttempts) ?? 0; createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""; statusAt = try c.decodeIfPresent(String.self, forKey: .statusAt) ?? ""
    }
    private enum Keys: String, CodingKey { case id, type, requesterId, orderId, vehicleKind, pickupLabel, dropLabel, km, fare, pin, status, driverId, paidWith, pinAttempts, createdAt, statusAt }
}

/// A task with its points as lat/lng (view `tasks_geo`). `pin` is only filled for the requester; `statusAt` is when the status last changed.
public struct TaskGeoRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var requesterId: String
    public var orderId: String?
    public var vehicleKind: String
    public var pickupLabel: String
    public var dropLabel: String
    public var km: Double
    public var fare: Int
    public var pin: String
    public var status: String
    public var driverId: String?
    public var vehicleId: String?
    public var paidWith: String?
    public var createdAt: String
    public var statusAt: String
    public var pickupLat: Double, pickupLng: Double, dropLat: Double, dropLng: Double
    public var driverLat: Double?, driverLng: Double?
    public var orderItems: Int?
    /// Delivery only: what the rider takes from the buyer at the door (0 = nothing); nil when not readable yet.
    public var collect: Int?
    public var pinAttempts: Int
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); type = try c.decode(String.self, forKey: .type); requesterId = try c.decode(String.self, forKey: .requesterId)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId); vehicleKind = try c.decode(String.self, forKey: .vehicleKind)
        pickupLabel = try c.decodeIfPresent(String.self, forKey: .pickupLabel) ?? ""; dropLabel = try c.decodeIfPresent(String.self, forKey: .dropLabel) ?? ""
        km = try c.decodeIfPresent(Double.self, forKey: .km) ?? 0; fare = try c.decodeIfPresent(Int.self, forKey: .fare) ?? 0; pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? ""
        status = try c.decode(String.self, forKey: .status); driverId = try c.decodeIfPresent(String.self, forKey: .driverId); vehicleId = try c.decodeIfPresent(String.self, forKey: .vehicleId)
        paidWith = try c.decodeIfPresent(String.self, forKey: .paidWith); createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""; statusAt = try c.decodeIfPresent(String.self, forKey: .statusAt) ?? ""
        pickupLat = try c.decode(Double.self, forKey: .pickupLat); pickupLng = try c.decode(Double.self, forKey: .pickupLng); dropLat = try c.decode(Double.self, forKey: .dropLat); dropLng = try c.decode(Double.self, forKey: .dropLng)
        driverLat = try c.decodeIfPresent(Double.self, forKey: .driverLat); driverLng = try c.decodeIfPresent(Double.self, forKey: .driverLng)
        orderItems = try c.decodeIfPresent(Int.self, forKey: .orderItems); collect = try c.decodeIfPresent(Int.self, forKey: .collect); pinAttempts = try c.decodeIfPresent(Int.self, forKey: .pinAttempts) ?? 0
    }
    private enum Keys: String, CodingKey { case id, type, requesterId, orderId, vehicleKind, pickupLabel, dropLabel, km, fare, pin, status, driverId, vehicleId, paidWith, createdAt, statusAt, pickupLat, pickupLng, dropLat, dropLng, driverLat, driverLng, orderItems, collect, pinAttempts }
    public var pickup: LatLng { LatLng(pickupLat, pickupLng) }
    public var drop: LatLng { LatLng(dropLat, dropLng) }
    public var driverAt: LatLng? { if let la = driverLat, let ln = driverLng { return LatLng(la, ln) } else { return nil } }
    public var isDelivery: Bool { type == "DELIVERY" }
}

/// An online driver near a point (`online_drivers_near`). Trust comes from their DRIVER listing, 0/0 without one.
public struct NearDriverRow: Codable, Hashable, Sendable {
    public var profileId: String
    public var kind: String
    public var lat: Double, lng: Double
    public var name: String, model: String, plate: String
    public var up: Int, down: Int
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        profileId = try c.decode(String.self, forKey: .profileId); kind = try c.decode(String.self, forKey: .kind); lat = try c.decode(Double.self, forKey: .lat); lng = try c.decode(Double.self, forKey: .lng)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""; model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""; plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
        up = try c.decodeIfPresent(Int.self, forKey: .up) ?? 0; down = try c.decodeIfPresent(Int.self, forKey: .down) ?? 0
    }
    private enum Keys: String, CodingKey { case profileId, kind, lat, lng, name, model, plate, up, down }
}

/// The driver of a task as the requester may see them (`task_driver`); `listingId` is what a review goes to.
public struct TaskDriverRow: Codable, Hashable, Sendable {
    public var profileId: String
    public var name: String, kind: String, model: String, plate: String
    public var up: Int, down: Int
    public var listingId: String?
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        profileId = try c.decode(String.self, forKey: .profileId); name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""; kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "AUTO"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""; plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
        up = try c.decodeIfPresent(Int.self, forKey: .up) ?? 0; down = try c.decodeIfPresent(Int.self, forKey: .down) ?? 0; listingId = try c.decodeIfPresent(String.self, forKey: .listingId)
    }
    private enum Keys: String, CodingKey { case profileId, name, kind, model, plate, up, down, listingId }
}

public struct ContactRow: Codable, Hashable, Sendable {
    public var phone: String?
    public var upiUri: String?
}

struct PrivateRow: Codable { var profileId: String; var phone: String?; var upiUri: String? }
struct SettingRow: Codable { var key: String; var value: Double }

// MARK: - What the screens show

/// A destination. `at` is the real point; a ride is booked to it.
public struct Place: Hashable, Sendable {
    public var name: String
    public var km: Double
    public var at: LatLng
    public init(name: String, km: Double, at: LatLng) { self.name = name; self.km = km; self.at = at }
}

public enum RideStatus: String, Sendable { case searching, matched, arrived, inRide, completed, paid, noDriver, cancelled }
public enum DriverRideStatus: String, Sendable { case ringing, toPickup, arrived, inRide, done, rate }

public struct Driver: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var vehicle: VehicleKind
    public var plate: String
    public var model: String
    public var distanceKm: Double
    public var up: Int, down: Int
    public var online: Bool
    public var phone: String
    public var at: LatLng?
    public init(id: String, name: String, vehicle: VehicleKind, plate: String, model: String, distanceKm: Double, up: Int, down: Int, online: Bool, phone: String = "", at: LatLng? = nil) {
        self.id = id; self.name = name; self.vehicle = vehicle; self.plate = plate; self.model = model; self.distanceKm = distanceKm; self.up = up; self.down = down; self.online = online; self.phone = phone; self.at = at
    }
    public var trust: Trust { Trust(up: up, down: down) }
}

public struct Ride: Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: VehicleKind
    public var dest: Place
    public var fare: Int
    public var status: RideStatus
    public var pin: String
    public var driver: Driver?
    /// Minutes until pick-up: -1 means no position yet ("on the way"), 0 is "under a minute".
    public var etaMin: Int
    public var progress: Double
    public var paidWith: String?
    public var reason: String?
    /// Where the driver really is.
    public var driverAt: LatLng?
    /// Where the rider was picked up, as named when booked.
    public var pickupLabel: String
    public init(id: String, kind: VehicleKind, dest: Place, fare: Int, status: RideStatus, pin: String, driver: Driver? = nil, etaMin: Int = 0, progress: Double = 0, paidWith: String? = nil, reason: String? = nil, driverAt: LatLng? = nil, pickupLabel: String = "") {
        self.id = id; self.kind = kind; self.dest = dest; self.fare = fare; self.status = status; self.pin = pin; self.driver = driver; self.etaMin = etaMin; self.progress = progress; self.paidWith = paidWith; self.reason = reason; self.driverAt = driverAt; self.pickupLabel = pickupLabel
    }
}

public struct DriverRide: Hashable, Sendable, Identifiable {
    public var id: String
    public var status: DriverRideStatus
    public var customer: String
    public var customerTrust: Trust
    public var pickupAt: String
    public var dropAt: String
    public var km: Double
    public var fare: Int
    public var secondsLeft: Int
    public var pickupKm: Double
    public var kind: VehicleKind
    public var driver: LatLng?
    public var pickup: LatLng?
    public var drop: LatLng?
    public var progress: Double
    public var paidWith: String?
    public var customerPhone: String
    /// Wrong PINs tried at the pick-up (the server locks the trip at 5).
    public var pinAttempts: Int
    public var pinLocked: Bool
    public init(id: String, status: DriverRideStatus, customer: String, customerTrust: Trust, pickupAt: String, dropAt: String, km: Double, fare: Int, secondsLeft: Int, pickupKm: Double, kind: VehicleKind = .bike, driver: LatLng? = nil, pickup: LatLng? = nil, drop: LatLng? = nil, progress: Double = 0, paidWith: String? = nil, customerPhone: String = "", pinAttempts: Int = 0, pinLocked: Bool = false) {
        self.id = id; self.status = status; self.customer = customer; self.customerTrust = customerTrust; self.pickupAt = pickupAt; self.dropAt = dropAt; self.km = km; self.fare = fare; self.secondsLeft = secondsLeft; self.pickupKm = pickupKm
        self.kind = kind; self.driver = driver; self.pickup = pickup; self.drop = drop; self.progress = progress; self.paidWith = paidWith; self.customerPhone = customerPhone; self.pinAttempts = pinAttempts; self.pinLocked = pinLocked
    }
    /// A bike request is always a delivery: pick up at the shop, drop at the customer.
    public var isDelivery: Bool { kind == .bike }
}
