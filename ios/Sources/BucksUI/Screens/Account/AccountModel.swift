import SwiftUI
import BucksCore

/// What the Account tab shows beyond the session: my ride and order history, how many people I'm synced with, and whether I'm staff.
/// Loaded straight from Supabase when the tab opens; a failed load leaves the last list in place.
@MainActor @Observable
final class AccountModel {
    var rides: [TaskRow] = []
    var orders: [OrderRow] = []
    var ordersLoaded = false
    var titles: [String: String] = [:]
    var syncedCount = 0
    var isStaff = false

    func titleOf(_ listingId: String) -> String { titles[listingId] ?? "Shop" }

    func loadActivity(me: String) async {
        if let r = try? await Backend.shared.accountMyRides(me: me) { rides = r }
        if let o = try? await Backend.shared.accountMyOrders(me: me) {
            orders = o; ordersLoaded = true
            let missing = Array(Set(o.map(\.listingId)).filter { titles[$0] == nil })
            if let t = try? await Backend.shared.accountListingTitles(missing) { titles.merge(t) { $1 } }
        }
    }
    func loadSynced() async { if let n = try? await Backend.shared.accountSyncedCount() { syncedCount = n } }
    func loadStaff() async { isStaff = (try? await Backend.shared.accountIsStaff()) ?? false }
}
