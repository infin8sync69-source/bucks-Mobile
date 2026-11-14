package com.bucks.app.ui

import com.bucks.app.R
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
    /** The Terms version I still have to accept (BucksAppUi shows a dialog that can't be dismissed), or null. */
    var termsNeeded by mutableStateOf<String?>(null); private set
    fun acceptTerms() = go {
        val v = termsNeeded ?: return@go
        com.bucks.app.data.BackendSafety.recordTerms(v)
        com.bucks.app.data.Prefs.acceptedTerms = v
        termsNeeded = null
    }
    var inbox by mutableStateOf<List<InboxRow>>(emptyList()); private set
    /** Notifications (Messages screen, second tab): what needs my attention besides chat. */
    var notes by mutableStateOf<List<NotificationRow>>(emptyList()); private set
    val notesUnread get() = notes.count { it.readAt == null }
    /** The badge on the messages icon: unread chats. Notifications have their own bell ([notesUnread]). */
    val unread get() = inbox.sumOf { it.unread }
    /** Set once I've asked someone to sync: the moment to ask for the notification permission, so their answer can reach me. */
    var wantsAlerts by mutableStateOf(false); private set
    private var poller: kotlinx.coroutines.Job? = null
    private var arrivals: kotlinx.coroutines.Job? = null
    /** Contact details I attached to people I'm synced with, by their profile id. Private to me. */
    var links by mutableStateOf<Map<String, ContactLinkRow>>(emptyMap()); private set
    fun refreshLinks() = go { links = Backend.contactLinks().associateBy { it.profileId } }
    fun saveLink(l: ContactLinkRow, then: () -> Unit = {}) = go { val p = me ?: return@go
        if (l.isEmpty) { if (links.containsKey(l.profileId)) Backend.deleteContactLink(l.profileId); links = links - l.profileId; then(); return@go }
        if (links.containsKey(l.profileId)) Backend.updateContactLink(l) else Backend.insertContactLink(p.id, l)
        links = links + (l.profileId to l); toast(Str.get(R.string.g5_link_saved)); then() }
    fun removeLink(profileId: String) = go { Backend.deleteContactLink(profileId); links = links - profileId; toast(Str.get(R.string.g5_link_removed)) }
    var feed by mutableStateOf<List<FeedRow>>(emptyList()); private set
    var feedEnd by mutableStateOf(false); private set
    var tray by mutableStateOf<List<TrayRow>>(emptyList()); private set
    /** People asking to sync with me. */
    var incoming by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var synced by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var suggestions by mutableStateOf<List<PersonSuggestion>>(emptyList()); private set
    var blocked by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    var closeFriends by mutableStateOf<Set<String>>(emptySet()); private set
    /** People whose Moments I've hidden from my tray. */
    var mutedMoments by mutableStateOf<List<ProfileRow>>(emptyList()); private set
    /** True while a photo or file is uploading. */
    var busy by mutableStateOf(false); private set
    /** Profile id -> display name, filled as rows arrive. */
    val names: SnapshotStateMap<String, String> = mutableStateMapOf()
    /** Profile picture links of the people in [names] (null: no picture), for avatars on posts, comments and chats. */
    val photos: SnapshotStateMap<String, String?> = mutableStateMapOf()
    var here: LatLng = Geo.CENTER
    /** True once a real fix has set [here]; until then it is only the map's default centre and must not be sent as my position. */
    var hereKnown = false

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: Exception) { toast(friendly(e)) } }
    /** Our own database errors come back wrapped; show just the sentence we wrote. */
    private fun friendly(e: Exception): String {
        val m = e.message ?: return Str.get(R.string.g5_something_wrong)
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1) ?: m.substringAfter("message: ", m).substringBefore("\n").take(140)
    }

    fun signedIn(name: String, phone: String) = go {
        // Right after the first sign-in the Supabase role claim may still be on its way: try again before giving up.
        var tries = 0
        val p = run { while (true) { try { return@run Backend.ensureProfile(name, phone) } catch (e: Exception) { if (++tries >= 3) throw e; kotlinx.coroutines.delay(2_000L * tries) } }; error("unreachable") }
        me = p; names[p.id] = p.name; photos[p.id] = p.photoUrl
        // Onboarding choices made before there was an account: the accepted terms version, the country and the language.
        com.bucks.app.data.Prefs.acceptedTerms?.let { v -> runCatching { com.bucks.app.data.BackendSafety.recordTerms(v) } }
        // The Terms changed since this person accepted them (or they never did, on an older app): ask before they carry on.
        termsNeeded = com.bucks.app.data.BackendSafety.termsStatus()?.takeIf { it.needed }?.current
        runCatching { com.bucks.app.data.BackendSafety.setMyLocale(com.bucks.app.data.Prefs.countryIso, com.bucks.app.data.AppLanguages.current().tag) }
        settings = Backend.mySettings(p.id)
        Push.registerIfSignedIn()
        repo.clearDemoSocial()
        refreshInbox(); refreshSyncs(); refreshLinks()
        // The badge on the messages icon stays fresh while the app is open: one small check a minute.
        poller?.cancel(); poller = scope.launch { while (true) { kotlinx.coroutines.delay(60_000); runCatching { inbox = Backend.inbox(); notes = Backend.notifications() } } }
        // A push that lands while the app is open (a sync request, a message, an order) shows in the badges and lists at once, not at the next check.
        arrivals?.cancel(); arrivals = scope.launch { Push.arrivals.collect { runCatching { inbox = Backend.inbox(); notes = Backend.notifications() }; refreshSyncs() } }
    }
    /** Which of my pictures is uploading (the header shows a spinner on it), or null. */
    var mediaBusy by mutableStateOf<com.bucks.app.data.ProfileMedia.Slot?>(null); private set
    /** Replaces my profile picture or cover with [picked]; the old file is removed once the new link is saved. */
    fun setMyPicture(slot: com.bucks.app.data.ProfileMedia.Slot, picked: com.bucks.app.data.Picked) = go {
        val p = me ?: return@go; if (mediaBusy != null) return@go; mediaBusy = slot
        try {
            val photo = slot == com.bucks.app.data.ProfileMedia.Slot.PHOTO
            val url = com.bucks.app.data.ProfileMedia.setMine(p.id, slot, picked, if (photo) p.photoUrl else p.coverUrl)
            me = (me ?: p).let { if (photo) it.copy(photoUrl = url) else it.copy(coverUrl = url) }
            toast(Str.get(if (photo) R.string.g5_photo_updated else R.string.g5_cover_updated))
        } finally { mediaBusy = null }
    }
    fun clearMyPicture(slot: com.bucks.app.data.ProfileMedia.Slot) = go {
        val p = me ?: return@go; if (mediaBusy != null) return@go; mediaBusy = slot
        try {
            val photo = slot == com.bucks.app.data.ProfileMedia.Slot.PHOTO
            com.bucks.app.data.ProfileMedia.clearMine(p.id, slot, if (photo) p.photoUrl else p.coverUrl)
            me = (me ?: p).let { if (photo) it.copy(photoUrl = null) else it.copy(coverUrl = null) }
            toast(Str.get(if (photo) R.string.g5_photo_removed else R.string.g5_cover_removed))
        } finally { mediaBusy = null }
    }
    /** Starts a new year on my Bucks ID card (allowed in its last 30 days or after it lapsed). */
    fun renewBucksId() = go { val t = Backend.renewBucksId(); me = me?.copy(idIssuedAt = t); toast(Str.get(R.string.g5_id_renewed)) }
    fun signedOut() { poller?.cancel(); poller = null; arrivals?.cancel(); arrivals = null; wantsAlerts = false; notes = emptyList(); links = emptyMap(); me = null; settings = null; inbox = emptyList(); feed = emptyList(); tray = emptyList(); incoming = emptyList(); synced = emptyList(); suggestions = emptyList(); blocked = emptyList(); closeFriends = emptySet(); mutedMoments = emptyList() }
    /** [home] null leaves the saved home point alone; it is never guessed from the map's default centre. */
    fun profileSaved(name: String, area: String, bio: String, home: LatLng? = null) = go { val p = me ?: Backend.ensureProfile(name, null).also { me = it }; Backend.updateProfile(p.id, name, bio, area, home); me = p.copy(name = name, area = area, bio = bio); names[p.id] = name }

    /** Saved quietly: a database that doesn't have the column yet (before profile_details.sql) just keeps it on the phone. */
    fun genderSaved(label: String) { val p = me ?: return; val code = when (label) { "Woman" -> "WOMAN"; "Man" -> "MAN"; "Non-binary" -> "NON_BINARY"; "Prefer not to say" -> "UNSAID"; else -> null }
        scope.launch { runCatching { Backend.setGender(p.id, code) } } }

    suspend fun namesFor(ids: Collection<String>) { val missing = ids.filter { it !in names || !photos.containsKey(it) }.distinct(); if (missing.isNotEmpty()) Backend.profiles(missing).forEach { names[it.id] = it.name; photos[it.id] = it.photoUrl } }
    fun nameOf(id: String) = names[id] ?: "…"
    /** My own picture comes from [me], so a change shows at once; anyone else's from the last profiles read. */
    fun photoOf(id: String): String? = if (id == me?.id) me?.photoUrl else photos[id]

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
    fun syncWithCode(code: String) = go { val p = Backend.profileByCode(code) ?: run { toast(Str.get(R.string.g5_id_not_found, code.uppercase())); return@go }; if (p.id == me?.id) { toast(Str.get(R.string.g5_id_own)); return@go }
        // An ID card lapses a year after issue; the owner renews it in one tap from Menu > Bucks Pro.
        BucksIdCardInfo.of(p.idIssuedAt)?.takeIf { it.expired }?.let { toast(if (p.name.isBlank()) Str.get(R.string.g5_id_expired_their, it.validTill.toString()) else Str.get(R.string.g5_id_expired_named, p.name, it.validTill.toString())); return@go }
        syncWith(p.id, p.name) }
    fun syncWith(id: String, name: String) = go { val r = Backend.sync(id); wantsAlerts = true; com.bucks.app.data.Analytics.log(if (r == "ACCEPTED") com.bucks.app.data.Analytics.SYNC_ACCEPTED else com.bucks.app.data.Analytics.SYNC_REQUESTED); toast(Str.get(if (r == "ACCEPTED") R.string.g5_synced_with else R.string.g5_sync_sent, name)); refreshSyncs(); refreshSuggestions() }
    fun acceptSync(requester: String) = go { val p = me ?: return@go; Backend.acceptSync(requester, p.id); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.SYNC_ACCEPTED); toast(Str.get(R.string.g5_synced)); refreshSyncs() }
    fun unsync(other: String) = go { val p = me ?: return@go; Backend.unsync(p.id, other); refreshSyncs() }
    fun block(other: String) = go { val p = me ?: return@go; Backend.block(p.id, other); toast(Str.get(R.string.g5_blocked)); refreshSyncs(); refreshBlocked(); refreshInbox() }
    fun unblock(other: String) = go { val p = me ?: return@go; Backend.unblock(p.id, other); refreshBlocked() }
    fun refreshBlocked() = go { blocked = Backend.profiles(Backend.blocked().map { it.blockedId }) }
    fun setClose(other: String, on: Boolean) = go { val p = me ?: return@go; Backend.setCloseFriend(p.id, other, on); closeFriends = if (on) closeFriends + other else closeFriends - other }
    fun saveSettings(row: SettingsRow) = go { Backend.saveSettings(row); settings = row; toast(Str.get(R.string.g5_saved)) }

    // ---------- inbox and chat ----------
    fun refreshInbox() = go { inbox = Backend.inbox(); notes = runCatching { Backend.notifications() }.getOrDefault(notes) }
    fun markNoteRead(id: String) { notes = notes.map { if (it.id == id && it.readAt == null) it.copy(readAt = "now") else it }; scope.launch { runCatching { Backend.markNotificationsRead(listOf(id)) } } }
    fun markAllNotesRead() = go { notes = notes.map { if (it.readAt == null) it.copy(readAt = "now") else it }; Backend.markNotificationsRead() }
    fun deleteNote(id: String) = go { notes = notes.filterNot { it.id == id }; Backend.deleteNotification(id) }
    fun openDirect(other: String, onOpen: (String) -> Unit) = go { onOpen(Backend.startDirect(other)) }
    suspend fun messages(conv: String): List<MessageRow> { val rows = Backend.messages(conv); namesFor(rows.map { it.senderId }); return rows }
    fun send(conv: String, body: String) = go { val p = me ?: return@go; Backend.send(conv, p.id, body); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.MESSAGE_SENT) }
    fun sendFile(conv: String, f: Picked) = go { val p = me ?: return@go; busy = true
        try { val path = "$conv/${f.objectName()}"; Backend.upload("chat", path, f.bytes); Backend.send(conv, p.id, "", FileRef(path, f.name, f.mime, f.bytes.size.toLong())) } finally { busy = false } }
    fun markRead(conv: String) = go { Backend.markRead(conv); inbox = inbox.map { if (it.conversationId == conv) it.copy(unread = 0) else it } }
    suspend fun seenUpTo(conv: String) = Backend.seenUpTo(conv)
    fun editMessage(id: String, body: String) = go { Backend.editMessage(id, body) }
    fun deleteMessage(id: String) = go { Backend.deleteMessage(id) }
    fun mute(conv: String, on: Boolean) = go { val p = me ?: return@go; Backend.mute(conv, p.id, if (on) "2999-01-01T00:00:00Z" else null); refreshInbox() }
    suspend fun fileUrl(bucket: String, path: String) = Backend.signedUrl(bucket, path)

    // ---------- groups and listing chats ----------
    /** The conversation's own row: kind (DIRECT / GROUP / LISTING), title and listing id. Null when I'm not a member. */
    suspend fun conversation(conv: String): ConversationRow? = Backend.conversation(conv)
    /** Members of a group or listing inbox, admins first, with their names loaded into [names]. */
    suspend fun members(conv: String): List<ConversationMemberRow> { val rows = Backend.conversationMembers(conv); namesFor(rows.map { it.profileId }); return rows }
    /** Only synced people can be in a group (the database drops anyone else). */
    fun createGroup(title: String, members: List<String>, onCreated: (String) -> Unit, onFailed: () -> Unit = {}) = scope.launch {
        try { val id = Backend.createGroup(title.trim(), members); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.GROUP_CREATED, "members" to members.size); refreshInbox(); toast(Str.get(R.string.g5_group_created)); onCreated(id) } catch (e: Exception) { toast(friendly(e)); onFailed() } }
    fun renameGroup(conv: String, title: String, then: () -> Unit = {}) = go { Backend.renameGroup(conv, title.trim()); refreshInbox(); toast(Str.get(R.string.g5_group_renamed)); then() }
    fun addToGroup(conv: String, members: List<String>, then: () -> Unit = {}) = go {
        val n = Backend.addGroupMembers(conv, members)
        toast(if (n == 0) Str.get(R.string.g5_group_none_added) else Str.plural(R.plurals.g5_group_people_added, n)); then() }
    fun removeFromGroup(conv: String, member: String, then: () -> Unit = {}) = go { Backend.removeGroupMember(conv, member); toast(Str.get(R.string.g5_member_removed, nameOf(member))); then() }
    /** Leaving deletes my membership row; the chat leaves my inbox and I can't read it any more. */
    fun leaveConversation(conv: String, then: () -> Unit = {}) = go { val p = me ?: return@go; Backend.leaveConversation(conv, p.id); inbox = inbox.filterNot { it.conversationId == conv }; toast(Str.get(R.string.g5_left_group)); then() }

    // ---------- feed ----------
    fun refreshFeed() = go { feed = Backend.feedSynced(here, me?.id); feedEnd = feed.size < 30; refreshTray(); runCatching { namesFor(feed.map { it.authorId }) } }
    fun loadMoreFeed() = go { val last = feed.lastOrNull() ?: return@go; val more = Backend.feedSynced(here, me?.id, last.createdAt); feed = feed + more; feedEnd = more.size < 30; runCatching { namesFor(more.map { it.authorId }) } }
    fun post(body: String, media: List<Picked>, visibility: String, area: String) = go { val p = me ?: return@go; busy = true
        try { val paths = media.map { f -> "${p.id}/${f.objectName()}".also { Backend.upload("posts", it, f.bytes) } to f.mime }
              // A still frame beside each video, so lists of videos have a picture to show without downloading the video. Best effort.
              val posters = HashMap<String, String>()
              media.forEachIndexed { i, f -> if (f.isVideo) kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { Upload.videoPoster(f.bytes) }?.let { jpg ->
                  val to = paths[i].first.substringBeforeLast('.') + "-poster.jpg"; if (runCatching { Backend.upload("posts", to, jpg) }.isSuccess) posters[paths[i].first] = to } }
              Backend.post(p.id, body, paths, visibility, here, area, posters = posters); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.POST_CREATED, "visibility" to visibility, "media" to paths.size); toast(Str.get(R.string.g5_posted)); refreshFeed() } finally { busy = false } }
    fun deletePost(id: String) = go { Backend.deletePost(id); feed = feed.filterNot { it.id == id } }
    fun vote(postId: String, v: Int) = go { val p = me ?: return@go
        val cur = feed.firstOrNull { it.id == postId } ?: return@go
        val prev = cur.myVote ?: 0; val next = if (prev == v) 0 else v
        Backend.vote(postId, p.id, next); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.POST_VOTE, "vote" to next)
        feed = feed.map { if (it.id != postId) it else it.copy(myVote = next.takeIf { n -> n != 0 }, up = it.up - (prev == 1).toInt() + (next == 1).toInt(), down = it.down - (prev == -1).toInt() + (next == -1).toInt()) } }
    suspend fun comments(postId: String): List<CommentRow> { val rows = Backend.comments(postId); namesFor(rows.map { it.authorId }); return rows }
    fun comment(postId: String, body: String, then: () -> Unit) = go { val p = me ?: return@go; Backend.comment(postId, p.id, body); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.COMMENT); feed = feed.map { if (it.id == postId) it.copy(comments = it.comments + 1) else it }; then() }

    // ---------- moments ----------
    fun refreshTray() = go { tray = Backend.momentsTray(here) }
    /** Photos (re-encoded by Upload.read) or MP4 videos up to [MAX_VIDEO_BYTES], the bucket's limit. */
    fun postMoment(f: Picked, caption: String, audience: String) = go { val p = me ?: return@go
        if (f.isVideo && f.bytes.size > MAX_VIDEO_BYTES) { toast(Str.get(R.string.g5_video_too_big)); return@go }
        if (f.isVideo && f.mime != "video/mp4") { toast(Str.get(R.string.g5_video_mp4_only)); return@go }
        busy = true
        try { val path = "${p.id}/${f.objectName()}"; Backend.upload("moments", path, f.bytes); Backend.postMoment(p.id, path, if (f.isVideo) "VIDEO" else "IMAGE", caption, audience, here); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.MOMENT_CREATED, "video" to f.isVideo); toast(Str.get(R.string.g5_moment_up)); refreshTray() } finally { busy = false } }
    /** Opening (not just listing) grants access to nearby moments from people I'm not synced with, so their media can be signed. */
    suspend fun momentsOf(author: String): List<Pair<MomentRow, String>> = Backend.openMoments(author, here).map { it to Backend.signedUrl("moments", it.mediaPath) }
    fun viewMoment(id: String, reaction: String? = null) = go { Backend.viewMoment(id, reaction); if (reaction != null) toast(Str.get(R.string.g5_reaction_sent, reaction)) }
    fun replyToMoment(id: String, body: String, onOpen: (String) -> Unit) = go { onOpen(Backend.replyToMoment(id, body)) }
    suspend fun momentViewers(id: String) = Backend.momentViewers(id)
    fun deleteMoment(id: String) = go { Backend.deleteMoment(id); refreshTray() }
    fun muteMoments(author: String, on: Boolean) = go { val p = me ?: return@go; Backend.muteMoments(p.id, author, on); toast(if (on) Str.get(R.string.g5_moments_hidden, nameOf(author)) else Str.get(R.string.g5_unmuted)); refreshTray(); refreshMutedMoments() }
    fun unmuteMoments(author: String) = muteMoments(author, false)
    fun refreshMutedMoments() = go { val rows = Backend.momentMutes(); val people = Backend.profiles(rows.map { it.mutedId }); people.forEach { names[it.id] = it.name }; mutedMoments = people }

    companion object { const val MAX_VIDEO_BYTES = 30 * 1024 * 1024; /** The posts bucket's limit. */ const val MAX_POST_VIDEO_BYTES = 15 * 1024 * 1024 }
}
private fun Boolean.toInt() = if (this) 1 else 0
