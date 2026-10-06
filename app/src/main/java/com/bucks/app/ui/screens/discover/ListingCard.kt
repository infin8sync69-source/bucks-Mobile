package com.bucks.app.ui.screens.discover

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
                Muted(listOfNotNull(hit.category.ifBlank { null }, if (ships && hit.distanceM > 25_000) "Ships across India" else formatDistance(hit.distanceM), hit.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) { OnlineDot(hit.online); Spacer(Modifier.width(6.dp)); Muted(onlineText(hit.kind, hit.online), maxLines = 1) }
                hit.ownerName?.takeIf { it.isNotBlank() }?.let { Muted("by $it", Modifier.padding(top = 2.dp), maxLines = 1) }
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
    "SKILL" -> listOfNotNull(h.matchedItem, proRate(h.details, h.minPrice)).joinToString(" · ")
    "DRIVER" -> driverKind(h.details, h.category)?.let { k -> listOfNotNull("${k.label} · ₹${k.farePerKm}/km", h.details.str("model")).joinToString(" · ") } ?: "Driver"
    else -> h.description.take(80)
}

/** What a business page's card says under the name: by type, with the matched item first when the query hit one. */
private fun businessLine(h: SearchHit, t: PageType?): String {
    val matched = h.matchedItem; val from = h.minPrice
    return when (t?.key) {
        "LOCAL_SERVICE", "HOSPITAL" -> listOfNotNull(matched?.let { "Offers $it" }, from?.let { "services from ₹$it" } ?: "book a visit").joinToString(" · ").replaceFirstChar { it.uppercase() }
        "IT_COMPANY", "COLLECTIVE", "PRO_FIRM", "MANUFACTURER" -> listOfNotNull(matched?.let { "Offers $it" }, from?.let { "from ₹$it" } ?: "quotes on request").joinToString(" · ").replaceFirstChar { it.uppercase() }
        "NGO_CHARITY" -> listOfNotNull(matched?.let { "Program: $it" } ?: "Programs you can join", "volunteers welcome").joinToString(" · ")
        "SCHOOL_COLLEGE" -> listOfNotNull(matched, "Admissions and programs").joinToString(" · ")
        "COMMUNITY_GROUP", "ASSOCIATION", "WORSHIP_PLACE" -> listOfNotNull(matched, "Events and updates").joinToString(" · ")
        else -> when {
            matched != null -> "Sells $matched" + (from?.let { " · products from ₹$it" } ?: "")
            from != null -> "Products from ₹$from"
            else -> "No products listed yet · message to ask"
        }
    }
}

/** "Open now" for a shop, "Available now" for a pro, "Online now" for a driver, and their opposites. */
fun onlineText(kind: String, online: Boolean): String = when (kind) {
    "BUSINESS" -> if (online) "Open now" else "Closed now"
    "SKILL" -> if (online) "Available now" else "Not available right now"
    "ASSET" -> if (online) "Available" else "Not available now"
    else -> if (online) "Online now" else "Offline"
}

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
