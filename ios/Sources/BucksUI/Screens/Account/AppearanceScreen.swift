import SwiftUI
import BucksCore

extension Prefs {
    /// The scheme the person forced, or nil to follow the phone. Apply with `.preferredColorScheme(Prefs.shared.colorScheme)` at the app root.
    var colorScheme: ColorScheme? { forcedDark.map { $0 ? .dark : .light } }

    /// The Dynamic Type size for the person's text size (Small, Normal, Large, Huge). Apply with `.dynamicTypeSize(Prefs.shared.dynamicTypeSize)`.
    var dynamicTypeSize: DynamicTypeSize {
        switch textSize { case .small: .small; case .normal: .large; case .large: .xLarge; case .huge: .xxxLarge }
    }
}

/// Appearance and data: theme, text size, motion, media downloads, data saver and language. Stored on this phone (Prefs).
struct AppearanceScreen: View {
    @Environment(Router.self) private var router
    private var prefs: Prefs { Prefs.shared }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Appearance and data", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AccountChoiceGroup(title: "Theme", options: Prefs.Theme.allCases.map { ($0, $0.label) }, selected: prefs.theme) { prefs.chooseTheme($0) }
                        AccountChoiceGroup(title: "Text size", options: Prefs.TextSize.allCases.map { ($0, $0.label) }, selected: prefs.textSize) { prefs.chooseTextSize($0) }
                        AccountToggleRow(label: "Reduce motion", detail: "Turns off pulses and other looping animations.",
                                         isOn: Binding(get: { prefs.reduceMotion }, set: { prefs.enableReduceMotion($0) }))
                        AccountChoiceGroup(title: "Download photos and files", detail: "Applies to chats and Moments on mobile data.",
                                           options: Prefs.MediaDownload.allCases.map { ($0, $0.label) }, selected: prefs.mediaDownload) { prefs.chooseMediaDownload($0) }
                        AccountToggleRow(label: "Data saver", detail: "Lighter maps and smaller images.",
                                         isOn: Binding(get: { prefs.dataSaver }, set: { prefs.enableDataSaver($0) }))
                        AccountChoiceGroup(title: "App language", detail: "Menus and buttons. Translations are being added; English is complete.",
                                           options: Prefs.languages.map { ($0.tag, $0.name) }, selected: prefs.language) { prefs.chooseLanguage($0) }
                    }.padding(Gutter)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
    }
}
