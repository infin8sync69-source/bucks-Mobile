#if os(macOS)
import Foundation

/// Feed, posts, comments and Moments for the harness: one neighbour (Meera) with a post and two moments, me with none.
func fakeFeed(method: String, path: String, query: String, params: [String: Any]) -> (Int, Any)? {
    let now = FakeSupabase.iso(Date().addingTimeInterval(-600))
    let post: [String: Any] = ["id": "p1", "author_id": "u9", "author_name": "Meera Shah", "author_code": "CU0009", "body": "Anyone know a good plumber near 4th Block? Mine has gone on leave.",
                               "media": [["path": "u9/a.jpg", "mime": "image/jpeg"]], "visibility": "LOCAL", "area": "Jayanagar", "up": 3, "down": 0, "comments": 2, "created_at": now, "synced": true]
    switch (method, path) {
    case ("POST", "/rest/v1/rpc/feed"): return (200, [post])
    case ("POST", "/rest/v1/rpc/moments_tray"):
        return (200, [["author_id": "me", "author_name": "Asha Rao", "author_code": "ME0001", "moments": 0, "unseen": 0, "latest_at": now, "is_me": true],
                      ["author_id": "u9", "author_name": "Meera Shah", "author_code": "CU0009", "moments": 2, "unseen": 1, "latest_at": now, "is_me": false]])
    case ("GET", "/rest/v1/posts"): return (200, [["id": "p1", "author_id": "u9", "body": post["body"] as Any, "media": post["media"] as Any, "visibility": "LOCAL", "up": 3, "down": 0, "comments": 2, "created_at": now]])
    case ("GET", "/rest/v1/post_comments"):
        return (200, [["id": "c1", "post_id": "p1", "author_id": "u9", "body": "I have a number, will message you.", "created_at": now], ["id": "c2", "post_id": "p1", "author_id": "me", "body": "Thank you!", "created_at": now]])
    case ("POST", "/rest/v1/rpc/open_moments"):
        return (200, [["id": "m1", "author_id": "u9", "media_path": "u9/m1.jpg", "media_type": "IMAGE", "caption": "Sunset from the terrace", "audience": "SYNCED", "created_at": now, "expires_at": now],
                      ["id": "m2", "author_id": "u9", "media_path": "u9/m2.mp4", "media_type": "VIDEO", "caption": "", "audience": "SYNCED", "created_at": now, "expires_at": now]])
    case ("POST", "/rest/v1/rpc/view_moment"): return (204, [:])
    case ("GET", "/rest/v1/moment_mutes"): return (200, [])
    case ("POST", "/rest/v1/rpc/moment_viewers"): return (200, [["viewer_id": "u9", "name": "Meera Shah", "reaction": "🔥", "viewed_at": now]])
    case ("GET", "/rest/v1/user_settings"): return (200, [])
    default: return nil
    }
}
#endif
