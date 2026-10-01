#if os(macOS)
import Foundation

/// Fake chat, sync, notification, settings and contact-link endpoints for the Mac preview harness.
enum FakeChat {
    nonisolated(unsafe) static var messages: [String: [[String: Any]]] = [
        "c1": [
            msg("m1", "c1", "u2", "Hi Asha, I can pick up the parcel at 6?", "2026-09-30T09:00:00+00:00"),
            msg("m2", "c1", "me", "Yes, 6 works. Please call when you're outside.", "2026-09-30T09:02:00+00:00"),
            msg("m3", "c1", "u2", "", "2026-09-30T09:05:00+00:00", attachment: ["path": "c1/receipt.pdf", "name": "receipt.pdf", "mime": "application/pdf", "size": 183_000]),
            msg("m4", "c1", "u2", "That one was sent by mistake", "2026-09-30T09:06:00+00:00", deleted: true),
            msg("m5", "c1", "me", "Thanks, see you soon", "2026-09-30T09:10:00+00:00", edited: true),
        ],
        "g1": [msg("g1m1", "g1", "u3", "Match on Sunday at 7?", "2026-09-30T08:00:00+00:00"), msg("g1m2", "g1", "me", "I'm in", "2026-09-30T08:05:00+00:00")],
    ]
    nonisolated(unsafe) static var notes: [[String: Any]] = [
        ["id": "n1", "kind": "SYNC_REQUEST", "title": "Imran S wants to sync", "body": "Accept to see each other's posts and Moments.", "route": "sync", "created_at": iso(-300)],
        ["id": "n2", "kind": "ORDER_NEW", "title": "New order from Meera", "body": "2 items · ₹340", "route": "orders-for/L1", "created_at": iso(-7200)],
        ["id": "n3", "kind": "REVIEW", "title": "Ravi recommended you", "body": "", "created_at": iso(-90000), "read_at": iso(-80000)],
    ]
    nonisolated(unsafe) static var blocks: [String] = ["u5"]
    nonisolated(unsafe) static var close: [String] = ["u3"]
    nonisolated(unsafe) static var settings: [String: Any]?
    nonisolated(unsafe) static var links: [[String: Any]] = [["profile_id": "u2", "phones": ["98450 12345"], "emails": [], "org": "Bala Electricals", "title": "", "address": "", "note": ""]]
    nonisolated(unsafe) static var groupTitle = "Sunday cricket"
    nonisolated(unsafe) static var extraGroups: [(id: String, title: String)] = []

    static let people: [String: (name: String, code: String, area: String)] = [
        "u2": ("Ravi Kumar", "H6VFYWYF", "Jayanagar"), "u3": ("Meera Shah", "K3PQ7NTD", "JP Nagar"), "u4": ("Imran S", "M9WX2RBC", "Koramangala"), "u5": ("Divya N", "D2CF8GHJ", "BTM Layout"),
    ]

