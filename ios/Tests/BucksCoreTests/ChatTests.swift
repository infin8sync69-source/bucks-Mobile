import Foundation
import Testing
@testable import BucksCore

/// What the chat, sync, block, settings, notification and contact-link calls put on the wire, written against supabase/schema.sql,
/// migrations/{social-extras,notifications,contact_links}.sql and the Kotlin calls in Backend.kt / BackendSocialExtras.kt / BackendStudio.kt.
extension DispatchTests {
    private func calls(_ path: String) -> [(method: String, path: String, query: String, body: [String: Any])] { FakeServer.calls.filter { $0.path == path } }

    @Test func messagingCallsUseTheServersNames() async throws {
        boot { path, query, params in
            switch path {
            case "/rest/v1/rpc/inbox": return (200, [["conversation_id": "c1", "kind": "DIRECT", "title": "Ravi", "other_id": "u2", "last_body": "hi", "last_at": "2026-09-30T10:00:00+00:00", "unread": 2, "muted": false, "archived": false]])
            case "/rest/v1/rpc/start_direct": return (200, "c1")
            case "/rest/v1/rpc/create_group": return (200, "g1")
            case "/rest/v1/messages":
                if !params.isEmpty { return (201, [["id": "m1", "conversation_id": "c1", "sender_id": "me", "body": params["body"] ?? "", "created_at": "2026-09-30T10:00:00+00:00"]]) }
                return (200, [["id": "m2", "conversation_id": "c1", "sender_id": "u2", "body": "later", "created_at": "2026-09-30T10:01:00+00:00"],
                              ["id": "m1", "conversation_id": "c1", "sender_id": "me", "body": "first", "created_at": "2026-09-30T10:00:00+00:00"]])
            case "/rest/v1/rpc/mark_read": return (204, [:])
            case "/rest/v1/rpc/seen_up_to": return (200, "2026-09-30T10:02:00+00:00")
            case "/rest/v1/conversation_members": return (204, [:])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let b = Backend.shared
        let inbox = try await b.inbox()
        #expect(inbox.first?.conversationId == "c1"); #expect(inbox.first?.unread == 2)
        #expect(try await b.startDirect("u2") == "c1")
        #expect(calls("/rest/v1/rpc/start_direct").first?.body as NSDictionary? == ["p_other": "u2"] as NSDictionary)
        #expect(try await b.createGroup(title: "Cricket", members: ["u2", "u3"]) == "g1")
        let g = try #require(calls("/rest/v1/rpc/create_group").first)
        #expect(g.body["p_title"] as? String == "Cricket"); #expect(g.body["p_members"] as? [String] == ["u2", "u3"])

        // The latest 50, newest first from the server, shown oldest first.
        let msgs = try await b.messages("c1")
        #expect(msgs.map(\.id) == ["m1", "m2"])
        let list = try #require(calls("/rest/v1/messages").first)
        #expect(list.query.contains("conversation_id=eq.c1")); #expect(list.query.contains("order=created_at.desc")); #expect(list.query.contains("limit=50"))

        let sent = try await b.send("c1", me: "me", body: "hello", attachment: FileRef(path: "c1/a.jpg", name: "a.jpg", mime: "image/jpeg", size: 1234))
        #expect(sent.id == "m1")
        let post = try #require(calls("/rest/v1/messages").last)
        #expect(post.method == "POST"); #expect(Set(post.body.keys) == ["conversation_id", "sender_id", "body", "attachment"])
        let att = try #require(post.body["attachment"] as? [String: Any])
        #expect(att["path"] as? String == "c1/a.jpg"); #expect(att["name"] as? String == "a.jpg"); #expect(att["mime"] as? String == "image/jpeg"); #expect(att["size"] as? Int == 1234)
        #expect(FakeServer.prefer["POST /rest/v1/messages"]?.contains("return=representation") == true)

        try await b.markRead("c1")
        #expect(calls("/rest/v1/rpc/mark_read").first?.body as NSDictionary? == ["p_conv": "c1"] as NSDictionary)
        #expect(try await b.seenUpTo("c1") == "2026-09-30T10:02:00+00:00")

        try await b.mute("c1", me: "me", untilIso: "2999-01-01T00:00:00Z")
        let mute = try #require(calls("/rest/v1/conversation_members").last)
        #expect(mute.method == "PATCH"); #expect(mute.body["muted_until"] as? String == "2999-01-01T00:00:00Z")
        #expect(mute.query.contains("conversation_id=eq.c1")); #expect(mute.query.contains("profile_id=eq.me"))
        try await b.mute("c1", me: "me", untilIso: nil)
        #expect(calls("/rest/v1/conversation_members").last?.body["muted_until"] is NSNull)   // unmute sends JSON null
    }

    @Test func seenUpToIsNilWhenNobodyHasRead() async throws {
        boot { path, _, _ -> (Int, Any) in if path == "/rest/v1/rpc/seen_up_to" { return (200, NSNull()) }; return (404, ["message": "no stub"]) }
        #expect(try await Backend.shared.seenUpTo("c1") == nil)
    }

    @Test func editAndDeleteAreUpdatesNotDeletes() async throws {
        boot { path, _, _ -> (Int, Any) in if path == "/rest/v1/messages" { return (204, [String: Any]()) }; return (404, ["message": "no stub"]) }
        try await Backend.shared.editMessage("m1", body: "fixed")
        let e = try #require(calls("/rest/v1/messages").first)
        #expect(e.method == "PATCH"); #expect(e.query.contains("id=eq.m1")); #expect(e.body["body"] as? String == "fixed")
        try await Backend.shared.deleteMessage("m1")
        let d = try #require(calls("/rest/v1/messages").last)
        #expect(d.method == "PATCH"); #expect(Set(d.body.keys) == ["deleted_at"]); #expect((d.body["deleted_at"] as? String)?.hasPrefix("20") == true)
    }

    @Test func groupCallsUseTheSocialExtrasNames() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/add_group_members": return (200, 2)
            case "/rest/v1/rpc/remove_group_member": return (204, [:])
            case "/rest/v1/conversations": return (200, [["id": "g1", "kind": "GROUP", "title": "Cricket", "created_by": "me", "last_message_at": "2026-09-30T10:00:00+00:00", "created_at": "2026-09-30T10:00:00+00:00"]])
            case "/rest/v1/conversation_members": return (200, [["conversation_id": "g1", "profile_id": "me", "role": "ADMIN", "last_read_at": "2026-09-30T10:00:00+00:00"]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let b = Backend.shared
        #expect(try await b.addGroupMembers("g1", members: ["u2", "u3"]) == 2)
        let add = try #require(calls("/rest/v1/rpc/add_group_members").first)
        #expect(Set(add.body.keys) == ["p_conv", "p_members"]); #expect(add.body["p_members"] as? [String] == ["u2", "u3"])
        try await b.removeGroupMember("g1", member: "u2")
        #expect(calls("/rest/v1/rpc/remove_group_member").first?.body as NSDictionary? == ["p_conv": "g1", "p_member": "u2"] as NSDictionary)
        let conv = try #require(try await b.conversation("g1"))
        #expect(conv.kind == "GROUP"); #expect(conv.title == "Cricket"); #expect(conv.listingId == nil)
        let members = try await b.conversationMembers("g1")
        #expect(members.first?.role == "ADMIN")
        #expect(calls("/rest/v1/conversation_members").first?.query.contains("order=role.asc") == true)

        try await b.renameGroup("g1", title: "Sunday cricket")
        let r = try #require(calls("/rest/v1/conversations").last)
        #expect(r.method == "PATCH"); #expect(r.body as NSDictionary == ["title": "Sunday cricket"] as NSDictionary); #expect(r.query.contains("id=eq.g1"))
        try await b.leaveConversation("g1", me: "me")
        let leave = try #require(calls("/rest/v1/conversation_members").last)
        #expect(leave.method == "DELETE"); #expect(leave.query.contains("conversation_id=eq.g1")); #expect(leave.query.contains("profile_id=eq.me"))
    }

    @Test func syncBlockAndCloseFriendCalls() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/rpc/request_sync": return (200, "PENDING")
            case "/rest/v1/syncs": return (200, [["requester_id": "u2", "addressee_id": "me", "status": "PENDING"]])
            case "/rest/v1/profiles": return (200, [["id": "u2", "short_code": "H6VFYWYF", "name": "Ravi", "id_issued_at": "2026-01-02T00:00:00+00:00"]])
            case "/rest/v1/blocks", "/rest/v1/close_friends", "/rest/v1/user_settings": return (200, [])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let b = Backend.shared
        #expect(try await b.sync("u2") == "PENDING")
        #expect(calls("/rest/v1/rpc/request_sync").first?.body as NSDictionary? == ["p_other": "u2"] as NSDictionary)
        #expect(try await b.mySyncs().first?.requesterId == "u2")
        try await b.acceptSync(requester: "u2", me: "me")
        let acc = try #require(calls("/rest/v1/syncs").last)
        #expect(acc.method == "PATCH"); #expect(acc.body as NSDictionary == ["status": "ACCEPTED"] as NSDictionary)
        #expect(acc.query.contains("requester_id=eq.u2")); #expect(acc.query.contains("addressee_id=eq.me"))
        try await b.unsync(me: "me", other: "u2")
        let un = try #require(calls("/rest/v1/syncs").last)
        #expect(un.method == "DELETE")
        // Either direction: me asked them, or they asked me.
        let q = un.query.removingPercentEncoding ?? un.query
        #expect(q.contains("or=(and(requester_id.eq.me,addressee_id.eq.u2),and(requester_id.eq.u2,addressee_id.eq.me))"))

        // A typed Bucks ID is looked up upper-case, through the readable columns only.
        let p = try await b.profileByCode(" h6vfywyf ")
        #expect(p?.name == "Ravi")
        let look = try #require(calls("/rest/v1/profiles").first)
        #expect(look.query.contains("short_code=eq.H6VFYWYF")); #expect(!look.query.contains("select=*"))

        try await b.block(me: "me", other: "u2")
        let blk = try #require(calls("/rest/v1/blocks").last)
        #expect(blk.method == "POST"); #expect(blk.body as NSDictionary == ["blocker_id": "me", "blocked_id": "u2"] as NSDictionary)
        try await b.unblock(me: "me", other: "u2")
        #expect(calls("/rest/v1/blocks").last?.method == "DELETE")

        try await b.setCloseFriend(me: "me", friend: "u2", on: true)
        let on = try #require(calls("/rest/v1/close_friends").last)
        #expect(on.method == "POST"); #expect(FakeServer.prefer["POST /rest/v1/close_friends"]?.contains("resolution=merge-duplicates") == true)
        #expect(on.body as NSDictionary == ["profile_id": "me", "friend_id": "u2"] as NSDictionary)
        try await b.setCloseFriend(me: "me", friend: "u2", on: false)
        #expect(calls("/rest/v1/close_friends").last?.method == "DELETE")
    }

    @Test func settingsRoundTripAndDefaults() async throws {
        boot { path, _, _ -> (Int, Any) in if path == "/rest/v1/user_settings" { return (200, [Any]()) }; return (404, ["message": "no stub"]) }
        // No row yet: the defaults.
        let d = try await Backend.shared.mySettings(me: "me")
        #expect(d.whoCanMessage == "SYNCED"); #expect(d.whoCanSync == "EVERYONE"); #expect(d.momentsAudience == "SYNCED"); #expect(d.readReceipts); #expect(d.discoverable)
        var row = d; row.whoCanMessage = "NOBODY"; row.notify = .object(["offers": .bool(true)]); row.quietHours = .object(["from": .string("22:00"), "to": .string("07:00")])
        try await Backend.shared.saveSettings(row)
        let save = try #require(calls("/rest/v1/user_settings").last)
        #expect(save.method == "POST"); #expect(FakeServer.prefer["POST /rest/v1/user_settings"]?.contains("resolution=merge-duplicates") == true)
        #expect(Set(save.body.keys) == ["profile_id", "who_can_message", "who_can_sync", "moments_audience", "read_receipts", "show_online", "discoverable", "notify", "quiet_hours", "app"])
        #expect(save.body["who_can_message"] as? String == "NOBODY")
        #expect((save.body["quiet_hours"] as? [String: Any])?["from"] as? String == "22:00")
        #expect((save.body["notify"] as? [String: Any])?["offers"] as? Bool == true)
    }

    @Test func notificationCalls() async throws {
        boot { path, _, _ in
            switch path {
            case "/rest/v1/notifications": return (200, [["id": "n1", "kind": "SYNC_REQUEST", "title": "Ravi wants to sync", "created_at": "2026-09-30T10:00:00+00:00"]])
            case "/rest/v1/rpc/mark_notifications_read": return (200, 1)
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let b = Backend.shared
        let n = try await b.notifications()
        #expect(n.first?.id == "n1"); #expect(n.first?.readAt == nil)
        let list = try #require(calls("/rest/v1/notifications").first)
        #expect(list.query.contains("order=created_at.desc")); #expect(list.query.contains("limit=60"))
        try await b.markNotificationsRead(["n1"])
        #expect(calls("/rest/v1/rpc/mark_notifications_read").last?.body["p_ids"] as? [String] == ["n1"])
        try await b.markNotificationsRead()
        #expect(calls("/rest/v1/rpc/mark_notifications_read").last?.body.isEmpty == true)   // no p_ids = mark every one
        try await b.deleteNotification("n1")
        let del = try #require(calls("/rest/v1/notifications").last)
        #expect(del.method == "DELETE"); #expect(del.query.contains("id=eq.n1"))
    }

    @Test func contactLinksInsertThenEditColumnByColumn() async throws {
        boot { path, _, _ -> (Int, Any) in
            if path == "/rest/v1/contact_links" { return (200, [["profile_id": "u2", "phones": ["98450 12345"], "emails": [String](), "org": "Bala", "title": "", "address": "", "note": ""] as [String: Any]]) }
            return (404, ["message": "no stub"])
        }
        let link = ContactLinkRow(profileId: "u2", phones: ["98450 12345"], emails: ["a@b.in"], org: "Bala", title: "Owner", address: "JP Nagar", note: "met")
        try await Backend.shared.insertContactLink(me: "me", link)
        let ins = try #require(calls("/rest/v1/contact_links").last)
        #expect(ins.method == "POST"); #expect(Set(ins.body.keys) == ["owner_id", "profile_id", "phones", "emails", "org", "title", "address", "note"])
        #expect(ins.body["owner_id"] as? String == "me"); #expect(ins.body["phones"] as? [String] == ["98450 12345"])
        try await Backend.shared.updateContactLink(link)
        let up = try #require(calls("/rest/v1/contact_links").last)
        #expect(up.method == "PATCH"); #expect(up.query.contains("profile_id=eq.u2"))
        #expect(Set(up.body.keys) == ["phones", "emails", "org", "title", "address", "note"])   // who it is about can't change
        let all = try await Backend.shared.contactLinks()
        #expect(all.first?.phones == ["98450 12345"]); #expect(all.first?.isEmpty == false)
        try await Backend.shared.deleteContactLink("u2")
        #expect(calls("/rest/v1/contact_links").last?.method == "DELETE")
        #expect(ContactLinkRow(profileId: "u2", note: "  ").isEmpty)
    }

    @Test func phoneContactHelpers() {
        #expect(PhoneContacts.dialable("98450 12345") == "+919845012345")
        #expect(PhoneContacts.dialable("919845012345") == "+919845012345")
        #expect(PhoneContacts.dialable("+44 7700 900123") == "+447700900123")
        #expect(PhoneContacts.dialable("112") == "112")
        #expect(PhoneContacts.tail10("+91 98450-12345") == "9845012345")
        #expect(PhoneContacts.nameScore("Ravi Kumar", "Ravi K") == 1)   // "ravi" matches, "kumar" doesn't
        #expect(PhoneContacts.splitList("9845012345, 080 2222 3333;\n9845012345") == ["9845012345", "080 2222 3333"])
        let c = PhoneContact(id: "1", name: "Asha Rao", phones: ["98450 12345"], emails: ["asha@x.in"], org: "Bala Electricals")
        #expect(c.initials == "AR"); #expect(PhoneContact(id: "2", name: "").initials == "#")
        #expect(c.matches("bala")); #expect(c.matches("845")); #expect(!c.matches("zzz")); #expect(c.matches("  "))
        #expect(!c.matches("99"))   // two digits only match as text, never as part of a number
    }

    @Test func idCardExpiryBlocksSyncByCode() {
        // A card lapses a year after issue.
        let old = BucksIdCardInfo.of("2024-01-02T00:00:00+00:00", today: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(old?.expired == true)
        #expect(BucksIdCardInfo.of(nil) == nil)
    }

    // MARK: the state holders

    private func session() -> (AppSession, () -> [String]) {
        let s = AppSession(); s.me = ProfileRow(id: "me", shortCode: "ME0001", name: "Asha Rao")
        var toasts: [String] = []
        s.toastHandler = { toasts.append($0) }
        return (s, { toasts })
    }

    @Test func addingToAGroupTellsTheSheetWhenItFails() async throws {
        boot { path, _, _ -> (Int, Any) in path == "/rest/v1/rpc/add_group_members" ? (400, ["message": "not a member"]) : (404, ["message": "no stub"]) }
        let (s, toasts) = session()
        var failed = false, done = false
        s.chat.addToGroup("g1", members: ["u2"], then: { done = true }, onFailed: { failed = true })
        for _ in 0..<50 where !failed { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(failed); #expect(!done); #expect(toasts() == ["Not a member"])
    }

    @Test func syncByCodeRefusesYourOwnAndLapsedIds() async throws {
        boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/profiles":
                return (200, [["id": "u2", "short_code": "H6VFYWYF", "name": "Ravi", "id_issued_at": "2020-01-02T00:00:00+00:00"] as [String: Any]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, toasts) = session()
        s.social.syncWithCode("h6vfywyf")
        #expect(await wait { !toasts().isEmpty })
        #expect(toasts().first?.hasPrefix("Ravi's Bucks ID expired on 2 Jan 2021.") == true)
        #expect(calls("/rest/v1/rpc/request_sync").isEmpty)   // never asked the server to sync
    }

    @Test func creatingAGroupTrimsTheNameAndRefreshesTheInbox() async throws {
        boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/rpc/create_group": return (200, "g1")
            case "/rest/v1/rpc/inbox": return (200, [Any]())
            case "/rest/v1/notifications": return (200, [Any]())
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, toasts) = session()
        let id = await s.chat.createGroup(title: "  Cricket  ", members: ["u2"])
        #expect(id == "g1"); #expect(toasts() == ["Group created."])
        #expect(calls("/rest/v1/rpc/create_group").first?.body["p_title"] as? String == "Cricket")
        #expect(!calls("/rest/v1/rpc/inbox").isEmpty)
    }

    @Test func theBadgeCountsUnreadChatsPlusUnreadNotifications() async throws {
        boot { path, _, _ -> (Int, Any) in
            switch path {
            case "/rest/v1/rpc/inbox": return (200, [["conversation_id": "c1", "kind": "DIRECT", "last_at": "2026-09-30T10:00:00+00:00", "unread": 2] as [String: Any],
                                                     ["conversation_id": "c2", "kind": "GROUP", "last_at": "2026-09-30T10:00:00+00:00", "unread": 1] as [String: Any]])
            case "/rest/v1/notifications": return (200, [["id": "n1", "kind": "REVIEW", "title": "New review"] as [String: Any], ["id": "n2", "kind": "REVIEW", "title": "Old", "read_at": "2026-09-30T10:00:00+00:00"] as [String: Any]])
            default: return (404, ["message": "no stub for \(path)"])
            }
        }
        let (s, _) = session()
        await s.chat.refreshInboxNow()
        #expect(s.chat.notesUnread == 1)
        #expect(s.chat.inbox.reduce(0) { $0 + $1.unread } == 3)
        s.chat.markNoteRead("n1")
        #expect(s.chat.notesUnread == 0)
    }
}
