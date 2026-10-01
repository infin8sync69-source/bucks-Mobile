import Foundation
import Observation

/// Appearance and data preferences (port of data/Prefs.kt). They describe this phone, not the person, so they live in UserDefaults and work
/// signed out. Privacy and notification settings live in Supabase (user_settings) because the server enforces them.
@MainActor @Observable
public final class Prefs {
    public enum Theme: String, CaseIterable, Sendable {
        case system = "SYSTEM", light = "LIGHT", dark = "DARK"
        public var label: String { switch self { case .system: "Match phone"; case .light: "Light"; case .dark: "Dark" } }
    }
    public enum TextSize: String, CaseIterable, Sendable {
        case small = "SMALL", normal = "NORMAL", large = "LARGE", huge = "HUGE"
        public var label: String { switch self { case .small: "Small"; case .normal: "Normal"; case .large: "Large"; case .huge: "Huge" } }
        public var scale: Double { switch self { case .small: 0.9; case .normal: 1; case .large: 1.15; case .huge: 1.3 } }
    }
    public enum MediaDownload: String, CaseIterable, Sendable {
        case wifi = "WIFI", always = "ALWAYS", never = "NEVER"
        public var label: String { switch self { case .wifi: "Wi-Fi only"; case .always: "Always"; case .never: "Ask each time" } }
    }

    /// Language tag and its own-script name, as in Prefs.LANGUAGES.
    public static let languages: [(tag: String, name: String)] = [("en", "English"), ("kn", "ಕನ್ನಡ"), ("hi", "हिन्दी"), ("ta", "தமிழ்"), ("te", "తెలుగు"), ("ml", "മലയാളം")]

    public static let shared = Prefs()

    public private(set) var theme: Theme
    public private(set) var textSize: TextSize
    public private(set) var mediaDownload: MediaDownload
    public private(set) var reduceMotion: Bool
    public private(set) var dataSaver: Bool
    public private(set) var language: String

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        textSize = TextSize(rawValue: defaults.string(forKey: "text") ?? "") ?? .normal
        mediaDownload = MediaDownload(rawValue: defaults.string(forKey: "media") ?? "") ?? .wifi
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        dataSaver = defaults.bool(forKey: "dataSaver")
        language = defaults.string(forKey: "language") ?? "en"
    }

    public func chooseTheme(_ t: Theme) { theme = t; defaults.set(t.rawValue, forKey: "theme") }
    public func chooseTextSize(_ t: TextSize) { textSize = t; defaults.set(t.rawValue, forKey: "text") }
    public func chooseMediaDownload(_ m: MediaDownload) { mediaDownload = m; defaults.set(m.rawValue, forKey: "media") }
    public func enableReduceMotion(_ v: Bool) { reduceMotion = v; defaults.set(v, forKey: "reduceMotion") }
    public func enableDataSaver(_ v: Bool) { dataSaver = v; defaults.set(v, forKey: "dataSaver") }
    public func chooseLanguage(_ tag: String) { language = tag; defaults.set(tag, forKey: "language") }

    /// The text size multiplier (Small 0.9 … Huge 1.3).
    public var textScale: Double { textSize.scale }
    /// True when the phone's own colour scheme is overridden; nil when following the phone.
    public var forcedDark: Bool? { switch theme { case .system: nil; case .light: false; case .dark: true } }
}
