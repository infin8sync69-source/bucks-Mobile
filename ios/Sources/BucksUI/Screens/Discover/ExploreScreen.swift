import SwiftUI
import BucksCore

/*
 * Explore (the tab that was "For you"; ui/screens/ExploreScreen.kt): a search bar, a row of pills, and a page per pill.
 *   All       what the people I'm synced with recommend comes first ("Asha and 22 others recommended"), then public posts;
 *             shops and products they recommend ride in a row at the top.
 *   Videos    only videos, a wide frame then title, author and votes.     Images   only photos, as a grid.
 *   Files     only documents, as a list.                                  Places, Products   what my synced people recommend.
 * Anything opened goes full screen in one viewer that steps (swipe or the side arrows) to the next and previous piece of that page.
 */

private enum ExploreKind: String, CaseIterable {
    case all = "ALL", video = "VIDEO", image = "IMAGE", file = "FILE", places = "PLACES", products = "PRODUCTS"
    var label: String { switch self { case .all: "All"; case .video: "Videos"; case .image: "Images"; case .file: "Files"; case .places: "Places"; case .products: "Products" } }
    var icon: String { switch self { case .all: "sparkles"; case .video: "play.circle"; case .image: "photo"; case .file: "doc.text"; case .places: "storefront"; case .products: "bag" } }
    /// What the explore() call is asked for; Places and Products use the recommendations instead.
    var postKind: String { switch self { case .video, .image, .file: rawValue; default: "ALL" } }
    var placeKind: String? { switch self { case .places: "LISTING"; case .products: "PRODUCT"; default: nil } }
}

private extension PostMediaItem {
    var isImage: Bool { !isVideo && (mime.hasPrefix("image/") || mime.isEmpty) }
    var isFile: Bool { !isVideo && !isImage }
}

/// A piece of content in the viewer's order: its post, which of the post's media it is, and the media.
private struct Flat: Identifiable { let post: FeedRow; let index: Int; let item: PostMediaItem; var id: String { item.path } }

private extension FeedRow {
    var items: [PostMediaItem] { postMediaItems(media) }
    func matches(_ k: ExploreKind) -> Bool {
        switch k { case .video: items.contains { $0.isVideo }; case .image: items.contains { $0.isImage }; case .file: items.contains { $0.isFile }; default: true }
    }
    func headline(_ fallback: String) -> String {
        body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }.map { String($0.prefix(120)) } ?? fallback
    }
    var who: String { listingTitle ?? authorName }
}

