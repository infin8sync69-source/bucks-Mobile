package com.bucks.app.data

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/*
 * Showcase documents (migration showcase_docs.sql): what a business, NGO or institution shows on its profile.
 * Not the compliance documents Bucks staff check for go-live (BackendServices / listing_documents). Every call goes through a server
 * function that decides who may see what: PUBLIC to anyone, ON_REQUEST after the owner approves, PRIVATE to the team only.
 */
private val docDb get() = Backend.client.postgrest

/** A document on a profile as I see it: [canOpen] says whether I may read the file now, [myRequest] where my access request stands. */
@Serializable data class ShowcaseDoc(
    val id: String, @SerialName("listing_id") val listingId: String, val kind: String, val title: String, val issuer: String = "", val number: String = "",
    val registry: String? = null, val mime: String = "", @SerialName("size_bytes") val sizeBytes: Int = 0, val visibility: String = "ON_REQUEST",
    @SerialName("expires_on") val expiresOn: String? = null, @SerialName("bucks_checked") val bucksChecked: Boolean = false,
    @SerialName("checks_up") val checksUp: Int = 0, @SerialName("checks_down") val checksDown: Int = 0, val sort: Int = 0,
    @SerialName("created_at") val createdAt: String = "", @SerialName("can_open") val canOpen: Boolean = false,
    /** PENDING, APPROVED or DECLINED when I asked to see it; null when I haven't (or it lapsed). */
    @SerialName("my_request") val myRequest: String? = null,
    /** My opinion once I opened it: 1 looks genuine, -1 doesn't look right, null none. */
    @SerialName("my_check") val myCheck: Int? = null,
    /** For the team only: requests waiting for an answer. */
    @SerialName("pending_requests") val pendingRequests: Int = 0,
) {
    val isPdf get() = mime == "application/pdf"
    val checks get() = checksUp + checksDown
    val expired get() = expiresOn?.let { runCatching { java.time.LocalDate.parse(it.take(10)).isBefore(java.time.LocalDate.now()) }.getOrDefault(false) } ?: false
}

/** A request to see an ON_REQUEST document, or an approval still running, as the owner or an admin sees it. */
@Serializable data class DocRequest(
    val id: String, @SerialName("doc_id") val docId: String, @SerialName("doc_title") val docTitle: String,
    @SerialName("requester_id") val requesterId: String, @SerialName("requester_name") val requesterName: String = "",
    /** "Has ordered here", "Follows this page" or "No past activity here". */
    val relation: String = "", val message: String = "", val status: String, @SerialName("created_at") val createdAt: String = "", @SerialName("expires_at") val expiresAt: String = "",
)

/** Who opened which document (owner and admins only). */
@Serializable data class DocView(@SerialName("doc_title") val docTitle: String, @SerialName("viewer_id") val viewerId: String, @SerialName("viewer_name") val viewerName: String = "", @SerialName("last_at") val lastAt: String = "", val times: Int = 1)

/** Where an opened document's file is (inside my own folder of the docs bucket for the team, or the owner's folder for viewers). */
@Serializable data class OpenedDoc(val path: String, val mime: String = "", val title: String = "", @SerialName("expires_on") val expiresOn: String? = null)

/** The kinds a profile can show. "Other" lets the owner name it; the others suggest a name. */
object ShowcaseKinds {
    val all = listOf(
        Triple("REGISTRATION", "Registration", "Company, society, trust or NGO registration"),
        Triple("LICENCE", "Licence", "Trade licence, FSSAI, RERA or a professional licence"),
        Triple("TAX", "Tax", "GST, 12A / 80G or other tax registration"),
        Triple("CERTIFICATE", "Certificate", "Quality, training or safety certificate"),
        Triple("AFFILIATION", "Affiliation", "Board, university or association"),
        Triple("AWARD", "Award", "Awards and recognition"),
        Triple("REPORT", "Report", "Annual or audited report"),
        Triple("BROCHURE", "Brochure", "Brochure, catalogue or price list"),
        Triple("OTHER", "Other", "Anything else; you choose the name"),
    )
    fun label(kind: String) = all.firstOrNull { it.first == kind }?.second ?: "Document"
    /** Documents that usually carry a registration number the public can look up. */
    fun hasNumber(kind: String) = kind in setOf("REGISTRATION", "LICENCE", "TAX")
    /** Safe to show to everyone by default; the rest start as "on request". */
    fun defaultVisibility(kind: String) = if (kind in setOf("CERTIFICATE", "AFFILIATION", "AWARD", "REPORT", "BROCHURE")) "PUBLIC" else "ON_REQUEST"
}

