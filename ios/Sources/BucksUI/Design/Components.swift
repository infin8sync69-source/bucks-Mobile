import SwiftUI
import BucksCore

// MARK: - Text

/// Screen headline (headlineMedium).
public struct Headline: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).bucks(.headlineMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader) }
}

/// Secondary text (bodySmall in onSurfaceVariant).
public struct Muted: View {
    let text: String; var align: TextAlignment; var maxLines: Int?
    public init(_ text: String, align: TextAlignment = .leading, maxLines: Int? = nil) { self.text = text; self.align = align; self.maxLines = maxLines }
    public var body: some View {
        Text(text).bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant).multilineTextAlignment(align).lineLimit(maxLines)
            .frame(maxWidth: .infinity, alignment: align == .center ? .center : align == .trailing ? .trailing : .leading)
    }
}

/// Small label above a field (Android `Label`).
public struct FieldLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).bucks(.labelMedium).foregroundStyle(BucksColor.onSurfaceVariant).padding(.bottom, 6) }
}

/// Section heading with an optional trailing text action.
public struct SectionTitle: View {
    let text: String; var action: String?; var onAction: (() -> Void)?
    public init(_ text: String, action: String? = nil, onAction: (() -> Void)? = nil) { self.text = text; self.action = action; self.onAction = onAction }
    public var body: some View {
        HStack {
            Text(text).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            if let action, let onAction { Button(action, action: onAction).buttonStyle(.plain).font(.bucks(.labelMedium)).foregroundStyle(BucksColor.primary) }
        }
    }
}

public func initials(_ name: String) -> String {
    name.split(separator: " ").filter { !$0.allSatisfy(\.isWhitespace) }.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
}

// MARK: - Buttons

enum ButtonKind { case primary, dark, ghost, tint, good, bad }

struct BucksButtonStyle: ButtonStyle {
    let kind: ButtonKind
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .primary: (BucksColor.primary, BucksColor.onPrimary)
            case .dark: (BucksColor.secondary, BucksColor.onSecondary)
            case .ghost: (.clear, BucksColor.primary)
            case .tint: (BucksColor.primaryContainer, BucksColor.onPrimaryContainer)
            case .good: (BucksColor.good, .white)
            case .bad: (.clear, BucksColor.error)
            }
        }()
        let shape = RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous)
        configuration.label
            .font(.bucks(.labelLarge)).foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: kind == .bad ? 48 : 52)
            .background(shape.fill(bg))
            .overlay { if kind == .ghost { shape.strokeBorder(BucksColor.outline, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private func bucksButton(_ title: String, kind: ButtonKind, enabled: Bool, haptic: Bool = true, action: @escaping () -> Void) -> some View {
    Button { if haptic { Haptics.tap() }; action() } label: { Text(title).lineLimit(1) }
        .buttonStyle(BucksButtonStyle(kind: kind)).disabled(!enabled)
}

/// Full-width purple button.
public struct PrimaryButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .primary, enabled: enabled, action: action) }
}
/// Full-width ink button (near-white in dark mode): the calm confirming action.
public struct DarkButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .dark, enabled: enabled, action: action) }
}
/// Outlined full-width button.
public struct GhostButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .ghost, enabled: enabled, haptic: false, action: action) }
}
/// Full-width tinted (purple container) button.
public struct TintButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .tint, enabled: enabled, haptic: false, action: action) }
}
/// Full-width green button.
public struct GoodButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .good, enabled: enabled, haptic: false, action: action) }
}
/// Red text button for cancel / hand-back actions.
public struct BadButton: View {
    let title: String; var enabled: Bool; let action: () -> Void
    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
    public var body: some View { bucksButton(title, kind: .bad, enabled: enabled, haptic: false, action: action) }
}

