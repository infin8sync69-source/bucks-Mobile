import SwiftUI
import BucksCore

/// Contacts: the phone's address book, searchable, with what each person has (numbers, emails, organisation, address), a way to call,
/// message or email them through the phone's own apps, and Invite for people who aren't on Bucks yet. Sync (Bucks people) is separate.
/// The address book is read here on the phone and never uploaded.
struct ContactsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var access = PhoneContacts.access
    @State private var contacts: [PhoneContact]?
    @State private var q = ""
    @State private var open: String?
    @State private var attachFor: PhoneContact?
    @Environment(\.scenePhase) private var scenePhase

    private var social: SocialStore { session.social }
    private var granted: Bool { access == .granted }

    /// People I attached contact details to are recognised here by their number, so a phonebook entry shows "On Bucks" and can be messaged.
    private var byPhone: [String: ProfileRow] {
        var out: [String: ProfileRow] = [:]
        for p in social.synced { for n in social.links[p.id]?.phones ?? [] { out[PhoneContacts.tail10(n)] = p } }
        return out
    }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Contacts", onBack: { router.pop() }) {
                    if granted { barButton("arrow.clockwise", "Refresh from phonebook") { reload() } }
                    barButton("person.badge.plus", "People I synced with") { router.push(.sync) }
                }
                if !granted { permissionCard } else { list }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task(id: granted) { if granted { contacts = await PhoneContacts.load() } }
        .task { social.refreshSyncs(); social.refreshLinks() }
        // Back from the phone's Settings after allowing contacts there.
        .onChange(of: scenePhase) { _, p in if p == .active { access = PhoneContacts.access } }
        .sheet(item: $attachFor) { c in PickSyncedPersonSheet(contact: c) { attachFor = nil }.presentationDetents([.large]) }
    }

    private func barButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func reload() { Task { contacts = nil; contacts = await PhoneContacts.load() } }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            BucksCard {
                HStack(spacing: 14) {
                    Avatar(systemImage: "person.2.fill", size: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Bring in your phonebook").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("See everyone you know in one searchable list, call or message them, and invite them to Bucks.")
                    }
                }
                Muted("Your contacts are read on this phone and shown only to you. Bucks doesn't upload or store them.").padding(.top, 12)
                PrimaryButton(access == .denied ? "Allow in Settings" : "Allow contacts") { allow() }.padding(.top, 14)
            }
            if access == .denied { Muted("Contacts permission is off. Turn it on in the app's settings, then come back.").padding(.top, 10) }
            Spacer(minLength: 0)
        }.padding(Gutter)
    }

    private func allow() {
        if access == .denied {
            #if canImport(UIKit)
            openSystemURL(UIApplication.openSettingsURLString)
            #endif
        } else {
            Task { _ = await PhoneContacts.requestAccess(); access = PhoneContacts.access }
        }
    }

    @ViewBuilder private var list: some View {
        if let all = contacts {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = all.filter { $0.matches(t) }
            let people = byPhone
            BucksField($q, placeholder: "Search name, number, email, company, place").padding(.horizontal, Gutter).padding(.top, 4).padding(.bottom, -10)
            Muted(t.isEmpty ? "\(all.count) contact\(all.count == 1 ? "" : "s")" : "\(shown.count) of \(all.count)").padding(.horizontal, Gutter).padding(.vertical, 4)
            if all.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No contacts found").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("Your phonebook is empty or has no numbers. Add contacts in your Phone app and tap refresh.")
                }.padding(Gutter)
            } else if shown.isEmpty { Muted("Nobody matches \"\(t)\".").padding(Gutter) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { c in
                        ContactRow(c: c, expanded: open == c.id, onToggle: { open = open == c.id ? nil : c.id },
                                   person: c.phones.compactMap { people[PhoneContacts.tail10($0)] }.first,
                                   onMessage: { p in Task { if let id = await session.chat.openDirect(p.id) { router.push(.chat(id)) } } }, onAttach: { attachFor = c })
                        BucksDivider()
                    }
                }.padding(.bottom, 24)
            }
        } else {
            BucksLoader().frame(maxWidth: .infinity).padding(40)
            Spacer()
        }
    }
}

private struct ContactRow: View {
    let c: PhoneContact
    let expanded: Bool
    let onToggle: () -> Void
    let person: ProfileRow?
    let onMessage: (ProfileRow) -> Void
    let onAttach: () -> Void
    @Environment(AppSession.self) private var session

    private var first: String? { c.phones.first }
    private var inviteText: String { Invite.contactText(firstName: c.name.components(separatedBy: " ")[0]) }

    private func start(_ url: String) { openSystemURL(url) { ok in if !ok { session.toast("No app on this phone can do that.") } } }
    private func encoded(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? s }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Avatar(initials: c.initials, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    let sub = [person.map { "On Bucks as \($0.name)" }, c.org.isEmpty ? nil : c.org, first].compactMap { $0 }.joined(separator: " · ")
                    Muted(sub.isEmpty ? (c.emails.first ?? "") : sub, maxLines: 1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                if let person { SmallButton("Message", tonal: true) { onMessage(person) } } else { inviteMenu }
            }
            if expanded { details.padding(.leading, 56).padding(.top, 8) }
        }
        .padding(.horizontal, Gutter).padding(.vertical, 10).contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private var inviteMenu: some View {
        Menu {
            if let first {
                let num = PhoneContacts.dialable(first)
                Button { start("sms:\(num)&body=\(encoded(inviteText))") } label: { Label("By SMS", systemImage: "message") }
                Button { start("https://wa.me/\(num.filter(\.isNumber))?text=\(encoded(inviteText))") } label: { Label("On WhatsApp", systemImage: "paperplane") }
            }
            ShareLink(item: inviteText) { Label("Other app…", systemImage: "square.and.arrow.up") }
        } label: {
            Text("Invite").font(.bucks(.labelLarge)).foregroundStyle(BucksColor.onSecondaryContainer).padding(.horizontal, 16).frame(minHeight: 36)
                .background(Capsule().fill(BucksColor.secondaryContainer))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if person == nil { SmallButton("Attach to a synced person", tonal: true, action: onAttach) }
            ForEach(c.phones, id: \.self) { p in
                detail("phone", p) {
                    detailButton("phone", "Call \(p)") { start("tel:\(PhoneContacts.dialable(p))") }
                    detailButton("message", "Message \(p)") { start("sms:\(PhoneContacts.dialable(p))") }
                }
            }
            ForEach(c.emails, id: \.self) { e in
                detail("envelope", e) { detailButton("paperplane", "Email \(e)") { start("mailto:\(e)") } }
            }
            if !c.org.isEmpty { detail("briefcase", [c.org, c.title.isEmpty ? nil : c.title].compactMap { $0 }.joined(separator: " · ")) {} }
            if !c.address.isEmpty {
                detail("mappin.and.ellipse", c.address) { detailButton("mappin", "Show on map") { start("http://maps.apple.com/?q=\(encoded(c.address))") } }
            }
        }
    }

    private func detail<A: View>(_ symbol: String, _ text: String, @ViewBuilder actions: () -> A) -> some View {
        HStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 18)
            Text(text).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            actions()
        }
    }
    private func detailButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(BucksColor.primary).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
