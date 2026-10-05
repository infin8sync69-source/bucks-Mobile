import SwiftUI
import BucksCore

/// The Feed tab: the Moments row, a "Share with your neighbours" bar, then the posts nearby (CloudFeedScreen).
struct FeedScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    @State private var compose = false
    @State private var commentsFor: String?
    @State private var muteFor: TrayRow?
    @State private var showMuted = false

    private var feed: FeedStore { session.feed }

    var body: some View {
        VStack(spacing: 0) {
            BucksTopBar(title: "Feed", onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
            ScrollView {
                LazyVStack(spacing: 0) {
                    MomentsTray(tray: feed.tray, myName: session.me?.name ?? "You",
                                onOpen: { router.push(.moments($0)) }, onNew: { router.push(.momentNew) }, onMute: { muteFor = $0 }, onMore: { showMuted = true })
                    composeBar
                    if feed.feed.isEmpty { Muted("Nothing here yet. Sync with people nearby, or be the first to post.").padding(Gutter) }
                    ForEach(feed.feed) { p in
                        PostCard(post: p, onVote: { v in Task { await feed.vote(p.id, v) } }, onComments: { commentsFor = p.id }, onDelete: { Task { await feed.deletePost(p.id) } })
                    }
                    if !feed.feed.isEmpty && !feed.feedEnd {
                        Button("Load more") { Task { await feed.loadMoreFeed() } }.buttonStyle(.plain).bucksFont(.labelLarge).foregroundStyle(BucksColor.primary)
                            .frame(maxWidth: .infinity, minHeight: 48).padding(8)
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .refreshable { await feed.refreshFeed() }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .task(id: session.me?.id) { if session.me != nil { await feed.refreshFeed() } }
        .sheet(isPresented: $compose) { SheetBody { NewPostForm(showTitle: true) { compose = false } }.feedSheetStyle() }
        .sheet(item: Binding(get: { commentsFor.map(IDItem.init) }, set: { commentsFor = $0?.id })) { item in CommentsSheet(postId: item.id).feedSheetStyle() }
        .sheet(isPresented: $showMuted) { MutedMomentsSheet().feedSheetStyle() }
        .bucksConfirm(isPresented: Binding(get: { muteFor != nil }, set: { if !$0 { muteFor = nil } }),
                      title: "Hide \(muteFor?.authorName.split(separator: " ").first.map(String.init) ?? "")'s moments?",
                      message: "Their moments leave this row. You stay synced and can still message each other. Unmute any time from the More button at the end of the row.",
                      confirmTitle: "Mute") {
            if let t = muteFor { Task { await feed.muteMoments(t.authorId, on: true) } }
        }
    }

    private var composeBar: some View {
        Button { compose = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(BucksColor.onSurface).frame(width: 24)
                Text("Share with your neighbours").bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surfaceContainer))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, Gutter).padding(.vertical, 8)
    }
}

private struct IDItem: Identifiable { let id: String }

// MARK: - Moments row

/// The row of circles at the top of the feed: me first (with a + to add), then people with unseen moments ringed. Long-press someone to mute them; the last circle lists who's muted.
struct MomentsTray: View {
    let tray: [TrayRow]
    let myName: String
    let onOpen: (String) -> Void
    let onNew: () -> Void
    var onMute: ((TrayRow) -> Void)?
    var onMore: (() -> Void)?

    var body: some View {
        let mine = tray.first { $0.isMe }
        let others = tray.filter { !$0.isMe }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        MomentRing(unseen: false, has: mine != nil) { Avatar(initials: initials(myName), size: 56) }
                            .contentShape(Rectangle()).onTapGesture { if let mine { onOpen(mine.authorId) } else { onNew() } }
                        Button(action: onNew) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(BucksColor.onPrimary)
                                .frame(width: 22, height: 22).background(Circle().fill(BucksColor.primary))
                                .overlay(Circle().strokeBorder(BucksColor.surface, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Add a moment")
                    }.frame(width: 64, height: 64)
                    Text(mine != nil ? "Your moment" : "Add moment").bucks(.labelSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                }.frame(width: 68)
                ForEach(others) { t in
                    VStack(spacing: 4) {
                        MomentRing(unseen: t.unseen > 0, has: true) { Avatar(initials: initials(t.authorName), size: 56) }
                        Text(t.listingTitle ?? t.authorName.split(separator: " ").first.map(String.init) ?? t.authorName).bucks(.labelSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    }
                    .frame(width: 68).contentShape(Rectangle())
                    .onTapGesture { onOpen(t.authorId) }
                    .onLongPressGesture { onMute?(t) }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                }
                if let onMore {
                    Button(action: onMore) {
                        VStack(spacing: 4) {
                            MomentRing(unseen: false, has: false) { Avatar(systemImage: "ellipsis", size: 56, tinted: false) }
                            Text("More").bucks(.labelSmall).foregroundStyle(BucksColor.onSurface)
                        }.frame(width: 68)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Gutter).padding(.vertical, 10)
        }
    }
}

private struct MomentRing<Content: View>: View {
    let unseen: Bool
    let has: Bool
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            if unseen {
                Circle().fill(AngularGradient(colors: [BucksColor.primary, Color(hex: 0xFF4D8D), BucksColor.primary], center: .center))
            } else if has {
                Circle().fill(BucksColor.outline)
            }
            if unseen || has { Circle().fill(BucksColor.surface).frame(width: 58, height: 58) }
            content
        }.frame(width: 64, height: 64)
    }
}

/// Who I've muted from the Moments row, with a way back. Reached from the row's More circle.
struct MutedMomentsSheet: View {
    @Environment(AppSession.self) private var session
    var body: some View {
        let feed = session.feed
        ScrollView {
            SheetBody {
                Text("Muted moments").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                Muted("People here stay synced with you; only their moments are hidden from the row.").padding(.top, 4).padding(.bottom, 10)
                if feed.mutedMoments.isEmpty {
                    Muted("Nobody is muted. Press and hold someone's circle in the Moments row to hide their moments.").padding(.vertical, 12)
                } else {
                    ForEach(feed.mutedMoments) { p in
                        HStack(spacing: 0) {
                            Avatar(initials: initials(p.name), size: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted(p.area.isEmpty ? BucksIdCode.pretty(p.shortCode) : p.area)
                            }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                            SmallButton("Unmute", tonal: true) { Task { await feed.muteMoments(p.id, on: false) } }
                        }.padding(.vertical, 8)
                        BucksDivider()
                    }
                }
            }
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .task { await feed.refreshMutedMoments() }
    }
}

// MARK: - Posts

struct PostCard: View {
    @Environment(AppSession.self) private var session
    let post: FeedRow
    let onVote: (Int) -> Void
    let onComments: () -> Void
    let onDelete: () -> Void

    private var mine: Bool { post.authorId == session.me?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(post.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                PostMediaView(media: post.media)
                actions
            }
            .padding(.horizontal, Gutter).padding(.vertical, 14)
            .contextMenu { if mine { Button("Delete post", role: .destructive, action: onDelete) } }
            BucksDivider()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(initials: initials(post.authorName), size: 40)
            VStack(alignment: .leading, spacing: 0) {
                (Text(post.listingTitle ?? post.authorName).font(.bucks(.titleMedium)).foregroundColor(BucksColor.onSurface)
                 + Text(mine ? "  ·  You" : (post.synced ? "  ·  Synced" : "")).font(.bucks(.bodySmall)).foregroundColor(BucksColor.onSurfaceVariant)).lineLimit(1)
                Muted([feedAgo(post.createdAt), post.area.isEmpty ? nil : post.area, post.visibility == "SYNCED" ? "Synced only" : (post.visibility == "PUBLIC" ? "Public" : nil)].compactMap { $0 }.joined(separator: " · "))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if mine {
                Menu { Button("Delete post", role: .destructive, action: onDelete) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("More")
            }
        }
    }

    private var actions: some View {
        let my = post.myVote ?? 0
        let upColor = my == 1 ? BucksColor.good : BucksColor.onSurfaceVariant
        let downColor = my == -1 ? BucksColor.bad : BucksColor.onSurfaceVariant
        return HStack(spacing: 0) {
            actionButton("arrow.up", "Recommend", " \(post.up)", upColor, icon: 20) { onVote(1) }
            actionButton("arrow.down", "Not recommended", " \(post.down)", downColor, icon: 20) { onVote(-1) }
            Spacer(minLength: 0)
            actionButton("bubble.left", "Comments", " \(post.comments)", BucksColor.onSurfaceVariant, icon: 18, action: onComments)
            ShareLink(item: "\(post.authorName) on Bucks: \(post.body)") {
                Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 48, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("Share")
        }.padding(.top, 8)
    }

    private func actionButton(_ icon: String, _ label: String, _ count: String, _ color: Color, icon size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
                Text(count).bucks(.labelLarge).foregroundStyle(color)
            }.padding(6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

// MARK: - Comments

struct CommentsSheet: View {
    @Environment(AppSession.self) private var session
    let postId: String
    @State private var rows: [CommentRow] = []
    @State private var reply = ""
    @State private var tick = 0
    @State private var sending = false

    var body: some View {
        let feed = session.feed
        VStack(spacing: 0) {
            ScrollView {
                SheetBody {
                    Text("Comments").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                    if rows.isEmpty { Muted("Be the first to reply.").padding(.vertical, 12) }
                    ForEach(rows) { c in
                        VStack(alignment: .leading, spacing: 0) {
                            (Text(feed.nameOf(c.authorId)).font(.bucks(.titleSmall)).foregroundColor(BucksColor.onSurface) + Text("  \(feedAgo(c.createdAt))").font(.bucks(.bodySmall)).foregroundColor(BucksColor.onSurfaceVariant))
                            Text(c.body).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                        }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        BucksDivider()
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $reply, prompt: Text("Reply").foregroundStyle(BucksColor.onSurfaceVariant))
                    .font(.bucks(.bodyLarge)).foregroundStyle(BucksColor.onSurface).submitLabel(.send).onSubmit(send)
                    .padding(.horizontal, 14).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
                Button(action: send) {
                    Image(systemName: "paperplane.fill").font(.system(size: 18)).foregroundStyle(BucksColor.onPrimary).frame(width: 48, height: 48)
                        .background(Circle().fill(reply.trimmingCharacters(in: .whitespaces).isEmpty ? BucksColor.onSurface.opacity(0.12) : BucksColor.primary))
                }.buttonStyle(.plain).disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send")
            }.padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 8)
        }
        .background(BucksColor.surface.ignoresSafeArea())
        .task(id: tick) { rows = (try? await feed.comments(postId)) ?? [] }
    }

    private func send() {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        sending = true
        Task { defer { sending = false }; if await session.feed.comment(postId, t) { reply = ""; tick += 1 } }
    }
}
