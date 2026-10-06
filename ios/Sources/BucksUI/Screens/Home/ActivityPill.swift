import SwiftUI
import BucksCore

// Home's activity pill (a customer's open ride or orders), the "You're offline · Go online" chip, and the online sheet's list of my live shops
// and pro profiles (port of ActivityFab.kt and the HomeScreens / DriverScreens changes).

/// Pill at the bottom-left of Home while a ride or an order is open: shows where it stands and opens it (or the list, when there are several).
struct ActivityPill: View {
    let items: [ActivityItem]
    let action: () -> Void
    var body: some View {
        if let first = items.first {
            let one = items.count == 1
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: first.systemImage).font(.system(size: 22)).foregroundStyle(BucksColor.onPrimaryContainer)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(one ? first.title : "Your activity").bucks(.labelLarge).foregroundStyle(BucksColor.onPrimaryContainer).lineLimit(1)
                        Text(one ? first.status : "\(items.count) in progress").bucks(.labelSmall).foregroundStyle(BucksColor.onPrimaryContainer).lineLimit(1)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 232, minHeight: 56, alignment: .leading)
                .background(Capsule().fill(BucksColor.primaryContainer).shadow(color: .black.opacity(0.22), radius: 6, y: 3))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .breathe(items.contains { $0.needsYou }, amount: 0.03, period: 1.2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(one ? "\(first.title): \(first.status)" : "\(items.count) things in progress")
            .accessibilityHint("See your activity")
        }
    }
}

/// Every open ride and order with its status; tap one to open it.
struct ActivitySheet: View {
    let items: [ActivityItem]
    let onOpen: (ActivityItem) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your activity").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("Tap one to see where it stands.").padding(.top, 2).padding(.bottom, 8)
                if items.isEmpty { Muted("Nothing in progress right now.").padding(.vertical, 12) }
                ForEach(items) { a in
                    Button { onOpen(a) } label: {
                        HStack(spacing: 12) {
                            ListingThumb(systemImage: a.systemImage, size: 44)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                                Muted(a.status, maxLines: 2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant)
                        }
                        .padding(.vertical, 8).frame(minHeight: 64).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(a.title): \(a.status)")
                }
            }
            .padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 24)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

/// The small chip in Home's sheet for a provider who is offline but could go online; it opens the same online sheet as the round button.
struct GoOnlineChip: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "power").font(.system(size: 13, weight: .semibold))
                Text("You're offline · Go online").font(.bucks(.labelMedium)).lineLimit(1)
            }
            .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(BucksColor.surfaceContainer))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

/// My live shops and pro profiles with a switch each (Android's OnlineSheet rows, switched with `ListingsStore.setOnline`).
struct OnlineListingRows: View {
    @Environment(AppSession.self) private var session
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.listings.listings.filter { isWorkListing($0) }) { l in
                HStack(spacing: 12) {
                    ListingThumb(systemImage: Studio.icon(l), size: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Muted(Studio.onlineLabel(l.kind, l.online))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ListingSwitch(studioSwitchBinding(l.online) { on in session.listings.setOnline(l.id, on) })
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .contain)
            }
        }
    }
}

/// The sheet behind Home's online button and the offline chip. A driver with a checked vehicle gets `OnlineSheet` (vehicle switch, earnings,
/// payment QR) with my live shops and pro profiles under it; anyone else gets just the switches.
struct HomeOnlineSheet: View {
    var onEarnings: () -> Void
    @Environment(AppSession.self) private var session

    private var hasWork: Bool { session.listings.listings.contains { isWorkListing($0) } }

    var body: some View {
        if session.dispatch.cloudVehicle != nil {
            OnlineSheet(onEarnings: onEarnings)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if hasWork {
                        VStack(alignment: .leading, spacing: 0) {
                            BucksDivider()
                            ScrollView { OnlineListingRows().padding(.vertical, 12) }.frame(maxHeight: 220)
                        }
                        .padding(.horizontal, 20).background(BucksColor.surface)
                    }
                }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.providerOnline ? "You're online" : "You're offline").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    Muted("Only online listings receive rides, orders and service requests.")
                    if hasWork { OnlineListingRows().padding(.top, 14) }
                    else if !session.listings.loaded { CenteredLoading() }
                    else { Muted("Nothing to switch on yet. Your shops and pro profiles show here once they are live.").padding(.top, 14) }
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
            }
            .background(BucksColor.surface.ignoresSafeArea())
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }
}
