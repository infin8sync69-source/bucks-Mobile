package com.bucks.app.ui.screens.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Apartment
import androidx.compose.material.icons.rounded.Handyman
import androidx.compose.material.icons.rounded.LocalTaxi
import androidx.compose.material.icons.rounded.Storefront
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
import com.bucks.app.ui.components.*
import com.bucks.app.ui.driverKind
import com.bucks.app.ui.formatDistance
import com.bucks.app.ui.kindLabel
import com.bucks.app.ui.proRate
import com.bucks.app.ui.str
import com.bucks.app.ui.theme.status

/**
 * The one card every search result uses, whatever its kind: photo or initials, title, kind badge, category,
 * distance, open/online dot, trust, and one line that says what matters for that kind
 * (the matched item and the shop's starting price for a shop, the rate for a pro, the vehicle and fare for a driver).
 */
@Composable
fun ListingCard(hit: SearchHit, onClick: () -> Unit) {
    BucksCard(padding = 12, onClick = onClick) {
        Row(verticalAlignment = Alignment.Top) {
            ListingPhoto(Backend.listingPhoto(hit.photoUrl), hit.title, size = 56)
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(hit.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Spacer(Modifier.width(8.dp)); KindBadge(hit.kind)
                }
                Muted(listOfNotNull(hit.category.ifBlank { null }, formatDistance(hit.distanceM), hit.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) { OnlineDot(hit.online); Spacer(Modifier.width(6.dp)); Muted(onlineText(hit.kind, hit.online), maxLines = 1) }
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
 * min_price is the cheapest in-stock product of the whole shop (search_listings), so the two are never joined as one price:
 * "Sells Sugar · products from ₹5", not "Sugar · from ₹5".
 */
private fun kindLine(h: SearchHit): String = when (h.kind) {
    "BUSINESS" -> when {
        h.matchedItem != null -> "Sells ${h.matchedItem}" + (h.minPrice?.let { " · products from ₹$it" } ?: "")
        h.minPrice != null -> "Products from ₹${h.minPrice}"
        else -> "No products listed yet · message to ask"
    }
    "SKILL" -> listOfNotNull(h.matchedItem, proRate(h.details, h.minPrice)).joinToString(" · ")
    "DRIVER" -> driverKind(h.details, h.category)?.let { k -> listOfNotNull("${k.label} · ₹${k.farePerKm}/km", h.details.str("model")).joinToString(" · ") } ?: "Driver"
    else -> h.description.take(80)
}

/** "Open now" for a shop, "Available now" for a pro, "Online now" for a driver, and their opposites. */
fun onlineText(kind: String, online: Boolean): String = when (kind) {
    "BUSINESS" -> if (online) "Open now" else "Closed now"
    "SKILL" -> if (online) "Available now" else "Not available right now"
    "ASSET" -> if (online) "Available" else "Not available now"
    else -> if (online) "Online now" else "Offline"
}

fun kindIcon(kind: String): ImageVector = when (kind) { "BUSINESS" -> Icons.Rounded.Storefront; "SKILL" -> Icons.Rounded.Handyman; "ASSET" -> Icons.Rounded.Apartment; else -> Icons.Rounded.LocalTaxi }

/** Shop / Pro / Driver pill with its icon. */
@Composable
fun KindBadge(kind: String) = Row(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 8.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(kindIcon(kind), null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer); Spacer(Modifier.width(4.dp))
    Text(kindLabel(kind), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onPrimaryContainer, maxLines = 1)
}

/** Green when open / available / online, grey otherwise. */
@Composable
fun OnlineDot(online: Boolean) = Box(Modifier.size(8.dp).clip(CircleShape).background(if (online) MaterialTheme.status.good else MaterialTheme.colorScheme.outline))

/** The listing's photo in a circle, or its initials when it has none. */
@Composable
fun ListingPhoto(url: String?, title: String, size: Int = 44) {
    if (url == null) Avatar(initials(title).ifBlank { "?" }, size = size)
    else Box(Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh)) { AsyncImage(url, title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
}
