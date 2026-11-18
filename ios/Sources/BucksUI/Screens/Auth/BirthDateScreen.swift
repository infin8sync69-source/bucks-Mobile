import SwiftUI
import BucksCore

/// Date of birth, asked once after sign-in (onboarding/OnboardingScreens.kt NameScreen). Free entry with no default and no picker limited
/// to "allowed" years: the neutral way to ask. The server decides the age band and refuses anyone below the sign-up age.
struct BirthDateScreen: View {
    @Environment(AppSession.self) private var session
    @State private var dd = ""
    @State private var mm = ""
    @State private var yyyy = ""
    @State private var busy = false
    @State private var tried = false
    @State private var error: String?

    /// yyyy-MM-dd when the three boxes make a real date in the past, else nil.
    private var isoDate: String? {
        guard yyyy.count == 4, let y = Int(yyyy), let m = Int(mm), let d = Int(dd), y >= 1900 else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = DateComponents(year: y, month: m, day: d)
        guard parts.isValidDate(in: cal), let date = cal.date(from: parts), date < Date() else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    var body: some View {
        ContentColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Headline("When's your birthday?")
                    Muted("Needed once to finish setting up your account. It isn't shown on your profile.").padding(.top, 8).padding(.bottom, 24)
                    FieldLabel("Date of birth")
                    HStack(spacing: 10) {
                        BucksField(digits($dd, 2), placeholder: "DD", keyboard: .number).frame(width: 84)
                        BucksField(digits($mm, 2), placeholder: "MM", keyboard: .number).frame(width: 84)
                        BucksField(digits($yyyy, 4), placeholder: "YYYY", keyboard: .number).frame(width: 112)
                    }
                    if tried && isoDate == nil { Text("Check the date").bucks(.bodyMedium).foregroundStyle(BucksColor.bad).padding(.top, 8) }
                    if let error { Text(error).bucks(.bodyMedium).foregroundStyle(BucksColor.bad).padding(.top, 8) }
                    PrimaryButton(busy ? "Saving…" : "Continue", enabled: !busy) { save() }.padding(.top, 24)
                    GhostButton("Sign out") { Task { await session.logout() } }.padding(.top, 8)
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
    }

    private func digits(_ text: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(max)) })
    }

    private func save() {
        tried = true
        guard let iso = isoDate, !busy else { return }
        busy = true; error = nil
        Task { error = await session.setBirthDate(iso); busy = false }
    }
}

/// Shown after a date of birth below the sign-up age, and on every later launch from this phone: neutral, no way round it.
struct AgeBlockedScreen: View {
    var body: some View {
        ContentColumn {
            VStack(alignment: .leading, spacing: 0) {
                Headline("You can't create an account right now")
                Muted("Bucks isn't available to you yet.").padding(.top, 8)
            }.padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground()
    }
}
