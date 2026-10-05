import SwiftUI
import BucksCore

private struct OpenFile: Identifiable { let bucket: String, path: String, mime: String; var id: String { bucket + path } }

/// Photos and videos from my posts, three to a row; tap for full size or to play.
struct AccountMediaTab: View {
    let posts: [PostRow]?
    let failed: Bool
    @State private var open: OpenFile?

    private var items: [(path: String, mime: String)] {
        (posts ?? []).flatMap { p in p.media.compactMap { m -> (String, String)? in
            guard let path = m["path"]?.string, !path.isEmpty else { return nil }
            return (path, m["mime"]?.string ?? "")
        } }
    }

    var body: some View {
        Group {
            if posts == nil && !failed { BucksLoader().frame(maxWidth: .infinity).padding(.top, 40) }
            else if failed { Muted("Couldn't load your media. Check your connection and open this tab again.").padding(Gutter) }
            else if items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No photos or videos yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("Photos and videos you add to posts collect here.")
                }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
                VStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, it in tile(it.path, it.mime) }
                            ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                        }
                    }
                }.padding(.horizontal, Gutter).padding(.vertical, 12)
            }
        }
        .bucksFullScreenCover(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) {
            if let o = open { AccountAttachmentViewer(bucket: o.bucket, path: o.path, mime: o.mime) { open = nil } }
        }
    }

    private func tile(_ path: String, _ mime: String) -> some View {
        let video = mime.hasPrefix("video/") || path.lowercased().hasSuffix(".mp4")
        return Button { open = OpenFile(bucket: "posts", path: path, mime: video ? "video/mp4" : "image/jpeg") } label: {
            ZStack {
                if video { Color.black; Image(systemName: "play.fill").font(.system(size: 28)).foregroundStyle(.white) }
                else { SignedImage(bucket: "posts", path: path) }
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel(video ? "Video" : "Photo")
    }
}

/// Files and photos shared in my chats, sent or received; tap opens it.
struct AccountFilesTab: View {
    @Environment(AppSession.self) private var session
    @State private var files: [MessageRow]?
    @State private var failed = false
    @State private var viewing: OpenFile?

    var body: some View {
        Group {
            if files == nil && !failed { BucksLoader().frame(maxWidth: .infinity).padding(.top, 40) }
            else if failed { Muted("Couldn't load your files. Check your connection and open this tab again.").padding(Gutter) }
            else if (files ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No files yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted("Photos, videos and documents you send or receive in chats collect here.")
                }.padding(Gutter).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) { ForEach(files ?? []) { m in if let a = m.attachment { row(m, a) } } }
            }
        }
        .task(id: session.me?.id) { await load() }
        .bucksFullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let o = viewing { AccountAttachmentViewer(bucket: o.bucket, path: o.path, mime: o.mime) { viewing = nil } }
        }
    }

    private func row(_ m: MessageRow, _ a: JSONValue) -> some View {
        let path = a["path"]?.string ?? "", mime = a["mime"]?.string ?? ""
        let name = (a["name"]?.string).flatMap { $0.isEmpty ? nil : $0 } ?? "File"
        let size = a["size"]?.int ?? a["size"]?.string.flatMap(Int.init) ?? 0
        let mine = m.senderId == session.me?.id
        let sub = [size > 0 ? accountHumanBytes(size) : nil, mine ? "Sent by you" : "From \(session.names[m.senderId] ?? "")", accountAgo(m.createdAt)].compactMap { $0 }.joined(separator: " · ")
        let icon = mime.hasPrefix("image/") ? "photo" : mime.hasPrefix("video/") ? "video.fill" : mime == "application/pdf" ? "doc.richtext.fill" : "doc.fill"
        return VStack(spacing: 0) {
            ListRow(name, subtitle: sub, onTap: { open(path: path, mime: mime, name: name) }, leading: { Avatar(systemImage: icon, size: 40) })
            BucksDivider()
        }
    }

    private func open(path: String, mime: String, name: String) {
        if mime.hasPrefix("image/") || mime.hasPrefix("video/") { viewing = OpenFile(bucket: "chat", path: path, mime: mime); return }
        session.toast("Opening…")
        Task {
            guard let url = try? await Backend.shared.signedURL(bucket: "chat", path: path) else { session.toast("No app on this phone can open that file, or the download failed."); return }
            openSystemURL(url.absoluteString) { ok in if !ok { session.toast("No app on this phone can open that file, or the download failed.") } }
        }
    }

    private func load() async {
        do {
            let rows = try await Backend.shared.accountChatFiles()
            let missing = Array(Set(rows.map(\.senderId)).filter { session.names[$0] == nil })
            if !missing.isEmpty, let ps = try? await Backend.shared.profiles(missing) { for p in ps { session.names[p.id] = p.name } }
            files = rows; failed = false
        } catch { if files == nil { failed = true } }
    }
}

