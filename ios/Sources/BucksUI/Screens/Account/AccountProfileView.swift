import SwiftUI
import BucksCore

/// My own profile in the Account tab: name, Bucks ID, synced people, a composer, and the Feed / Media / Files / Recommended tabs.
struct AccountProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    let model: AccountModel
    @State private var tab = 0
    @State private var posts: [PostRow]?
    @State private var failed = false
    @State private var votes: [String: Int] = [:]
    @State private var deleting: PostRow?

    private var name: String { session.me.flatMap { $0.name.isEmpty ? nil : $0.name } ?? session.user?.name ?? "" }
    private var area: String { session.me.flatMap { $0.area.isEmpty ? nil : $0.area } ?? session.user?.area ?? "" }
    private var bio: String { session.me.flatMap { $0.bio.isEmpty ? nil : $0.bio } ?? session.user?.bio ?? "" }

    var body: some View {
        ContentColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AccountProfileCover(initials: initials(name))
                    header
                    BucksDivider()
                    composer
                    tabRow
                    switch tab {
                    case 0: feedTab
                    case 1: AccountMediaTab(posts: posts, failed: failed)
                    case 2: AccountFilesTab()
                    default: AccountRecommendationsTab()
                    }
                    Spacer(minLength: 24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            // The cover has no top bar on Android; the menu and chat buttons float over it.
            ProfileTopButtons(unread: session.chat.unread)
        }
        .task(id: session.me?.id) { await load() }
        .bucksConfirm(isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), title: "Delete this post?", confirmTitle: "Delete", destructive: true) {
            if let p = deleting { Task { await delete(p) } }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).bucks(.headlineSmall).foregroundStyle(BucksColor.onSurface)
            Muted(session.me.map { "Bucks ID \($0.shortCode)" } ?? accountHandle(name))
            if !area.isEmpty {
                HStack(spacing: 2) { Image(systemName: "mappin.and.ellipse").font(.system(size: 14)); Muted(" \(area)") }
                    .foregroundStyle(BucksColor.onSurfaceVariant).padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 24) {
                Button { router.push(.sync) } label: {
                    HStack(alignment: .lastTextBaseline, spacing: 0) { Text("\(model.syncedCount)").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface); Muted(" synced") }
                }.buttonStyle(.plain)
                Button { router.push(.contacts) } label: {
                    HStack(spacing: 0) { Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(BucksColor.onSurfaceVariant); Muted(" Contacts") }
                }.buttonStyle(.plain)
            }.padding(.top, 12)
            if !bio.isEmpty { Text(bio).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 12) }
            HStack(spacing: 12) {
                AccountSoftButton(text: "Edit profile", systemImage: "square.and.pencil") { router.push(.editProfile) }
                ShareLink(item: shareText) {
                    HStack(spacing: 6) { Image(systemName: "square.and.arrow.up").font(.system(size: 16)); Text("Share").bucks(.labelLarge) }
                        .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
                }.buttonStyle(.plain)
            }.padding(.top, 14)
        }
        .padding(.horizontal, Gutter).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareText: String {
        "\(name) on Bucks" + (session.me.map { " · Bucks ID \($0.shortCode)" } ?? "") + (area.isEmpty ? "" : " · \(area)")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Avatar(initials: initials(name), size: 40)
            Button { router.push(.createPost) } label: {
                Muted("Share with people nearby").padding(.horizontal, 14).frame(height: 40)
                    .overlay(Capsule().strokeBorder(BucksColor.outline, lineWidth: 1)).contentShape(Capsule())
            }.buttonStyle(.plain)
            Button { router.push(.createPost) } label: {
                Image(systemName: "plus").font(.system(size: 20)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 48, height: 48)
            }.buttonStyle(.plain).accessibilityLabel("Create a post")
        }.padding(.horizontal, Gutter).padding(.vertical, 12)
    }

    private var tabRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Feed", "Media", "Files", "Recommended"].enumerated()), id: \.offset) { i, l in
                    Button { tab = i } label: {
                        VStack(spacing: 0) {
                            Text(l).bucks(.labelLarge).lineLimit(1).foregroundStyle(tab == i ? BucksColor.primary : BucksColor.onSurfaceVariant)
                                .frame(maxWidth: .infinity, minHeight: 46)
                            Rectangle().fill(tab == i ? BucksColor.primary : .clear).frame(height: 3)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == i ? .isSelected : [])
                }
            }
            BucksDivider()
        }.background(BucksColor.surface)
    }

    // MARK: feed

    @ViewBuilder private var feedTab: some View {
        if let posts {
            if session.me != nil, posts.isEmpty {
                Muted("Your recent posts show here. Share a recommendation, a deal or a question above; people nearby see it in their Feed.").padding(Gutter)
            }
            ForEach(posts) { p in
                AccountPostCard(post: p, name: name, myVote: votes[p.id] ?? 0, onVote: { v in Task { await vote(p, v) } },
                                onComments: { router.push(.post(p.id)) }, onDelete: { deleting = p })
            }
        } else if failed {
            Muted("Couldn't load your posts. Check your connection and open this tab again.").padding(Gutter)
        } else { BucksLoader().frame(maxWidth: .infinity).padding(.top, 40) }
    }

    private func load() async {
        guard let me = session.me?.id else { return }
        await model.loadSynced()
        do {
            let rows = try await Backend.shared.accountMyPosts(me: me)
            posts = rows; failed = false
            votes = (try? await Backend.shared.accountMyVotes(me: me, postIds: rows.map(\.id))) ?? [:]
        } catch { if posts == nil { failed = true } }
    }

    private func vote(_ p: PostRow, _ v: Int) async {
        guard let me = session.me?.id, let i = posts?.firstIndex(where: { $0.id == p.id }) else { return }
        let prev = votes[p.id] ?? 0, next = prev == v ? 0 : v
        do {
            try await Backend.shared.accountVote(postId: p.id, me: me, vote: next)
            votes[p.id] = next
            posts?[i].up += (next == 1 ? 1 : 0) - (prev == 1 ? 1 : 0)
            posts?[i].down += (next == -1 ? 1 : 0) - (prev == -1 ? 1 : 0)
        } catch { session.toast(friendlyError(error)) }
    }

    private func delete(_ p: PostRow) async {
        do { try await Backend.shared.accountDeletePost(p.id); posts?.removeAll { $0.id == p.id } }
        catch { session.toast(friendlyError(error)) }
    }
}

