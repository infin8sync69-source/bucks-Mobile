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
import com.bucks.app.ui.PageType
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.data.Str

/* Shared pieces of the Studio: asset vocabulary, money, covers and the go-live checklist. */

/** Asset types. The property ones (studio.sql asset_service) belong to Properties and need the owner's ID checked. */
internal val ASSET_TYPES = listOf("House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space", "Vehicle", "Equipment", "Other")
internal val PROPERTY_TYPES = setOf("House", "Flat", "Villa", "Plot / Land", "Shop", "Office", "Warehouse", "PG / Room", "Commercial space")
internal val RESIDENTIAL_TYPES = setOf("House", "Flat", "Villa", "PG / Room")
/** Listing mode: what the owner wants to do with the asset. */
internal val ASSET_MODES: List<Pair<String, String>> get() = listOf("SELL" to Str.get(R.string.g6_asset_mode_sell), "RENT" to Str.get(R.string.g6_asset_mode_rent), "LEASE" to Str.get(R.string.g6_asset_mode_lease), "PG" to Str.get(R.string.g6_asset_mode_pg))
internal val PRICE_UNITS: List<Pair<String, String>> get() = listOf("TOTAL" to Str.get(R.string.g6_price_unit_total), "MONTH" to Str.get(R.string.g6_price_unit_month), "YEAR" to Str.get(R.string.g6_price_unit_year), "DAY" to Str.get(R.string.g6_price_unit_day))
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

/** An amount in the person's country currency (see Money). */
internal fun rupees(n: Long): String = com.bucks.app.data.Money.format(n)
internal fun rupees(n: Int) = rupees(n.toLong())

internal fun JsonObject.num(k: String): Double? = (this[k] as? JsonPrimitive)?.doubleOrNull
/** "Rent · ₹28,000 per month" for an asset's details; "Price on request" when it has none. */
internal fun assetPriceLine(d: JsonObject): String {
    val mode = d.str("mode"); val price = d.num("price")?.toLong()
    val unitKey = d.str("price_unit").ifBlank { "TOTAL" }
    val unit = PRICE_UNITS.firstOrNull { it.first == unitKey }?.second.orEmpty()
    val money = if (price == null || price == 0L) Str.get(R.string.g6_price_on_request) else if (unit.isNotBlank() && unitKey != "TOTAL") Str.get(R.string.g6_price_with_unit, rupees(price), unit) else rupees(price)
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
    "LIVE" -> if (l.online) PillGood(if (l.kind == "ASSET") stringResource(R.string.g6_pill_live_available) else stringResource(R.string.g6_pill_live_state, onlineLabel(l, true))) else PillGrey(stringResource(R.string.g6_pill_live_state, onlineLabel(l, false)))
    "SUSPENDED" -> PillBad(if (l.complianceHold) stringResource(R.string.g6_pill_paused_docs) else stringResource(R.string.g6_pill_suspended))
    else -> PillWarn(pluralStringResource(R.plurals.g6_pill_not_live, NEEDED, recs, NEEDED))
}

/** One step towards going live. [required] steps are what the server checks; the others make the listing worth finding. */
internal data class GoLiveStep(val title: String, val detail: String, val done: Boolean, val required: Boolean, val waiting: Boolean = false, val action: String? = null, val target: String)

/**
 * The go-live checklist for [l]. Targets: EDIT, PHOTOS, ITEMS, VEHICLES, DOCS, RECOMMEND.
 * [items] and [compliance] are null while loading (the step shows as not done yet). [type] is the page type of a business,
 * which words the catalogue step (products, services, programs or events).
 */
