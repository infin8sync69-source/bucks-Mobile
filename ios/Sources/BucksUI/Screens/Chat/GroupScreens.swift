import SwiftUI
import BucksCore

/// Start a group: name it, tick synced people, Create. Only people synced with you can be members.
struct NewGroupScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var title = ""
    @State private var selected: Set<String> = []
    @State private var creating = false

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "New group", onBack: { router.pop() })
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        BucksField(Binding(get: { title }, set: { title = String($0.prefix(60)) }), label: "Group name", placeholder: "Sunday cricket, 4th Cross neighbours, shop staff")
                        FieldLabel("People")
                        Muted("Only people synced with you can join. Ask the others to sync with you first.").padding(.bottom, 8)
                    }.padding(.horizontal, Gutter)
                    PeoplePicker(people: session.social.synced, selected: selected, onToggle: toggle,
                                 emptyText: "Nobody is synced with you yet. Open Sync from Messages, share your Bucks ID, then come back to make a group.")
                        .frame(maxHeight: .infinity, alignment: .top)
                }.frame(maxHeight: .infinity, alignment: .top)
                PrimaryButton(creating ? "Creating…" : selected.isEmpty ? "Create group" : "Create group with \(selected.count)",
                              enabled: !title.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty && !creating) { create() }
                    .padding(Gutter)
            }
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { session.social.refreshSyncs() }
    }

    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }

    private func create() {
        creating = true
        Task {
            if let id = await session.chat.createGroup(title: title, members: Array(selected)) {
                router.pop(); router.push(.chat(id))
            } else { creating = false }
        }
    }
}

/// Who's in a group or listing chat. Groups: add synced people, rename, admins remove, anyone leaves.
struct MembersSheet: View {
    let conv: String
    let kind: String
    let title: String
    let members: [ConversationMemberRow]
    let onReload: () -> Void
    let onRenamed: (String) -> Void
    let onLeft: () -> Void
    let onOpenListing: (() -> Void)?

    @Environment(AppSession.self) private var session
    @State private var rename: String?
    @State private var adding = false
    @State private var removeFor: ConversationMemberRow?
    @State private var leaving = false

    private var meId: String? { session.me?.id }
    private var group: Bool { kind == "GROUP" }
    private var iAmAdmin: Bool { members.contains { $0.profileId == meId && $0.role == "ADMIN" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if group {
                    Button { rename = title } label: { Image(systemName: "pencil").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Rename group")
                }
            }
            Muted(group ? "\(members.count) people · only people synced with you can be added" : "The shop or pro and everyone who runs it share this chat with you.").padding(.bottom, 8)
            if group {
                HStack(spacing: 8) { SmallButton("Add people", tonal: true) { adding = true }; SmallButton("Rename", tonal: true) { rename = title } }.padding(.bottom, 6)
            }
            if !group, let onOpenListing { SmallButton("Open listing", tonal: true, action: onOpenListing).padding(.bottom, 6) }
            if members.isEmpty { Muted("Loading people…").padding(.vertical, 12) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(members, id: \.profileId) { m in
                        let name = session.social.nameOf(m.profileId)
                        HStack(spacing: 0) {
                            Avatar(initials: initials(name.isEmpty ? "?" : name), size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.profileId == meId ? "\(name) (you)" : name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                                if m.role == "ADMIN" { Muted(group ? "Admin" : "Runs the listing") }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                            if group && iAmAdmin && m.profileId != meId {
                                Button { removeFor = m } label: { Image(systemName: "person.badge.minus").foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                    .buttonStyle(.plain).accessibilityLabel("Remove \(name)")
                            }
                        }.padding(.vertical, 8)
                        BucksDivider()
                    }
                }
            }
            if group { BadButton("Leave group") { leaving = true }.padding(.top, 10) }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BucksColor.surface.ignoresSafeArea())
        .task { onReload(); if group { session.social.refreshSyncs() } }
        .alert("Rename group", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField("Group name", text: Binding(get: { rename ?? "" }, set: { rename = String($0.prefix(60)) }))
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let t = (rename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { session.chat.renameGroup(conv, title: t) { onRenamed(t) } }
            }
        }
        .bucksConfirm(isPresented: Binding(get: { removeFor != nil }, set: { if !$0 { removeFor = nil } }), title: "Remove \(removeFor.map { session.social.nameOf($0.profileId) } ?? "")?",
                      message: "They'll stop getting the group's messages. You can add them again later.", confirmTitle: "Remove", destructive: true) {
            if let m = removeFor { session.chat.removeFromGroup(conv, member: m.profileId) { onReload() } }
        }
        .bucksConfirm(isPresented: $leaving, title: "Leave \(title)?", message: "You'll stop getting its messages and can't read the chat any more. Someone in the group can add you back later.", confirmTitle: "Leave", destructive: true) {
            session.chat.leaveConversation(conv) { onLeft() }
        }
        .sheet(isPresented: $adding) {
            AddPeopleSheet(conv: conv, already: Set(members.map(\.profileId)), onAdded: { adding = false; onReload() })
                .presentationDetents([.large])
        }
    }
}

private struct AddPeopleSheet: View {
    let conv: String
    let already: Set<String>
    let onAdded: () -> Void
    @Environment(AppSession.self) private var session
    @State private var selected: Set<String> = []
    @State private var busy = false

    var body: some View {
        let candidates = session.social.synced.filter { !already.contains($0.id) }
        VStack(alignment: .leading, spacing: 0) {
            Text("Add people").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.horizontal, Gutter).padding(.top, 20)
            Muted("People synced with you who aren't in the group yet.").padding(.horizontal, Gutter).padding(.vertical, 6)
            PeoplePicker(people: candidates, selected: selected, onToggle: { id in if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } },
                         emptyText: session.social.synced.isEmpty ? "Nobody is synced with you yet. Share your Bucks ID from Sync first." : "Everyone synced with you is already in this group.")
                .frame(maxHeight: .infinity, alignment: .top)
            PrimaryButton(busy ? "Adding…" : selected.isEmpty ? "Add" : "Add \(selected.count)", enabled: !selected.isEmpty && !busy) {
                busy = true; session.chat.addToGroup(conv, members: Array(selected), then: { onAdded() }, onFailed: { busy = false })
            }.padding(Gutter)
        }
        .background(BucksColor.surface.ignoresSafeArea())
    }
}
