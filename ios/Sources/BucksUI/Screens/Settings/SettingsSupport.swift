import SwiftUI
import BucksCore

/// A label with an optional detail and a switch (ToggleRow in SettingsScreens.kt). Ends with a divider.
struct SettingsToggleRow: View {
    let label: String
    var detail: String?
    @Binding var on: Bool

    init(_ label: String, detail: String? = nil, on: Binding<Bool>) { self.label = label; self.detail = detail; self._on = on }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    if let detail { Muted(detail) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
                Toggle("", isOn: $on).labelsHidden().tint(BucksColor.primary)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
            .onTapGesture { on.toggle() }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
            BucksDivider()
        }
    }
}

/// A titled group of radio choices (ChoiceGroup in SettingsScreens.kt). Ends with a divider.
struct SettingsChoiceGroup<T: Hashable>: View {
    let title: String
    var detail: String?
    let options: [(T, String)]
    @Binding var selected: T

    init(_ title: String, detail: String? = nil, options: [(T, String)], selected: Binding<T>) { self.title = title; self.detail = detail; self.options = options; self._selected = selected }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                if let detail { Muted(detail) }
                ForEach(options.indices, id: \.self) { i in
                    let (v, l) = options[i]
                    Button { selected = v } label: {
                        HStack(spacing: 8) {
                            Image(systemName: v == selected ? "largecircle.fill.circle" : "circle").font(.system(size: 20))
                                .foregroundStyle(v == selected ? BucksColor.primary : BucksColor.onSurfaceVariant).frame(width: 32, height: 32)
                            Text(l).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(v == selected ? .isSelected : [])
                }
            }.padding(.vertical, 8)
            BucksDivider()
        }
    }
}
