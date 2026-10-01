import SwiftUI
import BucksCore

/// One author's live Moments, full screen: progress bars, tap zones, reactions, a reply box, and "Seen by" for my own.
struct MomentViewerScreen: View {
    let author: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    private struct Slide: Identifiable { let moment: MomentRow; let url: URL; var id: String { moment.id } }
    private struct TimerKey: Equatable { var id: String?; var paused: Bool; var video: Bool }

    @State private var slides: [Slide] = []
    @State private var index = 0
    @State private var progress: CGFloat = 0
    @State private var reply = ""
    @State private var viewers: [ViewerRow]?
    @FocusState private var replyFocused: Bool

    private var feed: FeedStore { session.feed }
    private var mine: Bool { author == session.me?.id }
    /// Photos and videos both wait while the reply field is in use or the viewers list is open.
    private var paused: Bool { replyFocused || !reply.trimmingCharacters(in: .whitespaces).isEmpty || viewers != nil }
    private var cur: Slide? { slides.indices.contains(index) ? slides[index] : nil }
    private var isVideo: Bool { cur?.moment.mediaType == "VIDEO" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let cur {
                Group {
                    media(cur)
                    tapZones
                    VStack(spacing: 0) { header(cur.moment); Spacer(minLength: 0) }
                }.ignoresSafeArea(.keyboard)
                VStack(spacing: 0) { Spacer(minLength: 0); footer(cur.moment) }
            } else { BucksLoader(color: .white) }
            if let list = viewers { viewersDialog(list) }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .bucksHideNavigationBar()
        .task(id: author) {
            slides = ((try? await feed.momentsOf(author)) ?? []).map { Slide(moment: $0.moment, url: $0.url) }
            await feed.namesFor([author])
            if slides.isEmpty { close() }
        }
        .task(id: cur?.id) {
            progress = 0
            if let cur, !mine { await feed.viewMoment(cur.moment.id) }
        }
        // Photos: 6 seconds each. Videos: the player drives the bar and moves on when the clip ends.
        .task(id: TimerKey(id: cur?.id, paused: paused, video: isVideo)) {
            guard cur != nil, !paused, !isVideo else { return }
            while progress < 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                progress += 50.0 / 6000.0
            }
            next()
        }
    }

    private func close() { router.pop() }
    private func go(to i: Int) { index = i; progress = 0 }
    private func next() { if index < slides.count - 1 { go(to: index + 1) } else { close() } }

    @ViewBuilder private func media(_ s: Slide) -> some View {
        if isVideo {
            MomentVideo(url: s.url, paused: paused, onProgress: { progress = CGFloat($0) }, onEnded: { next() }).id(s.id).ignoresSafeArea()
        } else {
            AsyncImage(url: s.url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else if phase.error == nil { BucksLoader(color: .white) } else { Color.clear }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea().accessibilityLabel(s.moment.caption)
        }
    }

    /// Left third goes back, the rest goes forward.
    private var tapZones: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Color.clear.frame(width: g.size.width / 3).contentShape(Rectangle()).onTapGesture { if index > 0 { go(to: index - 1) } else { progress = 0 } }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
            }
        }.ignoresSafeArea()
    }

    private func header(_ m: MomentRow) -> some View {
        let name = feed.nameOf(m.authorId)
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(slides.indices, id: \.self) { i in
                    let frac: CGFloat = i < index ? 1 : (i == index ? min(max(progress, 0), 1) : 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.35))
                        GeometryReader { g in Capsule().fill(.white).frame(width: g.size.width * frac) }
                    }.frame(height: 3)
                }
            }
            HStack(spacing: 0) {
                Avatar(initials: initials(name.isEmpty ? "?" : name), size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).bucks(.titleSmall).foregroundStyle(.white)
                    Text([feedAgo(m.createdAt), isVideo ? "Video" : nil].compactMap { $0 }.joined(separator: " · ")).bucks(.labelSmall).foregroundStyle(.white.opacity(0.7))
                }.padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                if mine { barIcon("trash", "Delete") { delete(m) } }
                barIcon("xmark", "Close") { close() }
            }.padding(.top, 10)
        }.padding(8)
    }

    private func barIcon(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func delete(_ m: MomentRow) {
        Task { await feed.deleteMoment(m.id) }
        if slides.count == 1 { close() } else { slides.removeAll { $0.id == m.id }; go(to: min(index, slides.count - 1)) }
    }

    private func footer(_ m: MomentRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !m.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(m.caption).bucks(.bodyLarge).foregroundStyle(.white).padding(.bottom, 10).allowsHitTesting(false)
            }
            if mine {
                Button { Task { viewers = (try? await feed.momentViewers(m.id)) ?? [] } } label: {
                    HStack(spacing: 0) { Image(systemName: "eye"); Text("  Seen by") }.bucksFont(.labelLarge).foregroundStyle(.white).frame(minHeight: 44)
                }.buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    ForEach(["❤️", "🔥", "👏", "😂", "😮"], id: \.self) { e in
                        Button { Task { await feed.viewMoment(m.id, reaction: e) } } label: { Text(e).bucks(.headlineSmall).padding(6) }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 8)
                HStack(spacing: 8) {
                    TextField("", text: $reply, prompt: Text("Reply to \(feed.nameOf(m.authorId).split(separator: " ").first.map(String.init) ?? "")…").foregroundStyle(.white.opacity(0.7)))
                        .font(.bucks(.bodyLarge)).foregroundStyle(.white).tint(.white).focused($replyFocused).submitLabel(.send).onSubmit { sendReply(m) }
                        .padding(.horizontal, 16).frame(height: 56)
                        .overlay(Capsule().strokeBorder(replyFocused ? .white : .white.opacity(0.5), lineWidth: replyFocused ? 2 : 1))
                    Button { sendReply(m) } label: {
                        Image(systemName: "paperplane.fill").font(.system(size: 18)).foregroundStyle(BucksColor.onPrimary).frame(width: 48, height: 48)
                            .background(Circle().fill(reply.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.12) : BucksColor.primary))
                    }.buttonStyle(.plain).disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private func sendReply(_ m: MomentRow) {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task { await feed.replyToMoment(m.id, body: t) { conv in router.popToRoot(); router.push(.chat(conv)) } }
    }

    private func viewersDialog(_ list: [ViewerRow]) -> some View {
        FeedDialog(title: "Seen by \(list.count)", closeTitle: "Close", onClose: { viewers = nil }) {
            VStack(alignment: .leading, spacing: 0) {
                if list.isEmpty { Muted("No views yet.") }
                ForEach(Array(list.prefix(30).enumerated()), id: \.offset) { _, v in
                    HStack(spacing: 0) {
                        Avatar(initials: initials(v.name), size: 32)
                        Text(v.name).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
                        Text(v.reaction ?? "").bucks(.bodyLarge)
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}
