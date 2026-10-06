package com.bucks.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.graphics.vector.ImageVector
import com.bucks.app.data.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * One tile of the Services menu. The server decides whether it is open where the customer stands (services_near); this is
 * what only the app needs: the icon, what the supply side is asked to do, and the categories a business of it can pick.
 */
data class ServiceDef(
    val key: String, val label: String, val icon: ImageVector,
    /** Button on the locked sheet that asks providers to join ("Run a restaurant? List it"). */
    val joinPrompt: String, val joinAction: String,
    /** Categories a business of this service can pick (empty for services that are not businesses). */
    val categories: List<String> = emptyList(),
)

val SERVICE_CATALOG = listOf(
    ServiceDef("TAXI", "Taxi", Icons.Rounded.LocalTaxi, "Drive a cab?", "Add your cab"),
    ServiceDef("AUTO", "Auto", Icons.Rounded.ElectricRickshaw, "Drive an auto?", "Add your auto"),
    ServiceDef("PARCEL", "Parcel", Icons.Rounded.DeliveryDining, "Ride a bike?", "Add your bike"),
    ServiceDef("FOOD", "Food", Icons.Rounded.Restaurant, "Run a restaurant?", "List it", listOf("Restaurant", "Bakery", "Cafe", "Sweets", "Cloud kitchen", "Tiffin")),
    ServiceDef("GROCERY", "Grocery", Icons.Rounded.LocalGroceryStore, "Run a grocery store?", "List it", listOf("Grocery", "Supermarket", "Dairy")),
    ServiceDef("VEGETABLES", "Vegetables", Icons.Rounded.Eco, "Sell vegetables or fruit?", "List your stall", listOf("Vegetables", "Fruits")),
    ServiceDef("MEAT", "Meat", Icons.Rounded.KebabDining, "Run a meat or fish shop?", "List it", listOf("Chicken", "Mutton", "Fish", "Eggs")),
    ServiceDef("SHOPPING", "Shopping", Icons.Rounded.ShoppingBag, "Run a shop?", "List it", listOf("Electronics", "Mobile repair", "Hardware", "Furniture", "Clothing", "Stationery", "Salon", "Tailor", "Other")),
    ServiceDef("GIGS", "Gigs", Icons.Rounded.Handyman, "Have a skill?", "Offer it"),
    ServiceDef("JOBS", "Jobs", Icons.Rounded.Work, "Hiring?", "Post a job from your business"),
    ServiceDef("PROPERTIES", "Properties", Icons.Rounded.Apartment, "Have a place to rent or sell?", "List it", listOf("Property owner", "Real estate agent", "Builder")),
)
fun serviceDef(key: String?): ServiceDef? = SERVICE_CATALOG.firstOrNull { it.key == key }
/** The services a BUSINESS listing can belong to (skills are always Gigs, drivers have none). */
val BUSINESS_SERVICES = listOf("FOOD", "GROCERY", "VEGETABLES", "MEAT", "SHOPPING", "PROPERTIES")
/** Same mapping as service_for_category() on the server, for listings saved before a service was chosen. */
fun serviceForCategory(category: String?): String {
    val c = category?.trim()?.lowercase()
    BUSINESS_SERVICES.firstOrNull { k -> serviceDef(k)!!.categories.any { it.equals(c, ignoreCase = true) } }?.let { return it }
    return when (c) {
        "catering", "juice bar", "ice cream", "street food", "food truck" -> "FOOD"
        "kirana", "organic store" -> "GROCERY"
        else -> "SHOPPING"
    }
}

/** Demo builds (no backend): the pilot's services open, everything else "coming soon". */
private val DEMO_OPEN = setOf("TAXI", "AUTO", "JOBS")
private fun demoStates() = SERVICE_CATALOG.map { ServiceState(it.key, it.label, state = if (it.key in DEMO_OPEN) "OPEN" else "SOON") }

/**
 * Service unlocking and listing documents. Same shape as [Social]: Compose state plus actions wrapped in go { }, so every
 * failure reaches the person as a toast.
 */
