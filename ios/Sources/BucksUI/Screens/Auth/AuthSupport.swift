import SwiftUI
import BucksCore

/// "Indiranagar, Bengaluru" from a place hit; a street becomes "12th Main, Indiranagar".
func placeLabel(_ hit: MapServices.PlaceHit) -> String {
    let second = hit.detail.components(separatedBy: ", ").first { !$0.isEmpty && $0 != hit.name }
    return [hit.name, second].compactMap { $0 }.joined(separator: ", ")
}

/// The area part of a reverse-geocoded label ("12th Main, Indiranagar" -> "Indiranagar").
func areaOf(_ label: String?) -> String? {
    guard let label else { return nil }
    let last = label.components(separatedBy: ", ").last ?? label
    return last.isEmpty ? nil : last
}

/// Full-width white button used on the purple splash.
struct SplashButton: View {
    let title: String; let enabled: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).bucks(.labelLarge).foregroundStyle(BucksColor.purpleDeep)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(Color.white))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled)
    }
}