/// Recommendations: locals I recommended, reviews I gave, and how many people recommended my own listings.
struct AccountRecommendationsTab: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var mine: [ListingRow] = []
    @State private var counts: [String: Int] = [:]
    @State private var given: [(RecGiven, ListingRow?)]?
    @State private var reviews: [(ReviewRow, ListingRow?)]?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("For my listings").padding(.horizontal, Gutter).padding(.top, 14).padding(.bottom, 4)
            if mine.isEmpty { Muted("When you list a business, skill or asset, the people who recommend it show here.").padding(.horizontal, Gutter) }
            ForEach(mine) { l in
                let n = counts[l.id]
                VStack(spacing: 0) {
                    ListRow(l.title, subtitle: [n.map { "\($0) \($0 == 1 ? "person" : "people") recommended" }, l.status == "LIVE" ? "Live" : "Not live yet"].compactMap { $0 }.joined(separator: " · "),
                            onTap: { router.push(.studio(l.id)) }, leading: { Avatar(systemImage: "hand.thumbsup.fill", size: 40) }, trailing: { TrustBadge(up: l.trustUp, down: l.trustDown, compact: true) })
                    BucksDivider()
                }
            }
            SectionTitle("Locals I recommended").padding(.horizontal, Gutter).padding(.top, 18).padding(.bottom, 4)
            if let given {
                if given.isEmpty { Muted("Scan someone's code in person (Menu > Recommend a local) to vouch for a shop, skill or driver you know.").padding(.horizontal, Gutter) }
                ForEach(Array(given.enumerated()), id: \.offset) { _, pair in
                    let (r, l) = pair
                    VStack(spacing: 0) {
                        ListRow(l?.title ?? "A listing", subtitle: [l.flatMap { $0.category.isEmpty ? nil : $0.category }, l.flatMap { $0.area.isEmpty ? nil : $0.area }, accountAgo(r.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                onTap: l.map { x in { router.push(.listing(x.id)) } }, leading: { Avatar(systemImage: "checkmark.seal.fill", size: 40) })
                        BucksDivider()
                    }
                }
            } else if failed { Muted("Couldn't load your recommendations. Open this tab again.").padding(.horizontal, Gutter) }
            else { BucksLoader().frame(maxWidth: .infinity).padding(.top, 20) }
            SectionTitle("Reviews I gave").padding(.horizontal, Gutter).padding(.top, 18).padding(.bottom, 4)
            if let reviews {
                if reviews.isEmpty { Muted("After an order, visit or trip you can review it from its page.").padding(.horizontal, Gutter) }
                ForEach(Array(reviews.enumerated()), id: \.offset) { _, pair in
                    let (r, l) = pair
                    VStack(spacing: 0) {
                        ListRow(l?.title ?? "A listing", subtitle: [String(r.comment.prefix(70)), accountAgo(r.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "),
                                onTap: l.map { x in { router.push(.listing(x.id)) } },
                                leading: {
                                    Image(systemName: r.vote > 0 ? "hand.thumbsup.fill" : "arrow.down").foregroundStyle(r.vote > 0 ? BucksColor.good : BucksColor.bad)
                                        .frame(width: 40, height: 40).accessibilityLabel(r.vote > 0 ? "Recommended" : "Not recommended")
                                })
                        BucksDivider()
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .task(id: session.me?.id) { await load() }
    }

    private func load() async {
        guard let me = session.me?.id else { return }
        do { given = try await Backend.shared.accountRecommendationsIGave(me: me); failed = false } catch { failed = true }
        reviews = try? await Backend.shared.accountReviewsIWrote(me: me)
        if let l = try? await Backend.shared.accountMyListings(me: me) {
            mine = l
            if let c = try? await Backend.shared.accountRecommendationCounts(l.map(\.id)) { counts = Dictionary(uniqueKeysWithValues: l.map { ($0.id, c[$0.id] ?? 0) }) }
        }
    }
}
