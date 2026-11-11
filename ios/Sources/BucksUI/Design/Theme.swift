import SwiftUI
import CoreText
import BucksCore

/// Palette from Theme.kt (Light / Dark colour schemes plus StatusColors). The roles that change with the colour theme list one
/// (light, dark) pair per `Prefs.Accent`, in its order: purple, sapphire, emerald, ruby, graphite (the same values as Android's `Accent`).
public enum BucksColor {
    // Fixed brand colours.
    public static let purple = Color(hex: 0x811FF0)
    public static let purpleDeep = Color(hex: 0x4A0AA6)
    public static let purpleTint = Color(hex: 0xEFE6FE)
    public static let ink = Color(hex: 0x15111C)

    public static let primary = Color(tones: [(0x811FF0, 0xA874FF), (0x1D4ED8, 0x8FB0FF), (0x0A7A5A, 0x5FD3A8), (0xBE185D, 0xFF8FB8), (0x26262C, 0xD6D6DE)])
    public static let onPrimary = Color(tones: [(0xFFFFFF, 0x23074F), (0xFFFFFF, 0x0A2463), (0xFFFFFF, 0x033526), (0xFFFFFF, 0x4F0625), (0xFFFFFF, 0x1A1A1F)])
    public static let primaryContainer = Color(tones: [(0xEFE6FE, 0x2A1D45), (0xE4ECFE, 0x172A52), (0xDDF3EA, 0x123528), (0xFCE4EE, 0x46182B), (0xE9E9EC, 0x2B2B32)])
    public static let onPrimaryContainer = Color(tones: [(0x4A0AA6, 0xD2B8FF), (0x123A9E, 0xC3D5FF), (0x07563F, 0xB4EBD4), (0x8A0F42, 0xFFC4D9), (0x17171B, 0xE6E6EC)])
    /// Dark buttons: ink in light mode, near-white in dark mode.
    public static let secondary = Color(tones: [(0x15111C, 0xEFEBF6), (0x11141C, 0xEBEEF6), (0x121B18, 0xECF5F2), (0x1C1115, 0xF6EBEF), (0x151518, 0xEFEFF2)])
    public static let onSecondary = Color(tones: [(0xFFFFFF, 0x15111C), (0xFFFFFF, 0x11141C), (0xFFFFFF, 0x121B18), (0xFFFFFF, 0x1C1115), (0xFFFFFF, 0x151518)])
    public static let secondaryContainer = Color(tones: [(0xEDEAF3, 0x2A2533), (0xEAEDF3, 0x252933), (0xEAF3F0, 0x26322E), (0xF3EAED, 0x33252A), (0xEDEDF0, 0x2A2A2E)])
    public static let onSecondaryContainer = Color(tones: [(0x15111C, 0xEFEBF6), (0x11141C, 0xEBEEF6), (0x121B18, 0xECF5F2), (0x1C1115, 0xF6EBEF), (0x151518, 0xEFEFF2)])
    public static let background = Color(tones: [(0xFAF9FC, 0x0F0C14), (0xF9FAFC, 0x0C0E14), (0xF9FCFB, 0x0C1411), (0xFCF9FA, 0x140C0F), (0xFAFAFB, 0x0F0F11)])
    public static let surface = Color(tones: [(0xFFFFFF, 0x15111C), (0xFFFFFF, 0x11141C), (0xFFFFFF, 0x121B18), (0xFFFFFF, 0x1C1115), (0xFFFFFF, 0x151518)])
    public static let surfaceVariant = Color(tones: [(0xF3F1F7, 0x1E1926), (0xF1F3F7, 0x191D26), (0xF1F7F5, 0x1A2521), (0xF7F1F3, 0x26191D), (0xF3F3F5, 0x1E1E21)])
    public static let surfaceContainerLow = Color(tones: [(0xFBFAFD, 0x17131F), (0xFAFBFD, 0x13171F), (0xFAFDFC, 0x141E1B), (0xFDFAFB, 0x1F1317), (0xFBFBFC, 0x17171A)])
    public static let surfaceContainer = Color(tones: [(0xF6F4F9, 0x1B1723), (0xF4F6F9, 0x171B23), (0xF4F9F7, 0x18221F), (0xF9F4F6, 0x23171B), (0xF6F6F7, 0x1C1C1E)])
    public static let surfaceContainerHigh = Color(tones: [(0xF0EDF4, 0x221D2C), (0xEDEFF4, 0x1D212C), (0xEDF4F2, 0x1E2B27), (0xF4EDEF, 0x2C1D22), (0xF0F0F1, 0x232326)])
    public static let onSurface = Color(tones: [(0x15111C, 0xEFEBF6), (0x11141C, 0xEBEEF6), (0x121B18, 0xECF5F2), (0x1C1115, 0xF6EBEF), (0x151518, 0xEFEFF2)])
    public static let onSurfaceVariant = Color(tones: [(0x5F586C, 0xB2ABBF), (0x585E6C, 0xABB1BF), (0x596B65, 0xACBEB8), (0x6C585F, 0xBFABB2), (0x606064, 0xB2B2B7)])
    public static let outline = Color(tones: [(0xE4E0EB, 0x2E2838), (0xE0E3EB, 0x282D38), (0xE1EAE7, 0x293732), (0xEBE0E4, 0x38282D), (0xE4E4E7, 0x2E2E32)])
    public static let outlineVariant = Color(tones: [(0xEDEAF1, 0x241F2D), (0xEAECF1, 0x1F232D), (0xEAF1EF, 0x202C28), (0xF1EAEC, 0x2D1F24), (0xEDEDEE, 0x242428)])
    public static let error = Color(light: 0xB42323, dark: 0xF09393)

