import SwiftUI
import BucksCore

/// Swarm Phase 1: "Similar shops nearby" for an order a shop turned down (order_alternatives: up to 3 other shops near the drop that
/// list the same items). Opened from the order page or the recovery notification. A tap opens the shop; ordering there is the usual
/// cart and confirm sheet. Nothing is ordered for the buyer. Same screen as Android's SimilarShopsScreen.kt.
struct SimilarShopsScreen: View {
    let orderId: String
    @Environment(Router.self) private var router
    @State private var shops: [SimilarShop]?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ContentColumn {
            VStack(alignment: .leading, spacing: 0) {
                BucksTopBar(title: "Similar shops nearby", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Muted("Other shops near you that list what you ordered. Open one to order it there.")
                        if failed {
                            Muted("Couldn't load similar shops. Check your connection.").padding(.top, 4)
                            PrimaryButton("Try again") { attempt += 1 }
                        } else if let list = shops {
                            if list.isEmpty { Muted("No other shop nearby lists these items right now.").padding(.top, 4) }
                            ForEach(list) { s in card(s) }
                        } else {
                            BucksLoader().frame(maxWidth: .infinity).padding(.top, 40)
                        }
                    }.padding(Gutter)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { _ = try? await Backend.shared.recoveryChoice(kind: Recovery.order, subject: orderId, choice: Recovery.similarShops) }
        .task(id: attempt) {
            failed = false
            do { shops = try await Backend.shared.orderAlternatives(orderId) } catch { failed = true }
        }
    }

    private func card(_ s: SimilarShop) -> some View {
        BucksCard(onTap: { router.push(.listing(s.listingId)) }) {
            HStack(spacing: 14) {
                Avatar(systemImage: "storefront.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted([s.area, formatDistance(s.distanceM)].filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
            Muted("Has: \(s.matchedItems.joined(separator: ", "))" + (s.minPrice.map { " · from \(rupees($0))" } ?? "")).padding(.top, 6)
        }
    }
}
