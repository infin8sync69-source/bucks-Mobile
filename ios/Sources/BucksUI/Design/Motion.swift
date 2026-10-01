import SwiftUI

/// Radar rings expanding from the centre: "we're ringing drivers near you".
public struct PulseRings<Content: View>: View {
    var color: Color; var rings: Int; var period: Double
    let content: Content
    public init(color: Color = BucksColor.primary, rings: Int = 3, periodMs: Int = 2000, @ViewBuilder content: () -> Content) {
        self.color = color; self.rings = rings; self.period = Double(periodMs) / 1000; self.content = content()
    }
    public var body: some View {
        ZStack {
            if !bucksReduceMotion {
                TimelineView(.animation) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    GeometryReader { g in
                        let d = min(g.size.width, g.size.height)
                        ForEach(0..<rings, id: \.self) { i in
                            let p = (phase + Double(i) / Double(rings)).truncatingRemainder(dividingBy: 1)
                            Circle().fill(color.opacity((1 - p) * 0.35)).frame(width: d * (0.3 + 0.7 * p), height: d * (0.3 + 0.7 * p))
                                .position(x: g.size.width / 2, y: g.size.height / 2)
                        }
                    }
                }.allowsHitTesting(false)
            }
            content
        }
    }
}
public extension PulseRings where Content == EmptyView {
    init(color: Color = BucksColor.primary, rings: Int = 3, periodMs: Int = 2000) { self.init(color: color, rings: rings, periodMs: periodMs) { EmptyView() } }
}

/// Pops in with a small overshoot when it appears; `index` staggers siblings (PIN digits, success marks).
public struct PopIn<Content: View>: View {
    var index: Int; var step: Double
    let content: Content
    @State private var shown = false
    public init(index: Int = 0, step: Double = 0.07, @ViewBuilder content: () -> Content) { self.index = index; self.step = step; self.content = content() }
    public var body: some View {
        content.scaleEffect(shown || bucksReduceMotion ? 1 : 0.01).opacity(shown || bucksReduceMotion ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(Double(index) * step)) { shown = true } }
    }
}

public extension View {
    func popIn(index: Int = 0, step: Double = 0.07) -> some View { PopIn(index: index, step: step) { self } }

    /// Fades and rises into place, `index` steps after its siblings.
    func enterStagger(index: Int, step: Double = 0.04) -> some View { modifier(EnterStagger(index: index, step: step)) }

    /// Gentle scale loop that draws the eye to the one action that matters.
    func breathe(_ enabled: Bool = true, amount: CGFloat = 0.04, period: Double = 0.9) -> some View {
        modifier(Breathe(enabled: enabled && !bucksReduceMotion, amount: amount, period: period))
    }

    /// Shakes sideways each time `trigger` goes up: "no", without a dialog.
    func shake(on trigger: Int) -> some View { modifier(Shake(trigger: trigger)) }
}

private struct EnterStagger: ViewModifier {
    let index: Int; let step: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        let on = shown || bucksReduceMotion
        content.opacity(on ? 1 : 0).offset(y: on ? 0 : 20).scaleEffect(on ? 1 : 0.94)
            .onAppear { withAnimation(Motion.emphasized().delay(Double(index) * step)) { shown = true } }
    }
}

private struct Breathe: ViewModifier {
    let enabled: Bool; let amount: CGFloat; let period: Double
    @State private var big = false
    func body(content: Content) -> some View {
        content.scaleEffect(enabled && big ? 1 + amount : 1)
            .onAppear { if enabled { withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { big = true } } }
    }
}

private struct Shake: ViewModifier {
    let trigger: Int
    @State private var x: CGFloat = 0
    func body(content: Content) -> some View {
        content.offset(x: x).onChange(of: trigger) { _, new in
            guard new > 0 else { return }
            Task { @MainActor in
                for v: CGFloat in [10, -8, 6, -4, 2, 0] { withAnimation(.linear(duration: 0.05)) { x = v }; try? await Task.sleep(nanoseconds: 50_000_000) }
            }
        }
    }
}

/// Counts up to `value` instead of jumping (fares, earnings): `AnimatedAmount(fare)` shows "₹120".
public struct AnimatedAmount: View {
    let target: Int
    var prefix: String
    var style: BucksTextStyle
    var color: Color?
    @State private var shown: Double = 0
    public init(_ value: Int, prefix: String = "₹", style: BucksTextStyle = .headlineSmall, color: Color? = nil) {
        self.target = value; self.prefix = prefix; self.style = style; self.color = color
    }
    public var body: some View {
        Counter(value: shown, prefix: prefix, style: style, color: color ?? BucksColor.onSurface)
            .onAppear { go() }
            .onChange(of: target) { _, _ in go() }
    }
    private func go() {
        if bucksReduceMotion { shown = Double(target) } else { withAnimation(Motion.emphasized(0.9)) { shown = Double(target) } }
    }
    private struct Counter: View, Animatable {
        var value: Double; var prefix: String; var style: BucksTextStyle; var color: Color
        var animatableData: Double { get { value } set { value = newValue } }
        var body: some View { Text("\(prefix)\(Int(value.rounded()))").bucks(style).foregroundStyle(color).monospacedDigit() }
    }
}
