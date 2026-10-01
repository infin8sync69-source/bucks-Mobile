import SwiftUI
import BucksCore

/// A buyer following their delivery: the shop, their door and the rider's live position on the map, the status,
/// the rider's name and bike, call/message, and the 4-digit pickup PIN the rider asks for at the shop.
/// Follows the task through realtime on `tasks` with a 5-second poll of `tasks_geo` as the fallback.
struct DeliveryTrackScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var task: TaskGeoRow?
    @State private var rider: TaskDriverRow?
    @State private var phone: String?
    @State private var failed = false
    @State private var loader = RoadRouteLoader()

    init(id: String) { self.id = id }

    var body: some View {
        VStack(spacing: 0) {
            BucksTopBar(title: "Track delivery", onBack: { router.pop() })
            if let t = task {
                DeliveryBody(t: t, rider: rider, phone: phone, loader: loader,
                             onCall: { if let phone { dial(phone) } else { noPhone() } },
                             onMessage: { if let phone { sms(phone) } else { noPhone() } },
                             onDone: { router.pop() })
            } else if failed {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Couldn't load this delivery").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Check your connection and pull down, or go back to the order.").padding(.top, 6)
                        PrimaryButton("Try again") { Task { await refresh() } }.padding(.top, 16)
                    }.padding(Gutter)
                }.frame(maxHeight: .infinity, alignment: .top)
            } else {
                BucksLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) {
            while !Task.isCancelled {
                await refresh()
                let done = ["COMPLETED", "PAID", "CANCELLED", "NO_DRIVER"].contains(task?.status ?? "")
                try? await Task.sleep(nanoseconds: done ? 30_000_000_000 : 5_000_000_000)
            }
        }
        .task(id: id) { for await _ in Backend.shared.changes(table: "tasks", filter: "id=eq.\(id)") { await refresh() } }
        .task(id: routeKey) { await loader.load(from: ends.first, to: ends.count > 1 ? ends[1] : nil) }
    }

    private func noPhone() { session.toast("The rider's number will show once they've picked up the job.") }

    private func refresh() async {
        let t: TaskGeoRow
        do { guard let row = try await session.dispatch.task(id) else { return }; t = row } catch is CancellationError { return } catch { failed = true; return }
        task = t; failed = false
        if let driver = t.driverId, rider?.profileId != driver {
            rider = try? await session.dispatch.driverOf(taskId: id); phone = nil
        }
        if t.driverId == nil { rider = nil; phone = nil }
        if t.driverId != nil, phone == nil, ["MATCHED", "ARRIVED", "IN_PROGRESS", "COMPLETED"].contains(t.status) {
            phone = (try? await session.dispatch.contact(taskId: id))?.phone
        }
    }

    /// The two ends of the road shown on the map for the current stage.
    private var ends: [LatLng] {
        guard let t = task else { return [] }
        switch t.status {
        case "MATCHED": return [t.driverAt, t.pickup].compactMap { $0 }
        case "IN_PROGRESS": return [t.driverAt ?? t.pickup, t.drop]
        default: return [t.pickup, t.drop]
        }
    }
    private var routeKey: RouteKey { RouteKey(ends.first, ends.count > 1 ? ends[1] : nil) }
}

private struct DeliveryBody: View {
    let t: TaskGeoRow
    let rider: TaskDriverRow?
    let phone: String?
    let loader: RoadRouteLoader
    let onCall: () -> Void
    let onMessage: () -> Void
    let onDone: () -> Void
    @Environment(AppSession.self) private var session

    private var shop: LatLng { t.pickup }
    private var door: LatLng { t.drop }
    private var at: LatLng? { t.driverAt }
    private var moving: Bool { ["MATCHED", "ARRIVED", "IN_PROGRESS"].contains(t.status) }
    private var shopName: String { t.pickupLabel.isEmpty ? "the shop" : t.pickupLabel }
    /// open_tasks_near stops ringing a task once the ring window has passed since it started searching (created, or handed back by a rider);
    /// past that, "finding a rider" would be a lie.
    private var stale: Bool { t.status == "SEARCHING" && (secondsSince(t.statusAt.isEmpty ? t.createdAt : t.statusAt) ?? 0) >= session.dispatch.ringWindowS }

    private var ends: [LatLng] {
        switch t.status {
        case "MATCHED": return [at, shop].compactMap { $0 }
        case "IN_PROGRESS": return [at ?? shop, door]
        default: return [shop, door]
        }
    }
    private var route: [LatLng] {
        guard ends.count >= 2 else { return [] }
        return loader.route?.points ?? ends
    }
    private var pins: [MapPin] {
        var p = [MapPin(id: "door", at: door, title: "You", tint: BucksColor.primary, isMe: true),
                 MapPin(id: "shop", at: shop, title: t.pickupLabel.isEmpty ? "Shop" : t.pickupLabel, tint: BucksColor.bad)]
        if moving, let at { p.append(MapPin(id: "rider", at: at, title: rider?.name.components(separatedBy: " ").first.flatMap { $0.isEmpty ? nil : $0 } ?? "Rider", tint: BucksColor.good)) }
        return p
    }

