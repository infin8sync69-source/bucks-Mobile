import Foundation
import Observation

/// Port of the Android `Social` state holder, minus the feed and Moments (FeedStore) and the inbox (ChatStore):
/// privacy settings, Sync (requests, suggestions, synced people), blocking, close friends, contact links and the names cache.
/// Every action reports a failure as a toast.
@MainActor @Observable
public final class SocialStore {
    @ObservationIgnored public unowned let session: AppSession
    public init(session: AppSession) { self.session = session }

    public var me: ProfileRow? { session.me }
    public private(set) var settings: SettingsRow?
    /// People asking to sync with me.
    public private(set) var incoming: [ProfileRow] = []
    public private(set) var synced: [ProfileRow] = []
    public private(set) var suggestions: [PersonSuggestion] = []
    public private(set) var blocked: [ProfileRow] = []
    public private(set) var closeFriends: Set<String> = []
    /// Contact details I attached to people I'm synced with, by their profile id. Private to me.
    public private(set) var links: [String: ContactLinkRow] = [:]

    // MARK: lifecycle

    /// Loads what the screens need right after sign-in (the settings row, sync state, contact links).
    public func signedIn() {
        go {
            guard let p = self.me else { return }
            self.settings = try await Backend.shared.mySettings(me: p.id)
            await self.refreshSyncsNow(); await self.refreshLinksNow()
        }
    }
    public func signedOut() {
        settings = nil; incoming = []; synced = []; suggestions = []; blocked = []; closeFriends = []; links = [:]
    }

    @discardableResult
    private func go(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do { try await block() } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
        }
    }

    // MARK: names

    /// Fills the name cache for people not seen yet.
    public func namesFor(_ ids: [String]) async {
        var seen = Set<String>()
        let missing = ids.filter { session.names[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty, let rows = try? await Backend.shared.profiles(missing) else { return }
        for r in rows { session.names[r.id] = r.name }
    }
    public func nameOf(_ id: String) -> String { session.names[id] ?? "…" }

    // MARK: contact links

    public func refreshLinks() { go { await self.refreshLinksNow() } }
    private func refreshLinksNow() async {
        guard let rows = try? await Backend.shared.contactLinks() else { return }
        links = Dictionary(rows.map { ($0.profileId, $0) }, uniquingKeysWith: { _, b in b })
    }
    /// An empty link removes the stored one. `then` runs after a successful save.
    public func saveLink(_ l: ContactLinkRow, then: @escaping () -> Void = {}) {
        go {
            guard let p = self.me else { return }
            if l.isEmpty {
                if self.links[l.profileId] != nil { try await Backend.shared.deleteContactLink(l.profileId) }
                self.links[l.profileId] = nil; then(); return
            }
            if self.links[l.profileId] != nil { try await Backend.shared.updateContactLink(l) } else { try await Backend.shared.insertContactLink(me: p.id, l) }
            self.links[l.profileId] = l
            self.session.toast("Saved. Only you can see this."); then()
        }
    }
    public func removeLink(_ profileId: String) {
        go { try await Backend.shared.deleteContactLink(profileId); self.links[profileId] = nil; self.session.toast("Contact details removed.") }
    }

    // MARK: sync

    public func refreshSyncs() { go { await self.refreshSyncsNow() } }
    func refreshSyncsNow() async {
        guard let p = me else { return }
        do {
            let rows = try await Backend.shared.mySyncs()
            let inIds = rows.filter { $0.status == "PENDING" && $0.addresseeId == p.id }.map(\.requesterId)
            let okIds = rows.filter { $0.status == "ACCEPTED" }.map { $0.requesterId == p.id ? $0.addresseeId : $0.requesterId }
            var all: [String] = []; for id in inIds + okIds where !all.contains(id) { all.append(id) }
            let people = Dictionary((try await Backend.shared.profiles(all)).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for r in people.values { session.names[r.id] = r.name }
            incoming = inIds.compactMap { people[$0] }; synced = okIds.compactMap { people[$0] }
            closeFriends = Set(try await Backend.shared.closeFriends())
        } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
    }
    public func refreshSuggestions() { go { self.suggestions = try await Backend.shared.suggestPeople(self.session.here) } }

    /// Sync by Bucks ID, typed or scanned.
    public func syncWithCode(_ code: String) {
        go {
            guard let p = try await Backend.shared.profileByCode(code) else { self.session.toast("No one has the Bucks ID \(code.uppercased())."); return }
            if p.id == self.me?.id { self.session.toast("That's your own Bucks ID."); return }
            // An ID card lapses a year after issue; the owner renews it in one tap from Menu > Bucks Pro.
            if let v = BucksIdCardInfo.of(p.idIssuedAt), v.expired {
                self.session.toast("\(p.name.isEmpty ? "Their" : p.name)'s Bucks ID expired on \(v.validTill). Ask them to renew it from Menu > Bucks Pro."); return
            }
            await self.syncNow(p.id, p.name)
        }
    }
    public func syncWith(_ id: String, name: String) { go { await self.syncNow(id, name) } }
    private func syncNow(_ id: String, _ name: String) async {
        do {
            let r = try await Backend.shared.sync(id)
            session.toast(r == "ACCEPTED" ? "You and \(name) are now synced." : "Sync request sent to \(name).")
            await refreshSyncsNow(); suggestions = (try? await Backend.shared.suggestPeople(session.here)) ?? suggestions
        } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
    }
    public func acceptSync(_ requester: String) {
        go { guard let p = self.me else { return }; try await Backend.shared.acceptSync(requester: requester, me: p.id); self.session.toast("Synced."); await self.refreshSyncsNow() }
    }
    public func unsync(_ other: String) {
        go { guard let p = self.me else { return }; try await Backend.shared.unsync(me: p.id, other: other); await self.refreshSyncsNow() }
    }

    // MARK: blocking and close friends

    public func block(_ other: String) {
        go {
            guard let p = self.me else { return }
            try await Backend.shared.block(me: p.id, other: other)
            self.session.toast("Blocked. They can't message you, sync with you or see your posts.")
            await self.refreshSyncsNow(); await self.refreshBlockedNow(); await self.session.chat.refreshInboxNow()
        }
    }
    public func unblock(_ other: String) { go { guard let p = self.me else { return }; try await Backend.shared.unblock(me: p.id, other: other); await self.refreshBlockedNow() } }
    public func refreshBlocked() { go { await self.refreshBlockedNow() } }
    private func refreshBlockedNow() async {
        do { blocked = try await Backend.shared.profiles(try await Backend.shared.blocked().map(\.blockedId)) } catch is CancellationError {} catch { session.toast(friendlyError(error)) }
    }
    public func setClose(_ other: String, on: Bool) {
        go {
            guard let p = self.me else { return }
            try await Backend.shared.setCloseFriend(me: p.id, friend: other, on: on)
            if on { self.closeFriends.insert(other) } else { self.closeFriends.remove(other) }
        }
    }

    // MARK: settings

    public func saveSettings(_ row: SettingsRow) { go { try await Backend.shared.saveSettings(row); self.settings = row; self.session.toast("Saved.") } }
}
