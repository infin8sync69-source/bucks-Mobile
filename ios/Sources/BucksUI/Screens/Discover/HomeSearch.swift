import SwiftUI
import BucksCore

/// The home search, typed into right here: after 3 letters the nearest matching places (streets, landmarks, towns) list under the field;
/// tapping one opens it on the map with directions, and the search key (or the last row) searches shops, pros and drivers instead.
struct HomeSearch: View {
    let hint: String
    var onSearchAll: (String) -> Void
    var onPlace: (MapServices.PlaceHit) -> Void
    @Environment(AppSession.self) private var session
    @State private var q = ""
    @State private var places: [MapServices.PlaceHit] = []

    private var trimmed: String { q.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
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
        .task(id: q) {
            places = []
            guard trimmed.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            places = Array(await MapServices.search(trimmed, near: session.here).prefix(3))
        }
    }
}