struct ExploreScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openBucksMenu) private var openMenu
    @State private var kind: ExploreKind = .all
    @State private var q = ""
    @State private var rows: [FeedRow]?
    @State private var loading = false
    @State private var places: [ForYouItem] = []
    @State private var commentsFor: String?
    @State private var viewing: Int?
    @State private var opening: AttachmentRef?

    private var list: [FeedRow] { rows ?? [] }
    private var flat: [Flat] {
        list.flatMap { p in p.items.enumerated().map { Flat(post: p, index: $0.offset, item: $0.element) } }.filter {
            switch kind { case .video: $0.item.isVideo; case .image: $0.item.isImage; default: $0.item.isVideo || $0.item.isImage }
        }
    }
    private var shownPlaces: [ForYouItem] {
        let t = q.trimmingCharacters(in: .whitespaces)
        return places.filter { (kind.placeKind == nil || $0.kind == kind.placeKind) && (t.isEmpty || $0.title.localizedCaseInsensitiveContains(t) || $0.subtitle.localizedCaseInsensitiveContains(t)) }
    }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Explore", onMenu: openMenu, unread: session.chat.unread, onChat: { router.push(.messages) })
                searchField
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(ExploreKind.allCases, id: \.self) { k in BucksChip(k.label, selected: kind == k, systemImage: k.icon) { kind = k } } }
                        .padding(.horizontal, Gutter)
                }.padding(.vertical, 6)
                if loading && kind.placeKind == nil { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary).padding(.horizontal, Gutter) }
                page.frame(maxHeight: .infinity, alignment: .top)
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task(id: "\(session.me?.id ?? "")|\(kind.postKind)|\(q)") { await load() }
        .task(id: session.me?.id) { if session.me != nil { places = (try? await Backend.shared.forYouNamed()) ?? [] } }
        .sheet(item: Binding(get: { commentsFor.map(ExploreId.init) }, set: { commentsFor = $0?.id })) { b in CommentsSheet(postId: b.id) }
        .bucksFullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let start = viewing, !flat.isEmpty { ExploreViewer(items: flat, start: min(start, flat.count - 1), votes: { id in list.first { $0.id == id } }, onVote: vote, onClose: { viewing = nil }) }
        }
        .bucksAttachmentViewer(item: $opening)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(BucksColor.onSurfaceVariant)
            TextField("", text: Binding(get: { q }, set: { q = String($0.prefix(60)) }), prompt: Text("Search Explore").foregroundStyle(BucksColor.onSurfaceVariant))
                .bucksFont(.bodyLarge).foregroundStyle(BucksColor.onSurface).submitLabel(.search)
            if !q.isEmpty {
                Button { q = "" } label: { Image(systemName: "xmark").foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Clear")
            }
        }
        .padding(.leading, 16).padding(.trailing, 4).frame(height: 48)
        .background(Capsule().fill(BucksColor.surfaceContainer))
        .padding(.horizontal, Gutter).padding(.bottom, 4)
    }

    @ViewBuilder private var page: some View {
        let searching = !q.trimmingCharacters(in: .whitespaces).isEmpty
        let empty = { (what: String) in ExploreEmpty(text: searching ? "Nothing found for “\(q.trimmingCharacters(in: .whitespaces))”" : what, searching: searching) { router.push(.sync) } }
        if let pk = kind.placeKind {
            if shownPlaces.isEmpty { empty(pk == "LISTING" ? "No places recommended by people you're synced with yet." : "No products recommended by people you're synced with yet.") }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(shownPlaces) { r in PlaceRow(item: r) { if let l = r.listingId { router.push(.listing(l)) } } } }.padding(.vertical, 8) } }
        } else if rows == nil {
            Color.clear.frame(height: 1)
        } else {
            switch kind {
            case .video:
                if flat.isEmpty { empty("No videos to show yet.") } else {
                    ScrollView { LazyVStack(spacing: 0) { ForEach(Array(flat.enumerated()), id: \.element.id) { i, f in
                        VideoCard(post: f.post, item: f.item, onOpen: { viewing = i }, onVote: { vote(f.post, $0) }, onPerson: { router.push(.person(f.post.authorId)) }, onComments: { commentsFor = f.post.id })
                    } }.padding(.top, 10) }
                }
            case .image:
                if flat.isEmpty { empty("No photos to show yet.") } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                            ForEach(Array(flat.enumerated()), id: \.element.id) { i, f in
                                Button { viewing = i } label: {
                                    Color.clear.aspectRatio(1, contentMode: .fit)
                                        .overlay { SignedImage(bucket: "posts", path: f.item.path) }.clipped()
                                        .overlay(alignment: .bottomLeading) { if f.post.recommenders > 0 { upCount(f.post.recommenders).padding(4) } }
                                }.buttonStyle(.plain).accessibilityLabel("View full screen")
                            }
                        }.padding(.horizontal, 2).padding(.top, 8)
                    }
                }
            case .file:
                let files = list.flatMap { p in p.items.filter(\.isFile).map { (p, $0) } }
                if files.isEmpty { empty("No files to show yet.") } else {
                    ScrollView { LazyVStack(spacing: 0) { ForEach(files, id: \.1.path) { p, m in
                        let ext = String((m.path.split(separator: ".").last.map(String.init) ?? "").uppercased().prefix(5))
                        let name = p.headline("Shared by \(p.who)")
                        ListRow(name, subtitle: [ext.isEmpty ? nil : ext, p.who, feedAgo(p.createdAt)].compactMap { $0 }.joined(separator: " · "),
                                onTap: { opening = AttachmentRef(bucket: "posts", path: m.path, name: name, mime: m.mime) },
                                leading: { Avatar(systemImage: m.mime == "application/pdf" ? "doc.richtext" : "doc", size: 44) },
                                trailing: { if p.recommenders > 0 { upCount(p.recommenders, dark: false) } })
                        BucksDivider()
                    } }.padding(.top, 8) }
                }
            default:
                if list.isEmpty && shownPlaces.isEmpty { empty("Public posts, and what the people you're synced with recommend, show up here.") } else {
                    ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
                        if !shownPlaces.isEmpty {
                            Text("Recommended by people you know").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).padding(.horizontal, Gutter).padding(.top, 6).padding(.bottom, 8)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) { ForEach(shownPlaces) { r in PlaceCard(item: r) { if let l = r.listingId { router.push(.listing(l)) } } } }.padding(.horizontal, Gutter)
                            }.padding(.bottom, 10)
                        }
                        ForEach(list) { p in
                            if p.recommenders > 0 { RecommendedBy(name: p.recommenderName, count: p.recommenders).padding(.horizontal, Gutter).padding(.top, 12) }
                            PostCard(post: p, onVote: { vote(p, $0) }, onComments: { commentsFor = p.id }, onDelete: {})
                        }
                    }.padding(.vertical, 8) }
                }
            }
        }
    }

    private func upCount(_ n: Int, dark: Bool = true) -> some View {
        HStack(spacing: 2) { Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)); Text("\(n)").bucks(.labelSmall) }
            .foregroundStyle(dark ? .white : BucksColor.primary).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(dark ? Color.black.opacity(0.55) : BucksColor.primaryContainer))
            .accessibilityLabel("Recommended by \(n)")
    }

    /// Posts for the chosen pill and the typed words, after a short pause while typing. The old list stays up until the new one arrives.
    private func load() async {
        guard session.me != nil else { return }
        if !q.trimmingCharacters(in: .whitespaces).isEmpty { try? await Task.sleep(nanoseconds: 350_000_000); if Task.isCancelled { return } }
        loading = true
        let k = kind
        let got = ((try? await Backend.shared.explore(kind: k.postKind, q: q)) ?? []).filter { $0.matches(k) }
        if Task.isCancelled { return }
        rows = got; loading = false; viewing = nil
    }

    /// The arrow answers at once; the server call follows, and a failure puts the numbers back. Tapping my vote again takes it back.
    private func vote(_ p: FeedRow, _ v: Int) {
        guard let me = session.me?.id, let cur = rows?.first(where: { $0.id == p.id }) else { return }
        let prev = cur.myVote ?? 0, next = prev == v ? 0 : v
        shift(p.id, prev, next)
        Task { do { try await Backend.shared.vote(postId: p.id, me: me, vote: next) } catch { shift(p.id, next, prev); session.toast(friendlyError(error)) } }
    }
    private func shift(_ id: String, _ from: Int, _ to: Int) {
        guard let i = rows?.firstIndex(where: { $0.id == id }) else { return }
        rows?[i].myVote = to == 0 ? nil : to
        rows?[i].up += (to == 1 ? 1 : 0) - (from == 1 ? 1 : 0)
        rows?[i].down += (to == -1 ? 1 : 0) - (from == -1 ? 1 : 0)
    }
}

