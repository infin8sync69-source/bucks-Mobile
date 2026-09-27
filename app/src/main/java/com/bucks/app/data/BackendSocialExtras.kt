package com.bucks.app.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Social extras on top of [Backend]: the open conversation's own row (kind, title, listing), group
 * membership (list, add, remove, leave, rename) and the list of people whose Moments I've muted.
 * Row-level security in schema.sql decides what each call may see; supabase/migrations/social-extras.sql
 * adds the two group functions.
 */
private val sdb get() = Backend.client.postgrest

/** The conversation itself; null when I'm not a member (or it doesn't exist). */
suspend fun Backend.conversation(id: String): ConversationRow? =
    sdb.from("conversations").select { filter { eq("id", id) } }.decodeSingleOrNull()

/** Everyone in a conversation, admins first. Names come from [Backend.profiles]. */
suspend fun Backend.conversationMembers(conversationId: String): List<ConversationMemberRow> =
    sdb.from("conversation_members").select { filter { eq("conversation_id", conversationId) }; order("role", Order.ASCENDING) }.decodeList()

/** Leaving a group (or a listing inbox) = deleting my own membership row; the chat disappears from my inbox. */
suspend fun Backend.leaveConversation(conversationId: String, me: String) {
    sdb.from("conversation_members").delete { filter { eq("conversation_id", conversationId); eq("profile_id", me) } }
}

/** Any member may rename a GROUP (policy conv_rename); direct and listing chats keep their names. */
suspend fun Backend.renameGroup(conversationId: String, title: String) {
    sdb.from("conversations").update({ set("title", title) }) { filter { eq("id", conversationId) } }
}

/** Adds synced, unblocked people to a group I'm in. Returns how many were actually added. */
suspend fun Backend.addGroupMembers(conversationId: String, members: List<String>): Int =
    sdb.rpc("add_group_members", buildJsonObject { put("p_conv", conversationId); put("p_members", buildJsonArray { members.forEach { add(JsonPrimitive(it)) } }) }).decodeAs()

/** Group admins can remove someone; the person removed can no longer read the chat. */
suspend fun Backend.removeGroupMember(conversationId: String, member: String) {
    sdb.rpc("remove_group_member", buildJsonObject { put("p_conv", conversationId); put("p_member", member) })
}

/** People whose Moments I've hidden from my tray (row-level security returns only my own rows). */
suspend fun Backend.momentMutes(): List<MomentMuteRow> = sdb.from("moment_mutes").select().decodeList()

@Serializable data class ConversationRow(val id: String, val kind: String = "DIRECT", val title: String? = null, @SerialName("listing_id") val listingId: String? = null,
    @SerialName("created_by") val createdBy: String, @SerialName("last_message_at") val lastMessageAt: String, @SerialName("created_at") val createdAt: String)
@Serializable data class ConversationMemberRow(@SerialName("conversation_id") val conversationId: String, @SerialName("profile_id") val profileId: String, val role: String = "MEMBER",
    @SerialName("last_read_at") val lastReadAt: String, @SerialName("muted_until") val mutedUntil: String? = null, val archived: Boolean = false)
@Serializable data class MomentMuteRow(@SerialName("profile_id") val profileId: String, @SerialName("muted_id") val mutedId: String)
