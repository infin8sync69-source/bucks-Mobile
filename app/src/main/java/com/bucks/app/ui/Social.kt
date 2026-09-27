package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import com.bucks.app.data.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Cloud-backed social state: profile and Bucks ID, Sync, inbox, feed, Moments, privacy settings.
 * Screens read the state and call the actions; every action reports a failure as a toast.
 * Nothing here runs unless Supabase and Firebase are configured ([enabled]); the demo screens
 * stay in use otherwise.
 */
class Social(private val scope: CoroutineScope, private val repo: BucksRepository, private val toast: (String) -> Unit) {
    val enabled get() = Backend.enabled
    var me by mutableStateOf<ProfileRow?>(null); private set
    var settings by mutableStateOf<SettingsRow?>(null); private set
    var inbox by mutableStateOf<List<InboxRow>>(emptyList()); private set
    val unread get() = inbox.sumOf { it.unread }
    var feed by mutableStateOf<List<FeedRow>>(emptyList()); private set
    var feedEnd by mutableStateOf(false); private set
    var tray by mutableStateOf<List<TrayRow>>(emptyList()); private set
    /** People asking to sync with me. */
    var incoming by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var synced by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var suggestions by mutableStateOf<List<PersonSuggestion>>(emptyList()); private set
    var blocked by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var closeFriends by mutableStateOf<Set<String>>(emptySet()); private set
    /** True while a photo or file is uploading. */
    var busy by mutableStateOf(false); private set
    /** Profile id -> display name, filled as rows arrive. */
    val names: SnapshotStateMap<String, String> = mutableStateMapOf()
    var here: LatLng = Geo.CENTER

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }

    fun signedIn(name: String, phone: String) = go {
        val p = Backend.ensureProfile(name, phone); me = p; names[p.id] = p.name
        settings = Backend.mySettings(p.id)
        repo.clearDemoSocial()
        refreshInbox(); refreshSyncs()
    }
    fun signedOut() { me = null; settings = null; inbox = emptyList(); feed = emptyList(); tray = emptyList(); incoming = emptyList(); synced = emptyList(); suggestions = emptyList(); blocked = emptyList(); closeFriends = emptySet() }
    fun profileSaved(name: String, area: String, bio: String) = go { val p = me ?: return@go; Backend.updateProfile(p.id, name, bio, area, here); me = p.copy(name = name, area = area, bio = bio); names[p.id] = name }

    suspend fun namesFor(ids: Collection<String>) { val missing = ids.filter { it !in names }.distinct(); if (missing.isNotEmpty()) Backend.profiles(missing).forEach { names[it.id] = it.name } }
    fun nameOf(id: String) = names[id] ?: "…"

    // ---------- sync ----------
    fun refreshSyncs() = go { val p = me ?: return@go
        val rows = Backend.mySyncs()
        val inIds = rows.filter { it.status == "PENDING" && it.addresseeId == p.id }.map { it.requesterId }
        val okIds = rows.filter { it.status == "ACCEPTED" }.map { if (it.requesterId == p.id) it.addresseeId else it.requesterId }
        val people = Backend.profiles((inIds + okIds).distinct()).associateBy { it.id }
        people.values.forEach { names[it.id] = it.name }
        incoming = inIds.mapNotNull { people[it] }; synced = okIds.mapNotNull { people[it] }
        closeFriends = Backend.closeFriends().toSet()
    }
    fun refreshSuggestions() = go { suggestions = Backend.suggestPeople(here) }
    /** Sync by Bucks ID, typed or scanned. */
    fun syncWithCode(code: String) = go { val p = Backend.profileByCode(code) ?: run { toast("No one has the Bucks ID ${code.uppercase()}."); return@go }; if (p.id == me?.id) { toast("That's your own Bucks ID."); return@go }; syncWith(p.id, p.name) }
    fun syncWith(id: String, name: String) = go { val r = Backend.sync(id); toast(if (r == "ACCEPTED") "You and $name are now synced." else "Sync request sent to $name."); refreshSyncs(); refreshSuggestions() }
    fun acceptSync(requester: String) = go { val p = me ?: return@go; Backend.acceptSync(requester, p.id); toast("Synced."); refreshSyncs() }
    fun unsync(other: String) = go { val p = me ?: return@go; Backend.unsync(p.id, other); refreshSyncs() }
    fun block(other: String) = go { val p = me ?: return@go; Backend.block(p.id, other); toast("Blocked. They can't message you, sync with you or see your posts."); refreshSyncs(); refreshBlocked(); refreshInbox() }
    fun unblock(other: String) = go { val p = me ?: return@go; Backend.unblock(p.id, other); refreshBlocked() }
    fun refreshBlocked() = go { blocked = Backend.profiles(Backend.blocked().map { it.blockedId }) }
    fun setClose(other: String, on: Boolean) = go { val p = me ?: return@go; Backend.setCloseFriend(p.id, other, on); closeFriends = if (on) closeFriends + other else closeFriends - other }
    fun saveSettings(row: SettingsRow) = go { Backend.saveSettings(row); settings = row; toast("Saved.") }

    // ---------- inbox and chat ----------
    fun refreshInbox() = go { inbox = Backend.inbox() }
    fun openDirect(other: String, onOpen: (String) -> Unit) = go { onOpen(Backend.startDirect(other)) }
    suspend fun messages(conv: String): List<MessageRow> { val rows = Backend.messages(conv); namesFor(rows.map { it.senderId }); return rows }
    fun send(conv: String, body: String) = go { val p = me ?: return@go; Backend.send(conv, p.id, body) }
    fun sendFile(conv: String, f: Picked) = go { val p = me ?: return@go; busy = true
        try { val path = "$conv/${f.objectName()}"; Backend.upload("chat", path, f.bytes); Backend.send(conv, p.id, "", FileRef(path, f.name, f.mime, f.bytes.size.toLong())) } finally { busy = false } }
    fun markRead(conv: String) = go { Backend.markRead(conv); inbox = inbox.map { if (it.conversationId == conv) it.copy(unread = 0) else it } }
    suspend fun seenUpTo(conv: String) = Backend.seenUpTo(conv)
    fun editMessage(id: String, body: String) = go { Backend.editMessage(id, body) }
    fun deleteMessage(id: String) = go { Backend.deleteMessage(id) }
    fun mute(conv: String, on: Boolean) = go { val p = me ?: return@go; Backend.mute(conv, p.id, if (on) "2999-01-01T00:00:00Z" else null); refreshInbox() }
    suspend fun fileUrl(bucket: String, path: String) = Backend.signedUrl(bucket, path)

    // ---------- feed ----------
    fun refreshFeed() = go { feed = Backend.feed(here); feedEnd = feed.size < 30; refreshTray() }
    fun loadMoreFeed() = go { val last = feed.lastOrNull() ?: return@go; val more = Backend.feed(here, last.createdAt); feed = feed + more; feedEnd = more.size < 30 }
    fun post(body: String, media: List<Picked>, visibility: String, area: String) = go { val p = me ?: return@go; busy = true
        try { val paths = media.map { f -> "${p.id}/${f.objectName()}".also { Backend.upload("posts", it, f.bytes) } }
              Backend.post(p.id, body, paths, visibility, here, area); toast("Posted."); refreshFeed() } finally { busy = false } }
    fun deletePost(id: String) = go { Backend.deletePost(id); feed = feed.filterNot { it.id == id } }
    fun vote(postId: String, v: Int) = go { val p = me ?: return@go
        val cur = feed.firstOrNull { it.id == postId } ?: return@go; val prev = cur.myVote ?: 0; val next = if (prev == v) 0 else v
        Backend.vote(postId, p.id, next)
        feed = feed.map { if (it.id != postId) it else it.copy(myVote = next.takeIf { n -> n != 0 }, up = it.up - (prev == 1).toInt() + (next == 1).toInt(), down = it.down - (prev == -1).toInt() + (next == -1).toInt()) } }
    suspend fun comments(postId: String): List<CommentRow> { val rows = Backend.comments(postId); namesFor(rows.map { it.authorId }); return rows }
    fun comment(postId: String, body: String, then: () -> Unit) = go { val p = me ?: return@go; Backend.comment(postId, p.id, body); feed = feed.map { if (it.id == postId) it.copy(comments = it.comments + 1) else it }; then() }

    // ---------- moments ----------
    fun refreshTray() = go { tray = Backend.momentsTray(here) }
    fun postMoment(f: Picked, caption: String, audience: String) = go { val p = me ?: return@go; busy = true
        try { val path = "${p.id}/${f.objectName()}"; Backend.upload("moments", path, f.bytes); Backend.postMoment(p.id, path, if (f.isVideo) "VIDEO" else "IMAGE", caption, audience, here); toast("Your moment is up for 24 hours."); refreshTray() } finally { busy = false } }
    suspend fun momentsOf(author: String): List<Pair<MomentRow, String>> = Backend.momentsOf(author, here).map { it to Backend.signedUrl("moments", it.mediaPath) }
    fun viewMoment(id: String, reaction: String? = null) = go { Backend.viewMoment(id, reaction); if (reaction != null) toast("Sent $reaction") }
    fun replyToMoment(id: String, body: String, onOpen: (String) -> Unit) = go { onOpen(Backend.replyToMoment(id, body)) }
    suspend fun momentViewers(id: String) = Backend.momentViewers(id)
    fun deleteMoment(id: String) = go { Backend.deleteMoment(id); refreshTray() }
    fun muteMoments(author: String, on: Boolean) = go { val p = me ?: return@go; Backend.muteMoments(p.id, author, on); refreshTray() }
}
private fun Boolean.toInt() = if (this) 1 else 0
