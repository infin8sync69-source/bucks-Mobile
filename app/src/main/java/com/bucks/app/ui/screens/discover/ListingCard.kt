package com.bucks.app.ui.screens.discover

import com.bucks.app.data.Money
import com.bucks.app.data.Str
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.Backend
import com.bucks.app.data.SearchHit
import com.bucks.app.data.Trust
import com.bucks.app.data.listingPhoto
import com.bucks.app.ui.PageType
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.driverKind
import com.bucks.app.ui.formatDistance
import com.bucks.app.ui.kindIcon
import com.bucks.app.ui.kindLabel
import com.bucks.app.ui.proRate
import com.bucks.app.ui.str
import com.bucks.app.ui.theme.status

/**
 * The one card every search result uses, whatever its kind: photo or initials, title, type badge (the page type for a business,
 * the kind otherwise), category, distance, open/online dot, trust, and one line that says what matters for that page
 * (the matched item and the starting price for a shop, bookings for a service, programs for an NGO, the rate for a pro, the vehicle and fare for a driver).
 */
@Composable
fun ListingCard(hit: SearchHit, onClick: () -> Unit) {
    // A store that ships shows "Ships across India" instead of a distance that means nothing to a buyer far away.
    val ships = hit.details.str("ships_india") == "true"
    BucksCard(padding = 12, onClick = onClick) {
        Row(verticalAlignment = Alignment.Top) {
            ListingPhoto(Backend.listingPhoto(hit.photoUrl), hit.title, size = 56)
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(hit.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Spacer(Modifier.width(8.dp)); KindBadge(PageTypes.badge(hit.kind, hit.typeKey, ships), PageTypes.badgeIcon(hit.kind, hit.typeKey, ships))
                }
                Muted(listOfNotNull(hit.category.ifBlank { null }, if (ships && hit.distanceM > 25_000) stringResource(R.string.g1_card_ships_india) else formatDistance(hit.distanceM), hit.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) { OnlineDot(hit.online); Spacer(Modifier.width(6.dp)); Muted(onlineText(hit.kind, hit.online), maxLines = 1) }
                hit.ownerName?.takeIf { it.isNotBlank() }?.let { Muted(stringResource(R.string.g1_card_by, it), Modifier.padding(top = 2.dp), maxLines = 1) }
            }
        }
        Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(kindLine(hit), style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(end = 10.dp))
            TrustBadge(Trust(hit.trustUp, hit.trustDown), compact = true)
        }
    }
}

/**
 * The kind-specific line of a result card. For a shop, matched_item is the product whose name matched the query while
 * min_price is the cheapest priced, in-stock item of the whole page (search_listings; null when everything is free), so the two
 * are never joined as one price: "Sells Sugar · products from ₹5", not "Sugar · from ₹5". A business reads by its page type.
 */
private fun kindLine(h: SearchHit): String = when (h.kind) {
    "BUSINESS" -> businessLine(h, PageTypes.of(h))
    "SKILL" -> listOfNotNull(matchedLine(h), proRate(h.details, h.minPrice)).joinToString(" · ")
    "DRIVER" -> driverKind(h.details, h.category)?.let { k -> listOfNotNull(Str.get(R.string.g1_card_driver_fare, k.label, Money.format(k.farePerKm)), h.details.str("model")).joinToString(" · ") } ?: Str.get(R.string.g1_card_driver)
    else -> h.description.take(80)
}

/** The matched product with its own price ("Basmati Rice ₹120") when the server sent it. */
private fun matchedLine(h: SearchHit): String? = h.matchedItem?.let { n -> h.matchedPrice?.let { Str.get(R.string.g1_card_item_price, n, Money.format(it)) } ?: n }

/** What a business page's card says under the name: by type, with the matched item first when the query hit one. */
private fun businessLine(h: SearchHit, t: PageType?): String {
    val matched = matchedLine(h); val from = h.minPrice?.let { Money.format(it) }
    return when (t?.key) {
        "LOCAL_SERVICE", "HOSPITAL" -> when {
            matched != null && from != null -> Str.get(R.string.g1_card_service_offers_from, matched, from)
            matched != null -> Str.get(R.string.g1_card_service_offers_visit, matched)
            from != null -> Str.get(R.string.g1_card_service_from, from)
            else -> Str.get(R.string.g1_card_service_visit)
        }
        "IT_COMPANY", "COLLECTIVE", "PRO_FIRM", "MANUFACTURER" -> when {
            matched != null && from != null -> Str.get(R.string.g1_card_firm_offers_from, matched, from)
            matched != null -> Str.get(R.string.g1_card_firm_offers_quotes, matched)
            from != null -> Str.get(R.string.g1_card_firm_from, from)
            else -> Str.get(R.string.g1_card_firm_quotes)
        }
        "NGO_CHARITY" -> if (matched != null) Str.get(R.string.g1_card_ngo_program, matched) else Str.get(R.string.g1_card_ngo)
        "SCHOOL_COLLEGE" -> listOfNotNull(matched, Str.get(R.string.g1_card_school)).joinToString(" · ")
        "COMMUNITY_GROUP", "ASSOCIATION", "WORSHIP_PLACE" -> listOfNotNull(matched, Str.get(R.string.g1_card_community)).joinToString(" · ")
        else -> when {
            matched != null && from != null -> Str.get(R.string.g1_card_shop_sells_from, matched, from)
            matched != null -> Str.get(R.string.g1_card_shop_sells, matched)
            from != null -> Str.get(R.string.g1_card_shop_from, from)
            else -> Str.get(R.string.g1_card_shop_empty)
        }
    }
}

/** "Open now" for a shop, "Available now" for a pro, "Online now" for a driver, and their opposites. */
fun onlineText(kind: String, online: Boolean): String = Str.get(when (kind) {
    "BUSINESS" -> if (online) R.string.g1_card_open else R.string.g1_card_closed
    "SKILL" -> if (online) R.string.g1_card_pro_available else R.string.g1_card_pro_unavailable
    "ASSET" -> if (online) R.string.g1_card_asset_available else R.string.g1_card_asset_unavailable
    else -> if (online) R.string.g1_card_online else R.string.g1_card_offline
})

/** A small pill with an icon: the page type of a business ("NGO / charity"), or Shop / Pro / Driver for the other kinds. */
@Composable
fun KindBadge(label: String, icon: ImageVector) = Row(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 8.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer); Spacer(Modifier.width(4.dp))
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1)
}
/** Shop / Pro / Driver pill by kind alone (older call sites). */
@Composable
fun KindBadge(kind: String) = KindBadge(kindLabel(kind), kindIcon(kind))

/** Green when open / available / online, grey otherwise. */
@Composable
fun OnlineDot(online: Boolean) = Box(Modifier.size(8.dp).clip(CircleShape).background(if (online) MaterialTheme.status.good else MaterialTheme.colorScheme.outline))

/** The listing's photo in a circle, or its initials when it has none. */
@Composable
fun ListingPhoto(url: String?, title: String, size: Int = 44) {
    if (url == null) Avatar(initials(title).ifBlank { "?" }, size = size)
    else Box(Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh)) { AsyncImage(url, title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
}
