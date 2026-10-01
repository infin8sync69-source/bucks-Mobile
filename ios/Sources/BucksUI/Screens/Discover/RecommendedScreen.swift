import SwiftUI
import BucksCore

private let recommendedFilters = ["All", "Food & shops", "Skills", "Riders", "Posts"]

/// The "For you" tab: people you may know, then the live shops and pros near you ranked by the reviews of people who ordered or booked.
struct RecommendedScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    @State private var filter = "All"

    private var shown: [SearchHit] {
        // Best reviewed first; the server's order breaks ties.
        let ranked = session.discover.top.enumerated().sorted { $0.element.trustUp != $1.element.trustUp ? $0.element.trustUp > $1.element.trustUp : $0.offset < $1.offset }.map(\.element)
        switch filter {
        case "Food & shops": return ranked.filter { $0.kind == "BUSINESS" }
        case "Skills": return ranked.filter { $0.kind == "SKILL" }
        case "Riders", "Posts": return []
        default: return ranked
        }
    }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "For you", onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("People near you").padding(.horizontal, Gutter).padding(.top, 8).padding(.bottom, 10)
                        people
                        VStack(alignment: .leading, spacing: 0) {
                            SectionTitle("Top rated near you")
                            Muted("Ranked by reviews from people who ordered or booked.")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) { ForEach(recommendedFilters, id: \.self) { f in BucksChip(f, selected: filter == f) { filter = f } } }
                            }.padding(.top, 12)
                        }.padding(.init(top: 24, leading: Gutter, bottom: 6, trailing: Gutter))
                        let items = shown
                        if items.isEmpty && session.discover.topLoaded {
                            Muted("No reviewed shops or pros near you yet. Search for what you need; every order or booking you review helps your neighbours.").padding(.horizontal, Gutter).padding(.vertical, 14)
                        }
                        ForEach(items) { h in
                            RecoRow(hit: h) { router.push(.listing(h.id)) }
                            BucksDivider()
                        }
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .task(id: session.me?.id) { session.discover.loadTop(); session.social.refreshSuggestions() }
    }

    @ViewBuilder private var people: some View {
        let list = session.social.suggestions
        if list.isEmpty { Muted("Nobody to suggest yet. Share your Bucks ID to start syncing.").padding(.horizontal, Gutter) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) { ForEach(list) { p in SuggestionCard(p: p) { session.social.syncWith(p.id, name: p.name) } } }.padding(.horizontal, Gutter)
        }
    }
}

/// Someone you may know: mutual syncs or nearby, with a Sync button.
private struct SuggestionCard: View {
    let p: PersonSuggestion
    var onSync: () -> Void
    var body: some View {
        BucksCard(padding: 14) {
            HStack(spacing: 10) {
                Avatar(initials: initials(p.name), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted(p.area.isEmpty ? "Nearby" : p.area, maxLines: 1)
                }
                Spacer(minLength: 0)
            }
            Muted(p.mutual > 0 ? "\(p.mutual) mutual sync\(p.mutual > 1 ? "s" : "")" : (p.distanceM.map { String(format: "%.1f km away", $0 / 1000) } ?? "Nearby"), maxLines: 2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading).padding(.vertical, 8)
            WideSmallButton(title: "Sync", action: onSync)
        }.frame(width: 200)
    }
}

/// One live shop or pro: icon, name, kind pill, where and whether it is open, and its trust number.
private struct RecoRow: View {
    let hit: SearchHit
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Avatar(systemImage: hit.kind == "BUSINESS" ? "storefront.fill" : "wrench.and.screwdriver.fill", tinted: false)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(hit.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                            PillGrey(hit.category.isEmpty ? (hit.kind == "BUSINESS" ? "Shop" : "Pro") : hit.category)
                        }
                        Muted([hit.area.isEmpty ? nil : hit.area, hit.online ? "Open now" : "Closed now"].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    }
                }
                TrustBadge(up: hit.trustUp, down: hit.trustDown).padding(.top, 10).padding(.leading, 58)
            }
            .padding(.horizontal, Gutter).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
