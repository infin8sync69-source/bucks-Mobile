import SwiftUI
import BucksCore

/// Someone else's profile (ui/social/Profile.kt PersonScreen): Sync (or Accept / Requested / Synced), Message, and ⋯ for Close friend,
/// Unsync, Report and Block. Their posts show what I'm allowed to see; a private person I'm not synced with shows only name and Bucks ID.
struct PersonScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var person: ProfileRow?
    @State private var missing = false
    @State private var posts: [FeedRow]?
    @State private var requested = false
    @State private var confirmBlock = false
    @State private var commentsFor: String?

    private var social: SocialStore { session.social }
    private var synced: Bool { social.synced.contains { $0.id == id } }
    private var incoming: Bool { social.incoming.contains { $0.id == id } }
    private var close: Bool { social.closeFriends.contains(id) }
    private var firstName: String? { person?.name.split(separator: " ").first.map(String.init) }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: person?.name ?? "", onBack: { router.pop() }) { menu }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        if missing { Muted("This profile isn't available.").padding(Gutter) } else { buttons }
                        if !synced && !missing {
                            Muted(firstName.map { "Sync with \($0) to see what they share with people they know." } ?? "Sync to see what they share with people they know.")
                                .padding(.horizontal, Gutter)
                        }
                        Text("Posts").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, Gutter).padding(.top, 20).padding(.bottom, 4)
                        if let posts {
                            if posts.isEmpty { Muted("Nothing to show yet.").padding(Gutter) }
                            ForEach(posts) { p in
                                PostCard(post: p, onVote: { v in Task { await vote(p, v) } }, onComments: { commentsFor = p.id }, onDelete: {})
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(32)
                        }
                    }.padding(.bottom, 24)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) { await load() }
        .sheet(item: Binding(get: { commentsFor.map(IdBox.init) }, set: { commentsFor = $0?.id })) { b in CommentsSheet(postId: b.id) }
        .bucksConfirm(isPresented: $confirmBlock, title: person.map { "Block \($0.name)?" } ?? "Block this person?",
                      message: "They won't be able to find you, message you or see your posts. They aren't told.", confirmTitle: "Block", destructive: true) {
            social.block(id); router.pop()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Avatar(initials: initials(person?.name ?? "?"), size: 92)
            Text(person?.name ?? " ").font(.bucks(.headlineSmall)).fontWeight(.bold).foregroundStyle(BucksColor.onSurface).padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            let meta = [person.map { "Bucks ID \(BucksIdCode.pretty($0.shortCode))" }, person?.area.isEmpty == false ? person?.area : nil].compactMap { $0 }.joined(separator: " · ")
            if !meta.isEmpty { Muted(meta) }
            if let bio = person?.bio, !bio.isEmpty { Text(bio).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 10) }
            if let n = posts?.count { (Text("\(n)").fontWeight(.bold) + Text(n == 1 ? " post" : " posts").foregroundColor(BucksColor.onSurfaceVariant)).bucks(.bodyMedium).padding(.top, 12) }
        }.padding(.horizontal, Gutter).padding(.top, 12)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Group {
                if synced { SecondaryAction("Synced", "checkmark") {} }
                else if incoming { PrimaryButton("Accept sync") { social.acceptSync(id) } }
                else if requested { SecondaryAction("Requested", "clock", enabled: false) {} }
                else { PrimaryButton("Sync", enabled: person != nil) { requested = true; social.syncWith(id, name: person?.name ?? "") } }
            }.frame(maxWidth: .infinity)
            SecondaryAction("Message", "bubble.left", enabled: person != nil) {
                Task { if let c = await session.chat.openDirect(id) { router.push(.chat(c)) } }
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, Gutter).padding(.vertical, 12)
    }

    private var menu: some View {
        Menu {
            if synced {
                Button(close ? "Remove from close friends" : "Add to close friends", systemImage: "heart") { social.setClose(id, on: !close) }
                Button("Unsync", systemImage: "person.badge.minus") { social.unsync(id) }
            }
            Button("Report", systemImage: "flag") { session.reportTarget = ReportTarget(kind: "PROFILE", targetId: id, ownerId: id, ownerName: person?.name ?? "") }
            Button("Block", systemImage: "nosign", role: .destructive) { confirmBlock = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel("More options")
    }

    private func load() async {
        person = try? await Backend.shared.profiles([id]).first
        missing = person == nil
        social.refreshSyncs()
        posts = (try? await Backend.shared.postsBy(id)) ?? []
    }

    /// Tapping the vote I already gave takes it back.
    private func vote(_ p: FeedRow, _ v: Int) async {
        guard let me = session.me?.id, let i = posts?.firstIndex(where: { $0.id == p.id }) else { return }
        let prev = p.myVote ?? 0, next = prev == v ? 0 : v
        do { try await Backend.shared.vote(postId: p.id, me: me, vote: next) } catch { session.toast(friendlyError(error)); return }
        posts?[i].myVote = next == 0 ? nil : next
        posts?[i].up += (next == 1 ? 1 : 0) - (prev == 1 ? 1 : 0)
        posts?[i].down += (next == -1 ? 1 : 0) - (prev == -1 ? 1 : 0)
    }
}

private struct IdBox: Identifiable { let id: String }

/// An outlined full-width action with an icon (Synced, Requested, Message).
private struct SecondaryAction: View {
    let title: String, icon: String; var enabled = true; let action: () -> Void
    init(_ title: String, _ icon: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.icon = icon; self.enabled = enabled; self.action = action }
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).bucks(.labelLarge).foregroundStyle(BucksColor.primary).frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).stroke(BucksColor.outline, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }
}

