import SwiftUI
import BucksCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Cross-platform shims: BucksUI also builds on macOS (no iOS SDK needed), where iOS-only modifiers become no-ops.

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that follows the system light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #elseif canImport(AppKit)
        self.init(NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #else
        self.init(hex: light)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

public enum BucksKeyboard { case `default`, number, decimal, phone, email, url }

public extension View {
    /// Keyboard type for the next text field (iOS only).
    @ViewBuilder func bucksKeyboard(_ kind: BucksKeyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .default: self.keyboardType(.default)
        case .number: self.keyboardType(.numberPad)
        case .decimal: self.keyboardType(.decimalPad)
        case .phone: self.keyboardType(.phonePad)
        case .email: self.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .url: self.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        #else
        self
        #endif
    }

    /// Small inline navigation title (iOS only).
    @ViewBuilder func bucksInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Full-screen cover on iOS, a sheet on macOS.
    @ViewBuilder func bucksFullScreenCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Capitalise every character (plates, codes).
    @ViewBuilder func bucksAutocapCharacters() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters).autocorrectionDisabled()
        #else
        self
        #endif
    }

    /// Hide the navigation bar's own background/toolbar chrome (iOS only).
    @ViewBuilder func bucksHideNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// Light taps on confirming actions. No-op off iOS.
@MainActor public enum Haptics {
    public static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    public static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    public static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    public static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

/// True when the system or the person's own "Reduce motion" setting (Appearance and data) asks for it; loops and entrances then stay still.
public var bucksReduceMotion: Bool {
    let own = Thread.isMainThread ? MainActor.assumeIsolated { Prefs.shared.reduceMotion } : false
    #if canImport(UIKit)
    return own || UIAccessibility.isReduceMotionEnabled
    #elseif canImport(AppKit)
    return own || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    #else
    return own
    #endif
}

public extension View {
    /// Lets iOS offer the SMS code above the keyboard.
    @ViewBuilder func bucksOneTimeCode() -> some View {
        #if os(iOS)
        self.textContentType(.oneTimeCode)
        #else
        self
        #endif
    }
}


private struct OpenBucksMenuKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
public extension EnvironmentValues {
    /// Opens the "Bucks Pro" side menu (the hamburger button on tab roots). The app shell provides it.
    var openBucksMenu: () -> Void { get { self[OpenBucksMenuKey.self] } set { self[OpenBucksMenuKey.self] = newValue } }
}
