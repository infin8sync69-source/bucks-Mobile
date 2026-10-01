import SwiftUI
import BucksCore

/// One post with its photos and its comments; where a comment, like or reply notification opens.
struct PostDetailScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var post: PostRow?
    @State private var state = "loading"
    @State private var comments = true

    var body: some View {
        VStack(spacing: 0) {
            BucksTopBar(title: "Post", onBack: { router.pop() })
            if let p = post { content(p) }
            else if state == "loading" { Spacer(); BucksLoader(); Spacer() }
            else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state == "error" ? "Couldn't load this post" : "This post is gone").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted(state == "error" ? "Check your connection and try again." : "It was deleted, or you can no longer see it.")
                }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
        }
        .bucksBackground()
        .bucksHideNavigationBar()
        .task(id: id) { await load() }
        .sheet(isPresented: Binding(get: { comments && post != nil }, set: { comments = $0 })) { CommentsSheet(postId: id).feedSheetStyle() }
    }

    private func content(_ p: PostRow) -> some View {
        let name = session.feed.nameOf(p.authorId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Avatar(initials: initials(name), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(feedAgo(p.createdAt))
                    }
                }
                if !p.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(p.body).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                }
                PostMediaView(media: p.media)
                Muted("\(p.up) recommended · \(p.comments) comment\(p.comments == 1 ? "" : "s")").padding(.top, 12)
                SmallButton("Comments", tonal: true) { comments = true }.padding(.top, 10)
            }.padding(Gutter)
        }
    }

    private func load() async {
        state = "loading"
        do {
            if let p = try await session.feed.post(id: id) { post = p; state = "ok" } else { state = "gone" }
        } catch { state = "error" }
    }
}
