import Foundation
import Observation

/// Port of the Android `Social` inbox and chat half: the inbox, the Notifications tab, messages, attachments, read receipts,
/// muting, groups and listing chats. Every action reports a failure as a toast.
@MainActor @Observable
public final class ChatStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    public private(set) var inbox: [InboxRow] = []
    /// Notifications (Messages screen, second tab): what needs my attention besides chat.
    public private(set) var notes: [NotificationRow] = []
    /// True while a photo or file is uploading.
    public private(set) var uploading = false

    public var notesUnread: Int { notes.filter { $0.readAt == nil }.count }
    /// The badge on the messages icon: unread chats plus unread notifications. Reading it starts the background refresh (see `supervise`).
    public var unread: Int { superviseOnce(); return inbox.reduce(0) { $0 + $1.unread } + notesUnread }

    private var me: ProfileRow? { session.me }
    @ObservationIgnored private var supervisor: Task<Void, Never>?

    // MARK: lifecycle

    /// Keeps the badge fresh while the app is open: loads everything once a profile exists, then one small check every minute
    /// (like the poller `Social.signedIn` starts on Android). Starts itself the first time `unread` is read; clears on sign-out.
    private func superviseOnce() {
        guard supervisor == nil else { return }
        supervisor = Task { @MainActor [weak self] in
            var signedInAs: String?
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                if let id = self.session.me?.id {
                    if signedInAs != id { signedInAs = id; tick = 0; self.session.social.signedIn(); await self.refreshInboxNow() }
                    else if tick % 30 == 0 { self.inbox = (try? await Backend.shared.inbox()) ?? self.inbox; self.notes = (try? await Backend.shared.notifications()) ?? self.notes }
                    tick += 1
                } else if signedInAs != nil { signedInAs = nil; self.signedOut(); self.session.social.signedOut() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    public func signedOut() { inbox = []; notes = [] }

    @discardableResult
    private func go(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
        }
    }

    // MARK: inbox and notifications

    public func refreshInbox() { go { await self.refreshInboxNow() } }
    func refreshInboxNow() async {
        do { inbox = try await Backend.shared.inbox() } catch is CancellationError { return } catch { session.toast(friendlyError(error)); return }
        if let n = try? await Backend.shared.notifications() { notes = n }
    }
    public func markNoteRead(_ id: String) {
        notes = notes.map { var n = $0; if n.id == id, n.readAt == nil { n.readAt = "now" }; return n }
        Task { try? await Backend.shared.markNotificationsRead([id]) }
    }
    public func markAllNotesRead() {
        notes = notes.map { var n = $0; if n.readAt == nil { n.readAt = "now" }; return n }
        go { try await Backend.shared.markNotificationsRead() }
    }
    public func deleteNote(_ id: String) { notes.removeAll { $0.id == id }; go { try await Backend.shared.deleteNotification(id) } }

    // MARK: chat

    /// Opens (or creates) the direct chat with `other`; nil after a failure (already toasted).
    public func openDirect(_ other: String) async -> String? {
        do { return try await Backend.shared.startDirect(other) } catch is CancellationError { return nil } catch { session.toast(friendlyError(error)); return nil }
    }
    public func messages(_ conv: String) async throws -> [MessageRow] {
        let rows = try await Backend.shared.messages(conv)
        await session.social.namesFor(rows.map(\.senderId))
        return rows
    }
    /// Sends a text message; the stored row, or nil after a failure (already toasted).
    public func send(_ conv: String, body: String) async -> MessageRow? {
        guard let p = me else { return nil }
        do { return try await Backend.shared.send(conv, me: p.id, body: body) } catch is CancellationError { return nil } catch { session.toast(friendlyError(error)); return nil }
    }
    /// Uploads the file to the `chat` bucket and sends it as an attachment.
    public func sendFile(_ conv: String, _ f: Picked) async -> MessageRow? {
        guard let p = me else { return nil }
        uploading = true; defer { uploading = false }
        do {
            let path = "\(conv)/\(f.objectName())"
            try await Backend.shared.upload(bucket: "chat", path: path, data: f.data, contentType: f.mime)
            return try await Backend.shared.send(conv, me: p.id, body: "", attachment: FileRef(path: path, name: f.name, mime: f.mime, size: f.data.count))
        } catch is CancellationError { return nil } catch { session.toast(friendlyError(error)); return nil }
    }
    public func markRead(_ conv: String) {
        go { try await Backend.shared.markRead(conv); self.inbox = self.inbox.map { var r = $0; if r.conversationId == conv { r.unread = 0 }; return r } }
    }
    public func seenUpTo(_ conv: String) async -> String? { (try? await Backend.shared.seenUpTo(conv)) ?? nil }
    public func editMessage(_ id: String, body: String) { go { try await Backend.shared.editMessage(id, body: body) } }
    public func deleteMessage(_ id: String) { go { try await Backend.shared.deleteMessage(id) } }
    public func mute(_ conv: String, on: Bool) {
        go {
            guard let p = self.me else { return }
            try await Backend.shared.mute(conv, me: p.id, untilIso: on ? "2999-01-01T00:00:00Z" : nil)
            await self.refreshInboxNow()
        }
    }
    /// A short-lived URL for a private file (nil when it can't be signed).
    public func fileURL(_ bucket: String, _ path: String) async -> URL? { try? await Backend.shared.signedURL(bucket: bucket, path: path) }

    // MARK: groups and listing chats

    /// The conversation's own row: kind, title and listing id. Nil when I'm not a member.
    public func conversation(_ conv: String) async -> ConversationRow? { (try? await Backend.shared.conversation(conv)) ?? nil }
    /// Members of a group or listing inbox, admins first, with their names loaded into the names cache.
    public func members(_ conv: String) async -> [ConversationMemberRow] {
        guard let rows = try? await Backend.shared.conversationMembers(conv) else { return [] }
        await session.social.namesFor(rows.map(\.profileId))
        return rows
    }
    /// Only synced people can be in a group (the database drops anyone else). Returns the new conversation id; nil after a failure (already toasted).
    public func createGroup(title: String, members: [String]) async -> String? {
        do {
            let id = try await Backend.shared.createGroup(title: title.trimmingCharacters(in: .whitespacesAndNewlines), members: members)
            await refreshInboxNow(); session.toast("Group created."); return id
        } catch is CancellationError { return nil } catch { session.toast(friendlyError(error)); return nil }
    }
    public func renameGroup(_ conv: String, title: String, then: @escaping () -> Void = {}) {
        go { try await Backend.shared.renameGroup(conv, title: title.trimmingCharacters(in: .whitespacesAndNewlines)); await self.refreshInboxNow(); self.session.toast("Group renamed."); then() }
    }
    /// `onFailed` runs after a failure (already toasted) so the sheet can offer the button again.
    public func addToGroup(_ conv: String, members: [String], then: @escaping () -> Void = {}, onFailed: @escaping () -> Void = {}) {
        go {
            do {
                let n = try await Backend.shared.addGroupMembers(conv, members: members)
                self.session.toast(n == 0 ? "Nobody new was added. Only people synced with you can join." : n == 1 ? "1 person added." : "\(n) people added."); then()
            } catch { onFailed(); throw error }
        }
    }
    public func removeFromGroup(_ conv: String, member: String, then: @escaping () -> Void = {}) {
        go { try await Backend.shared.removeGroupMember(conv, member: member); self.session.toast("\(self.session.social.nameOf(member)) removed."); then() }
    }
    /// Leaving deletes my membership row; the chat leaves my inbox and I can't read it any more.
    public func leaveConversation(_ conv: String, then: @escaping () -> Void = {}) {
        go {
            guard let p = self.me else { return }
            try await Backend.shared.leaveConversation(conv, me: p.id)
            self.inbox.removeAll { $0.conversationId == conv }; self.session.toast("You left the group."); then()
        }
    }
}
