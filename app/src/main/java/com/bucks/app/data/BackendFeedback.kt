package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The feedback board (supabase/migrations/feedback_board.sql). */
object BackendFeedback {
    private val db get() = Backend.client.postgrest
    /** [sort]: TOP or NEW. [status]: null = everything but declined. */
    suspend fun list(sort: String, status: String? = null, mine: Boolean = false): List<FeedbackRow> =
        db.rpc("feedback_list", buildJsonObject { put("sort", sort); put("p_status", status); put("mine", mine) }).decodeList()
    suspend fun post(title: String, body: String, category: String): String =
        db.rpc("feedback_post", buildJsonObject { put("p_title", title); put("p_body", body); put("p_category", category) }).decodeAs()
    suspend fun vote(id: String, on: Boolean): Int = db.rpc("feedback_vote", buildJsonObject { put("p_post", id); put("p_on", on) }).decodeAs()
    suspend fun delete(id: String) { db.rpc("feedback_delete", buildJsonObject { put("p_post", id) }) }
    suspend fun setStatus(id: String, status: String, note: String?) { db.rpc("feedback_set_status", buildJsonObject { put("p_post", id); put("p_status", status); put("p_note", note) }) }
}

@Serializable data class FeedbackRow(val id: String, val category: String, val title: String, val body: String = "", val status: String,
                                     @SerialName("staff_note") val staffNote: String = "", val votes: Int = 0, val voted: Boolean = false,
                                     @SerialName("is_mine") val isMine: Boolean = false, @SerialName("author_name") val authorName: String = "",
                                     @SerialName("created_at") val createdAt: String)
