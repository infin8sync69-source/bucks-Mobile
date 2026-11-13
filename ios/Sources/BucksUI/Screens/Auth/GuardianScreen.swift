import SwiftUI
import BucksCore

/// A parent's or guardian's consent for an under-18 account (ui/social/Onboarding.kt GuardianScreen). Shown after the date of birth, and on
/// every launch until it is given: the server refuses a minor's posts, messages and orders without it.
struct GuardianScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var phone = ""
    @State private var relation = "PARENT"
    @State private var agree = false
    @State private var busy = false
    @State private var error: String?

    private static let privacyURL = URL(string: "https://infin8sync69-source.github.io/bucks-Mobile/legal/privacy")!
    private var ok: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && phone.count == 10 && agree }

    var body: some View {
        ContentColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        GhostButton("Sign out") { Task { await session.logout() } }
                    }
                    Image(systemName: "figure.2.and.child.holdinghands")
                        .font(.system(size: 28)).foregroundStyle(BucksColor.primary)
                        .frame(width: 64, height: 64).background(Circle().fill(BucksColor.primary.opacity(0.14)))
                        .accessibilityHidden(true)
                    Headline("Ask a parent or guardian").padding(.top, 20)
                    Muted("You're under 18, so a parent or guardian must agree before you use Bucks. Hand your phone to them for this step.")
                        .padding(.top, 8).padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("For parents: how Bucks protects teens").bucks(.titleSmall)
                        rule("Their profile is private. Adults they aren't connected to can't find them in search or suggestions.")
                        rule("Only people they've synced with can message them.")
                        rule("Their exact location is never stored. Nearby posts use an area of about 2 km.")
                        rule("Anyone can report a post, message or account. Our team reviews every report.")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(BucksColor.surfaceContainer))

                    BucksField(Binding(get: { name }, set: { name = String($0.prefix(80)) }), label: "Parent or guardian's full name", placeholder: "Name")
                        .padding(.top, 18)
                    FieldLabel("Their mobile number").padding(.top, 12)
                    HStack(spacing: 10) {
                        BucksField(.constant("+91"), readOnly: true).frame(width: 80)
                        BucksField(Binding(get: { phone }, set: { phone = String($0.filter(\.isNumber).prefix(10)) }), placeholder: "98765 43210", keyboard: .phone)
                    }
                    FieldLabel("You are their").padding(.top, 12)
                    HStack(spacing: 8) {
                        BucksChip("Parent", selected: relation == "PARENT") { relation = "PARENT" }
                        BucksChip("Legal guardian", selected: relation == "GUARDIAN") { relation = "GUARDIAN" }
                    }

                    Button { agree.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agree ? "checkmark.square.fill" : "square").font(.system(size: 22))
                                .foregroundStyle(agree ? BucksColor.primary : BucksColor.onSurfaceVariant)
                            Text("I'm this person's parent or legal guardian. I agree to them using Bucks and to Bucks processing their data as the Privacy Policy describes.")
                                .bucks(.bodyMedium).multilineTextAlignment(.leading)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.top, 16)
                    .accessibilityAddTraits(agree ? .isSelected : [])

                    GhostButton("Read the Privacy Policy") { openURL(Self.privacyURL) }.padding(.top, 4)
                    if let error { Text(error).bucks(.bodyMedium).foregroundStyle(BucksColor.bad).padding(.top, 8) }
                    PrimaryButton(busy ? "Saving…" : "Agree and continue", enabled: ok && !busy) { save() }.padding(.top, 8)
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
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
        guard ok, !busy else { return }
        busy = true; error = nil
        Task { error = await session.recordGuardianConsent(name: name.trimmingCharacters(in: .whitespaces), phone: "+91" + phone, relation: relation); busy = false }
    }
}
