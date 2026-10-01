import Foundation
import Testing
@testable import BucksCore

/// The feed, posts, votes, comments and Moments: what they put on the wire (function names, `p_` parameters, filters) and how the state
/// moves, written against supabase/schema.sql and Backend.kt / BackendSocialExtras.kt.
@MainActor @Suite(.serialized) struct FeedTests {
    func boot(_ handler: @escaping (String, String, [String: Any]) -> (Int, Any)) {
        FakeServer.handler = handler; FakeServer.log = []; FakeServer.calls = []; FakeServer.prefer = [:]
        Backend.shared.configure(BackendConfig(url: "https://x.supabase.co", anonKey: "anon"), identity: FakeIdentity())
        Backend.shared.useProtocolClasses([FakeServer.self])
    }
    private func call(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }
    private func session() -> (AppSession, () -> [String]) {
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        let box = ToastBox(); s.toastHandler = { box.items.append($0) }
        return (s, { box.items })
    }
    private final class ToastBox { var items: [String] = [] }

    private func post(_ id: String, at: String, up: Int = 2, down: Int = 0, comments: Int = 0, myVote: Int? = nil) -> [String: Any] {
        var r: [String: Any] = ["id": id, "author_id": "u9", "author_name": "Meera Shah", "author_code": "CU0009", "body": "Great dosa at the corner shop", "media": [["path": "u9/a.jpg", "mime": "image/jpeg"]],
                                "visibility": "LOCAL", "area": "Jayanagar", "up": up, "down": down, "comments": comments, "created_at": at, "synced": true]
        if let myVote { r["my_vote"] = myVote }
        return r
    }

