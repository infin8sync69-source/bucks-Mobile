import SwiftUI
import BucksCore

/// Every order I placed, newest first, with the shop's name, what I paid in all (shop and rider) and where it stands.
struct MyOrdersScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    private var commerce: CommerceStore { session.commerce }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "My orders", onBack: { router.pop() }) {
                    Button { commerce.refreshMyOrders() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Refresh")
                }
                if !commerce.myOrdersLoaded {
                    BucksLoader().frame(maxWidth: .infinity).padding(.top, 80)
                } else if commerce.myOrders.isEmpty {
                    empty
                } else {
                    list
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        // Refresh on open and every 15 seconds while the list is showing, so an accept or delivery shows up without a tap.
        .task {
            while !Task.isCancelled {
                commerce.refreshMyOrders()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Avatar(systemImage: "bag.fill", size: 72)
            Text("No orders yet").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 16)
            Muted("Search for groceries, food or anything nearby, open a shop and tap Add. Your orders will show up here.", align: .center).padding(.top, 6)
            SmallButton("Find a shop") { router.pop() }.fixedSize().padding(.top, 18)
        }
        .frame(maxWidth: .infinity).padding(Gutter).padding(.top, 60)
    }

    private var list: some View {
        let live = commerce.myOrders.filter { orderLive($0.status) }
        let past = commerce.myOrders.filter { !orderLive($0.status) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !live.isEmpty { SectionTitle("In progress").padding(.horizontal, Gutter).padding(.top, 8).padding(.bottom, 4) }
                ForEach(live) { row($0) }
                if !past.isEmpty { SectionTitle("Earlier").padding(.horizontal, Gutter).padding(.top, 16).padding(.bottom, 4) }
                ForEach(past) { row($0) }
                Spacer().frame(height: 24)
            }
        }
    }

    private func row(_ o: OrderRow) -> some View {
        VStack(spacing: 0) {
            ListRow(commerce.titleOf(o.listingId), subtitle: "\(orderAgo(o.createdAt)) · \(deliveryModeLabel(o.deliveryMode)) · \(shortOrderId(o.id))", onTap: { router.push(.order(o.id)) }) {
                Avatar(systemImage: "storefront.fill", tinted: false)
            } trailing: {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rupees(buyerTotal(o.subtotal, o.deliveryFee, o.feePaidBy))).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    OrderStatusPill(o.status, o.deliveryMode)
                }
            }
            BucksDivider()
        }
    }
}
