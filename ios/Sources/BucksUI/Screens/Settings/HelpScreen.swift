import SwiftUI
import BucksCore

/// Help: common questions, how to reach us, the grievance officer required by the IT Rules 2021, and the legal pages (HelpScreen in
/// ui/social/Settings.kt). The support address and the grievance officer come from the build (`Legal`); without an address there is no
/// mail button, and Help points to the grievance page, which carries the contacts. iOS has no feedback board yet, so there is no link to it.
struct HelpScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    /// Android's questions and answers, with the iOS screens named where they differ (people are found from Home search, Contacts and Sync;
    /// a message is reported by pressing and holding it).
    private static let faq: [(question: String, answer: String)] = [
        ("What is a sync?", "A sync is a two-way connection, like a friend request. Once you're synced, you see each other's posts for syncs and can message each other."),
        ("Who can see my posts?", "You choose for each post: Synced only, Nearby (people within about 5 km), or Everyone. Moments last 24 hours and go to syncs, people nearby or close friends."),
        ("How do I find my friends?", "Search a name or Bucks ID on Home, check your phone contacts from your profile, or scan the Bucks ID QR on their phone in Sync."),
        ("Someone is bothering me. What can I do?", "Open their profile, tap ⋯ and choose Block or Report. To report a message, press and hold it. They aren't told who reported them."),
        ("Why do you ask for my date of birth?", "People under 18 get extra privacy and safety settings, and Indian law needs a parent's consent for them. Your birthday is never shown."),
        ("How do I delete my account?", "Profile → Settings → Delete account. Your profile, posts, Moments, comments and messages are removed. You can also ask us on the account deletion page."),
    ]

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Help and support", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heading("Common questions")
                        ForEach(Self.faq, id: \.question) { FaqItem(question: $0.question, answer: $0.answer) }

                        heading("Contact us").padding(.top, 24)
                        if !Legal.supportEmail.isEmpty {
                            AccountSettingRow(icon: "envelope.fill", label: "Email support", detail: Legal.supportEmail) { mail("Help with Bucks") }
                                .contextMenu {
                                    Button("Copy address", systemImage: "doc.on.doc") { copyToClipboard(Legal.supportEmail); session.toast("Address copied.") }
                                }
                            AccountSettingRow(icon: "ladybug.fill", label: "Report a problem with the app", detail: "Tell us what went wrong") { mail("Problem report") }
                        } else {
                            // No address in this build: the grievance page has the contacts, so there is no mail button that goes nowhere.
                            Muted("Use Report on any post, message or profile. Our team will see it.").padding(.top, 8)
                            AccountSettingRow(icon: "person.text.rectangle.fill", label: "Contact details", detail: "Email and address, on our grievance page") { openURL(Legal.url(.grievance)) }
                        }

                        SectionTitle("Grievance officer").padding(.top, 24)
                        Muted("Under the Information Technology (Intermediary Guidelines) Rules, 2021, you can raise a complaint with our grievance officer. We acknowledge complaints within 24 hours and resolve them within 15 days.").padding(.top, 6)
                        if !Legal.grievanceOfficer.isEmpty {
                            Text(Legal.grievanceOfficer).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).textSelection(.enabled).padding(.top, 8)
                        }
                        AccountSettingRow(icon: "arrow.up.right.square.fill", label: "Grievance details") { openURL(Legal.url(.grievance)) }
                        AccountSettingRow(icon: "trash.fill", label: "Account deletion") { openURL(Legal.url(.deleteAccount)) }

                        SectionTitle("Legal").padding(.top, 24)
                        AccountSettingRow(icon: "hand.raised.fill", label: "Community guidelines") { openURL(Legal.url(.guidelines)) }
                        AccountSettingRow(icon: "lock.shield.fill", label: "Privacy policy") { openURL(Legal.url(.privacy)) }
                        AccountSettingRow(icon: "doc.text.fill", label: "Terms of use") { openURL(Legal.url(.terms)) }
                        AccountSettingRow(icon: "figure.and.child.holdinghands", label: "Child safety standards") { openURL(Legal.url(.childSafety)) }
                    }.padding(Gutter).padding(.bottom, 16)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
    }

    private func heading(_ text: String) -> some View {
        Text(text).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }

    /// Opens the mail app addressed to support, with the build under the message; says where to write when no mail app takes it.
    private func mail(_ subject: String) {
        guard let url = Legal.supportMail(subject: subject) else { return }
        openSystemURL(url.absoluteString) { ok in if !ok { session.toast("No mail app on this phone. Write to \(Legal.supportEmail).") } }
    }
}

/// A question that opens to its answer (FaqItem in Settings.kt). Ends with a divider.
private struct FaqItem: View {
    let question: String
    let answer: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if bucksReduceMotion { expanded.toggle() } else { withAnimation(Motion.emphasized(Motion.short)) { expanded.toggle() } }
            } label: {
                HStack(spacing: 12) {
                    Text(question).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BucksColor.onSurfaceVariant).accessibilityHidden(true)
                }
                .padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the answer" : "Shows the answer")
            if expanded {
                Text(answer).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }
            BucksDivider()
        }
    }
}
