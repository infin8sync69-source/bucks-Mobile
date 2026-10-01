import Foundation

// Messaging, groups, sync, blocking, settings, notifications and contact links: a straight port of the matching parts of
// Backend.kt, BackendSocialExtras.kt and BackendStudio.kt. RPC names and `p_` parameters follow supabase/schema.sql and
// supabase/migrations/{social-extras,notifications,contact_links}.sql.

private extension KeyedDecodingContainer {
    func str(_ k: Key, _ d: String = "") -> String { (try? decodeIfPresent(String.self, forKey: k)) ?? d }
    func opt(_ k: Key) -> String? { (try? decodeIfPresent(String.self, forKey: k)) ?? nil }
    func list(_ k: Key) -> [String] { (try? decodeIfPresent([String].self, forKey: k)) ?? [] }
}

/// The conversation itself: kind (DIRECT / GROUP / LISTING), title and listing id.
public struct ConversationRow: Codable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var title: String?
    public var listingId: String?
    public var createdBy: String
    public var lastMessageAt: String
    public var createdAt: String
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id); kind = c.str(.kind, "DIRECT"); title = c.opt(.title); listingId = c.opt(.listingId)
        createdBy = c.str(.createdBy); lastMessageAt = c.str(.lastMessageAt); createdAt = c.str(.createdAt)
    }
    private enum K: String, CodingKey { case id, kind, title, listingId, createdBy, lastMessageAt, createdAt }
}

public struct ConversationMemberRow: Codable, Hashable, Sendable {
    public var conversationId: String
    public var profileId: String
    public var role: String
    public var lastReadAt: String
    public var mutedUntil: String?
    public var archived: Bool
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        conversationId = c.str(.conversationId); profileId = try c.decode(String.self, forKey: .profileId); role = c.str(.role, "MEMBER")
        lastReadAt = c.str(.lastReadAt); mutedUntil = c.opt(.mutedUntil); archived = (try? c.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
    }
    private enum K: String, CodingKey { case conversationId, profileId, role, lastReadAt, mutedUntil, archived }
}

/// Contact details I attached to a person I'm synced with (private to me; contact_links.sql).
public struct ContactLinkRow: Codable, Hashable, Sendable {
    public var profileId: String
    public var phones: [String]
    public var emails: [String]
    public var org: String
    public var title: String
    public var address: String
    public var note: String
    public init(profileId: String, phones: [String] = [], emails: [String] = [], org: String = "", title: String = "", address: String = "", note: String = "") {
        self.profileId = profileId; self.phones = phones; self.emails = emails; self.org = org; self.title = title; self.address = address; self.note = note
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        profileId = try c.decode(String.self, forKey: .profileId); phones = c.list(.phones); emails = c.list(.emails)
        org = c.str(.org); title = c.str(.title); address = c.str(.address); note = c.str(.note)
    }
    private enum K: String, CodingKey { case profileId, phones, emails, org, title, address, note }
    public var isEmpty: Bool { phones.isEmpty && emails.isEmpty && org.isBlankText && title.isBlankText && address.isBlankText && note.isBlankText }
}

private extension String { var isBlankText: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

extension Backend {
    /// Decodes a Realtime row (`RealtimeChange.record`) the way every other read is decoded.
    public func decodeRecord<T: Decodable>(_ type: T.Type, from data: Data) -> T? { try? Self.decoder.decode(T.self, from: data) }

    // MARK: people and sync

    /// Someone by their Bucks ID (8 characters); nil when nobody has it.
    public func profileByCode(_ code: String) async throws -> ProfileRow? {
        try await selectOne("profiles", columns: "id,short_code,name,bio,area,photo_url,trust_up,trust_down,id_issued_at", filters: [.eq("short_code", code.trimmingCharacters(in: .whitespaces).uppercased())])
    }
    public func mySyncs() async throws -> [SyncRow] { try await select("syncs") }
    /// Returns PENDING, or ACCEPTED when they had already asked to sync with me.
    public func sync(_ other: String) async throws -> String { try await rpc("request_sync", ["p_other": other]) }
    public func acceptSync(requester: String, me: String) async throws {
        try await update("syncs", ["status": "ACCEPTED"], filters: [.eq("requester_id", requester), .eq("addressee_id", me)])
    }
    /// Removes the sync in either direction (also how a request is ignored).
    public func unsync(me: String, other: String) async throws {
        try await delete("syncs", filters: [.raw("or", "(and(requester_id.eq.\(me),addressee_id.eq.\(other)),and(requester_id.eq.\(other),addressee_id.eq.\(me)))")])
    }
    public func suggestPeople(_ at: LatLng) async throws -> [PersonSuggestion] { try await rpcList("suggest_people", ["lat": at.lat, "lng": at.lng]) }

    // MARK: blocking, close friends

    public func block(me: String, other: String) async throws { try await insertVoid("blocks", ["blocker_id": me, "blocked_id": other]) }
    public func unblock(me: String, other: String) async throws { try await delete("blocks", filters: [.eq("blocker_id", me), .eq("blocked_id", other)]) }
    public func blocked() async throws -> [BlockRow] { try await select("blocks") }
    public func closeFriends() async throws -> [String] { (try await select("close_friends") as [CloseFriendRow]).map(\.friendId) }
    public func setCloseFriend(me: String, friend: String, on: Bool) async throws {
        if on { try await upsert("close_friends", ["profile_id": me, "friend_id": friend]) }
        else { try await delete("close_friends", filters: [.eq("profile_id", me), .eq("friend_id", friend)]) }
    }

