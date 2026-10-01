import SwiftUI
import CoreText

/// Palette from Theme.kt (Light / Dark colour schemes plus StatusColors).
public enum BucksColor {
    // Fixed brand colours.
    public static let purple = Color(hex: 0x811FF0)
    public static let purpleDeep = Color(hex: 0x4A0AA6)
    public static let purpleTint = Color(hex: 0xEFE6FE)
    public static let ink = Color(hex: 0x15111C)

    public static let primary = Color(light: 0x811FF0, dark: 0xA874FF)
    public static let onPrimary = Color(light: 0xFFFFFF, dark: 0x23074F)
    public static let primaryContainer = Color(light: 0xEFE6FE, dark: 0x2A1D45)
    public static let onPrimaryContainer = Color(light: 0x4A0AA6, dark: 0xD2B8FF)
    /// Dark buttons: ink in light mode, near-white in dark mode.
    public static let secondary = Color(light: 0x15111C, dark: 0xEFEBF6)
    public static let onSecondary = Color(light: 0xFFFFFF, dark: 0x15111C)
    public static let secondaryContainer = Color(light: 0xEDEAF3, dark: 0x2A2533)
    public static let onSecondaryContainer = Color(light: 0x15111C, dark: 0xEFEBF6)
    public static let background = Color(light: 0xFAF9FC, dark: 0x0F0C14)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x15111C)
    public static let surfaceVariant = Color(light: 0xF3F1F7, dark: 0x1E1926)
    public static let surfaceContainerLow = Color(light: 0xFBFAFD, dark: 0x17131F)
    public static let surfaceContainer = Color(light: 0xF6F4F9, dark: 0x1B1723)
    public static let surfaceContainerHigh = Color(light: 0xF0EDF4, dark: 0x221D2C)
    public static let onSurface = Color(light: 0x15111C, dark: 0xEFEBF6)
    public static let onSurfaceVariant = Color(light: 0x5F586C, dark: 0xB2ABBF)
    public static let outline = Color(light: 0xE4E0EB, dark: 0x2E2838)
    public static let outlineVariant = Color(light: 0xEDEAF1, dark: 0x241F2D)
    public static let error = Color(light: 0xB42323, dark: 0xF09393)

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
