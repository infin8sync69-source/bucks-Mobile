package com.bucks.app.data

import com.bucks.app.BuildConfig
import com.google.firebase.auth.FirebaseAuth
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.realtime.RealtimeChannel
import io.github.jan.supabase.realtime.realtime
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlin.time.Duration.Companion.hours
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Supabase data layer (schema: supabase/schema.sql). Sign-in stays with Firebase: every request
 * carries the Firebase ID token, which Supabase verifies, so row-level security sees the same person.
 * Enabled only when the build has a Supabase URL and key and Firebase is configured.
 */
object Backend {
    val enabled: Boolean get() = BuildConfig.SUPABASE_URL.isNotBlank() && BuildConfig.SUPABASE_ANON_KEY.isNotBlank() && Cloud.enabled

    val client: SupabaseClient by lazy {
        createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY) {
            accessToken = { FirebaseAuth.getInstance().currentUser?.getIdToken(false)?.await()?.token }
            install(Postgrest)
            install(Realtime)
            install(Storage)
        }
    }
    private val db get() = client.postgrest

    /** Postgres geography input: PostGIS reads this text form directly. */
    fun point(p: LatLng) = "SRID=4326;POINT(${p.lng} ${p.lat})"

    // ---------- people ----------
    suspend fun ensureProfile(name: String, phone: String?): ProfileRow =
        db.rpc("ensure_profile", buildJsonObject { put("p_name", name); put("p_phone", phone) }).decodeAs()
    suspend fun updateProfile(id: String, name: String, bio: String, area: String, home: LatLng?) {
        db.from("profiles").update({ set("name", name); set("bio", bio); set("area", area); home?.let { set("home", point(it)) } }) { filter { eq("id", id) } }
    }
    /** The columns the API may read from profiles; `home` is withheld (manage.sql), so `select *` would be refused. */
    private val PROFILE_COLUMNS = Columns.list("id", "short_code", "name", "bio", "area", "photo_url", "trust_up", "trust_down")
    suspend fun profiles(ids: Collection<String>): List<ProfileRow> = if (ids.isEmpty()) emptyList() else db.from("profiles").select(PROFILE_COLUMNS) { filter { isIn("id", ids.toList()) } }.decodeList()
    suspend fun profileByCode(code: String): ProfileRow? =
        db.from("profiles").select(PROFILE_COLUMNS) { filter { eq("short_code", code.trim().uppercase()) } }.decodeSingleOrNull()
    suspend fun setPaymentLink(profileId: String, upiUri: String) {
        db.from("profile_private").update({ set("upi_uri", upiUri) }) { filter { eq("profile_id", profileId) } }
    }

    // ---------- sync (connections) ----------
    suspend fun requestSync(me: String, other: String) { db.from("syncs").insert(buildJsonObject { put("requester_id", me); put("addressee_id", other) }) }
    suspend fun acceptSync(requester: String, me: String) { db.from("syncs").update({ set("status", "ACCEPTED") }) { filter { eq("requester_id", requester); eq("addressee_id", me) } } }
    suspend fun mySyncs(): List<SyncRow> = db.from("syncs").select().decodeList()

    // ---------- listings: business, skill, driver ----------
    suspend fun search(q: String, at: LatLng, radiusM: Int = 10_000, kinds: List<String>? = null): List<SearchHit> =
        db.rpc("search_listings", buildJsonObject {
            put("q", q); put("lat", at.lat); put("lng", at.lng); put("radius_m", radiusM)
            if (kinds != null) put("kinds", buildJsonArray { kinds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
        }).decodeList()
    suspend fun listing(id: String): ListingRow? = db.from("listings").select { filter { eq("id", id) } }.decodeSingleOrNull()
    suspend fun myListings(me: String): List<ListingRow> {
        val ids = db.from("listing_members").select { filter { eq("profile_id", me) } }.decodeList<MemberRow>().map { it.listingId }
        return if (ids.isEmpty()) emptyList() else db.from("listings").select { filter { isIn("id", ids) } }.decodeList()
    }
    suspend fun createListing(me: String, kind: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JsonObject = JsonObject(emptyMap())): ListingRow =
        db.from("listings").insert(buildJsonObject {
            put("kind", kind); put("owner_id", me); put("title", title); put("category", category); put("description", description); put("area", area)
            at?.let { put("location", point(it)) }; put("details", details)
        }) { select() }.decodeSingle()
    suspend fun updateListing(id: String, title: String, category: String, description: String, area: String, at: LatLng?, details: JsonObject) {
        db.from("listings").update({ set("title", title); set("category", category); set("description", description); set("area", area); at?.let { set("location", point(it)) }; set("details", details) }) { filter { eq("id", id) } }
    }
    suspend fun setOnline(id: String, online: Boolean) { db.from("listings").update({ set("online", online) }) { filter { eq("id", id) } } }
    suspend fun deleteListing(id: String) { db.from("listings").delete { filter { eq("id", id) } } }
    suspend fun members(listingId: String): List<MemberRow> = db.from("listing_members").select { filter { eq("listing_id", listingId) } }.decodeList()
    suspend fun removeMember(listingId: String, profileId: String) { db.from("listing_members").delete { filter { eq("listing_id", listingId); eq("profile_id", profileId) } } }

    // ---------- items: products and services ----------
    suspend fun items(listingId: String): List<ItemRow> = db.from("items").select { filter { eq("listing_id", listingId) }; order("sort", Order.ASCENDING) }.decodeList()
    suspend fun saveItem(item: ItemRow): ItemRow =
        if (item.id == null) db.from("items").insert(item) { select() }.decodeSingle()
        else db.from("items").update(item) { select(); filter { eq("id", item.id) } }.decodeSingle()
    suspend fun deleteItem(id: String) { db.from("items").delete { filter { eq("id", id) } } }

    // ---------- a listing's own posts (its profile feed) ----------
    suspend fun listingPosts(listingId: String): List<PostRow> = db.from("posts").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()

    // ---------- admins ----------
    suspend fun invite(listingId: String?, vehicleId: String?, bucksId: String, role: String): String =
        db.rpc("invite", buildJsonObject { put("p_listing", listingId); put("p_vehicle", vehicleId); put("p_short_code", bucksId); put("p_role", role) }).decodeAs()
    suspend fun myInvites(): List<InviteRow> = db.from("invites").select { filter { eq("status", "PENDING") } }.decodeList()
    suspend fun respondInvite(id: String, accept: Boolean) { db.rpc("respond_invite", buildJsonObject { put("p_invite", id); put("p_accept", accept) }) }

    // ---------- community cap ----------
    suspend fun recommendToken(listingId: String): String = db.rpc("recommend_token", buildJsonObject { put("p_listing", listingId) }).decodeAs()
    /** Returns the listing's recommendation count after this one; it goes live at 7. */
    suspend fun recommend(token: String, at: LatLng): Int = db.rpc("recommend", buildJsonObject { put("p_token", token); put("lat", at.lat); put("lng", at.lng) }).decodeAs()

    // ---------- vehicles ----------
    suspend fun myVehicles(): List<VehicleRow> = db.from("vehicles").select().decodeList()
    suspend fun addVehicle(me: String, kind: String, model: String, plate: String): VehicleRow =
        db.from("vehicles").insert(buildJsonObject { put("owner_id", me); put("kind", kind); put("model", model); put("plate", plate.uppercase().replace(" ", "")) }) { select() }.decodeSingle()
    suspend fun updateVehicle(id: String, model: String) { db.from("vehicles").update({ set("model", model) }) { filter { eq("id", id) } } }
    suspend fun deleteVehicle(id: String) { db.from("vehicles").delete { filter { eq("id", id) } } }
    suspend fun vehicleStats(): List<VehicleStat> = db.from("vehicle_stats").select().decodeList()

    // ---------- presence and tasks (rides + deliveries) ----------
    suspend fun setPresence(me: String, vehicleId: String, kind: String, online: Boolean, at: LatLng?) {
        db.from("driver_presence").upsert(buildJsonObject { put("profile_id", me); put("vehicle_id", vehicleId); put("kind", kind); put("online", online); at?.let { put("location", point(it)) } })
    }
    suspend fun updateLocation(at: LatLng) { db.rpc("update_location", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }) }
    suspend fun requestRide(kind: VehicleKind, from: LatLng, fromLabel: String, to: LatLng, toLabel: String, km: Double, fare: Int): TaskRow =
        db.rpc("request_ride", buildJsonObject { put("p_kind", kind.name); put("p_lat", from.lat); put("p_lng", from.lng); put("p_pickup_label", fromLabel)
            put("d_lat", to.lat); put("d_lng", to.lng); put("p_drop_label", toLabel); put("p_km", km); put("p_fare", fare) }).decodeAs()
    suspend fun openTasksNear(at: LatLng): List<TaskRow> = db.rpc("open_tasks_near", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList()
    suspend fun claimTask(id: String): Boolean = db.rpc("claim_task", buildJsonObject { put("p_task", id) }).decodeAs()
    suspend fun passTask(id: String, missed: Boolean) { db.rpc("pass_task", buildJsonObject { put("p_task", id); put("p_missed", missed) }) }
    suspend fun advanceTask(id: String, status: String, pin: String? = null, paidWith: String? = null): TaskRow =
        db.rpc("advance_task", buildJsonObject { put("p_task", id); put("p_status", status); put("p_pin", pin); put("p_paid_with", paidWith) }).decodeAs()
    suspend fun task(id: String): TaskRow? = db.from("tasks").select { filter { eq("id", id) } }.decodeSingleOrNull()
    suspend fun contactFor(taskId: String): ContactRow? = db.rpc("contact_for_task", buildJsonObject { put("p_task", taskId) }).decodeList<ContactRow>().firstOrNull()

    // ---------- orders ----------
    suspend fun placeOrder(listingId: String, lines: List<Pair<String, Int>>, drop: LatLng, dropLabel: String, payment: String, mode: String): String =
        db.rpc("place_order", buildJsonObject {
            put("p_listing", listingId)
            put("p_lines", buildJsonArray { lines.forEach { (item, qty) -> add(buildJsonObject { put("item_id", item); put("qty", qty) }) } })
            put("p_lat", drop.lat); put("p_lng", drop.lng); put("p_drop_label", dropLabel); put("p_payment", payment); put("p_mode", mode)
        }).decodeAs()
    suspend fun ordersFor(listingId: String): List<OrderRow> = db.from("orders").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()
    suspend fun myOrders(me: String): List<OrderRow> = db.from("orders").select { filter { eq("buyer_id", me) }; order("created_at", Order.DESCENDING) }.decodeList()
    suspend fun respondOrder(id: String, accept: Boolean) { db.rpc("respond_order", buildJsonObject { put("p_order", id); put("p_accept", accept) }) }

    // ---------- reviews ----------
    suspend fun review(listingId: String, taskId: String?, orderId: String?, up: Boolean, comment: String) {
        db.rpc("review", buildJsonObject { put("p_listing", listingId); put("p_task", taskId); put("p_order", orderId); put("p_vote", if (up) 1 else -1); put("p_comment", comment) })
    }
    suspend fun reviews(listingId: String): List<ReviewRow> = db.from("reviews").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()

    // ---------- jobs ----------
    suspend fun jobs(listingId: String): List<JobRow> = db.from("jobs").select { filter { eq("listing_id", listingId) }; order("created_at", Order.DESCENDING) }.decodeList()
    suspend fun postJob(listingId: String, me: String, title: String, description: String, pay: String, type: String) {
        db.from("jobs").insert(buildJsonObject { put("listing_id", listingId); put("created_by", me); put("title", title); put("description", description); put("pay", pay); put("job_type", type) })
    }
    suspend fun closeJob(id: String) { db.from("jobs").update({ set("open", false) }) { filter { eq("id", id) } } }
    suspend fun apply(jobId: String, me: String, skillListingIds: List<String>, note: String) {
        db.from("applications").insert(buildJsonObject { put("job_id", jobId); put("applicant_id", me); put("note", note)
            put("skill_listing_ids", buildJsonArray { skillListingIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }) })
    }
    suspend fun applications(jobId: String): List<ApplicationRow> = db.from("applications").select { filter { eq("job_id", jobId) } }.decodeList()
    suspend fun setApplicationStatus(id: String, status: String) { db.from("applications").update({ set("status", status) }) { filter { eq("id", id) } } }

    // ---------- settings, blocking, sync ----------
    suspend fun mySettings(me: String): SettingsRow = db.from("user_settings").select { filter { eq("profile_id", me) } }.decodeSingleOrNull() ?: SettingsRow(me)
    suspend fun saveSettings(row: SettingsRow) { db.from("user_settings").upsert(row) }
    suspend fun block(me: String, other: String) { db.from("blocks").insert(buildJsonObject { put("blocker_id", me); put("blocked_id", other) }) }
    suspend fun unblock(me: String, other: String) { db.from("blocks").delete { filter { eq("blocker_id", me); eq("blocked_id", other) } } }
    suspend fun blocked(): List<BlockRow> = db.from("blocks").select().decodeList()
    /** Returns PENDING, or ACCEPTED when they had already asked to sync with me. */
    suspend fun sync(other: String): String = db.rpc("request_sync", buildJsonObject { put("p_other", other) }).decodeAs()
    suspend fun unsync(me: String, other: String) {
        db.from("syncs").delete { filter { or { and { eq("requester_id", me); eq("addressee_id", other) }; and { eq("requester_id", other); eq("addressee_id", me) } } } }
    }
    suspend fun closeFriends(): List<String> = db.from("close_friends").select().decodeList<CloseFriendRow>().map { it.friendId }
    suspend fun setCloseFriend(me: String, friend: String, on: Boolean) {
        if (on) db.from("close_friends").upsert(buildJsonObject { put("profile_id", me); put("friend_id", friend) })
        else db.from("close_friends").delete { filter { eq("profile_id", me); eq("friend_id", friend) } }
    }

    // ---------- messaging ----------
    suspend fun inbox(): List<InboxRow> = db.rpc("inbox").decodeList()
    suspend fun startDirect(other: String): String = db.rpc("start_direct", buildJsonObject { put("p_other", other) }).decodeAs()
    suspend fun startListingChat(listingId: String): String = db.rpc("start_listing_chat", buildJsonObject { put("p_listing", listingId) }).decodeAs()
    suspend fun createGroup(title: String, members: List<String>): String =
        db.rpc("create_group", buildJsonObject { put("p_title", title); put("p_members", buildJsonArray { members.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }) }).decodeAs()
    suspend fun messages(conversationId: String, limit: Long = 50): List<MessageRow> =
        db.from("messages").select { filter { eq("conversation_id", conversationId) }; order("created_at", Order.DESCENDING); limit(limit) }.decodeList<MessageRow>().reversed()
    suspend fun send(conversationId: String, me: String, body: String, attachment: FileRef? = null, replyTo: String? = null): MessageRow =
        db.from("messages").insert(buildJsonObject {
            put("conversation_id", conversationId); put("sender_id", me); put("body", body); replyTo?.let { put("reply_to", it) }
            attachment?.let { a -> put("attachment", buildJsonObject { put("path", a.path); put("name", a.name); put("mime", a.mime); put("size", a.size) }) }
        }) { select() }.decodeSingle()
    suspend fun editMessage(id: String, body: String) { db.from("messages").update({ set("body", body) }) { filter { eq("id", id) } } }
    suspend fun deleteMessage(id: String) { db.from("messages").update({ set("deleted_at", "now()") }) { filter { eq("id", id) } } }
    suspend fun markRead(conversationId: String) { db.rpc("mark_read", buildJsonObject { put("p_conv", conversationId) }) }
    suspend fun seenUpTo(conversationId: String): String? = db.rpc("seen_up_to", buildJsonObject { put("p_conv", conversationId) }).data.trim().trim('"').takeIf { it.isNotEmpty() && it != "null" }
    suspend fun mute(conversationId: String, me: String, untilIso: String?) {
        db.from("conversation_members").update({ set("muted_until", untilIso) }) { filter { eq("conversation_id", conversationId); eq("profile_id", me) } }
    }
    /** New messages in a conversation as they arrive (row-level security still applies). Close the channel when the screen goes away. */
    fun liveMessages(conversationId: String): Pair<RealtimeChannel, Flow<MessageRow>> {
        val channel = client.channel("conv-$conversationId-${System.nanoTime()}")
        val flow = channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") { table = "messages"; filter("conversation_id", FilterOperator.EQ, conversationId) }
            .map { it.decodeRecord<MessageRow>() }
            .onStart { channel.subscribe() }
        return channel to flow
    }
    suspend fun closeChannel(channel: RealtimeChannel) { runCatching { client.realtime.removeChannel(channel) } }

    // ---------- files (Supabase Storage) ----------
    /** Uploads to a private bucket; the first folder decides who may read it (see storage policies in schema.sql). */
    suspend fun upload(bucket: String, path: String, bytes: ByteArray) { client.storage.from(bucket).upload(path, bytes) { upsert = false } }
    suspend fun signedUrl(bucket: String, path: String): String = client.storage.from(bucket).createSignedUrl(path, 1.hours)
    fun publicUrl(bucket: String, path: String): String = client.storage.from(bucket).publicUrl(path)

    // ---------- feed ----------
    suspend fun feed(at: LatLng, beforeIso: String? = null): List<FeedRow> =
        db.rpc("feed", buildJsonObject { put("lat", at.lat); put("lng", at.lng); beforeIso?.let { put("before", it) } }).decodeList()
    suspend fun post(me: String, body: String, media: List<String>, visibility: String, at: LatLng?, area: String, listingId: String? = null) {
        db.from("posts").insert(buildJsonObject {
            put("author_id", me); put("body", body); put("visibility", visibility); put("area", area); listingId?.let { put("listing_id", it) }
            at?.let { put("location", point(it)) }
            put("media", buildJsonArray { media.forEach { add(buildJsonObject { put("path", it) }) } })
        })
    }
    suspend fun deletePost(id: String) { db.from("posts").delete { filter { eq("id", id) } } }
    suspend fun vote(postId: String, me: String, vote: Int) {
        if (vote == 0) db.from("post_votes").delete { filter { eq("post_id", postId); eq("profile_id", me) } }
        else db.from("post_votes").upsert(buildJsonObject { put("post_id", postId); put("profile_id", me); put("vote", vote) })
    }
    suspend fun comments(postId: String): List<CommentRow> = db.from("post_comments").select { filter { eq("post_id", postId) }; order("created_at", Order.ASCENDING) }.decodeList()
    suspend fun comment(postId: String, me: String, body: String) { db.from("post_comments").insert(buildJsonObject { put("post_id", postId); put("author_id", me); put("body", body) }) }

    // ---------- moments ----------
    suspend fun momentsTray(at: LatLng): List<TrayRow> = db.rpc("moments_tray", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList()
    suspend fun momentsOf(author: String, at: LatLng): List<MomentRow> = db.rpc("moments_of", buildJsonObject { put("p_author", author); put("lat", at.lat); put("lng", at.lng) }).decodeList()
    suspend fun postMoment(me: String, mediaPath: String, type: String, caption: String, audience: String, at: LatLng?, listingId: String? = null) {
        db.from("moments").insert(buildJsonObject {
            put("author_id", me); put("media_path", mediaPath); put("media_type", type); put("caption", caption); put("audience", audience)
            listingId?.let { put("listing_id", it) }; at?.let { put("location", point(it)) }
        })
    }
    suspend fun deleteMoment(id: String) { db.from("moments").delete { filter { eq("id", id) } } }
    suspend fun viewMoment(id: String, reaction: String? = null) { db.rpc("view_moment", buildJsonObject { put("p_moment", id); put("p_reaction", reaction) }) }
    suspend fun momentViewers(id: String): List<ViewerRow> = db.rpc("moment_viewers", buildJsonObject { put("p_moment", id) }).decodeList()
    suspend fun replyToMoment(id: String, body: String): String = db.rpc("reply_to_moment", buildJsonObject { put("p_moment", id); put("p_body", body) }).decodeAs()
    suspend fun muteMoments(me: String, other: String, on: Boolean) {
        if (on) db.from("moment_mutes").upsert(buildJsonObject { put("profile_id", me); put("muted_id", other) })
        else db.from("moment_mutes").delete { filter { eq("profile_id", me); eq("muted_id", other) } }
    }

    // ---------- suggestions ----------
    suspend fun suggestPeople(at: LatLng): List<PersonSuggestion> = db.rpc("suggest_people", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList()
    suspend fun suggestListings(at: LatLng): List<ListingSuggestion> = db.rpc("suggest_listings", buildJsonObject { put("lat", at.lat); put("lng", at.lng) }).decodeList()
}

// ---------- rows, named as in schema.sql ----------

@Serializable data class ProfileRow(val id: String, @SerialName("short_code") val shortCode: String, val name: String = "", val bio: String = "", val area: String = "",
    @SerialName("photo_url") val photoUrl: String? = null, @SerialName("trust_up") val trustUp: Int = 0, @SerialName("trust_down") val trustDown: Int = 0)
@Serializable data class SyncRow(@SerialName("requester_id") val requesterId: String, @SerialName("addressee_id") val addresseeId: String, val status: String)
@Serializable data class ListingRow(val id: String, val kind: String, @SerialName("owner_id") val ownerId: String, val title: String, val category: String = "", val description: String = "",
    @SerialName("photo_url") val photoUrl: String? = null, val area: String = "", val details: JsonObject = JsonObject(emptyMap()), val status: String = "PENDING", val online: Boolean = false,
    @SerialName("trust_up") val trustUp: Int = 0, @SerialName("trust_down") val trustDown: Int = 0)
@Serializable data class SearchHit(val id: String, val kind: String, val title: String, val category: String = "", val description: String = "", @SerialName("photo_url") val photoUrl: String? = null,
    val area: String = "", val online: Boolean = false, @SerialName("trust_up") val trustUp: Int = 0, @SerialName("trust_down") val trustDown: Int = 0, val details: JsonObject = JsonObject(emptyMap()),
    @SerialName("distance_m") val distanceM: Double = 0.0, @SerialName("matched_item") val matchedItem: String? = null, @SerialName("min_price") val minPrice: Int? = null)
@Serializable data class MemberRow(@SerialName("listing_id") val listingId: String, @SerialName("profile_id") val profileId: String, val role: String)
@Serializable data class ItemRow(val id: String? = null, @SerialName("listing_id") val listingId: String, val kind: String = "PRODUCT", val name: String, val price: Int, val mrp: Int? = null,
    val unit: String = "", @SerialName("group_name") val group: String = "", @SerialName("photo_url") val photoUrl: String? = null, @SerialName("in_stock") val inStock: Boolean = true, val sort: Int = 0)
@Serializable data class PostRow(val id: String, @SerialName("author_id") val authorId: String, @SerialName("listing_id") val listingId: String? = null, val body: String = "",
    val media: kotlinx.serialization.json.JsonArray = kotlinx.serialization.json.JsonArray(emptyList()), val visibility: String = "LOCAL", val up: Int = 0, val down: Int = 0, val comments: Int = 0, @SerialName("created_at") val createdAt: String)
@Serializable data class InviteRow(val id: String, @SerialName("listing_id") val listingId: String? = null, @SerialName("vehicle_id") val vehicleId: String? = null,
    @SerialName("inviter_id") val inviterId: String, @SerialName("invitee_id") val inviteeId: String, val role: String, val status: String)
@Serializable data class VehicleRow(val id: String, @SerialName("owner_id") val ownerId: String, val kind: String, val model: String = "", val plate: String, val status: String = "PENDING")
@Serializable data class VehicleStat(@SerialName("vehicle_id") val vehicleId: String, val plate: String, val model: String = "", val kind: String, val accepted: Int = 0, val rejected: Int = 0,
    val completed: Int = 0, val km: Double = 0.0, val earnings: Int = 0)
@Serializable data class TaskRow(val id: String, val type: String, @SerialName("requester_id") val requesterId: String, @SerialName("order_id") val orderId: String? = null,
    @SerialName("vehicle_kind") val vehicleKind: String, @SerialName("pickup_label") val pickupLabel: String = "", @SerialName("drop_label") val dropLabel: String = "", val km: Double = 0.0,
    val fare: Int = 0, val pin: String = "", val status: String, @SerialName("driver_id") val driverId: String? = null, @SerialName("paid_with") val paidWith: String? = null)
@Serializable data class ContactRow(val phone: String? = null, @SerialName("upi_uri") val upiUri: String? = null)
@Serializable data class OrderRow(val id: String, @SerialName("listing_id") val listingId: String, @SerialName("buyer_id") val buyerId: String, val subtotal: Int, @SerialName("delivery_fee") val deliveryFee: Int = 0,
    @SerialName("fee_paid_by") val feePaidBy: String = "BUYER", @SerialName("delivery_mode") val deliveryMode: String = "MARKETPLACE", val payment: String = "UPI",
    @SerialName("drop_label") val dropLabel: String = "", val status: String, @SerialName("accept_by") val acceptBy: String, @SerialName("created_at") val createdAt: String)
@Serializable data class ReviewRow(val id: String, @SerialName("listing_id") val listingId: String, @SerialName("author_id") val authorId: String, val vote: Int, val comment: String, @SerialName("created_at") val createdAt: String)
@Serializable data class JobRow(val id: String, @SerialName("listing_id") val listingId: String, val title: String, val description: String = "", val pay: String = "", @SerialName("job_type") val jobType: String = "FULL_TIME", val open: Boolean = true)
@Serializable data class ApplicationRow(val id: String, @SerialName("job_id") val jobId: String, @SerialName("applicant_id") val applicantId: String,
    @SerialName("skill_listing_ids") val skillListingIds: List<String> = emptyList(), val note: String = "", val status: String)

/** A file already uploaded to the "chat" bucket at [path]. */
data class FileRef(val path: String, val name: String, val mime: String, val size: Long)

@Serializable data class SettingsRow(@SerialName("profile_id") val profileId: String, @SerialName("who_can_message") val whoCanMessage: String = "SYNCED",
    @SerialName("who_can_sync") val whoCanSync: String = "EVERYONE", @SerialName("moments_audience") val momentsAudience: String = "SYNCED",
    @SerialName("read_receipts") val readReceipts: Boolean = true, @SerialName("show_online") val showOnline: Boolean = true, val discoverable: Boolean = true,
    val notify: JsonObject = JsonObject(emptyMap()), @SerialName("quiet_hours") val quietHours: JsonObject? = null, val app: JsonObject = JsonObject(emptyMap()))
@Serializable data class BlockRow(@SerialName("blocker_id") val blockerId: String, @SerialName("blocked_id") val blockedId: String)
@Serializable data class CloseFriendRow(@SerialName("profile_id") val profileId: String, @SerialName("friend_id") val friendId: String)
@Serializable data class InboxRow(@SerialName("conversation_id") val conversationId: String, val kind: String, val title: String? = null, @SerialName("other_id") val otherId: String? = null,
    @SerialName("other_name") val otherName: String? = null, @SerialName("other_code") val otherCode: String? = null, @SerialName("last_body") val lastBody: String? = null,
    @SerialName("last_at") val lastAt: String, val unread: Int = 0, val muted: Boolean = false, val archived: Boolean = false)
@Serializable data class MessageRow(val id: String, @SerialName("conversation_id") val conversationId: String, @SerialName("sender_id") val senderId: String, val body: String = "",
    val attachment: JsonObject? = null, @SerialName("reply_to") val replyTo: String? = null, @SerialName("moment_id") val momentId: String? = null,
    @SerialName("created_at") val createdAt: String, @SerialName("edited_at") val editedAt: String? = null, @SerialName("deleted_at") val deletedAt: String? = null)
@Serializable data class FeedRow(val id: String, @SerialName("author_id") val authorId: String, @SerialName("author_name") val authorName: String, @SerialName("author_code") val authorCode: String,
    @SerialName("listing_id") val listingId: String? = null, @SerialName("listing_title") val listingTitle: String? = null, val body: String = "",
    val media: kotlinx.serialization.json.JsonArray = kotlinx.serialization.json.JsonArray(emptyList()), val visibility: String, val area: String = "", val up: Int = 0, val down: Int = 0,
    val comments: Int = 0, @SerialName("my_vote") val myVote: Int? = null, @SerialName("created_at") val createdAt: String, val synced: Boolean = false)
@Serializable data class CommentRow(val id: String, @SerialName("post_id") val postId: String, @SerialName("author_id") val authorId: String, val body: String, @SerialName("created_at") val createdAt: String)
@Serializable data class TrayRow(@SerialName("author_id") val authorId: String, @SerialName("author_name") val authorName: String, @SerialName("author_code") val authorCode: String,
    @SerialName("listing_title") val listingTitle: String? = null, val moments: Int, val unseen: Int, @SerialName("latest_at") val latestAt: String, @SerialName("is_me") val isMe: Boolean)
@Serializable data class MomentRow(val id: String, @SerialName("author_id") val authorId: String, @SerialName("media_path") val mediaPath: String, @SerialName("media_type") val mediaType: String,
    val caption: String = "", val audience: String, @SerialName("created_at") val createdAt: String, @SerialName("expires_at") val expiresAt: String)
@Serializable data class ViewerRow(@SerialName("viewer_id") val viewerId: String, val name: String, val reaction: String? = null, @SerialName("viewed_at") val viewedAt: String)
@Serializable data class PersonSuggestion(val id: String, val name: String, @SerialName("short_code") val shortCode: String, val area: String = "", val mutual: Int = 0, @SerialName("distance_m") val distanceM: Double? = null)
@Serializable data class ListingSuggestion(val id: String, val kind: String, val title: String, val category: String = "", val area: String = "",
    @SerialName("synced_recommenders") val syncedRecommenders: Int = 0, @SerialName("distance_m") val distanceM: Double? = null)
