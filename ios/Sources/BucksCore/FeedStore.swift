import Foundation
import Observation

/// "now", "2m", "3h", "Yesterday", "12 Mar" from an ISO timestamp (ago() in CloudSocialScreens.kt); "" when it can't be read.
public func feedAgo(_ iso: String, now: Date = Date()) -> String {
    var s = iso.replacingOccurrences(of: " ", with: "T")
    if !(s.hasSuffix("Z") || s.contains("+")) { s += "Z" }
    let plain = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let t = plain.date(from: s) ?? fractional.date(from: s) else { return "" }
    let secs = max(0, Int(now.timeIntervalSince(t)))
    switch secs {
    case ..<60: return "now"
    case ..<3600: return "\(secs / 60)m"
    case ..<86400: return "\(secs / 3600)h"
    case ..<172800: return "Yesterday"
    default:
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
        return f.string(from: t)
    }
}

/// "3.2 MB", "420 KB", "90 B"; "" for nothing.
public func humanFileSize(_ bytes: Int) -> String {
    if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    if bytes >= 1024 { return "\(bytes / 1024) KB" }
    return bytes > 0 ? "\(bytes) B" : ""
}

/// One photo or video of a post: its path in the posts bucket and its mime type.
public struct PostMediaItem: Hashable, Sendable {
    public var path: String
    public var mime: String
    public var isVideo: Bool { mime.hasPrefix("video/") || path.lowercased().hasSuffix(".mp4") }
}

/// The attachments of a post row, in order; entries without a path are dropped (PostMedia in CloudSocialScreens.kt).
public func postMediaItems(_ media: [JSONValue]) -> [PostMediaItem] {
    media.compactMap { v in
        guard case .object(let o) = v, case .string(let path)? = o["path"], !path.isEmpty else { return nil }
        var mime = ""
        if case .string(let m)? = o["mime"] { mime = m }
        return PostMediaItem(path: path, mime: mime)
    }
}