internal fun goLiveSteps(l: ListingRow, items: List<ItemRow>?, compliance: List<ComplianceRow>?, recs: Int, hasVehicle: Boolean, type: PageType? = null): List<GoLiveStep> {
    val steps = ArrayList<GoLiveStep>()
    val detailsDone = l.description.trim().length >= 20 && (l.kind != "ASSET" || (l.details.num("price") ?: 0.0) > 0)
    steps += GoLiveStep(Str.get(R.string.g6_gl_describe), if (l.kind == "ASSET") Str.get(R.string.g6_gl_describe_asset) else Str.get(R.string.g6_gl_describe_other), detailsDone, false, action = Str.get(R.string.g6_edit), target = "EDIT")
    val photos = !l.photoUrl.isNullOrBlank() || l.gallery.isNotEmpty()
    steps += GoLiveStep(if (l.kind == "SKILL") Str.get(R.string.g6_gl_show_work) else Str.get(R.string.g6_gl_add_photos), when (l.kind) { "SKILL" -> Str.get(R.string.g6_gl_photos_skill); "ASSET" -> Str.get(R.string.g6_gl_photos_asset); else -> Str.get(R.string.g6_gl_photos_other) }, photos, false, action = Str.get(R.string.g6_add), target = "PHOTOS")
    when (l.kind) {
        "BUSINESS" -> { val itemKind = type?.newItemKind ?: "PRODUCT"
            steps += GoLiveStep(when (itemKind) { "SERVICE" -> Str.get(R.string.g6_gl_add_services); "PROGRAM" -> Str.get(R.string.g6_gl_add_programs); "EVENT" -> Str.get(R.string.g6_gl_add_events); else -> Str.get(R.string.g6_gl_add_products) }, when (itemKind) {
                "SERVICE" -> Str.get(R.string.g6_gl_services_detail, rupees(200))
                "PROGRAM" -> Str.get(R.string.g6_gl_programs_detail)
                "EVENT" -> Str.get(R.string.g6_gl_events_detail)
                else -> Str.get(R.string.g6_gl_products_detail)
            }, !items.isNullOrEmpty(), false, action = Str.get(R.string.g6_add), target = "ITEMS") }
        "SKILL" -> steps += GoLiveStep(Str.get(R.string.g6_gl_add_skill_services), Str.get(R.string.g6_gl_skill_services_detail, rupees(300)), !items.isNullOrEmpty(), false, action = Str.get(R.string.g6_add), target = "ITEMS")
        "DRIVER" -> steps += GoLiveStep(Str.get(R.string.g6_gl_add_vehicle), Str.get(R.string.g6_gl_add_vehicle_detail), hasVehicle, true, action = Str.get(R.string.g6_open), target = "VEHICLES")
    }
    val needs = compliance.orEmpty().filter { it.required }
    if (l.kind != "DRIVER" && (compliance == null || needs.isNotEmpty())) {
        val verified = needs.count { it.status == "VERIFIED" }; val pending = needs.count { it.status == "PENDING" }
        steps += GoLiveStep(Str.get(R.string.g6_gl_documents), when {
            compliance == null -> Str.get(R.string.g6_gl_docs_checking)
            verified == needs.size -> Str.plural(R.plurals.g6_gl_docs_all_checked, needs.size)
            pending > 0 && verified + pending == needs.size -> Str.get(R.string.g6_gl_docs_uploaded)
            else -> Str.plural(R.plurals.g6_gl_docs_to_upload, needs.size - verified - pending)
        }, compliance != null && verified == needs.size, true, waiting = pending > 0 && verified + pending == needs.size, action = Str.get(R.string.g6_upload), target = "DOCS")
    }
    steps += GoLiveStep(Str.get(R.string.g6_gl_get_recommended), Str.plural(R.plurals.g6_gl_recommended_detail, NEEDED, recs, NEEDED), recs >= NEEDED, true, action = Str.get(R.string.g6_gl_show_code), target = "RECOMMEND")
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
                Text(s.title, style = MaterialTheme.typography.titleSmall); if (s.required && !s.done) PillPurple(stringResource(R.string.g6_gl_needed))
            }
            Muted(s.detail)
        }
        if (!s.done && s.action != null) SmallButton(s.action, tonal = true, onClick = onAction)
    }
}

/** A vehicle document: what it is, whether Bucks needs it before the vehicle can go online, and how to photograph it. */
internal data class DocKind(val key: String, val label: String, val required: Boolean, val hint: String)
internal fun vehicleDocKinds(vehicleKind: String) = listOf(
    DocKind("RC", Str.get(R.string.g6_doc_rc), true, Str.get(R.string.g6_doc_rc_hint)),
    DocKind("INSURANCE", Str.get(R.string.g6_doc_insurance), true, Str.get(R.string.g6_doc_insurance_hint)),
    DocKind("DL", Str.get(R.string.g6_doc_dl), true, Str.get(R.string.g6_doc_dl_hint)),
    DocKind("PERMIT", Str.get(R.string.g6_doc_permit), vehicleKind != "BIKE", if (vehicleKind == "BIKE") Str.get(R.string.g6_doc_permit_hint_bike) else Str.get(R.string.g6_doc_permit_hint)),
    DocKind("PUC", Str.get(R.string.g6_doc_puc), false, Str.get(R.string.g6_doc_puc_hint)),
)