    static func iso(_ offset: TimeInterval) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: Date().addingTimeInterval(offset)) }
    static func msg(_ id: String, _ conv: String, _ sender: String, _ body: String, _ at: String, attachment: [String: Any]? = nil, deleted: Bool = false, edited: Bool = false) -> [String: Any] {
        var m: [String: Any] = ["id": id, "conversation_id": conv, "sender_id": sender, "body": body, "created_at": at]
        if let attachment { m["attachment"] = attachment }
        if deleted { m["deleted_at"] = at }
        if edited { m["edited_at"] = at }
        return m
    }
    static func profile(_ id: String) -> [String: Any]? {
        guard let p = people[id] else { return nil }
        return ["id": id, "short_code": p.code, "name": p.name, "bio": "", "area": p.area, "trust_up": 3, "trust_down": 0, "id_issued_at": "2026-05-01T00:00:00+00:00"]
    }
    static func filter(_ query: String, _ col: String) -> String? {
        query.components(separatedBy: "&").first { $0.hasPrefix(col + "=eq.") }.map { String($0.dropFirst(col.count + 4)).removingPercentEncoding ?? "" }
    }

    static func handle(method: String, path: String, query: String, params: [String: Any]) -> (Int, Any)? {
        switch (method, path) {
        case ("POST", "/rest/v1/rpc/inbox"):
            var rows: [[String: Any]] = [
                ["conversation_id": "c1", "kind": "DIRECT", "title": "Ravi Kumar", "other_id": "u2", "other_name": "Ravi Kumar", "other_code": "H6VFYWYF", "last_body": "Thanks, see you soon", "last_at": iso(-600), "unread": 2, "muted": false, "archived": false],
                ["conversation_id": "g1", "kind": "GROUP", "title": groupTitle, "last_body": "I'm in", "last_at": iso(-3600), "unread": 0, "muted": true, "archived": false],
                ["conversation_id": "l1", "kind": "LISTING", "title": "Bala Electricals", "last_body": "We open at 9", "last_at": iso(-100_000), "unread": 0, "muted": false, "archived": false],
            ]
            for g in extraGroups { rows.append(["conversation_id": g.id, "kind": "GROUP", "title": g.title, "last_at": iso(-10), "unread": 0, "muted": false, "archived": false]) }
            return (200, rows)
        case ("POST", "/rest/v1/rpc/start_direct"): return (200, "c1")
        case ("POST", "/rest/v1/rpc/create_group"):
            let id = "g\(2 + extraGroups.count)"; extraGroups.append((id, params["p_title"] as? String ?? "Group")); return (200, id)
        case ("POST", "/rest/v1/rpc/mark_read"): return (204, [:])
        case ("POST", "/rest/v1/rpc/seen_up_to"): return (200, iso(-300))
        case ("POST", "/rest/v1/rpc/add_group_members"): return (200, (params["p_members"] as? [String])?.count ?? 0)
        case ("POST", "/rest/v1/rpc/remove_group_member"): return (204, [:])
        case ("POST", "/rest/v1/rpc/request_sync"): return (200, "PENDING")
        case ("POST", "/rest/v1/rpc/suggest_people"):
            return (200, [["id": "u4", "name": "Imran S", "short_code": "M9WX2RBC", "area": "Koramangala", "mutual": 2, "distance_m": 1800.0],
                          ["id": "u5", "name": "Divya N", "short_code": "D2CF8GHJ", "area": "BTM Layout", "mutual": 0, "distance_m": 3200.0]])
        case ("POST", "/rest/v1/rpc/mark_notifications_read"):
            let ids = params["p_ids"] as? [String]
            notes = notes.map { var n = $0; if ids == nil || ids!.contains(n["id"] as? String ?? "") { n["read_at"] = iso(0) }; return n }
            return (200, 1)
        case ("GET", "/rest/v1/notifications"): return (200, notes)
        case ("DELETE", "/rest/v1/notifications"): if let id = filter(query, "id") { notes.removeAll { $0["id"] as? String == id } }; return (204, [:])
        case ("GET", "/rest/v1/messages"):
            let conv = filter(query, "conversation_id") ?? "c1"
            return (200, Array((messages[conv] ?? []).reversed()))
        case ("POST", "/rest/v1/messages"):
            let conv = params["conversation_id"] as? String ?? "c1"
            var row = msg("m\(Int.random(in: 100...99999))", conv, "me", params["body"] as? String ?? "", iso(0))
            if let a = params["attachment"] { row["attachment"] = a }
            messages[conv, default: []].append(row)
            return (201, [row])
        case ("PATCH", "/rest/v1/messages"):
            if let id = filter(query, "id") {
                for (c, rows) in messages { messages[c] = rows.map { var r = $0; if r["id"] as? String == id { for (k, v) in params { r[k] = v }; if params["body"] != nil { r["edited_at"] = iso(0) } }; return r } }
            }
            return (204, [:])
        case ("GET", "/rest/v1/conversations"):
            let id = filter(query, "id") ?? "c1"
            switch id {
            case "g1": return (200, [["id": "g1", "kind": "GROUP", "title": groupTitle, "created_by": "me", "last_message_at": iso(0), "created_at": iso(-9000)]])
            case "l1": return (200, [["id": "l1", "kind": "LISTING", "title": "Bala Electricals", "listing_id": "L1", "created_by": "u2", "last_message_at": iso(0), "created_at": iso(-9000)]])
            default: return (200, [["id": id, "kind": id.hasPrefix("g") ? "GROUP" : "DIRECT", "title": extraGroups.first { $0.id == id }?.title as Any, "created_by": "me", "last_message_at": iso(0), "created_at": iso(-9000)]])
            }
        case ("PATCH", "/rest/v1/conversations"): if let t = params["title"] as? String { groupTitle = t }; return (204, [:])
        case ("GET", "/rest/v1/conversation_members"):
            let conv = filter(query, "conversation_id") ?? "g1"
            let ids = conv == "l1" ? ["me", "u2"] : ["me", "u3", "u4"]
            return (200, ids.enumerated().map { ["conversation_id": conv, "profile_id": $1, "role": $0 == 0 || (conv == "l1" && $1 == "u2") ? "ADMIN" : "MEMBER", "last_read_at": iso(-100)] })
        case ("PATCH", "/rest/v1/conversation_members"), ("DELETE", "/rest/v1/conversation_members"): return (204, [:])
        case ("GET", "/rest/v1/syncs"):
            return (200, [["requester_id": "u4", "addressee_id": "me", "status": "PENDING"], ["requester_id": "me", "addressee_id": "u2", "status": "ACCEPTED"], ["requester_id": "u3", "addressee_id": "me", "status": "ACCEPTED"]])
        case ("PATCH", "/rest/v1/syncs"), ("DELETE", "/rest/v1/syncs"): return (204, [:])
        case (_, "/rest/v1/profiles") where method == "GET":
            if let code = filter(query, "short_code") { return (200, people.keys.compactMap { profile($0) }.filter { $0["short_code"] as? String == code }) }
            if let r = query.range(of: "id=in.("), let end = query[r.upperBound...].firstIndex(of: ")") {
                let ids = query[r.upperBound..<end].split(separator: ",").map(String.init)
                let rows = ids.compactMap { profile($0) }
                if !rows.isEmpty { return (200, rows) }
            }
            return nil
        case ("GET", "/rest/v1/blocks"): return (200, blocks.map { ["blocker_id": "me", "blocked_id": $0] })
        case ("POST", "/rest/v1/blocks"): if let o = params["blocked_id"] as? String { blocks.append(o) }; return (201, [:])
        case ("DELETE", "/rest/v1/blocks"): if let o = filter(query, "blocked_id") { blocks.removeAll { $0 == o } }; return (204, [:])
        case ("GET", "/rest/v1/close_friends"): return (200, close.map { ["profile_id": "me", "friend_id": $0] })
        case ("POST", "/rest/v1/close_friends"): if let f = params["friend_id"] as? String, !close.contains(f) { close.append(f) }; return (201, [:])
        case ("DELETE", "/rest/v1/close_friends"): if let f = filter(query, "friend_id") { close.removeAll { $0 == f } }; return (204, [:])
        case ("GET", "/rest/v1/user_settings"): return (200, settings.map { [$0] } ?? [])
        case ("POST", "/rest/v1/user_settings"): settings = params; return (201, [:])
        case ("GET", "/rest/v1/contact_links"): return (200, links)
        case ("POST", "/rest/v1/contact_links"): links.append(params); return (201, [:])
        case ("PATCH", "/rest/v1/contact_links"): return (204, [:])
        case ("DELETE", "/rest/v1/contact_links"): if let p = filter(query, "profile_id") { links.removeAll { $0["profile_id"] as? String == p } }; return (204, [:])
        default: return nil
        }
    }
}

let fakeChat: (String, String, String, [String: Any]) -> (Int, Any)? = { FakeChat.handle(method: $0, path: $1, query: $2, params: $3) }
#endif