    /// One theme's own primary, whatever theme is in use: the swatches of the colour picker.
    public static func swatch(_ accent: Prefs.Accent) -> Color {
        switch accent {
        case .purple: Color(light: 0x811FF0, dark: 0xA874FF)
        case .sapphire: Color(light: 0x1D4ED8, dark: 0x8FB0FF)
        case .emerald: Color(light: 0x0A7A5A, dark: 0x5FD3A8)
        case .ruby: Color(light: 0xBE185D, dark: 0xFF8FB8)
        case .graphite: Color(light: 0x26262C, dark: 0xD6D6DE)
        }
    }
    /// The text colour on that swatch.
    public static func onSwatch(_ accent: Prefs.Accent) -> Color {
        switch accent {
        case .purple: Color(light: 0xFFFFFF, dark: 0x23074F)
        case .sapphire: Color(light: 0xFFFFFF, dark: 0x0A2463)
        case .emerald: Color(light: 0xFFFFFF, dark: 0x033526)
        case .ruby: Color(light: 0xFFFFFF, dark: 0x4F0625)
        case .graphite: Color(light: 0xFFFFFF, dark: 0x1A1A1F)
        }
    }

    // Status colours: foreground and pill tint.
    public static let good = Color(light: 0x117A47, dark: 0x6FD39B)
    public static let goodTint = Color(light: 0xE6F4EC, dark: 0x12301F)
    public static let warn = Color(light: 0x9A6A12, dark: 0xE8B962)
    public static let warnTint = Color(light: 0xFBF3E2, dark: 0x3A2E12)
    public static let bad = Color(light: 0xB42323, dark: 0xF09393)
    public static let badTint = Color(light: 0xFBEAEA, dark: 0x3A1717)
}

/// `Brand.primary` etc. read the same as Android's `Brand`.
public typealias Brand = BucksColor

/// 10 controls and menus, 14 fields and buttons, 20 cards, 28 sheets.
public enum BucksRadius {
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 14
    public static let large: CGFloat = 20
    public static let sheet: CGFloat = 28
}

/// Horizontal screen padding (Android `Gutter = 20.dp`).
public let Gutter: CGFloat = 20

