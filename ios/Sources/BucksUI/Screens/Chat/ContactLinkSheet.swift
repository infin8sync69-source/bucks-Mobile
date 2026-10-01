import SwiftUI
import BucksCore

/// Attach contact details to a person I'm synced with: their number, email, organisation, place and a note. Private: only I see it,
/// and it doesn't change their Bucks profile. The details can come from my phonebook (the best match is offered first) or be typed.
/// `prefill` starts the form from a phonebook contact (the Contacts screen uses this).
struct ContactLinkSheet: View {
    let person: ProfileRow
    var prefill: PhoneContact?
    let onDismiss: () -> Void

    @Environment(AppSession.self) private var session
    @State private var phones = ""
    @State private var emails = ""
    @State private var org = ""
    @State private var title = ""
    @State private var address = ""
    @State private var note = ""
    @State private var loaded = false
    @State private var picking = false

    init(person: ProfileRow, prefill: PhoneContact? = nil, onDismiss: @escaping () -> Void) { self.person = person; self.prefill = prefill; self.onDismiss = onDismiss }

    private var existing: ContactLinkRow? { session.social.links[person.id] }
    private var badEmail: String? { PhoneContacts.splitList(emails).first { !$0.contains("@") || !$0.contains(".") } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Contact details for \(person.name)").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("Only you can see this. It doesn't change \(person.name.components(separatedBy: " ")[0])'s Bucks profile, and they aren't told.").padding(.top, 2).padding(.bottom, 12)
                SmallButton("Pick from my phonebook", tonal: true) { pick() }.padding(.bottom, 12)
                BucksField(limited($phones, 200), label: "Mobile numbers", placeholder: "98450 12345, 080 2222 3333", keyboard: .phone)
                BucksField(limited($emails, 300), label: "Emails", placeholder: "name@example.com", keyboard: .email)
                HStack(alignment: .top, spacing: 10) {
                    BucksField(limited($org, 120), label: "Organisation", placeholder: "Bala Electricals")
                    BucksField(limited($title, 120), label: "Role", placeholder: "Owner")
                }
                BucksField(limited($address, 300), label: "Location", placeholder: "JP Nagar 2nd Phase, Bengaluru")
                BucksField(limited($note, 500), label: "Note", placeholder: "Met at the market, does home visits", singleLine: false, minLines: 2)
                PrimaryButton("Save", enabled: badEmail == nil) {
                    session.social.saveLink(ContactLinkRow(profileId: person.id, phones: PhoneContacts.splitList(phones).map { String($0.prefix(40)) },
                                                           emails: PhoneContacts.splitList(emails).map { String($0.prefix(120)) }, org: org.trimmingCharacters(in: .whitespacesAndNewlines),
                                                           title: title.trimmingCharacters(in: .whitespacesAndNewlines), address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                                                           note: note.trimmingCharacters(in: .whitespacesAndNewlines)), then: onDismiss)
                }
                if let bad = badEmail { Muted("\"\(bad)\" isn't an email address.").padding(.top, 6) }
                if existing != nil { BadButton("Remove these details") { session.social.removeLink(person.id); onDismiss() }.padding(.top, 4) }
            }.padding(.horizontal, Gutter).padding(.top, 24).padding(.bottom, 28)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .onAppear(perform: fill)
        .sheet(isPresented: $picking) {
            PhonebookPicker(forName: person.name) { c in
                phones = c.phones.joined(separator: ", "); emails = c.emails.joined(separator: ", ")
                if !c.org.isEmpty { org = c.org }; if !c.title.isEmpty { title = c.title }; if !c.address.isEmpty { address = c.address }
                picking = false
            }.presentationDetents([.large])
        }
    }

    private func limited(_ b: Binding<String>, _ n: Int) -> Binding<String> { Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.prefix(n)) }) }

    private func fill() {
        guard !loaded else { return }
        loaded = true
        phones = (existing?.phones ?? prefill?.phones ?? []).joined(separator: ", ")
        emails = (existing?.emails ?? prefill?.emails ?? []).joined(separator: ", ")
        org = existing?.org ?? prefill?.org ?? ""; title = existing?.title ?? prefill?.title ?? ""
        address = existing?.address ?? prefill?.address ?? ""; note = existing?.note ?? ""
    }

    private func pick() {
        switch PhoneContacts.access {
        case .granted: picking = true
        case .notAsked: Task { if await PhoneContacts.requestAccess() { picking = true } else { session.toast("Contacts permission is off. You can still type the details.") } }
        case .denied: session.toast("Contacts permission is off. You can still type the details.")
        }
    }
}