/// Compact 38pt button. `tonal` uses the soft container colour.
public struct SmallButton: View {
    let title: String; var tonal: Bool; var enabled: Bool; let action: () -> Void
    public init(_ title: String, tonal: Bool = false, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.tonal = tonal; self.enabled = enabled; self.action = action }
    public var body: some View {
        Button(action: action) {
            Text(title).font(.bucks(.labelMedium)).lineLimit(1).padding(.horizontal, 14).frame(minHeight: 38)
                .foregroundStyle(tonal ? BucksColor.onSecondaryContainer : BucksColor.onPrimary)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(tonal ? BucksColor.secondaryContainer : BucksColor.primary))
                .padding(.vertical, 3)   // 44 pt tap target around the 38 pt pill
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

/// Add, then a - qty + stepper once the item is in the cart. `onAdd` gets +1 or -1.
public struct AddStepper: View {
    let qty: Int; let onAdd: (Int) -> Void
    public init(qty: Int, onAdd: @escaping (Int) -> Void) { self.qty = qty; self.onAdd = onAdd }
    public var body: some View {
        if qty == 0 { SmallButton("Add", tonal: true) { onAdd(1) } }
        else {
            HStack(spacing: 0) {
                stepButton("minus", "Remove one", -1)
                Text("\(qty)").font(.bucks(.labelMedium)).foregroundStyle(BucksColor.onPrimary).frame(minWidth: 18)
                stepButton("plus", "Add one", 1)
            }
            .frame(height: 38).background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primary))
        }
    }
    private func stepButton(_ icon: String, _ label: String, _ d: Int) -> some View {
        Button { onAdd(d) } label: { Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(BucksColor.onPrimary).frame(width: 38, height: 38).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Round icon with a caption underneath.
public struct IconAction: View {
    let systemImage: String; let label: String; let action: () -> Void
    public init(_ systemImage: String, _ label: String, action: @escaping () -> Void) { self.systemImage = systemImage; self.label = label; self.action = action }
    public var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 19)).foregroundStyle(BucksColor.onSurface)
                    .frame(width: 46, height: 46).background(Circle().fill(BucksColor.surfaceContainerHigh))
                Text(label).font(.bucks(.labelSmall)).foregroundStyle(BucksColor.onSurfaceVariant)
            }.padding(6).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Styled switch for listing online/offline and similar.
public struct ListingSwitch: View {
    @Binding var isOn: Bool
    public init(_ isOn: Binding<Bool>) { self._isOn = isOn }
    public var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().tint(BucksColor.primary)
            .onChange(of: isOn) { _, _ in Haptics.tap() }
    }
}

// MARK: - Inputs

public struct BucksField: View {
    @Binding var text: String
    var label: String?; var placeholder: String; var singleLine: Bool; var minLines: Int; var readOnly: Bool; var keyboard: BucksKeyboard
    public init(_ text: Binding<String>, label: String? = nil, placeholder: String = "", singleLine: Bool = true, minLines: Int = 1, readOnly: Bool = false, keyboard: BucksKeyboard = .default) {
        self._text = text; self.label = label; self.placeholder = placeholder; self.singleLine = singleLine; self.minLines = minLines; self.readOnly = readOnly; self.keyboard = keyboard
    }
    @FocusState private var focused: Bool
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label { FieldLabel(label) }
            Group {
                if singleLine {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(BucksColor.onSurfaceVariant))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(BucksColor.onSurfaceVariant), axis: .vertical)
                        .lineLimit(max(1, minLines)...max(minLines, 8))
                }
            }
            .font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface).focused($focused)
            .disabled(readOnly).bucksKeyboard(keyboard)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(minHeight: 56, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
            .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(focused ? BucksColor.primary : BucksColor.outline, lineWidth: focused ? 2 : 1))
        }
        .padding(.bottom, 14)
    }
}