private struct ExploreId: Identifiable { let id: String }

/// "Asha and 22 others recommended": one of the people I'm synced with, by name, and how many more. Without a name, the count alone.
struct RecommendedBy: View {
    let name: String?; let count: Int
    var body: some View {
        let first = name?.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
        let text: String = {
            guard let first, !first.isEmpty else { return count == 1 ? "Recommended by 1 person you're synced with" : "Recommended by \(count) people you're synced with" }
            if count == 1 { return "\(first) recommended" }
            return count - 1 == 1 ? "\(first) and 1 other recommended" : "\(first) and \(count - 1) others recommended"
        }()
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(BucksColor.primary)
                Text(text).bucks(.labelMedium).foregroundStyle(BucksColor.onPrimaryContainer).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(BucksColor.primaryContainer.opacity(0.6)))
        }
    }
}

/// A video the way a video site lists it: the frame edge to edge with a play mark, then who posted it, the first line, and the arrows.
private struct VideoCard: View {
    @Environment(AppSession.self) private var session
    let post: FeedRow, item: PostMediaItem
    let onOpen: () -> Void, onVote: (Int) -> Void, onPerson: () -> Void, onComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x2B1B4D), Color(hex: 0x0E0A18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "play.fill").font(.system(size: 26)).foregroundStyle(.white).frame(width: 56, height: 56).background(Circle().fill(.black.opacity(0.55)))
                }.aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Play video")
            HStack(alignment: .top, spacing: 12) {
                Button(action: onPerson) { Avatar(initials: initials(post.authorName.isEmpty ? "?" : post.authorName), size: 38) }
                    .buttonStyle(.plain).accessibilityLabel("Open \(post.authorName)'s profile")
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.headline("Video by \(post.who)")).font(.bucks(.titleSmall)).fontWeight(.semibold).foregroundStyle(BucksColor.onSurface).lineLimit(2)
                    Muted([post.who, feedAgo(post.createdAt), post.area.isEmpty ? nil : post.area].compactMap { $0 }.joined(separator: " · "), maxLines: 1)
                    if post.recommenders > 0 { RecommendedBy(name: post.recommenderName, count: post.recommenders).padding(.top, 4) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, Gutter).padding(.top, 10)
            HStack(spacing: 0) {
                VotePill(my: post.myVote ?? 0, up: post.up, down: post.down, onVote: onVote)
                voteButton("bubble.left", "Comments", post.comments, BucksColor.onSurfaceVariant, action: onComments).padding(.leading, 6)
                Spacer(minLength: 0)
            }.padding(.horizontal, Gutter).padding(.top, 6)
            InlineCommentBox { t in Task { await session.feed.comment(post.id, t) } }.padding(.horizontal, Gutter).padding(.top, 2)
        }.padding(.bottom, 20)
    }

    private func voteButton(_ icon: String, _ label: String, _ n: Int, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)); Text(" \(n)").bucks(.labelLarge) }
                .foregroundStyle(color).padding(6).frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(label), \(n)")
    }
}

