import SwiftUI

/// Parses the absolute M / L / C / Z SVG paths the wordmark is made of.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var nums: [CGFloat] = []
        var cmd: Character = "M"
        var token = ""
        func flush() { if !token.isEmpty { if let v = Double(token) { nums.append(CGFloat(v)) }; token = "" } }
        func apply() {
            switch cmd {
            case "M": if nums.count >= 2 { path.move(to: CGPoint(x: nums[0], y: nums[1])) }
            case "L": if nums.count >= 2 { path.addLine(to: CGPoint(x: nums[0], y: nums[1])) }
            case "C": if nums.count >= 6 { path.addCurve(to: CGPoint(x: nums[4], y: nums[5]), control1: CGPoint(x: nums[0], y: nums[1]), control2: CGPoint(x: nums[2], y: nums[3])) }
            case "Z": path.closeSubpath()
            default: break
            }
            nums.removeAll()
        }
        for ch in d {
            if ch.isLetter {
                flush(); apply(); cmd = ch
                if ch == "Z" { apply() }
            } else if ch == "," || ch == " " { flush() }
            else if ch == "-" && !token.isEmpty && token.last != "e" { flush(); token = "-" }
            else { token.append(ch) }
            let need: Int = cmd == "C" ? 6 : (cmd == "M" || cmd == "L") ? 2 : 0
            if need > 0, nums.count == need { apply(); if cmd == "M" { cmd = "L" } }
        }
        flush(); if cmd != "Z" { apply() }
        return path
    }
}

/// One letter (0 = b ... 4 = s) of the wordmark, scaled to fit its rect by height.
struct WordmarkLetter: Shape {
    let index: Int
    static let paths: [Path] = WordmarkData.letters.map { SVGPath.parse($0) }
    func path(in rect: CGRect) -> Path {
        let s = rect.height / WordmarkData.height
        return Self.paths[index].applying(CGAffineTransform(scaleX: s, y: s)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The traced Bucks wordmark. Width follows the logo's proportions (about 3.47 x its height).
public struct BucksWordmark: View {
    var color: Color
    var height: CGFloat
    public init(color: Color = BucksColor.primary, height: CGFloat = 28) { self.color = color; self.height = height }
    public var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { WordmarkLetter(index: $0).fill(color, style: FillStyle(eoFill: true)) }
        }
        .frame(width: height * WordmarkData.width / WordmarkData.height, height: height)
        .accessibilityElement().accessibilityLabel("Bucks").accessibilityAddTraits(.isImage)
    }
}

/// Page-level loading indicator: the wordmark's letters ripple left to right.
public struct BucksLoader: View {
    var height: CGFloat
    var color: Color
    public init(height: CGFloat = 22, color: Color = BucksColor.primary) { self.height = height; self.color = color }
    public var body: some View {
        Group {
            if bucksReduceMotion { BucksWordmark(color: color.opacity(0.6), height: height) }
            else {
                TimelineView(.animation) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.15) / 1.15
                    ZStack {
                        ForEach(0..<5, id: \.self) { i in
                            let pose = Self.pose(phase: phase, index: i)
                            WordmarkLetter(index: i).fill(color, style: FillStyle(eoFill: true))
                                .scaleEffect(x: 1 - 0.03 * pose, y: 1 + 0.07 * pose, anchor: .bottom)
                                .offset(y: -0.2 * pose * height).opacity(0.5 + 0.5 * pose)
                        }
                    }
                }
                .frame(width: height * WordmarkData.width / WordmarkData.height, height: height)
            }
        }
        .accessibilityElement().accessibilityLabel("Loading")
    }
    private static func pose(phase: Double, index: Int) -> Double {
        var x = phase - Double(index) * 0.11; if x < 0 { x += 1 }
        return x < 0.42 ? sin(x / 0.42 * .pi) : 0
    }
}

/// Purple full-bleed background for brand screens (splash, welcome).
public struct SplashBackdrop: View {
    public init() {}
    public var body: some View { BucksColor.purple.ignoresSafeArea() }
}