    @Test func feedPagesWithTheLastCreatedAt() async throws {
        let page = (0..<30).map { post("p\($0)", at: "2026-10-01T10:\(String(format: "%02d", 59 - $0)):00+00:00") }
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/feed": return (200, FakeServer.calls.filter { $0.path == path }.count == 1 ? page : [self.post("p30", at: "2026-10-01T09:00:00+00:00")])
            case "/rest/v1/rpc/moments_tray": return (200, [["author_id": "me", "author_name": "Asha Rao", "author_code": "ME0001", "moments": 1, "unseen": 0, "latest_at": "2026-10-01T10:00:00+00:00", "is_me": true]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, toasts) = session(); let f = s.feed
        await f.refreshFeed()
        #expect(toasts() == [])
        // The feed and the tray take plain lat / lng; the first page sends no cursor.
        let first = try #require(call("/rest/v1/rpc/feed").first)
        #expect(Set(first.body.keys) == ["lat", "lng"])
        #expect(f.feed.count == 30); #expect(!f.feedEnd)
        #expect(Set(try #require(call("/rest/v1/rpc/moments_tray").first).body.keys) == ["lat", "lng"])
        #expect(f.tray.count == 1 && f.tray[0].isMe)
        await f.loadMoreFeed()
        let more = try #require(call("/rest/v1/rpc/feed").last)
        #expect(more.body["before"] as? String == "2026-10-01T10:30:00+00:00")
        #expect(f.feed.count == 31); #expect(f.feedEnd)
    }

    @Test func votingTogglesAndCountsLikeAndroid() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/feed": return (200, [self.post("p1", at: "2026-10-01T10:00:00+00:00", up: 2, down: 1, myVote: -1)])
            case "/rest/v1/rpc/moments_tray": return (200, [])
            case "/rest/v1/post_votes": return (201, [:])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, _) = session(); let f = s.feed
        await f.refreshFeed()
        await f.vote("p1", 1)    // from a down vote to an up vote
        let up = try #require(call("/rest/v1/post_votes").first)
        #expect(up.method == "POST"); #expect(FakeServer.prefer["POST /rest/v1/post_votes"]?.contains("resolution=merge-duplicates") == true)
        #expect(up.body as NSDictionary == ["post_id": "p1", "profile_id": "me", "vote": 1] as NSDictionary)
        #expect(f.feed[0].myVote == 1); #expect(f.feed[0].up == 3); #expect(f.feed[0].down == 0)
        await f.vote("p1", 1)    // the same vote again takes it back
        let del = try #require(call("/rest/v1/post_votes").last)
        #expect(del.method == "DELETE"); #expect(del.query.contains("post_id=eq.p1")); #expect(del.query.contains("profile_id=eq.me"))
        #expect(f.feed[0].myVote == nil); #expect(f.feed[0].up == 2)
    }

    @Test func postingUploadsThenInsertsWithMediaAndLocation() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/posts": return (201, [:])
            case "/rest/v1/rpc/feed": return (200, [])
            case "/rest/v1/rpc/moments_tray": return (200, [])
            default: return path.hasPrefix("/storage/v1/object/posts/") ? (200, ["Key": "ok"]) : (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, toasts) = session(); let f = s.feed
        let photo = Picked(data: Data([1, 2, 3]), name: "a.jpg", mime: "image/jpeg")
        await f.post(body: "Best chai", media: [photo], visibility: "SYNCED", area: "Jayanagar")
        let upload = try #require(FakeServer.calls.first { $0.path.hasPrefix("/storage/v1/object/posts/me/") })
        #expect(upload.method == "POST"); #expect(upload.path.hasSuffix(".jpg"))
        let row = try #require(call("/rest/v1/posts").first).body
        #expect(Set(row.keys) == ["author_id", "body", "visibility", "area", "media", "location"])
        #expect(row["author_id"] as? String == "me"); #expect(row["visibility"] as? String == "SYNCED"); #expect(row["area"] as? String == "Jayanagar")
        #expect((row["location"] as? String)?.hasPrefix("SRID=4326;POINT(") == true)
        let media = try #require(row["media"] as? [[String: String]])
        #expect(media.count == 1); #expect(media[0]["mime"] == "image/jpeg"); #expect(media[0]["path"]?.hasPrefix("me/") == true)
        #expect(media[0]["path"] == String(upload.path.dropFirst("/storage/v1/object/posts/".count)))
        #expect(toasts() == ["Posted."]); #expect(!f.busy)
        // The uploads happen before the row, and the feed reloads afterwards.
        let order = FakeServer.log
        #expect(order.firstIndex { $0.contains("/storage/v1/object/posts/") }! < order.firstIndex(of: "POST /rest/v1/posts")!)
        #expect(call("/rest/v1/rpc/feed").count == 1)
    }

    @Test func commentsAndDeletesUseTheTablesAndKeepTheCount() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/feed": return (200, [self.post("p1", at: "2026-10-01T10:00:00+00:00", comments: 4)])
            case "/rest/v1/rpc/moments_tray": return (200, [])
            case "/rest/v1/post_comments": return (201, [])
            case "/rest/v1/posts": return (204, [:])
            case "/rest/v1/profiles": return (200, [["id": "u9", "short_code": "CU0009", "name": "Meera Shah"]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, _) = session(); let f = s.feed
        await f.refreshFeed()
        #expect(await f.comment("p1", "Same here"))
        let c = try #require(call("/rest/v1/post_comments").first)
        #expect(c.method == "POST"); #expect(c.body as NSDictionary == ["post_id": "p1", "author_id": "me", "body": "Same here"] as NSDictionary)
        #expect(f.feed[0].comments == 5)
        _ = try await f.comments("p1")
        let list = try #require(call("/rest/v1/post_comments").last)
        #expect(list.method == "GET"); #expect(list.query.contains("post_id=eq.p1")); #expect(list.query.contains("order=created_at.asc"))
        await f.deletePost("p1")
        let del = try #require(call("/rest/v1/posts").last)
        #expect(del.method == "DELETE"); #expect(del.query.contains("id=eq.p1")); #expect(f.feed.isEmpty)
        // The post detail screen reads one live row.
        _ = try? await f.post(id: "p2")
        #expect(call("/rest/v1/posts").last?.query.contains("deleted_at=is.null") == true)
    }

    @Test func momentsUseTheServersParameterNames() async throws {
        boot { path, _, params in
            switch path {
            case "/rest/v1/rpc/open_moments": return (200, [["id": "m1", "author_id": "u9", "media_path": "u9/x.jpg", "media_type": "IMAGE", "caption": "Hi", "audience": "SYNCED", "created_at": "2026-10-01T10:00:00+00:00", "expires_at": "2026-10-02T10:00:00+00:00"]])
            case "/storage/v1/object/sign/moments/u9/x.jpg": return (200, ["signedURL": "/object/sign/moments/u9/x.jpg?token=t"])
            case "/rest/v1/rpc/view_moment": return (204, [:])
            case "/rest/v1/rpc/reply_to_moment": return (200, "conv-1")
            case "/rest/v1/rpc/moment_viewers": return (200, [["viewer_id": "u1", "name": "Ravi", "reaction": "🔥", "viewed_at": "2026-10-01T10:05:00+00:00"]])
            case "/rest/v1/moment_mutes": return (201, [])
            case "/rest/v1/moments": return (201, [:])
            case "/rest/v1/rpc/moments_tray": return (200, [])
            default: return path.hasPrefix("/storage/v1/object/moments/") ? (200, ["Key": "ok"]) : (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, toasts) = session(); let f = s.feed
        let slides = try await f.momentsOf("u9")
        let open = try #require(call("/rest/v1/rpc/open_moments").first).body
        #expect(Set(open.keys) == ["p_author", "lat", "lng"]); #expect(open["p_author"] as? String == "u9")
        #expect(slides.count == 1); #expect(slides[0].url.absoluteString == "https://x.supabase.co/storage/v1/object/sign/moments/u9/x.jpg?token=t")

        await f.viewMoment("m1")
        #expect(call("/rest/v1/rpc/view_moment").last?.body["p_reaction"] is NSNull)      // sent as JSON null, not left out
        await f.viewMoment("m1", reaction: "🔥")
        let react = try #require(call("/rest/v1/rpc/view_moment").last)
        #expect(Set(react.body.keys) == ["p_moment", "p_reaction"]); #expect(react.body["p_reaction"] as? String == "🔥"); #expect(toasts().last == "Sent 🔥")

        var opened: String?
        await f.replyToMoment("m1", body: "Lovely") { opened = $0 }
        #expect(opened == "conv-1")
        #expect(try #require(call("/rest/v1/rpc/reply_to_moment").first).body as NSDictionary == ["p_moment": "m1", "p_body": "Lovely"] as NSDictionary)
        #expect(try await f.momentViewers("m1").first?.reaction == "🔥")
        #expect(try #require(call("/rest/v1/rpc/moment_viewers").first).body as NSDictionary == ["p_moment": "m1"] as NSDictionary)

        await f.muteMoments("u9", on: true)
        let mute = try #require(call("/rest/v1/moment_mutes").first(where: { $0.method == "POST" }))
        #expect(mute.body as NSDictionary == ["profile_id": "me", "muted_id": "u9"] as NSDictionary)
        #expect(FakeServer.prefer["POST /rest/v1/moment_mutes"]?.contains("resolution=merge-duplicates") == true)
        await f.muteMoments("u9", on: false)
        let unmute = try #require(call("/rest/v1/moment_mutes").first(where: { $0.method == "DELETE" }))
        #expect(unmute.query.contains("profile_id=eq.me")); #expect(unmute.query.contains("muted_id=eq.u9")); #expect(toasts().last == "Unmuted.")

        let photo = Picked(data: Data([1]), name: "a.jpg", mime: "image/jpeg")
        #expect(await f.postMoment(photo, caption: "Sunset", audience: "LOCAL"))
        let m = try #require(call("/rest/v1/moments").first).body
        #expect(Set(m.keys) == ["author_id", "media_path", "media_type", "caption", "audience", "location"])
        #expect(m["media_type"] as? String == "IMAGE"); #expect(m["audience"] as? String == "LOCAL"); #expect(toasts().contains("Your moment is up for 24 hours."))
    }

    @Test func momentVideosAreCheckedBeforeUpload() async {
        boot { _, _, _ in (404, ["message": "no stub"]) }
        let (s, toasts) = session(); let f = s.feed
        let mov = Picked(data: Data([1]), name: "a.mov", mime: "video/quicktime")
        #expect(await f.postMoment(mov, caption: "", audience: "SYNCED") == false)
        #expect(toasts().last == "Only MP4 videos can be shared.")
        let big = Picked(data: Data(count: FeedStore.maxVideoBytes + 1), name: "a.mp4", mime: "video/mp4")
        #expect(await f.postMoment(big, caption: "", audience: "SYNCED") == false)
        #expect(toasts().last == "Videos up to 30 MB. Pick a shorter one.")
        #expect(FakeServer.calls.isEmpty)
    }

    @Test func loadMoreNeverShowsAPostTwice() async throws {
        let page = (0..<30).map { post("p\($0)", at: "2026-10-01T10:\(String(format: "%02d", 59 - $0)):00+00:00") }
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/feed": return (200, FakeServer.calls.filter { $0.path == path }.count == 1 ? page : [page[29], self.post("p30", at: "2026-10-01T09:00:00+00:00")])
            case "/rest/v1/rpc/moments_tray": return (200, [])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, _) = session(); let f = s.feed
        await f.refreshFeed()
        // Two taps on "Load more" at once fetch one page; a row the next page repeats is dropped.
        async let a: Void = f.loadMoreFeed(); async let b: Void = f.loadMoreFeed()
        _ = await (a, b)
        #expect(call("/rest/v1/rpc/feed").count == 2)
        #expect(f.feed.count == 31); #expect(Set(f.feed.map(\.id)).count == 31)
    }

    @Test func agoReadsLikeAndroid() {
        let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
        #expect(feedAgo("2026-10-01T11:59:40+00:00", now: now) == "now")
        #expect(feedAgo("2026-10-01T11:58:00+00:00", now: now) == "2m")
        #expect(feedAgo("2026-10-01T09:00:00+00:00", now: now) == "3h")
        #expect(feedAgo("2026-09-30T10:00:00+00:00", now: now) == "Yesterday")
        #expect(feedAgo("2026-03-12 10:00:00.123456+00", now: now) == "12 Mar" || feedAgo("2026-03-12T10:00:00+00:00", now: now) == "12 Mar")
        #expect(feedAgo("garbage") == "")
        #expect(humanFileSize(3_355_443) == "3.2 MB"); #expect(humanFileSize(2048) == "2 KB"); #expect(humanFileSize(0) == "")
    }
}