/// Four digit boxes over a hidden number-pad field. `onDone` fires once the fourth digit is in.
public struct PinBoxes: View {
    @Binding var value: String
    var onDone: (() -> Void)?
    public init(value: Binding<String>, onDone: (() -> Void)? = nil) { self._value = value; self.onDone = onDone }
    @FocusState private var focused: Bool
    public var body: some View {
        ZStack {
            TextField("", text: Binding(get: { value }, set: { raw in
                let v = String(raw.filter(\.isNumber).prefix(4)); let was = value
                value = v; if v.count == 4, was.count < 4 { onDone?() }
            })).focused($focused).bucksKeyboard(.number).opacity(0.01).frame(width: 1, height: 1)
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    let digit = value.count > i ? String(Array(value)[i]) : ""
                    Text(digit).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
                        .frame(minWidth: 52, minHeight: 52).padding(.horizontal, 6)
                        .overlay(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous)
                            .strokeBorder(BucksColor.primary.opacity(focused && i == value.count ? 1 : 0.5), lineWidth: 2))
                }
            }
            .contentShape(Rectangle()).onTapGesture { focused = true }
        }
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .accessibilityElement().accessibilityLabel("PIN, \(value.count) of 4 digits entered")
    }
}

// MARK: - Surfaces

public struct BucksCard<Content: View>: View {
    var tint: Bool; var onTap: (() -> Void)?; var padding: CGFloat
    let content: Content
    public init(tint: Bool = false, onTap: (() -> Void)? = nil, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.tint = tint; self.onTap = onTap; self.padding = padding; self.content = content()
    }
    public var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(tint ? BucksColor.primaryContainer : BucksColor.surfaceContainer))
            .contentShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
        if let onTap { Button(action: onTap) { card }.buttonStyle(.plain) } else { card }
    }
}

/// Bottom panel floating over a map: top corners 28, grabber, shadow.
public struct Sheet<Content: View>: View {
    var scrollable: Bool
    let content: Content
    public init(scrollable: Bool = false, @ViewBuilder content: () -> Content) { self.scrollable = scrollable; self.content = content() }
    public var body: some View {
        let inner = VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(BucksColor.outline).frame(width: 36, height: 4).frame(maxWidth: .infinity).padding(.bottom, 14)
            content
        }.padding(.horizontal, 20).padding(.vertical, 16)
        Group { if scrollable { ScrollView { inner } } else { inner } }
            .frame(maxWidth: .infinity)
            .background(UnevenRoundedRectangle(topLeadingRadius: BucksRadius.sheet, topTrailingRadius: BucksRadius.sheet, style: .continuous)
                .fill(BucksColor.surface).shadow(color: .black.opacity(0.18), radius: 12, y: -2).ignoresSafeArea(edges: .bottom))
    }
}

public struct BucksDivider: View {
    public init() {}
    public var body: some View { Rectangle().fill(BucksColor.outlineVariant).frame(height: 1) }
}

/// Keeps reading width comfortable on wide screens.
public struct ContentColumn<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { content.frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .top) }
}

/// Info box with a leading icon on the purple container.
public struct Notice: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").font(.system(size: 14)).foregroundStyle(BucksColor.onPrimaryContainer).padding(.top, 2)
            Text(text).bucks(.bodySmall).foregroundStyle(BucksColor.onPrimaryContainer).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.primaryContainer))
        .accessibilityElement(children: .combine)
    }
}

/// "The data could not load" card with a retry.
public struct LoadError: View {
    let message: String; var title: String; let retry: () -> Void
    public init(_ message: String, title: String = "Couldn't load this", retry: @escaping () -> Void) { self.message = message; self.title = title; self.retry = retry }
    public var body: some View {
        BucksCard {
            Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted(message).padding(.top, 4)
            SmallButton("Try again", tonal: true, action: retry).padding(.top, 12)
        }
    }
}

// MARK: - Avatars, badges, pills, chips

