import SwiftUI
import BucksCore

/// The status pill for a vehicle: Active, Suspended, or still being checked.
private func statusPill(_ v: VehicleRow) -> Pill {
    switch v.status { case "ACTIVE": PillGood("Active"); case "SUSPENDED": PillBad("Suspended"); default: PillWarn("Documents being checked") }
}

private struct DriversTarget: Hashable, Identifiable { let id: String }

/// Vehicles I own or drive: status, who drives them, and the owner dashboard.
struct VehiclesScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = VehicleStore()
    @State private var driversFor: DriversTarget?

    var body: some View {
        VStack(spacing: 0) {
            ContentColumn {
                VStack(spacing: 0) {
                    BucksTopBar(title: "Vehicles", onBack: { router.pop() }) {
                        IconAction("chart.bar.fill", "Earnings and trips") { router.push(.vehicleStats) }
                    }
                    if store.loading && !store.loaded { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary) }
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if let err = store.error, !store.loaded, store.vehicles.isEmpty { LoadError(err) { Task { await store.refresh() } } }
                            if store.vehicles.isEmpty && store.loaded {
                                BucksCard {
                                    Text("No vehicles yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                    Muted("Add the bike, auto or cab you drive with its RC, insurance and permit photos. Bucks checks them, then you can go online and take rides or deliveries. You can also invite other drivers to use your vehicle.").padding(.top, 4)
                                }
                            }
                            ForEach(store.vehicles) { v in vehicleCard(v) }
                            if !store.vehicles.isEmpty { GhostButton("Earnings and trips") { router.push(.vehicleStats) } }
                        }.padding(Gutter)
                    }
                }
            }
            PrimaryButton("Add vehicle") { router.push(.vehicleEdit(nil)) }.padding(.horizontal, Gutter).padding(.vertical, 12)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { await store.refresh() }
        .navigationDestination(item: $driversFor) { VehicleDriversScreen(vehicleId: $0.id) }
    }

    private func vehicleCard(_ v: VehicleRow) -> some View {
        let owner = v.ownerId == session.me?.id
        let docs = store.docs[v.id] ?? []
        return BucksCard {
            HStack(alignment: .top, spacing: 14) {
                Avatar(systemImage: vehicleSymbol(v.kind), size: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(v.model.isEmpty ? vehicleKindLabel(v.kind) : v.model).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted("\(vehicleKindLabel(v.kind)) · \(v.plate)")
                    HStack(spacing: 6) { statusPill(v); if !owner { PillGrey("Driver") } }.padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Muted(guidance(v, owner: owner, docs: docs)).padding(.top, 10)
            Muted(peopleLine(v)).padding(.top, 4)
            HStack(spacing: 8) {
                if owner { SmallButton("Edit", tonal: true) { router.push(.vehicleEdit(v.id)) } }
                SmallButton("Drivers", tonal: true) { driversFor = DriversTarget(id: v.id) }
            }.padding(.top, 12)
        }
    }

    private func guidance(_ v: VehicleRow, owner: Bool, docs: [VehicleDoc]) -> String {
        switch v.status {
        case "ACTIVE": return "Ready. Go online from Home to take " + (v.kind == "BIKE" ? "deliveries." : "rides and deliveries.")
        case "SUSPENDED": return "Suspended: it can't go online. Contact Bucks support."
        default:
            let missing = vehicleDocKinds(v.kind).filter { dk in dk.required && !docs.contains { $0.kind == dk.key } }
            if owner && !missing.isEmpty { return "Still needed: \(missing.map(\.label).joined(separator: ", ")). Bucks checks them before the vehicle can go online." }
            return "Bucks is checking the documents. You'll be able to go online once it's active."
        }
    }
    private func peopleLine(_ v: VehicleRow) -> String {
        guard let n = store.members[v.id] else { return "…" }
        return n <= 1 ? "Only you drive it" : "\(n) people can drive it"
    }
}

/// Owner dashboard: per vehicle, the last 30 days from the vehicle_stats view.
struct VehicleStatsScreen: View {
    @Environment(Router.self) private var router
    @State private var store = VehicleStore()

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Earnings and trips", onBack: { router.pop() })
                ScrollView {
                    LazyVStack(spacing: 12) {
                        let rows = store.stats
                        BucksCard(tint: true) {
                            Muted("Last 30 days, all vehicles")
                            Text("₹\(rows.reduce(0) { $0 + $1.earnings })").bucks(.displaySmall).foregroundStyle(BucksColor.onSurface)
                            Muted("\(rows.reduce(0) { $0 + $1.completed }) trips completed · \(String(format: "%.1f", rows.reduce(0) { $0 + $1.km })) km")
                        }
                        if rows.isEmpty {
                            let none = store.loaded && store.vehicles.isEmpty
                            BucksCard {
                                Text(none ? "No vehicles yet" : "Nothing to show yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted(none ? "Add a vehicle under Vehicles. Once it's active and online, every ride and delivery lands here." : "Trips taken with your vehicles in the last 30 days appear here: accepted, missed, completed, distance and fares.").padding(.top, 4)
                            }
                        }
                        ForEach(rows) { s in statCard(s) }
                    }.padding(Gutter)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await store.refreshStats(); if !store.loaded { await store.refresh() } }
    }

    private func statCard(_ s: VehicleStat) -> some View {
        BucksCard {
            HStack(spacing: 12) {
                Avatar(systemImage: vehicleSymbol(s.kind), size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.model.isEmpty ? vehicleKindLabel(s.kind) : s.model).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted(s.plate)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("₹\(s.earnings)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
            }
            HStack {
                stat("\(s.accepted)", "Accepted"); stat("\(s.rejected)", "Missed"); stat("\(s.completed)", "Completed"); stat(String(format: "%.1f", s.km), "km")
            }.padding(.top, 14)
            if s.accepted + s.rejected > 0 && s.rejected > s.accepted {
                Muted("More requests missed than accepted. Staying online only when you're free keeps your acceptance up.").padding(.top, 10)
            }
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) { Text(value).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface); Muted(label, align: .center) }.frame(maxWidth: .infinity)
    }
}
