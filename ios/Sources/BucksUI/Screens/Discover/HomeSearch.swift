import SwiftUI
import BucksCore

/// The home search, typed into right here: after 3 letters the nearest matching places (streets, landmarks, towns) list under the field;
/// tapping one opens it on the map with directions, and the search key (or the last row) searches shops, pros and drivers instead.
struct HomeSearch: View {
    let hint: String
    var onSearchAll: (String) -> Void
    var onPlace: (MapServices.PlaceHit) -> Void
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var q = ""
    @State private var places: [MapServices.PlaceHit] = []
    // People, by name or Bucks ID, as cards with their quick actions; a tap opens the profile.
    @State private var people: [PersonHit] = []
    @State private var allPeople = false
    @State private var sent: Set<String> = []

    private var trimmed: String { q.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            if !people.isEmpty { peopleSection }
            if trimmed.count >= 3 {
                ForEach(places, id: \.self) { h in
                    ListRow(h.name, subtitle: h.detail, onTap: { q = ""; onPlace(h) },
                            leading: { Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(BucksColor.primary) }, trailing: { Muted("Directions") })
                }
                ListRow("Search shops, pros and drivers for “\(trimmed)”", onTap: { let t = trimmed; q = ""; onSearchAll(t) },
                        leading: { Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface) })
            }
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface)
                TextField("", text: $q, prompt: Text(hint).foregroundStyle(BucksColor.onSurfaceVariant))
                    .bucksFont(.bodyLarge).foregroundStyle(BucksColor.onSurface).tint(BucksColor.primary).submitLabel(.search)
                    .onSubmit { if !trimmed.isEmpty { let t = trimmed; q = ""; onSearchAll(t) } }
                if !q.isEmpty {
                    Button { q = "" } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 40, height: 40).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 20).padding(.trailing, 4).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
        }
        .task(id: q) { await findPeople() }
        .task(id: q) {
            places = []
            guard trimmed.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            places = Array(await MapServices.search(trimmed, near: session.here).prefix(3))
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People").bucks(.labelLarge).foregroundStyle(BucksColor.onSurfaceVariant)
            ForEach(Array((allPeople ? people : Array(people.prefix(3))).enumerated()), id: \.element.id) { i, h in
                PersonResultCard(hit: h, state: syncState(h), onOpen: { q = ""; router.push(.person(h.id)) },
                                 onSync: { if syncState(h) == "INCOMING" { session.social.acceptSync(h.id) } else { sent.insert(h.id); session.social.syncWith(h.id, name: h.name) } },
                                 onMessage: { Task { if let c = await session.chat.openDirect(h.id) { q = ""; router.push(.chat(c)) } } })
                    .enterStagger(index: min(i, 6))
            }
            if !allPeople && people.count > 3 {
                let more = people.count - 3
                GhostButton(more == 1 ? "Show 1 more person" : "Show \(more) more people") { allPeople = true }
            }
        }.padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncState(_ h: PersonHit) -> String {
        if h.synced || session.social.synced.contains(where: { $0.id == h.id }) { return "SYNCED" }
        if session.social.incoming.contains(where: { $0.id == h.id }) { return "INCOMING" }
        return sent.contains(h.id) ? "SENT" : "NONE"
    }

    private func findPeople() async {
        allPeople = false
        let t = peopleQuery(q)
        guard t.count >= 2, session.me != nil else { people = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        people = (try? await Backend.shared.searchPeople(t)) ?? []
        if people.isEmpty == false { session.social.refreshSyncs() }
    }
}