/// Motion.kt timings, in milliseconds (`seconds` helpers for SwiftUI).
public enum Motion {
    public static let SHORT = 150, MEDIUM = 280, LONG = 450
    public static let short: Double = 0.150, medium: Double = 0.280, long: Double = 0.450
    /// Material "emphasized": quick start, gentle landing.
    public static func emphasized(_ seconds: Double = medium) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: seconds) }
}

/// The Android Typography scale.
public enum BucksTextStyle: CaseIterable {
    case displaySmall, headlineMedium, headlineSmall, titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall, labelLarge, labelMedium, labelSmall

    public var size: CGFloat {
        switch self {
        case .displaySmall: 34
        case .headlineMedium: 26
        case .headlineSmall: 22
        case .titleLarge: 18
        case .titleMedium, .bodyLarge, .labelLarge: 15
        case .titleSmall: 13
        case .bodyMedium: 14
        case .bodySmall, .labelMedium: 12
        case .labelSmall: 11
        }
    }
    public var weight: Font.Weight {
        switch self {
        case .displaySmall: .heavy
        case .headlineMedium, .headlineSmall, .titleLarge, .labelLarge: .bold
        case .titleMedium, .titleSmall, .labelMedium, .labelSmall: .semibold
        case .bodyLarge, .bodyMedium, .bodySmall: .medium
        }
    }
    /// Line height in points (nil = font default).
    public var lineHeight: CGFloat? {
        switch self {
        case .displaySmall: 38
        case .headlineMedium: 31
        case .headlineSmall: 27
        case .titleLarge: 23
        case .titleMedium: 20
        case .titleSmall: 18
        case .bodyLarge: 22
        case .bodyMedium: 20
        case .bodySmall: 16
        default: nil
        }
    }
    public var tracking: CGFloat {
        switch self {
        case .displaySmall: -1
        case .headlineMedium: -0.6
        case .headlineSmall: -0.4
        case .titleLarge: -0.2
        default: 0
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .displaySmall: .largeTitle
        case .headlineMedium, .headlineSmall: .title
        case .titleLarge: .title3
        case .titleMedium, .titleSmall, .bodyLarge, .bodyMedium: .body
        case .bodySmall, .labelMedium, .labelSmall: .caption
        case .labelLarge: .body
        }
    }
}

public enum BucksFonts {
    private static let family: String? = {
        guard let url = Bundle.module.url(forResource: "Manrope", withExtension: "ttf") else { return nil }
        // Already registered (second launch of a test host, previews): still resolve the family name.
        var err: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        guard let d = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else { return nil }
        return CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String
    }()

    /// Registers Manrope with the process. Safe to call any number of times.
    @discardableResult public static func register() -> Bool { family != nil }
    static var familyName: String? { family }
}

public extension Font {
    /// Manrope at the Android size and weight, scaling with Dynamic Type; system font if Manrope is missing.
    static func bucks(_ style: BucksTextStyle) -> Font {
        if let f = BucksFonts.familyName {
            return .custom(f, size: style.size, relativeTo: style.relativeTo).weight(style.weight)
        }
        return .system(size: style.size, weight: style.weight)
    }
}

public extension View {
    /// Font plus line height for any view (tracking needs `Text.bucks(_:)`).
    func bucksFont(_ style: BucksTextStyle) -> some View {
        modifier(BucksFontModifier(style: style))
    }
}

private struct BucksFontModifier: ViewModifier {
    let style: BucksTextStyle
    func body(content: Content) -> some View {
        content.font(.bucks(style)).lineSpacing(max(0, (style.lineHeight ?? style.size * 1.3) - style.size * 1.3))
    }
}

public extension Text {
    /// Style with Manrope, tracking and line height: `Text("Hi").bucks(.titleLarge)`.
    func bucks(_ style: BucksTextStyle) -> some View {
        self.font(.bucks(style)).tracking(style.tracking).bucksFont(style)
    }
}
