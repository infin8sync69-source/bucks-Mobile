import SwiftUI
import BucksCore

/// The five bottom-bar destinations (Components.kt `BottomTab`).
public enum BottomTab: CaseIterable, Hashable {
    case home, feed, services, recommended, account
    var label: String { switch self { case .home: "Home"; case .feed: "Feed"; case .services: "Services"; case .recommended: "For you"; case .account: "Profile" } }
    var systemImage: String { switch self { case .home: "house.fill"; case .feed: "play.rectangle.on.rectangle.fill"; case .services: "square.grid.2x2.fill"; case .recommended: "chart.bar.fill"; case .account: "person.fill" } }
}

/// Plain equal-width items with a hop on the selected icon, like Android's `BucksBottomBar`.
struct BucksBottomBar: View {
    let current: BottomTab
    let onSelect: (BottomTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            BucksDivider()
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases, id: \.self) { t in
                    let selected = t == current
                    Button { onSelect(t) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.systemImage).font(.system(size: 22))
                                .scaleEffect(selected ? 1.08 : 1).offset(y: selected ? -3 : 0)
                                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: selected)
                            Text(t.label).font(.bucks(.labelSmall)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selected ? BucksColor.primary : BucksColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.label).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.top, 8).padding(.bottom, 4)
        }
        .background(BucksColor.surface.ignoresSafeArea(edges: .bottom))
    }
}