/// A shop, pro or product my people recommend, as a card in the row at the top of Explore.
private struct PlaceCard: View {
    let item: ForYouItem; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                PlacePicture(item: item).frame(height: 118).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    Muted(item.subtitle.isEmpty ? " " : item.subtitle, maxLines: 1)
                    RecommendedBy(name: item.recommenderName, count: item.recommenders).padding(.top, 6)
                }.padding(12)
            }
            .frame(width: 232).background(BucksColor.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: BucksRadius.large, style: .continuous))
        }.buttonStyle(.plain)
    }
}

private struct PlaceRow: View {
    let item: ForYouItem; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                PlacePicture(item: item).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).lineLimit(1)
                    if !item.subtitle.isEmpty { Muted(item.subtitle, maxLines: 1) }
                    RecommendedBy(name: item.recommenderName, count: item.recommenders).padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, Gutter).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
        BucksDivider()
    }
}

private struct PlacePicture: View {
    let item: ForYouItem
    var body: some View {
        ZStack {
            BucksColor.primaryContainer
            Image(systemName: item.kind == "PRODUCT" ? "bag" : "storefront").font(.system(size: 30)).foregroundStyle(BucksColor.onPrimaryContainer)
            if let s = item.photoUrl, !s.isEmpty, let u = URL(string: s) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
    }
}

private struct ExploreEmpty: View {
    let text: String; let searching: Bool; let onFindPeople: () -> Void
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: searching ? "magnifyingglass" : "safari").font(.system(size: 36)).foregroundStyle(BucksColor.onSurfaceVariant)
            Text(searching ? text : "Nothing here yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).multilineTextAlignment(.center).padding(.top, 12)
            if !searching {
                Muted(text, align: .center)
                SmallButton("Find people to sync with", tonal: true, action: onFindPeople).padding(.top, 14)
            }
        }.padding(.horizontal, 32).padding(.vertical, 40).frame(maxWidth: .infinity)
    }
}

/// Photos and videos of an Explore page full screen, stepping to the next and previous with a swipe or the side arrows; the arrows at the
/// foot vote on the post the current piece belongs to.
private struct ExploreViewer: View {
    let items: [Flat]
    let votes: (String) -> FeedRow?
    let onVote: (FeedRow, Int) -> Void
    let onClose: () -> Void
    @State private var i: Int

    init(items: [Flat], start: Int, votes: @escaping (String) -> FeedRow?, onVote: @escaping (FeedRow, Int) -> Void, onClose: @escaping () -> Void) {
        self.items = items; self.votes = votes; self.onVote = onVote; self.onClose = onClose; _i = State(initialValue: start)
    }

    var body: some View {
        let f = items[i]
        let post = votes(f.post.id) ?? f.post
        ZStack {
            AttachmentViewer(bucket: "posts", path: f.item.path, name: post.who, mime: f.item.isVideo ? "video/mp4" : (f.item.mime.isEmpty ? "image/jpeg" : f.item.mime), onClose: onClose)
                .id(f.item.path)
            HStack {
                if i > 0 { stepButton("chevron.left", "Previous") { i -= 1 } }
                Spacer()
                if i < items.count - 1 { stepButton("chevron.right", "Next") { i += 1 } }
            }.padding(.horizontal, 8)
            VStack {
                Spacer()
                HStack(spacing: 18) {
                    Text(post.who).bucks(.titleSmall).foregroundStyle(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    voteButton("arrow.up", "Recommend", post.up, post.myVote == 1) { onVote(post, 1) }
                    voteButton("arrow.down", "Not recommended", post.down, post.myVote == -1) { onVote(post, -1) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10).background(Color.black.opacity(0.45))
            }
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if v.translation.width < -60, i < items.count - 1 { i += 1 } else if v.translation.width > 60, i > 0 { i -= 1 }
        })
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.4))) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private func voteButton(_ icon: String, _ label: String, _ n: Int, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) { Image(systemName: icon).font(.system(size: 18, weight: .bold)); Text("\(n)").bucks(.labelLarge) }
                .foregroundStyle(on ? BucksColor.primary : .white).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("\(label), \(n)")
    }
}