/// A typed Bucks ID with its spaces or dashes ("h6vf ywyf") goes as the bare code, which the server matches exactly; anything else as typed.
func peopleQuery(_ typed: String) -> String {
    let bare = String(typed.filter { $0.isLetter || $0.isNumber })
    return BucksQr.looksLikeBucksId(bare) ? bare.uppercased() : typed.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A person in search results, as a card (ui/social/Discover.kt PersonResultCard): picture, name, Bucks ID, area and people in common,
/// with the quick actions under it (Sync or its state, Message once synced, Profile). The whole card opens their profile.
struct PersonResultCard: View {
    let hit: PersonHit
    /// SYNCED, INCOMING, SENT or NONE.
    let state: String
    let onOpen: () -> Void, onSync: () -> Void, onMessage: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Avatar(initials: initials(hit.name.isEmpty ? "?" : hit.name), size: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hit.name.isEmpty ? "Bucks ID \(hit.shortCode)" : hit.name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                        Text("Bucks ID \(BucksIdCode.pretty(hit.shortCode))").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(BucksColor.primary).lineLimit(1)
                        let sub = [hit.area.isEmpty ? nil : hit.area, hit.mutual > 0 ? "\(hit.mutual) mutual" : nil].compactMap { $0 }.joined(separator: " · ")
                        if !sub.isEmpty { Muted(sub, maxLines: 1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    switch state {
                    case "SYNCED": QuickAction("bubble.left", "Message", filled: true, action: onMessage)
                    case "SENT": QuickAction("clock", "Requested", enabled: false) {}
                    case "INCOMING": QuickAction("checkmark", "Accept", filled: true, action: onSync)
                    default: QuickAction("arrow.triangle.2.circlepath", "Sync", filled: true, action: onSync)
                    }
                    QuickAction("person", "Profile", action: onOpen)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous).fill(BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct QuickAction: View {
    let icon: String, label: String; var filled = false; var enabled = true; let action: () -> Void
    init(_ icon: String, _ label: String, filled: Bool = false, enabled: Bool = true, action: @escaping () -> Void) { self.icon = icon; self.label = label; self.filled = filled; self.enabled = enabled; self.action = action }
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon).bucks(.labelLarge).lineLimit(1)
                .foregroundStyle(filled ? BucksColor.onPrimary : BucksColor.onSurface)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill((filled ? BucksColor.primary : BucksColor.surfaceContainerHigh).opacity(enabled ? 1 : 0.5)))
        }.buttonStyle(.plain).disabled(!enabled)
    }
}
