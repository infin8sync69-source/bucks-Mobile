import SwiftUI
import BucksCore

/// Who can message and sync with me, the default Moments audience, read receipts, online status and discoverability.
struct PrivacyScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var edited: SettingsRow?

    private var saved: SettingsRow { session.social.settings ?? SettingsRow(profileId: session.me?.id ?? "") }
    private var row: Binding<SettingsRow> { Binding(get: { edited ?? saved }, set: { edited = $0 }) }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Privacy", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsChoiceGroup("Who can message me", detail: "People on an active trip or order with you can always message you.",
                                            options: [("SYNCED", "People I've synced with"), ("EVERYONE", "Everyone"), ("NOBODY", "Nobody new")], selected: row.whoCanMessage)
                        SettingsChoiceGroup("Who can send me sync requests", options: [("EVERYONE", "Everyone"), ("NOBODY", "Nobody")], selected: row.whoCanSync)
                        SettingsChoiceGroup("Default audience for my Moments", detail: "You can change it on each moment.",
                                            options: [("SYNCED", "Synced people"), ("LOCAL", "Synced people and neighbours within 5 km"), ("CLOSE", "Close friends only")], selected: row.momentsAudience)
                        SettingsToggleRow("Read receipts", detail: "Off: nobody sees when you've read, and you don't see it either.", on: row.readReceipts)
                        SettingsToggleRow("Show when I'm online", on: row.showOnline)
                        SettingsToggleRow("Suggest me to people nearby", detail: "Off: you won't appear under 'People you may know'.", on: row.discoverable)
                        Muted("Your phone number is never shown to other users. Drivers and customers see each other's number only during a trip or delivery.").padding(.top, 12)
                        PrimaryButton("Save", enabled: row.wrappedValue != saved) { session.social.saveSettings(row.wrappedValue) }.padding(.top, 20)
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .onChange(of: session.social.settings) { _, _ in edited = nil }
    }
}
