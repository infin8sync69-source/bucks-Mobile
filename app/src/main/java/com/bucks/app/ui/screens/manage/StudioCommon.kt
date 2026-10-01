package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.ComplianceRow
import com.bucks.app.data.ItemRow
import com.bucks.app.data.ListingRow
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/* Shared pieces of the Studio: asset vocabulary, money, covers and the go-live checklist. */

/** Asset types. The property ones (studio.sql asset_service) belong to Properties and need the owner's ID checked. */
internal val ASSET_TYPES = listOf("House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space", "Vehicle", "Equipment", "Other")
internal val PROPERTY_TYPES = setOf("House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space")
internal val RESIDENTIAL_TYPES = setOf("House", "Flat", "Villa", "PG / Room")
/** Listing mode: what the owner wants to do with the asset. */
internal val ASSET_MODES = listOf("SELL" to "Sell", "RENT" to "Rent", "LEASE" to "Lease", "PG" to "PG / Hostel")
internal val PRICE_UNITS = listOf("TOTAL" to "Total", "MONTH" to "per month", "YEAR" to "per year", "DAY" to "per day")
internal val FURNISHING = listOf("Unfurnished", "Semi-furnished", "Furnished")

internal fun assetModeLabel(m: String) = ASSET_MODES.firstOrNull { it.first == m }?.second ?: m.lowercase().replaceFirstChar { it.uppercase() }
internal fun assetIcon(type: String): ImageVector = when (type) {
    "House", "Villa" -> Icons.Rounded.Home
    "Flat", "PG / Room" -> Icons.Rounded.Apartment
    "Plot / Land" -> Icons.Rounded.Place
    "Shop", "Commercial space" -> Icons.Rounded.Storefront
    "Office" -> Icons.Rounded.Work
    "Warehouse" -> Icons.Rounded.Inventory2
    "Vehicle" -> Icons.Rounded.DirectionsCar
    "Equipment" -> Icons.Rounded.Handyman
    else -> Icons.Rounded.Apartment
}

/** 150000 -> "1,50,000" (Indian grouping). */
internal fun rupees(n: Long): String {
    val s = kotlin.math.abs(n).toString()
    val grouped = if (s.length <= 3) s else s.dropLast(3).reversed().chunked(2).joinToString(",").reversed() + "," + s.takeLast(3)
    return (if (n < 0) "-₹" else "₹") + grouped
}
internal fun rupees(n: Int) = rupees(n.toLong())

internal fun JsonObject.num(k: String): Double? = (this[k] as? JsonPrimitive)?.doubleOrNull
/** "Rent · ₹28,000 per month" for an asset's details; "Price on request" when it has none. */
internal fun assetPriceLine(d: JsonObject): String {
    val mode = d.str("mode"); val price = d.num("price")?.toLong()
    val unit = PRICE_UNITS.firstOrNull { it.first == d.str("price_unit").ifBlank { "TOTAL" } }?.second.orEmpty()
    val money = if (price == null || price == 0L) "Price on request" else rupees(price) + if (unit.isNotBlank() && unit != "Total") " $unit" else ""
    return listOfNotNull(assetModeLabel(mode).takeIf { mode.isNotBlank() }, money).joinToString(" · ")
}