public struct Avatar: View {
    private enum Face { case text(String), icon(String) }
    private let face: Face; let size: CGFloat; let tinted: Bool
    public init(initials: String, size: CGFloat = 44, tinted: Bool = true) { face = .text(initials.isEmpty ? "?" : initials); self.size = size; self.tinted = tinted }
    public init(systemImage: String, size: CGFloat = 44, tinted: Bool = true) { face = .icon(systemImage); self.size = size; self.tinted = tinted }
    public var body: some View {
        ZStack {
            Circle().fill(tinted ? BucksColor.primaryContainer : BucksColor.surfaceContainerHigh)
            switch face {
            case .icon(let n): Image(systemName: n).font(.system(size: size * 0.45)).foregroundStyle(tinted ? BucksColor.onPrimaryContainer : BucksColor.onSurfaceVariant)
            case .text(let t): Text(t).bucks(size >= 64 ? .headlineSmall : .titleSmall).foregroundStyle(tinted ? BucksColor.onPrimaryContainer : BucksColor.onSurface)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The one trust number shown everywhere, coloured by the recommend rate.
public struct TrustBadge: View {
    let up: Int; let down: Int; var compact: Bool; var onTap: (() -> Void)?
    public init(up: Int, down: Int, compact: Bool = false, onTap: (() -> Void)? = nil) { self.up = up; self.down = down; self.compact = compact; self.onTap = onTap }
    public var body: some View {
        let total = up + down; let pct: Int? = total == 0 ? nil : up * 100 / total
        let (fg, bg): (Color, Color) = {
            guard let pct else { return (BucksColor.onSurfaceVariant, BucksColor.surfaceContainer) }
            return pct >= 85 ? (BucksColor.good, BucksColor.goodTint) : pct >= 60 ? (BucksColor.warn, BucksColor.warnTint) : (BucksColor.bad, BucksColor.badTint)
        }()
        let text = pct == nil ? (compact ? "New" : "New · no votes yet") : compact ? "\(pct!)% recommend" : "\(pct!)% recommend · \(total) votes"
        let pill = HStack(spacing: 5) {
            Image(systemName: "hand.thumbsup.fill").font(.system(size: 11)).foregroundStyle(fg)
            Text(text).font(.bucks(.labelMedium)).foregroundStyle(fg).lineLimit(1)
        }.padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(bg))
        if let onTap { Button(action: onTap) { pill }.buttonStyle(.plain).accessibilityHint("How is this ranked") } else { pill }
    }
}

public struct Pill: View {
    let text: String; let bg: Color; let fg: Color
    public init(_ text: String, bg: Color, fg: Color) { self.text = text; self.bg = bg; self.fg = fg }
    public var body: some View { Text(text).font(.bucks(.labelSmall)).foregroundStyle(fg).padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(bg)) }
}
public func PillGood(_ t: String) -> Pill { Pill(t, bg: BucksColor.goodTint, fg: BucksColor.good) }
public func PillWarn(_ t: String) -> Pill { Pill(t, bg: BucksColor.warnTint, fg: BucksColor.warn) }
public func PillBad(_ t: String) -> Pill { Pill(t, bg: BucksColor.badTint, fg: BucksColor.bad) }
public func PillGrey(_ t: String) -> Pill { Pill(t, bg: BucksColor.surfaceContainerHigh, fg: BucksColor.onSurfaceVariant) }
public func PillPurple(_ t: String) -> Pill { Pill(t, bg: BucksColor.primaryContainer, fg: BucksColor.onPrimaryContainer) }
/// Purple pill used for kinds ("Delivery", "Taxi").
public struct BrandPill: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).font(.bucks(.labelSmall)).foregroundStyle(BucksColor.onPrimaryContainer).padding(.horizontal, 12).padding(.vertical, 3).background(Capsule().fill(BucksColor.primaryContainer)) }
}

public struct BucksChip: View {
    let title: String; var selected: Bool; var systemImage: String?; let action: () -> Void
    public init(_ title: String, selected: Bool = false, systemImage: String? = nil, action: @escaping () -> Void) { self.title = title; self.selected = selected; self.systemImage = systemImage; self.action = action }
    public var body: some View {
        let fg = selected ? BucksColor.onPrimaryContainer : BucksColor.onSurface
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 13)) }
                Text(title).font(.bucks(.labelMedium)).lineLimit(1)
            }
            .foregroundStyle(fg).padding(.horizontal, 13).padding(.vertical, 8).frame(minWidth: 48)
            .background(Capsule().fill(selected ? BucksColor.primaryContainer : BucksColor.surfaceContainer))
            .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Horizontally scrolling single-select chips.
