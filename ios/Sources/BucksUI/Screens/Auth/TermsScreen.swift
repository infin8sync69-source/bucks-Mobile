import SwiftUI
import BucksCore

/// "I agree to the Terms and Privacy Policy", right after sign-in and whenever the Terms change (the server's terms_status decides).
/// Same text as Android's onboarding checkbox and its "We've updated our Terms" dialog (ui/BucksAppUi.kt). Nothing else opens until it is accepted.
struct TermsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var agree = false
    @State private var busy = false
    @State private var error: String?

    private static let base = "https://infin8sync69-source.github.io/bucks-Mobile/legal/"

    var body: some View {
        ContentColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        GhostButton("Sign out") { Task { await session.logout() } }
                    }
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 28)).foregroundStyle(BucksColor.primary)
                        .frame(width: 64, height: 64).background(Circle().fill(BucksColor.primary.opacity(0.14)))
                        .accessibilityHidden(true)
                    Headline("Terms and Privacy Policy").padding(.top, 20)
                    Muted("Please read and agree before you use Bucks.").padding(.top, 8).padding(.bottom, 20)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("In short").bucks(.titleSmall)
                        rule("Bucks connects you with people, drivers and shops. They're independent, and payments go directly between you and them.")
                        rule("You're responsible for what you do on Bucks. Breaking the law can be a crime, and we remove people who do.")
                        rule("We keep records of accounts, trips and orders, and share them with the police or courts when the law requires it.")
                        rule("In an emergency call 112. Bucks is not an emergency service.")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(BucksColor.surfaceContainer))

                    HStack(spacing: 4) {
                        GhostButton("Terms") { if let u = URL(string: Self.base + "terms") { openURL(u) } }
                        GhostButton("Privacy") { if let u = URL(string: Self.base + "privacy") { openURL(u) } }
                        GhostButton("Guidelines") { if let u = URL(string: Self.base + "community-guidelines") { openURL(u) } }
                    }.padding(.top, 12)

                    Button { agree.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agree ? "checkmark.square.fill" : "square").font(.system(size: 22))
                                .foregroundStyle(agree ? BucksColor.primary : BucksColor.onSurfaceVariant)
                            Text("I agree to the Terms and Privacy Policy.").bucks(.bodyMedium).multilineTextAlignment(.leading)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.top, 12)
                    .accessibilityAddTraits(agree ? .isSelected : [])

                    if let error { Text(error).bucks(.bodyMedium).foregroundStyle(BucksColor.bad).padding(.top, 8) }
                    PrimaryButton(busy ? "Saving…" : "Agree and continue", enabled: agree && !busy) { save() }.padding(.top, 12)
                }.padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(BucksColor.primary).padding(.top, 2)
                .accessibilityHidden(true)
            Text(text).bucks(.bodyMedium)
        }.padding(.top, 8)
    }

    private func save() {
        guard agree, !busy else { return }
        busy = true; error = nil
        Task { error = await session.acceptTerms(); busy = false }
    }
}