/// Port of the feed and Moments half of the Android `Social` state holder: the feed, posts, votes, comments and the Moments tray.
/// Every action reports a failure as a toast.
@MainActor @Observable
public final class FeedStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    public private(set) var feed: [FeedRow] = []
    public private(set) var feedEnd = false
    public private(set) var tray: [TrayRow] = []
    /// People whose Moments I've hidden from my tray.
    public private(set) var mutedMoments: [ProfileRow] = []
    /// True while a photo or file is uploading.
    public private(set) var busy = false

    /// The Moments bucket's limit.
    public static let maxVideoBytes = 30 * 1024 * 1024
    /// The posts bucket's limit.
    public static let maxPostVideoBytes = 15 * 1024 * 1024
    private static let pageSize = 30

    @ObservationIgnored private var loadingMore = false
    /// Posts whose vote is on its way; a second tap meanwhile would count the same vote twice.
    @ObservationIgnored private var voting = Set<String>()

    private var me: String? { session.me?.id }
    private var here: LatLng { session.here }

    private func report(_ e: Error) { if !(e is CancellationError) { session.toast(friendlyError(e)) } }

    /// Forgets everything (signing out).
    public func clear() { feed = []; feedEnd = false; tray = []; mutedMoments = [] }

    // MARK: names

    public func nameOf(_ id: String) -> String { session.names[id] ?? "…" }
    public func namesFor(_ ids: [String]) async {
        var seen = Set<String>()
        let missing = ids.filter { session.names[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty, let rows = try? await Backend.shared.profiles(missing) else { return }
        for p in rows { session.names[p.id] = p.name }
    }

    // MARK: feed

    public func refreshFeed() async {
        do { feed = try await Backend.shared.feed(at: here); feedEnd = feed.count < Self.pageSize } catch { report(error); return }
        await refreshTray()
    }
    public func loadMoreFeed() async {
        // A second tap while a page is on its way would fetch the same page twice and show every post in it twice.
        guard let last = feed.last, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let more = try await Backend.shared.feed(at: here, before: last.createdAt)
            let known = Set(feed.map(\.id))
            feed += more.filter { !known.contains($0.id) }
            feedEnd = more.count < Self.pageSize
        } catch { report(error) }
    }

    /// Uploads the attachments to the posts bucket, then writes the post. Reports "Posted." and reloads the feed.
    public func post(body: String, media: [Picked], visibility: String, area: String) async {
        guard let me else { return }
        busy = true; defer { busy = false }
        do {
            var paths: [(path: String, mime: String)] = []
            for f in media {
                let path = "\(me)/\(f.objectName())"
                try await Backend.shared.upload(bucket: "posts", path: path, data: f.data, contentType: f.mime)
                paths.append((path, f.mime))
            }
            try await Backend.shared.post(me: me, body: body, media: paths, visibility: visibility, at: here, area: area)
            session.toast("Posted.")
        } catch { report(error); return }
        await refreshFeed()
    }

    public func deletePost(_ id: String) async {
        do { try await Backend.shared.deletePost(id); feed.removeAll { $0.id == id } } catch { report(error) }
    }

    /// Tapping the vote I already gave takes it back.
    public func vote(_ postId: String, _ v: Int) async {
        guard let me, let cur = feed.first(where: { $0.id == postId }), voting.insert(postId).inserted else { return }
        defer { voting.remove(postId) }
        let prev = cur.myVote ?? 0, next = prev == v ? 0 : v
        do { try await Backend.shared.vote(postId: postId, me: me, vote: next) } catch { report(error); return }
        guard let i = feed.firstIndex(where: { $0.id == postId }) else { return }
        feed[i].myVote = next == 0 ? nil : next
        feed[i].up += (next == 1 ? 1 : 0) - (prev == 1 ? 1 : 0)
        feed[i].down += (next == -1 ? 1 : 0) - (prev == -1 ? 1 : 0)
    }

    public func comments(_ postId: String) async throws -> [CommentRow] {
        let rows = try await Backend.shared.comments(postId: postId)
        await namesFor(rows.map(\.authorId))
        return rows
    }
    /// Returns true when the comment was saved.
    @discardableResult
    public func comment(_ postId: String, _ body: String) async -> Bool {
        guard let me else { return false }
        do {
            try await Backend.shared.comment(postId: postId, me: me, body: body)
            if let i = feed.firstIndex(where: { $0.id == postId }) { feed[i].comments += 1 }
            return true
        } catch { report(error); return false }
    }

    /// One post for the detail screen: nil when it was deleted or I can't see it; throws when it couldn't be loaded.
    public func post(id: String) async throws -> PostRow? {
        guard let p = try await Backend.shared.postById(id) else { return nil }
        await namesFor([p.authorId])
        return p
    }

    // MARK: moments

    public func refreshTray() async {
        do { tray = try await Backend.shared.momentsTray(at: here) } catch { report(error) }
    }

    /// Photos (re-encoded by the picker) or MP4 videos up to `maxVideoBytes`, the bucket's limit. Returns true once shared.
    @discardableResult
    public func postMoment(_ f: Picked, caption: String, audience: String) async -> Bool {
        guard let me else { return false }
        if f.isVideo && f.data.count > Self.maxVideoBytes { session.toast("Videos up to 30 MB. Pick a shorter one."); return false }
        if f.isVideo && f.mime != "video/mp4" { session.toast("Only MP4 videos can be shared."); return false }
        busy = true; defer { busy = false }
        do {
            let path = "\(me)/\(f.objectName())"
            try await Backend.shared.upload(bucket: "moments", path: path, data: f.data, contentType: f.mime)
            try await Backend.shared.postMoment(me: me, mediaPath: path, type: f.isVideo ? "VIDEO" : "IMAGE", caption: caption, audience: audience, at: here)
            session.toast("Your moment is up for 24 hours.")
        } catch { report(error); return false }
        await refreshTray()
        return true
    }

    /// Opening (not just listing) grants access to nearby moments from people I'm not synced with, so their media can be signed.
    public func momentsOf(_ author: String) async throws -> [(moment: MomentRow, url: URL)] {
        let rows = try await Backend.shared.openMoments(author: author, at: here)
        var out: [(moment: MomentRow, url: URL)] = []
        for m in rows { out.append((m, try await Backend.shared.signedURL(bucket: "moments", path: m.mediaPath))) }
        return out
    }
    public func viewMoment(_ id: String, reaction: String? = nil) async {
        do { try await Backend.shared.viewMoment(id, reaction: reaction); if let reaction { session.toast("Sent \(reaction)") } } catch { report(error) }
    }
    /// Sends a reply to the author as a chat message; `onOpen` gets the conversation id.
    public func replyToMoment(_ id: String, body: String, onOpen: @escaping (String) -> Void) async {
        do { onOpen(try await Backend.shared.replyToMoment(id, body: body)) } catch { report(error) }
    }
    public func momentViewers(_ id: String) async throws -> [ViewerRow] { try await Backend.shared.momentViewers(id) }
    public func deleteMoment(_ id: String) async {
        do { try await Backend.shared.deleteMoment(id) } catch { report(error); return }
        await refreshTray()
    }
    public func muteMoments(_ author: String, on: Bool) async {
        guard let me else { return }
        do { try await Backend.shared.muteMoments(me: me, other: author, on: on) } catch { report(error); return }
        session.toast(on ? "\(nameOf(author))'s moments are hidden. Unmute from the Moments row's More button." : "Unmuted.")
        await refreshTray(); await refreshMutedMoments()
    }
    public func refreshMutedMoments() async {
        do {
            let rows = try await Backend.shared.momentMutes()
            let people = try await Backend.shared.profiles(rows.map(\.mutedId))
            for p in people { session.names[p.id] = p.name }
            mutedMoments = people
        } catch { report(error) }
    }

    /// My default audience for a new Moment (privacy setting), "SYNCED" until I save one.
    public var defaultAudience: String { session.social.settings?.momentsAudience ?? "SYNCED" }
}