    // MARK: settings

    public func mySettings(me: String) async throws -> SettingsRow {
        (try await selectOne("user_settings", filters: [.eq("profile_id", me)])) ?? SettingsRow(profileId: me)
    }
    public func saveSettings(_ row: SettingsRow) async throws { try await upsert("user_settings", row.body) }

    // MARK: inbox and messages

    public func inbox() async throws -> [InboxRow] { try await rpcList("inbox") }
    public func startDirect(_ other: String) async throws -> String { try await rpc("start_direct", ["p_other": other]) }
    public func createGroup(title: String, members: [String]) async throws -> String { try await rpc("create_group", ["p_title": title, "p_members": members]) }
    /// The latest `limit` messages, oldest first.
    public func messages(_ conversationId: String, limit: Int = 50) async throws -> [MessageRow] {
        let rows: [MessageRow] = try await select("messages", filters: [.eq("conversation_id", conversationId)], order: "created_at", ascending: false, limit: limit)
        return rows.reversed()
    }
    public func send(_ conversationId: String, me: String, body: String, attachment: FileRef? = nil, replyTo: String? = nil) async throws -> MessageRow {
        var row: [String: Any?] = ["conversation_id": conversationId, "sender_id": me, "body": body]
        if let replyTo { row["reply_to"] = replyTo }
        if let a = attachment { row["attachment"] = ["path": a.path, "name": a.name, "mime": a.mime, "size": a.size] as [String: Any] }
        return try await insert("messages", row)
    }
    public func editMessage(_ id: String, body: String) async throws { try await update("messages", ["body": body], filters: [.eq("id", id)]) }
    public func deleteMessage(_ id: String) async throws {
        try await update("messages", ["deleted_at": ISO8601DateFormatter().string(from: Date())], filters: [.eq("id", id)])
    }
    public func markRead(_ conversationId: String) async throws { try await rpcVoid("mark_read", ["p_conv": conversationId]) }
    /// When the other side last read this conversation; nil when read receipts are off or nobody has read it.
    public func seenUpTo(_ conversationId: String) async throws -> String? {
        let v: JSONValue = try await rpc("seen_up_to", ["p_conv": conversationId])
        guard let s = v.string?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "null" else { return nil }
        return s
    }
    public func mute(_ conversationId: String, me: String, untilIso: String?) async throws {
        try await update("conversation_members", ["muted_until": untilIso], filters: [.eq("conversation_id", conversationId), .eq("profile_id", me)])
    }

    // MARK: groups and listing chats (BackendSocialExtras.kt)

    /// The conversation's own row; nil when I'm not a member.
    public func conversation(_ id: String) async throws -> ConversationRow? { try await selectOne("conversations", filters: [.eq("id", id)]) }
    /// Everyone in a conversation, admins first.
    public func conversationMembers(_ conversationId: String) async throws -> [ConversationMemberRow] {
        try await select("conversation_members", filters: [.eq("conversation_id", conversationId)], order: "role", ascending: true)
    }
    /// Leaving = deleting my own membership row; the chat disappears from my inbox.
    public func leaveConversation(_ conversationId: String, me: String) async throws {
        try await delete("conversation_members", filters: [.eq("conversation_id", conversationId), .eq("profile_id", me)])
    }
    /// Any member may rename a GROUP (policy conv_rename).
    public func renameGroup(_ conversationId: String, title: String) async throws { try await update("conversations", ["title": title], filters: [.eq("id", conversationId)]) }
    /// Adds synced, unblocked people to a group I'm in. Returns how many were actually added.
    public func addGroupMembers(_ conversationId: String, members: [String]) async throws -> Int { try await rpc("add_group_members", ["p_conv": conversationId, "p_members": members]) }
    public func removeGroupMember(_ conversationId: String, member: String) async throws { try await rpcVoid("remove_group_member", ["p_conv": conversationId, "p_member": member]) }

    // MARK: notifications

    /// My latest notifications, newest first.
    public func notifications(limit: Int = 60) async throws -> [NotificationRow] { try await select("notifications", order: "created_at", ascending: false, limit: limit) }
    /// Marks the given notifications (or every one when `ids` is nil) read.
    public func markNotificationsRead(_ ids: [String]? = nil) async throws {
        try await rpcVoid("mark_notifications_read", ids.map { ["p_ids": $0] } ?? [:])
    }
    public func deleteNotification(_ id: String) async throws { try await delete("notifications", filters: [.eq("id", id)]) }

    // MARK: contact details I attach to people I'm synced with

    public func contactLinks() async throws -> [ContactLinkRow] { try await select("contact_links") }
    public func insertContactLink(me: String, _ l: ContactLinkRow) async throws {
        try await insertVoid("contact_links", ["owner_id": me, "profile_id": l.profileId, "phones": l.phones, "emails": l.emails, "org": l.org, "title": l.title, "address": l.address, "note": l.note])
    }
    /// Edits an existing link column by column (who it is about can't change, so an upsert of every column would be refused).
    public func updateContactLink(_ l: ContactLinkRow) async throws {
        try await update("contact_links", ["phones": l.phones, "emails": l.emails, "org": l.org, "title": l.title, "address": l.address, "note": l.note], filters: [.eq("profile_id", l.profileId)])
    }
    public func deleteContactLink(_ profileId: String) async throws { try await delete("contact_links", filters: [.eq("profile_id", profileId)]) }
}