public struct ChipRow: View {
    let items: [String]; var selected: String?; let onTap: (String) -> Void
    public init(_ items: [String], selected: String? = nil, onTap: @escaping (String) -> Void) { self.items = items; self.selected = selected; self.onTap = onTap }
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(items, id: \.self) { i in BucksChip(i, selected: i == selected) { onTap(i) } } }
        }
    }
}

/// Wrapping multi-select chips.
public struct FlowChips: View {
    let items: [String]; var selected: Set<String>; let onTap: (String) -> Void
    public init(_ items: [String], selected: Set<String> = [], onTap: @escaping (String) -> Void) { self.items = items; self.selected = selected; self.onTap = onTap }
    public var body: some View {
        FlowLayout(spacing: 8) { ForEach(items, id: \.self) { i in BucksChip(i, selected: selected.contains(i)) { onTap(i) } } }
    }
}

/// Left-to-right wrapping layout.
public struct FlowLayout: Layout {
    var spacing: CGFloat
    public init(spacing: CGFloat = 8) { self.spacing = spacing }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(bounds.width, subviews).frames.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified) }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowH))
    }
}

// MARK: - Rows

/// Icon + title + subtitle + trailing view.
public struct ListRow<Leading: View, Trailing: View>: View {
    let title: String; var subtitle: String?; let leading: Leading; let trailing: Trailing; var onTap: (() -> Void)?
    public init(_ title: String, subtitle: String? = nil, onTap: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.onTap = onTap; self.leading = leading(); self.trailing = trailing()
    }
    public var body: some View {
        let row = HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                if let subtitle { Text(subtitle).bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }.padding(.horizontal, 20).padding(.vertical, 12).contentShape(Rectangle())
        if let onTap { Button(action: onTap) { row }.buttonStyle(.plain) } else { row }
    }
}
public extension ListRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, onTap: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading) {
        self.init(title, subtitle: subtitle, onTap: onTap, leading: leading) { EmptyView() }
    }
}

/// One step of a status timeline (order / ride progress).
public struct StatusLine: View {
    let text: String; var detail: String?; let done: Bool; let now: Bool; var last: Bool
    public init(_ text: String, detail: String? = nil, done: Bool, now: Bool, last: Bool = false) { self.text = text; self.detail = detail; self.done = done; self.now = now; self.last = last }
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(done ? BucksColor.good : now ? BucksColor.primary : BucksColor.outline).frame(width: 12, height: 12)
                if !last { Rectangle().fill(done ? BucksColor.good : BucksColor.outlineVariant).frame(width: 2, height: 30) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(text).bucks(.titleSmall).foregroundStyle(done || now ? BucksColor.onSurface : BucksColor.onSurfaceVariant)
                if now, let detail { Text(detail).bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant) }
            }.offset(y: -3)
        }
    }
}

/// Thumbs-up / thumbs-down vote chip.
public struct VoteButton: View {
    let title: String; let active: Bool; let up: Bool; let action: () -> Void
    public init(_ title: String, active: Bool, up: Bool, action: @escaping () -> Void) { self.title = title; self.active = active; self.up = up; self.action = action }
    public var body: some View {
        let fg = !active ? BucksColor.onSurface : up ? BucksColor.good : BucksColor.bad
        let bg = !active ? BucksColor.surfaceContainer : up ? BucksColor.goodTint : BucksColor.badTint
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 6) {
                Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 12, weight: .bold))
                Text(title).font(.bucks(.labelMedium))
            }.foregroundStyle(fg).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(bg))
        }.buttonStyle(.plain)
    }
}

// MARK: - Top bar

