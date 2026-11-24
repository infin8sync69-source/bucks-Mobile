import SwiftUI
import BucksCore

/// Messages: two tabs in one place, conversations and everything else that needs me (sync requests, invites, orders, recommendations, documents).
struct MessagesScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var tab: Int
    @Environment(\.openPerson) private var openPerson
    /// 0 Messages, 1 Notifications (the bell opens this screen on Notifications).
    init(startTab: Int = 0) { _tab = State(initialValue: startTab) }
    @State private var menuFor: InboxRow?
    @State private var leaveFor: InboxRow?

    private var chat: ChatStore { session.chat }
    private var chatUnread: Int { chat.inbox.reduce(0) { $0 + $1.unread } }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: tab == 0 ? "Messages" : "Notifications", onBack: { router.pop() }) {
                    if tab == 0 {
                        topAction("person.2.badge.plus", "New group") { router.push(.newGroup) }
                        topAction("person.badge.plus", "Sync with someone") { router.push(.sync) }
                    } else if chat.notesUnread > 0 {
                        topAction("checkmark", "Mark all as read") { chat.markAllNotesRead() }
                    }
                }
                tabRow
                if tab == 1 { NotificationsList().task { session.social.refreshSyncs() } } else { conversations }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { while !Task.isCancelled { chat.refreshInbox(); try? await Task.sleep(nanoseconds: 20_000_000_000) } }
        .confirmationDialog(menuFor.map(rowName) ?? "Chat", isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }), titleVisibility: .visible, presenting: menuFor) { c in
            Button(c.muted ? "Unmute" : "Mute notifications") { chat.mute(c.conversationId, on: !c.muted) }
            if c.kind == "GROUP" { Button("Leave group", role: .destructive) { leaveFor = c } }
            if let o = c.otherId {
                Button("Report \(c.otherName ?? "")", role: .destructive) { session.reportTarget = ReportTarget(kind: "PROFILE", targetId: o, ownerId: o, ownerName: c.otherName ?? "") }
                Button("Block \(c.otherName ?? "")", role: .destructive) { session.social.block(o) }
            }
            Button("Close", role: .cancel) {}
        }
        .bucksConfirm(isPresented: Binding(get: { leaveFor != nil }, set: { if !$0 { leaveFor = nil } }), title: "Leave \(leaveFor?.title ?? "this group")?",
                      message: "You'll stop getting its messages and can't read the chat any more. Someone in the group can add you back later.", confirmTitle: "Leave", destructive: true) {
            if let c = leaveFor { chat.leaveConversation(c.conversationId) }
        }
    }

    private func topAction(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 19)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var tabRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(0, "Messages", chatUnread)
                tabButton(1, "Notifications", chat.notesUnread)
            }
            BucksDivider()
        }.background(BucksColor.surface)
    }
    private func tabButton(_ i: Int, _ label: String, _ count: Int) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(label).bucks(.labelLarge).foregroundStyle(tab == i ? BucksColor.primary : BucksColor.onSurfaceVariant)
                    CountBadge(count)
                }.frame(maxWidth: .infinity, minHeight: 46)
                Rectangle().fill(tab == i ? BucksColor.primary : .clear).frame(height: 3)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == i ? .isSelected : [])
    }

    private func rowName(_ c: InboxRow) -> String { c.otherName ?? c.title ?? "Chat" }

    private var conversations: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if chat.inbox.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Muted("No conversations yet. Sync with someone, then message them from their profile, or start a group with people you've synced with.")
                        SmallButton("New group", tonal: true) { router.push(.newGroup) }.padding(.top, 12)
                    }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(chat.inbox.filter { !$0.archived }) { c in row(c); BucksDivider() }
            }
        }
    }

    private func row(_ c: InboxRow) -> some View {
        // A listing chat names the customer for the people who run the listing (the server fills other_* only for them); customers see the listing.
        let customerRow = c.kind == "LISTING" && c.otherName != nil
        let name = c.otherName ?? c.title ?? (c.kind == "GROUP" ? "Group" : "Chat")
        let sub = [customerRow ? c.title.map { "about \($0)" } : nil, c.lastBody.map { String($0.prefix(60)) }, feedAgo(c.lastAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        return ListRow(name, subtitle: sub, onTap: { router.push(.chat(c.conversationId)) }, leading: {
            ZStack(alignment: .bottomTrailing) {
                if c.kind == "GROUP" { Avatar(systemImage: "person.2.fill") }
                // In a direct chat the picture opens the person's profile; the rest of the row opens the chat.
                else if c.kind == "DIRECT", let o = c.otherId { Avatar(initials: initials(name)).highPriorityGesture(TapGesture().onEnded { openPerson?(o) }).accessibilityHint("Opens \(name)'s profile") }
                else { Avatar(initials: initials(name)) }
                if c.kind == "LISTING" { Image(systemName: "storefront").font(.system(size: 12)).foregroundStyle(BucksColor.primary).background(Circle().fill(BucksColor.surface)) }
            }
        }, trailing: {
            HStack(spacing: 4) {
                if c.muted { Image(systemName: "bell.slash").font(.system(size: 13)).foregroundStyle(BucksColor.onSurfaceVariant) }
                CountBadge(c.unread)
                Button { menuFor = c } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(BucksColor.onSurface).frame(width: 40, height: 40).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("More")
            }
        })
    }
}

/// The Notifications tab: newest first, unread in bold with a dot, tap opens the thing it is about, the x removes it.
private struct NotificationsList: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let notes = session.chat.notes
        let incoming = session.social.incoming
        if notes.isEmpty && incoming.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing new").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                Muted("Sync requests, invites, orders, recommendations, reviews and document checks show up here.")
            }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Sync requests waiting for my answer come first, with the answer right here: no trip to the Sync screen.
                    if !incoming.isEmpty { syncRequests(incoming) }
                    ForEach(notes) { n in
                        let unread = n.readAt == nil
                        HStack(alignment: .top, spacing: 0) {
                            Image(systemName: noteSymbol(n.kind)).font(.system(size: 18))
                                .foregroundStyle(unread ? BucksColor.onPrimaryContainer : BucksColor.onSurfaceVariant)
                                .frame(width: 40, height: 40).background(Circle().fill(unread ? BucksColor.primaryContainer : BucksColor.surfaceContainerHigh))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(n.title).font(.bucks(.titleSmall)).fontWeight(unread ? .semibold : .regular).foregroundStyle(BucksColor.onSurface)
                                if !n.body.trimmingCharacters(in: .whitespaces).isEmpty { Muted(n.body, maxLines: 2) }
                                Muted(feedAgo(n.createdAt)).padding(.top, 2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                            if unread { Circle().fill(BucksColor.primary).frame(width: 10, height: 10).padding(.top, 6) }
                            Button { session.chat.deleteNote(n.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 32, height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Remove")
                        }
                        .padding(.horizontal, Gutter).padding(.vertical, 12).contentShape(Rectangle())
                        .onTapGesture { session.chat.markNoteRead(n.id); if let r = n.route { NotificationRouteOpener.open(r, router: router) } }
                        BucksDivider()
                    }
                }
            }
        }
    }
}

extension NotificationsList {
    func syncRequests(_ people: [ProfileRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(people.count == 1 ? "1 sync request" : "\(people.count) sync requests").bucks(.labelLarge).foregroundStyle(BucksColor.primary)
                .padding(.horizontal, Gutter).padding(.top, 14).padding(.bottom, 4)
            ForEach(people) { p in
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                    Avatar(initials: initials(p.name), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.name).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Muted(["Wants to sync with you", p.area.isEmpty ? nil : p.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    }.opensProfile(p.id, name: p.name)
                    SmallButton("Accept") { session.social.acceptSync(p.id) }
                    SmallButton("Ignore", tonal: true) { session.social.unsync(p.id) }
                }.padding(.horizontal, Gutter).padding(.vertical, 8)
            }
        }
        .padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
        .background(BucksColor.primaryContainer.opacity(0.35))
    }
}
