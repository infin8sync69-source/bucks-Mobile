import SwiftUI
import BucksCore

/// Pick where you are based, anywhere: use the phone's current location, or search any place (a locality, a landmark, a town).
/// `onPick` gets a short label and the exact point, so the profile's home is the place chosen and not a guess.
struct LocationPicker: View {
    let current: String
    let fix: LatLng?
    let fixLabel: String?
    let onPick: (String, LatLng) -> Void
    @State private var q = ""
    @State private var hits: [MapServices.PlaceHit] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 24)).foregroundStyle(BucksColor.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Muted("Your area")
                    Text(current.isEmpty ? "Not chosen yet" : current).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                }
            }.padding(.bottom, 10)
            if let fix {
                HStack {
                    SmallButton("Use my current location\(areaOf(fixLabel).map { " (\($0))" } ?? "")", tonal: true) {
                        onPick(areaOf(fixLabel) ?? "Current location", fix); reset()
                    }
                    Spacer(minLength: 0)
                }.padding(.bottom, 10)
            } else {
                Muted("Turn on location to use where you are now, or search for a place below.").padding(.bottom, 8)
            }
            BucksField($q, placeholder: "Search any area, landmark or town").padding(.bottom, -14)
            if searching {
                ProgressView().progressViewStyle(.linear).tint(BucksColor.primary).padding(.top, 4)
            } else if q.trimmingCharacters(in: .whitespaces).count >= 3 && hits.isEmpty {
                Muted("No places found for \"\(q.trimmingCharacters(in: .whitespaces))\". Try a nearby landmark or the town's name.").padding(.top, 6)
            }
            ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                Button { onPick(placeLabel(h), h.at); reset() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin").foregroundStyle(BucksColor.onSurfaceVariant)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(h.name).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                            if !h.detail.isEmpty { Muted(h.detail, maxLines: 1) }
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                BucksDivider()
            }
        }
        // Search after a short pause in typing, biased to where the phone is (else the middle of the city, only used to order results).
        .task(id: q) {
            let t = q.trimmingCharacters(in: .whitespaces)
            if t.count < 3 { hits = []; searching = false; return }
            searching = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            let found = await MapServices.search(q, near: fix ?? Geo.center)
            if Task.isCancelled { return }
            hits = found; searching = false
        }
    }

    private func reset() { q = ""; hits = [] }
}