public struct BucksTopBar<Actions: View>: View {
    var title: String?; var onBack: (() -> Void)?; var onMenu: (() -> Void)?; var unread: Int; var onChat: (() -> Void)?
    let actions: Actions
    public init(title: String? = nil, onBack: (() -> Void)? = nil, onMenu: (() -> Void)? = nil, unread: Int = 0, onChat: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.onBack = onBack; self.onMenu = onMenu; self.unread = unread; self.onChat = onChat; self.actions = actions()
    }
    public var body: some View {
        HStack(spacing: 0) {
            if let onBack { barButton("chevron.left", "Back", onBack) }
            else if let onMenu { barButton("line.3.horizontal", "Menu", onMenu) }
            else { Color.clear.frame(width: 12, height: 44) }
            Group {
                if let title { Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1).accessibilityAddTraits(.isHeader) }
                else { BucksWordmark(height: 26) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            actions
            if let onChat {
                Button(action: onChat) {
                    Image(systemName: "message.fill").font(.system(size: 21)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if unread > 0 { Text("\(unread)").font(.bucks(.labelSmall)).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(BucksColor.purple)).offset(x: -2, y: 4) }
                        }
                }.buttonStyle(.plain).accessibilityLabel("Messages")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity)
    }
    private func barButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
public extension BucksTopBar where Actions == EmptyView {
    init(title: String? = nil, onBack: (() -> Void)? = nil, onMenu: (() -> Void)? = nil, unread: Int = 0, onChat: (() -> Void)? = nil) {
        self.init(title: title, onBack: onBack, onMenu: onMenu, unread: unread, onChat: onChat) { EmptyView() }
    }
}

// MARK: - Dispatch visuals

/// Pickup (green dot) and drop (red dot) in a tinted box; `trailing` sits at the pickup row's end.
public struct RoutePoints<Trailing: View>: View {
    let pickup: String; let drop: String; let trailing: Trailing
    public init(pickup: String, drop: String, @ViewBuilder trailing: () -> Trailing) { self.pickup = pickup; self.drop = drop; self.trailing = trailing() }
    public var body: some View {
        VStack(spacing: 0) {
            row(pickup, BucksColor.good, showTrailing: true)
            row(drop, BucksColor.bad, showTrailing: false)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
    }
    private func row(_ t: String, _ c: Color, showTrailing: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).bucks(.bodySmall).foregroundStyle(BucksColor.onSurface).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if showTrailing { trailing }
        }.padding(.vertical, 5)
    }
}
public extension RoutePoints where Trailing == EmptyView {
    init(pickup: String, drop: String) { self.init(pickup: pickup, drop: drop) { EmptyView() } }
}

/// Round call button plus a "message ..." pill.
public struct MessageBar: View {
    let hint: String; let onCall: () -> Void; let onMessage: () -> Void
    public init(hint: String, onCall: @escaping () -> Void, onMessage: @escaping () -> Void) { self.hint = hint; self.onCall = onCall; self.onMessage = onMessage }
    public var body: some View {
        HStack(spacing: 10) {
            Button(action: onCall) {
                Image(systemName: "phone.fill").font(.system(size: 17)).foregroundStyle(BucksColor.onSurface)
                    .frame(width: 44, height: 44).background(Circle().fill(BucksColor.surfaceContainer))
            }.buttonStyle(.plain).accessibilityLabel("Call")
            Button(action: onMessage) {
                HStack {
                    Text(hint).bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "paperplane.fill").font(.system(size: 15)).foregroundStyle(BucksColor.onSurfaceVariant)
                }.padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(BucksColor.surfaceContainer)).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Message")
        }
    }
}

// MARK: - Confirm dialog

public extension View {
    /// Two-button confirmation alert. `destructive` colours the confirm button red.
    func bucksConfirm(isPresented: Binding<Bool>, title: String, message: String? = nil, confirmTitle: String, cancelTitle: String = "Cancel", destructive: Bool = false, onConfirm: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button(cancelTitle, role: .cancel) {}
            Button(confirmTitle, role: destructive ? .destructive : nil, action: onConfirm)
        } message: { if let message { Text(message) } }
    }

    /// Standard screen background.
    func bucksBackground() -> some View { background(BucksColor.background.ignoresSafeArea()) }
}