class Services(private val scope: CoroutineScope, private val social: Social, private val toast: (String) -> Unit) {
    /** Every service in menu order, as seen from [Social.here]. Demo builds get fixed states. */
    var rows by mutableStateOf(if (social.enabled) emptyList() else demoStates()); private set
    var loaded by mutableStateOf(!social.enabled); private set
    var error by mutableStateOf<String?>(null); private set
    /** listing id -> documents its service asks for. */
    val compliance: SnapshotStateMap<String, List<ComplianceRow>> = mutableStateMapOf()
    /** listing id -> verified documents shown on its public profile. */
    val badges: SnapshotStateMap<String, List<BadgeRow>> = mutableStateMapOf()
    /** Document type uploading right now, for the spinner on its row. */
    var uploading by mutableStateOf<String?>(null); private set
    var isStaff by mutableStateOf(false); private set
    var reviewQueue by mutableStateOf<List<ReviewItem>>(emptyList()); private set
    var reviewLoaded by mutableStateOf(false); private set

    private fun go(block: suspend () -> Unit) = scope.launch { try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { toast(friendly(e)) } }
    private fun friendly(e: Exception): String = e.message?.lineSequence()?.firstOrNull()?.substringAfter("ERROR: ")?.takeIf { it.isNotBlank() && it.length < 160 }
        ?.replaceFirstChar { it.uppercase() } ?: "Couldn't reach Bucks. Check your connection and try again."

    fun state(key: String): ServiceState? = rows.firstOrNull { it.key == key }

    /** Re-reads every service's state around where I am. */
    fun refresh() {
        if (!social.enabled) return
        scope.launch {
            try { rows = Backend.servicesNear(social.here); loaded = true; error = null }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = friendly(e); if (rows.isEmpty()) rows = SERVICE_CATALOG.map { ServiceState(it.key, it.label, state = "LOCKED") } }
        }
    }

    fun toggleInterest(key: String) = go {
        val on = Backend.toggleServiceInterest(key, social.here)
        rows = rows.map { if (it.key == key) it.copy(mine = on, interested = (it.interested + if (on) 1 else -1).coerceAtLeast(0)) else it }
        val label = serviceDef(key)?.label ?: "it"
        toast(if (on) "We'll let you know when $label opens near you." else "You won't get a note about $label.")
    }

    // ---------- listing documents ----------
    fun loadCompliance(listingId: String) = go { compliance[listingId] = Backend.listingCompliance(listingId) }
    fun loadBadges(listingId: String) = go { badges[listingId] = Backend.listingBadges(listingId) }

    /**
     * Uploads [file] to my private docs folder, then asks the server to record it (submit_document checks the number, expiry
     * and service). A rejected submit removes the uploaded file again; a replaced document's old file is removed after.
     */
    fun submit(listingId: String, row: ComplianceRow, file: Picked, number: String, expires: String?, onDone: () -> Unit = {}) = go {
        val me = social.me?.id ?: return@go
        uploading = row.docType
        try {
            val path = "$me/listing-${row.docType.lowercase()}-${file.objectName()}"
            Backend.upload("docs", path, file.bytes)
            try { Backend.submitDocument(listingId, row.docType, path, number.trim(), expires) }
            catch (e: Exception) { runCatching { Backend.deleteFiles("docs", listOf(path)) }; throw e }
            row.path?.takeIf { it != path && it.startsWith("$me/") }?.let { old -> runCatching { Backend.deleteFiles("docs", listOf(old)) } }
            toast("${row.label} sent. Bucks checks documents within two working days.")
            compliance[listingId] = Backend.listingCompliance(listingId)
            onDone()
        } finally { uploading = null }
    }

    fun remove(listingId: String, row: ComplianceRow) = go {
        Backend.deleteDocument(listingId, row.docType)
        val me = social.me?.id
        row.path?.takeIf { me != null && it.startsWith("$me/") }?.let { runCatching { Backend.deleteFiles("docs", listOf(it)) } }
        compliance[listingId] = Backend.listingCompliance(listingId)
        toast("${row.label} removed.")
    }

    // ---------- Bucks staff: document review ----------
    fun checkStaff() { if (social.enabled) scope.launch { isStaff = runCatching { Backend.isStaff() }.getOrDefault(false) } }
    fun loadReviewQueue() = go { reviewQueue = Backend.documentsToReview(); reviewLoaded = true }
    fun review(item: ReviewItem, approve: Boolean, note: String) = go {
        Backend.reviewDocument(item.id, approve, note)
        reviewQueue = reviewQueue.filterNot { it.id == item.id }
        toast(if (approve) "${item.label} for ${item.listingTitle} approved." else "Rejected. They'll see your reason.")
    }

    /** The next account on this phone starts clean. */
    fun signedOut() {
        rows = if (social.enabled) emptyList() else demoStates(); loaded = !social.enabled; error = null
        compliance.clear(); badges.clear(); isStaff = false; reviewQueue = emptyList(); reviewLoaded = false
    }
}