/** Official registries a number can be checked against; the app opens the registry's own search, it does not check for you. */
object Registries {
    val all = listOf("GST" to "GST", "FSSAI" to "FSSAI", "MCA" to "Company (MCA)")
    fun url(registry: String?): String? = when (registry) {
        "GST" -> "https://services.gst.gov.in/services/searchtp"
        "FSSAI" -> "https://foscos.fssai.gov.in/"
        "MCA" -> "https://www.mca.gov.in/"
        else -> null
    }
}

suspend fun Backend.showcaseDocs(listingId: String): List<ShowcaseDoc> = docDb.rpc("showcase_docs", buildJsonObject { put("p_listing", listingId) }).decodeList()

/** Uploads [bytes] to my folder of the private docs bucket and returns the path to give [addShowcaseDoc]. */
suspend fun Backend.uploadShowcaseFile(me: String, bytes: ByteArray, mime: String): String {
    val ext = when (mime) { "application/pdf" -> "pdf"; "image/png" -> "png"; "image/webp" -> "webp"; else -> "jpg" }
    val path = "$me/showcase-${java.util.UUID.randomUUID().toString().replace("-", "")}.$ext"
    upload("docs", path, bytes)
    return path
}

suspend fun Backend.addShowcaseDoc(listingId: String, kind: String, title: String, issuer: String, number: String, registry: String?, path: String, mime: String, size: Int, visibility: String, expires: String?): String =
    docDb.rpc("add_showcase_doc", buildJsonObject {
        put("p_listing", listingId); put("p_kind", kind); put("p_title", title); put("p_issuer", issuer); put("p_number", number); put("p_registry", registry)
        put("p_path", path); put("p_mime", mime); put("p_size", size); put("p_visibility", visibility); put("p_expires", expires)
    }).decodeAs()

suspend fun Backend.updateShowcaseDoc(docId: String, title: String, issuer: String, number: String, registry: String?, visibility: String, expires: String?) {
    docDb.rpc("update_showcase_doc", buildJsonObject {
        put("p_doc", docId); put("p_title", title); put("p_issuer", issuer); put("p_number", number); put("p_registry", registry); put("p_visibility", visibility); put("p_expires", expires)
    })
}

/** Removes the document and returns its file path; call [removeShowcaseFile] with it. (Server function delete_showcase_doc.) */
suspend fun Backend.removeShowcaseDoc(docId: String): String = docDb.rpc("delete_showcase_doc", buildJsonObject { put("p_doc", docId) }).decodeAs()
/** Best effort: only the person who uploaded a file may remove it from storage. */
suspend fun Backend.removeShowcaseFile(path: String) { runCatching { deleteFiles("docs", listOf(path)) } }

/** Asks the owner to share an ON_REQUEST document. Returns PENDING, or APPROVED when I already have access. */
suspend fun Backend.requestDocAccess(docId: String, message: String): String = docDb.rpc("request_doc_access", buildJsonObject { put("p_doc", docId); put("p_message", message) }).decodeAs()
suspend fun Backend.decideDocRequest(requestId: String, approve: Boolean, days: Int = 30): String =
    docDb.rpc("decide_doc_request", buildJsonObject { put("p_req", requestId); put("p_approve", approve); put("p_days", days) }).decodeAs()
suspend fun Backend.revokeDocAccess(requestId: String) { docDb.rpc("revoke_doc_access", buildJsonObject { put("p_req", requestId) }) }
suspend fun Backend.docRequestsFor(listingId: String): List<DocRequest> = docDb.rpc("doc_requests_for", buildJsonObject { put("p_listing", listingId) }).decodeList()
suspend fun Backend.docViewLog(listingId: String): List<DocView> = docDb.rpc("doc_view_log", buildJsonObject { put("p_listing", listingId) }).decodeList()

/** Checks I may read it, notes that I looked, and returns where the file is. Then [downloadShowcaseFile]. */
suspend fun Backend.openShowcaseDoc(docId: String): OpenedDoc = docDb.rpc("open_showcase_doc", buildJsonObject { put("p_doc", docId) }).decodeAs()
/** Reads the file with my own sign-in, so the storage rules decide again (an approval that was revoked stops working here). */
suspend fun Backend.downloadShowcaseFile(path: String): ByteArray = client.storage.from("docs").downloadAuthenticated(path)

/** "Looks genuine" (1) or "doesn't look right" (-1) after opening a document. A viewer signal only; never Bucks verification. */
suspend fun Backend.checkShowcaseDoc(docId: String, vote: Int, comment: String) { docDb.rpc("check_showcase_doc", buildJsonObject { put("p_doc", docId); put("p_vote", vote); put("p_comment", comment) }) }
suspend fun Backend.clearShowcaseCheck(docId: String) { docDb.rpc("clear_showcase_check", buildJsonObject { put("p_doc", docId) }) }