/** A listing's cover: its photo, or a soft brand gradient with the kind's icon when it has none. */
@Composable
internal fun ListingCover(l: ListingRow, modifier: Modifier) {
    val url = l.photoUrl?.takeIf { it.isNotBlank() } ?: l.gallery.firstOrNull()?.url
    if (url != null) AsyncImage(url, null, modifier.background(MaterialTheme.colorScheme.surfaceContainer), contentScale = ContentScale.Crop)
    else Box(modifier.background(Brush.linearGradient(listOf(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.surfaceContainerHigh))), contentAlignment = Alignment.Center) {
        Icon(studioIcon(l), null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}
internal fun studioIcon(l: ListingRow): ImageVector = if (l.kind == "ASSET") assetIcon(l.category) else listingIcon(l.kind, l.category)

/** Status pill used on cards and the dashboard. */
@Composable
internal fun ListingStatusPill(l: ListingRow, recs: Int) = when (l.status) {
    "LIVE" -> if (l.online) PillGood(if (l.kind == "ASSET") "Live · available" else "Live · ${onlineLabel(l.kind, true).lowercase()}") else PillGrey("Live · ${onlineLabel(l.kind, false).lowercase()}")
    "SUSPENDED" -> PillBad(if (l.complianceHold) "Paused: documents" else "Suspended")
    else -> PillWarn("Not live · $recs of $NEEDED recommendations")
}

/** One step towards going live. [required] steps are what the server checks; the others make the listing worth finding. */
internal data class GoLiveStep(val title: String, val detail: String, val done: Boolean, val required: Boolean, val waiting: Boolean = false, val action: String? = null, val target: String)

/**
 * The go-live checklist for [l]. Targets: EDIT, PHOTOS, ITEMS, VEHICLES, DOCS, RECOMMEND.
 * [items] and [compliance] are null while loading (the step shows as not done yet).
 */
internal fun goLiveSteps(l: ListingRow, items: List<ItemRow>?, compliance: List<ComplianceRow>?, recs: Int, hasVehicle: Boolean): List<GoLiveStep> {
    val steps = ArrayList<GoLiveStep>()
    val detailsDone = l.description.trim().length >= 20 && (l.kind != "ASSET" || (l.details.num("price") ?: 0.0) > 0)
    steps += GoLiveStep("Describe it", if (l.kind == "ASSET") "A few lines and the price, so people know what they're looking at." else "A few lines about what you do, so people pick you.", detailsDone, false, action = "Edit", target = "EDIT")
    val photos = !l.photoUrl.isNullOrBlank() || l.gallery.isNotEmpty()
    steps += GoLiveStep(if (l.kind == "SKILL") "Show your work" else "Add photos", when (l.kind) { "SKILL" -> "Photos of jobs you've done build trust fast."; "ASSET" -> "Listings with 4+ photos get far more enquiries."; else -> "A cover photo and a few of the place or products." }, photos, false, action = "Add", target = "PHOTOS")
    when (l.kind) {
        "BUSINESS" -> steps += GoLiveStep("Add products", "Put in what you sell with prices, so customers can order.", !items.isNullOrEmpty(), false, action = "Add", target = "ITEMS")
        "SKILL" -> steps += GoLiveStep("Add services and prices", "\"Tap repair · ₹300 per visit\". People request from this list.", !items.isNullOrEmpty(), false, action = "Add", target = "ITEMS")
        "DRIVER" -> steps += GoLiveStep("Add your vehicle", "With its RC, insurance and your licence. Bucks checks them before you can go online.", hasVehicle, true, action = "Open", target = "VEHICLES")
    }
    val needs = compliance.orEmpty().filter { it.required }
    if (l.kind != "DRIVER" && (compliance == null || needs.isNotEmpty())) {
        val verified = needs.count { it.status == "VERIFIED" }; val pending = needs.count { it.status == "PENDING" }
        steps += GoLiveStep("Documents", when {
            compliance == null -> "Checking what's needed…"
            verified == needs.size -> "All ${needs.size} required document${if (needs.size == 1) "" else "s"} checked by Bucks."
            pending > 0 && verified + pending == needs.size -> "Uploaded. Bucks is checking them."
            else -> "${needs.size - verified - pending} required document${if (needs.size - verified - pending == 1) "" else "s"} to upload. Only Bucks sees the files."
        }, compliance != null && verified == needs.size, true, waiting = pending > 0 && verified + pending == needs.size, action = "Upload", target = "DOCS")
    }
    steps += GoLiveStep("Get recommended", "$recs of $NEEDED people nearby have recommended you in person.", recs >= NEEDED, true, action = "Show code", target = "RECOMMEND")
    return steps
}

/** A tick, a clock or an empty circle with the step, and its action. */
@Composable
internal fun GoLiveRow(s: GoLiveStep, onAction: () -> Unit) {
    val st = MaterialTheme.status
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(when { s.done -> st.goodTint; s.waiting -> st.warnTint; else -> MaterialTheme.colorScheme.surfaceContainerHigh }), contentAlignment = Alignment.Center) {
            Icon(when { s.done -> Icons.Rounded.Check; s.waiting -> Icons.Rounded.Schedule; else -> Icons.Rounded.RadioButtonUnchecked }, null, Modifier.size(16.dp),
                tint = when { s.done -> st.good; s.waiting -> st.warn; else -> MaterialTheme.colorScheme.onSurfaceVariant })
        }
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.title, style = MaterialTheme.typography.titleSmall); if (s.required && !s.done) PillPurple("Needed to go live")
            }
            Muted(s.detail)
        }
        if (!s.done && s.action != null) SmallButton(s.action, tonal = true, onClick = onAction)
    }
}

/** A vehicle document: what it is, whether Bucks needs it before the vehicle can go online, and how to photograph it. */
internal data class DocKind(val key: String, val label: String, val required: Boolean, val hint: String)
internal fun vehicleDocKinds(vehicleKind: String) = listOf(
    DocKind("RC", "Registration certificate (RC)", true, "Both sides, with the number plate readable."),
    DocKind("INSURANCE", "Insurance", true, "The current policy page showing the vehicle number and dates."),
    DocKind("DL", "Driving licence", true, "Your licence, both sides. Drivers you invite add theirs from their own phone."),
    DocKind("PERMIT", "Permit", vehicleKind != "BIKE", if (vehicleKind == "BIKE") "Only if you carry goods commercially." else "Contract carriage or auto permit for passengers."),
    DocKind("PUC", "Pollution certificate (PUC)", false, "Valid PUC. Not needed for electric vehicles."),
)
