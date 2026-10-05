import SwiftUI
import BucksCore

/// A person in a list: avatar, name, a line under it (area, or their Bucks ID when there is none) and a trailing control. Ends with a divider.
struct PersonRow<Trailing: View>: View {
    let p: ProfileRow
    var sub: String?
    @ViewBuilder var trailing: Trailing

    init(_ p: ProfileRow, sub: String? = nil, @ViewBuilder trailing: () -> Trailing) { self.p = p; self.sub = sub; self.trailing = trailing() }

    var body: some View {
        let line = sub ?? p.area
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Avatar(initials: initials(p.name), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted(line.isEmpty ? BucksIdCode.pretty(p.shortCode) : line)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                trailing
            }.padding(.vertical, 8)
            BucksDivider()
        }
    }
}

/// Sync: enter or scan a Bucks ID, answer requests, browse suggestions, manage synced people.
struct SyncScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var code = ""
    @State private var menuFor: ProfileRow?
    @State private var linkFor: ProfileRow?
    @State private var scanning = false

    private var social: SocialStore { session.social }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Sync", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FieldLabel("Bucks ID")
                        HStack(alignment: .top, spacing: 8) {
                            BucksField(Binding(get: { code }, set: { code = String($0.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8)) }), placeholder: "H6VF YWYF")
                                .bucksAutocapCharacters()
                            Button(action: scan) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 22)).foregroundStyle(BucksColor.onSecondaryContainer)
                                    .frame(width: 56, height: 56).background(Circle().fill(BucksColor.secondaryContainer))
                            }.buttonStyle(.plain).accessibilityLabel("Scan a Bucks ID")
                        }
                        PrimaryButton("Send sync request", enabled: BucksQr.looksLikeBucksId(code)) { social.syncWithCode(code); code = "" }.padding(.top, -4)
                        Muted("Sync is two-way: once they accept, you see each other's posts and Moments and can message.").padding(.top, 8)

                        if !social.incoming.isEmpty {
                            SectionTitle("Requests").padding(.top, 24).padding(.bottom, 6)
                            ForEach(social.incoming) { p in
                                PersonRow(p) { HStack(spacing: 6) { SmallButton("Accept") { social.acceptSync(p.id) }; SmallButton("Ignore", tonal: true) { social.unsync(p.id) } } }
                            }
                        }
                        if !social.suggestions.isEmpty {
                            SectionTitle("People you may know").padding(.top, 24).padding(.bottom, 6)
                            ForEach(social.suggestions.prefix(8)) { s in suggestion(s) }
                        }
                        SectionTitle("Synced with you").padding(.top, 24).padding(.bottom, 6)
                        if social.synced.isEmpty { Muted("Nobody yet. Share your Bucks ID or scan a friend's.") }
                        else { Muted("Tap the three dots, then Contact details, to attach a number, email or company you already have for someone. Only you see it.").padding(.bottom, 4) }
                        ForEach(social.synced) { p in syncedRow(p) }
                        Spacer().frame(height: 24)
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { social.refreshSyncs(); social.refreshSuggestions(); social.refreshLinks() }
        .confirmationDialog(menuFor?.name ?? "", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }), titleVisibility: .visible, presenting: menuFor) { p in
            let close = social.closeFriends.contains(p.id)
            Button(social.links[p.id] != nil ? "Edit contact details" : "Contact details") { linkFor = p }
            Button(close ? "Remove from close friends" : "Add to close friends") { social.setClose(p.id, on: !close) }
            Button("Unsync") { social.unsync(p.id) }
            Button("Block", role: .destructive) { social.block(p.id) }
            Button("Close", role: .cancel) {}
        }
        .sheet(item: $linkFor) { p in ContactLinkSheet(person: p) { linkFor = nil }.presentationDetents([.large]) }
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            QRScannerSheet(onResult: scanned, onUnavailable: { session.toast("The scanner isn't available on this phone yet. Type the code instead.") })
        }
        #endif
    }

    private func scan() {
        #if os(iOS)
        scanning = true
        #else
        session.toast("The scanner isn't available on this phone yet. Type the code instead.")
        #endif
    }
    private func scanned(_ raw: String) {
        if case .bucksId(let c) = BucksQr.parse(raw) { social.syncWithCode(c) } else { session.toast("That isn't a Bucks ID code.") }
    }

    private func suggestion(_ s: PersonSuggestion) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Avatar(initials: initials(s.name), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted([s.area.isEmpty ? nil : s.area, s.mutual > 0 ? "\(s.mutual) mutual" : nil, s.distanceM.map { String(format: "%.1f km", $0 / 1000) }].compactMap { $0 }.joined(separator: " · "))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                SmallButton("Sync", tonal: true) { social.syncWith(s.id, name: s.name) }
            }.padding(.vertical, 8)
            BucksDivider()
        }
    }

    private func syncedRow(_ p: ProfileRow) -> some View {
        let link = social.links[p.id]
        let linkLine = link.map { [$0.org.isEmpty ? nil : $0.org, $0.phones.first, $0.emails.first].compactMap { $0 }.joined(separator: " · ") }
        let sub = (linkLine?.isEmpty == false ? linkLine : nil) ?? (social.closeFriends.contains(p.id) ? "Close friend" : p.area)
        return PersonRow(p, sub: sub) {
            HStack(spacing: 0) {
                if let num = link?.phones.first {
                    Button { openSystemURL("tel:" + PhoneContacts.dialable(num)) } label: {
                        Image(systemName: "phone").font(.system(size: 16)).foregroundStyle(BucksColor.primary).frame(width: 38, height: 38).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Call \(p.name)")
                }
                Button { Task { if let id = await session.chat.openDirect(p.id) { router.push(.chat(id)) } } } label: {
                    Image(systemName: "bubble.left").font(.system(size: 16)).foregroundStyle(BucksColor.onSecondaryContainer).frame(width: 38, height: 38).background(Circle().fill(BucksColor.secondaryContainer))
                }.buttonStyle(.plain).accessibilityLabel("Message")
                Button { menuFor = p } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("More")
            }
        }
    }
}