/// A searchable phonebook list; the contacts whose names best match `forName` come first.
private struct PhonebookPicker: View {
    let forName: String
    let onPick: (PhoneContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var all: [PhoneContact]?
    @State private var q = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pick from phonebook").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
            }.padding(.bottom, 12)
            BucksField($q, placeholder: "Search name, number or company")
            if let list = all {
                let t = q.trimmingCharacters(in: .whitespaces)
                let shown = list.filter { $0.matches(t) }.sorted {
                    let a = t.isEmpty ? PhoneContacts.nameScore(forName, $0.name) : 0, b = t.isEmpty ? PhoneContacts.nameScore(forName, $1.name) : 0
                    return a != b ? a > b : $0.name.lowercased() < $1.name.lowercased()
                }
                if shown.isEmpty { Muted("Nobody matches.") }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown.prefix(80)) { c in
                            let best = t.isEmpty && PhoneContacts.nameScore(forName, c.name) > 0
                            ListRow(c.name, subtitle: [best ? "Likely match" : nil, c.org.isEmpty ? nil : c.org, c.phones.first].compactMap { $0 }.joined(separator: " · "),
                                    onTap: { onPick(c) }, leading: { Avatar(initials: c.initials, size: 36) })
                                .padding(.horizontal, -20)
                            BucksDivider()
                        }
                    }
                }
            } else { BucksLoader().frame(maxWidth: .infinity).padding(24); Spacer() }
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .background(BucksColor.surface.ignoresSafeArea())
        .task { all = await PhoneContacts.load() }
    }
}

/// Choose which synced person a phonebook contact belongs to; the contact's details are attached to them.
struct PickSyncedPersonSheet: View {
    let contact: PhoneContact
    let onDismiss: () -> Void
    @Environment(AppSession.self) private var session
    @State private var q = ""

    var body: some View {
        let social: SocialStore = session.social
        let people = social.synced.filter { q.trimmingCharacters(in: .whitespaces).isEmpty || $0.name.localizedCaseInsensitiveContains(q.trimmingCharacters(in: .whitespaces)) }
            .sorted {
                let a = PhoneContacts.nameScore(contact.name, $0.name), b = PhoneContacts.nameScore(contact.name, $1.name)
                return a != b ? a > b : $0.name.lowercased() < $1.name.lowercased()
            }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Who is \(contact.name)?").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel", action: onDismiss).buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
            }.padding(.bottom, 12)
            if social.synced.isEmpty {
                Muted("Sync with them on Bucks first (Menu > Bucks Pro > Bucks ID, or the Sync screen), then attach their contact details here.")
            } else {
                Muted("Attach \(contact.name)'s details to a person you're synced with. Only you see them.").padding(.bottom, 8)
                BucksField($q, placeholder: "Search your synced people")
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { p in
                            ListRow(p.name, subtitle: [PhoneContacts.nameScore(contact.name, p.name) > 0 ? "Likely match" : nil, p.area.isEmpty ? nil : p.area].compactMap { $0 }.joined(separator: " · "),
                                    onTap: { attach(p) }, leading: { Avatar(initials: initials(p.name), size: 36) })
                                .padding(.horizontal, -20)
                            BucksDivider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .background(BucksColor.surface.ignoresSafeArea())
    }

    private func attach(_ p: ProfileRow) {
        let note = session.social.links[p.id]?.note ?? ""
        session.social.saveLink(ContactLinkRow(profileId: p.id, phones: Array(contact.phones.prefix(5)), emails: Array(contact.emails.prefix(5)), org: String(contact.org.prefix(120)),
                                               title: String(contact.title.prefix(120)), address: String(contact.address.prefix(300)), note: note), then: onDismiss)
    }
}