    private var texts: (String, String) {
        switch t.status {
        case "SEARCHING":
            return stale ? ("No rider yet", "Nobody nearby took it in time. Message the shop: they can send their own rider or refund you.")
                         : ("Finding a rider", "Bikes near \(shopName) are being rung. The first to accept collects your order.")
        case "MATCHED": return ("Rider on the way to the shop", at.map { String(format: "%.1f km from %@", Geo.distanceKm($0, shop), shopName) } ?? "Heading to \(shopName)")
        case "ARRIVED": return ("Rider is at the shop", "They'll call you for the pickup PIN below, then bring your order.")
        case "IN_PROGRESS": return ("On the way to you", at.map { String(format: "%.1f km away", Geo.distanceKm($0, door)) } ?? "Your order has left the shop")
        case "COMPLETED", "PAID": return ("Delivered", "Your order was handed over. Enjoy.")
        case "NO_DRIVER": return ("No rider was free", "Nobody nearby could take it. The shop can send its own rider or you can reorder.")
        case "CANCELLED": return ("Delivery cancelled", "This delivery was cancelled.")
        default: return (t.status, "")
        }
    }

    private var icon: String {
        switch t.status {
        case "COMPLETED", "PAID": "checkmark.circle.fill"
        case "CANCELLED", "NO_DRIVER", "SEARCHING": "nosign"
        default: "bicycle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BucksMap(pins: pins, route: route, zoomMeters: 3000)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Sheet(scrollable: true) { panel }.frame(maxHeight: 460)
        }
    }

    @ViewBuilder private var panel: some View {
        let (headline, detail) = texts
        HStack(spacing: 12) {
            if t.status == "SEARCHING" && !stale {
                PulseRings { Image(systemName: "bicycle").font(.system(size: 22)).foregroundStyle(BucksColor.primary) }.frame(width: 48, height: 48)
            } else {
                Avatar(systemImage: icon, size: 48)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(headline).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted(detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        BucksDivider().padding(.vertical, 12)
        if let rider {
            HStack(spacing: 12) {
                Avatar(initials: initials(rider.name.isEmpty ? "R" : rider.name), size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(rider.name.isEmpty ? "Your rider" : rider.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    let bike = [rider.model, rider.plate].filter { !$0.isEmpty }.joined(separator: " · ")
                    Muted(bike.isEmpty ? "Bike" : bike)
                }.frame(maxWidth: .infinity, alignment: .leading)
                TrustBadge(up: rider.up, down: rider.down, compact: true)
            }
            if moving { MessageBar(hint: "Message your rider", onCall: onCall, onMessage: onMessage).padding(.top, 12) }
        } else if t.status == "SEARCHING" && !stale {
            Muted("Your rider's name and bike will show here once someone accepts.")
        }
        if ["SEARCHING", "MATCHED", "ARRIVED"].contains(t.status) && !stale { pinCard }
        RoutePoints(pickup: t.pickupLabel.isEmpty ? "Shop" : t.pickupLabel, drop: t.dropLabel.isEmpty ? "Your location" : t.dropLabel).padding(.top, 14)
        HStack(spacing: 20) {
            Muted("\(t.km) km"); Muted("Delivery fee ₹\(t.fare)")
            if let n = t.orderItems { Muted("\(n) item\(n == 1 ? "" : "s")") }
        }.padding(.top, 10)
        if ["COMPLETED", "PAID", "CANCELLED", "NO_DRIVER"].contains(t.status) || stale {
            PrimaryButton("Back to order", action: onDone).padding(.top, 16)
        } else {
            Muted("Keep this screen open or come back any time; it follows the rider live.", align: .center).frame(maxWidth: .infinity).padding(.top, 12)
        }
    }

    private var pinCard: some View {
        BucksCard(tint: true) {
            Text("Pickup PIN").bucks(.labelMedium).foregroundStyle(BucksColor.onPrimaryContainer)
            HStack(spacing: 6) {
                ForEach(Array(t.pin.enumerated()), id: \.offset) { _, c in
                    Text(String(c)).bucks(.titleMedium).foregroundStyle(BucksColor.onPrimary)
                        .frame(minWidth: 34, minHeight: 34).padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primary))
                }
            }.padding(.top, 6)
            Text("Your rider will call you for this PIN when collecting your order at the shop. Only share it with them.").bucks(.bodySmall)
                .foregroundStyle(BucksColor.onPrimaryContainer).padding(.top, 8)
        }.padding(.top, 14)
    }
}