/// The menu and chat buttons over the profile's cover band (white on the gradient).
private struct ProfileTopButtons: View {
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    let unread: Int
    var body: some View {
        HStack {
            Button(action: openMenu) { Image(systemName: "line.3.horizontal").foregroundStyle(BucksColor.onPrimary).frame(width: 44, height: 44) }.accessibilityLabel("Menu")
            Spacer()
            Button { router.push(.messages) } label: {
                Image(systemName: "bubble.left").foregroundStyle(BucksColor.onPrimary).frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 { Text("\(min(unread, 99))").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(BucksColor.error)).offset(x: -4, y: 4) }
                    }
            }.accessibilityLabel("Messages")
        }.padding(.horizontal, 4)
    }
}

/// One of my posts: time, text, photos, votes, comments, share and (long-press or menu) delete.
private struct AccountPostCard: View {
    let post: PostRow, name: String, myVote: Int
    let onVote: (Int) -> Void, onComments: () -> Void, onDelete: () -> Void

    private var shareText: String { "\(name) on Bucks: \(post.body)" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Avatar(initials: initials(name), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) { Text(name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface); Muted("  ·  You") }
                        Muted([accountAgo(post.createdAt), post.visibility == "SYNCED" ? "Synced only" : post.visibility == "PUBLIC" ? "Public" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Menu { Button("Delete post", role: .destructive, action: onDelete) } label: {
                        Image(systemName: "ellipsis").foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 44, height: 44)
                    }.accessibilityLabel("More")
                }
                if !post.body.isEmpty { Text(post.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10) }
                let paths = post.media.compactMap { $0["path"]?.string }.filter { !$0.isEmpty }
                if !paths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(paths, id: \.self) { path in
                                let mime = post.media.first { $0["path"]?.string == path }?["mime"]?.string ?? ""
                                if mime.hasPrefix("video/") || path.lowercased().hasSuffix(".mp4") {
                                    ZStack { Color.black; Image(systemName: "play.fill").foregroundStyle(.white) }
                                        .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
                                } else {
                                    SignedImage(bucket: "posts", path: path).frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
                                }
                            }
                        }
                    }.padding(.top, 8)
                }
                HStack(spacing: 0) {
                    voteButton(1, "arrow.up", "Recommend", post.up, BucksColor.good)
                    voteButton(-1, "arrow.down", "Not recommended", post.down, BucksColor.bad)
                    Spacer()
                    Button(action: onComments) {
                        HStack(spacing: 4) { Image(systemName: "bubble.left").font(.system(size: 16)); Text(" \(post.comments)").bucks(.labelLarge) }
                            .foregroundStyle(BucksColor.onSurfaceVariant).padding(6).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Comments")
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up").font(.system(size: 17)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 44, height: 44) }
                        .accessibilityLabel("Share")
                }.padding(.top, 8)
            }.padding(.horizontal, Gutter).padding(.vertical, 14)
            BucksDivider()
        }
        .contextMenu { Button("Delete post", role: .destructive, action: onDelete) }
    }

    private func voteButton(_ v: Int, _ icon: String, _ label: String, _ count: Int, _ on: Color) -> some View {
        let color = myVote == v ? on : BucksColor.onSurfaceVariant
        return Button { onVote(v) } label: {
            HStack(spacing: 2) { Image(systemName: icon).font(.system(size: 17, weight: .semibold)); Text(" \(count)").bucks(.labelLarge) }
                .foregroundStyle(color).padding(6).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
