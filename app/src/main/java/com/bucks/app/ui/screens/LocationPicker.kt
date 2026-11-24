package com.bucks.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Str
import com.bucks.app.data.Geo
import com.bucks.app.data.LatLng
import com.bucks.app.data.MapServices
import com.bucks.app.ui.components.*
import kotlinx.coroutines.delay

/** "Indiranagar, Bengaluru" from a place hit; a street becomes "12th Main, Indiranagar". */
internal fun placeLabel(hit: MapServices.PlaceHit): String =
    listOfNotNull(hit.name, hit.detail.split(", ").firstOrNull { it.isNotBlank() && it != hit.name }).joinToString(", ")

/** The area part of a reverse-geocoded label ("12th Main, Indiranagar" -> "Indiranagar"). */
internal fun areaOf(label: String?): String? = label?.substringAfterLast(", ")?.ifBlank { null }

/**
 * Pick where you are based, anywhere: use the phone's current location, or search any place (a locality, a landmark, a town).
 * [current] is the label already chosen; [fix] and [fixLabel] are the phone's location and its name when it has one.
 * [onPick] gets a short label and the exact point, so the profile's home is the place chosen and not a guess.
 */
@Composable
fun LocationPicker(current: String, fix: LatLng?, fixLabel: String?, onPick: (label: String, at: LatLng) -> Unit) {
    var q by remember { mutableStateOf("") }; var hits by remember { mutableStateOf<List<MapServices.PlaceHit>>(emptyList()) }; var searching by remember { mutableStateOf(false) }
    var dropPin by remember { mutableStateOf(false) }
    if (dropPin) PinDropDialog(hits.firstOrNull()?.at ?: fix ?: Geo.CENTER, q, onPick = { label, at -> dropPin = false; onPick(label, at); q = ""; hits = emptyList() }) { dropPin = false }
    // Search after a short pause in typing, biased to where the phone is (else the middle of Bengaluru, only used to order results).
    LaunchedEffect(q) {
        if (q.trim().length < 3) { hits = emptyList(); searching = false; return@LaunchedEffect }
        searching = true; delay(450); hits = MapServices.search(q, fix ?: Geo.CENTER); searching = false
    }
    val currentLabel = stringResource(R.string.g4_loc_current)
    Column {
        Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.LocationOn, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.padding(start = 10.dp)) { Muted(stringResource(R.string.g4_loc_your_area)); Text(current.ifBlank { stringResource(R.string.g4_loc_not_chosen) }, style = MaterialTheme.typography.titleMedium) }
        }
        if (fix != null) SmallButton(areaOf(fixLabel)?.let { stringResource(R.string.g4_loc_use_current_area, it) } ?: stringResource(R.string.g4_loc_use_current), Modifier.padding(bottom = 10.dp), tonal = true) { onPick(areaOf(fixLabel) ?: currentLabel, fix); q = ""; hits = emptyList() }
        else Muted(stringResource(R.string.g4_loc_turn_on), Modifier.padding(bottom = 8.dp))
        BucksField(q, { q = it }, placeholder = stringResource(R.string.g4_loc_search_hint), singleLine = true)
        if (searching) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 4.dp))
        else if (q.trim().length >= 3 && hits.isEmpty()) Muted(stringResource(R.string.g4_loc_no_results, q.trim()), Modifier.padding(top = 6.dp))
        hits.forEach { h ->
            Row(Modifier.fillMaxWidth().clickable { onPick(placeLabel(h), h.at); q = ""; hits = emptyList() }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Place, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.padding(start = 12.dp)) { Text(h.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1); placeDetail(h).takeIf { it.isNotBlank() }?.let { Muted(it, maxLines = 1) } }
            }
            Divider()
        }
        // Maps miss many lanes, colonies and landmarks in smaller towns: put it on the map yourself (saved for everyone).
        if (q.trim().length >= 3 && !searching) TextButton({ dropPin = true }, Modifier.padding(top = 4.dp)) { Icon(Icons.Rounded.Place, null); Text(stringResource(R.string.g4_loc_drop_pin), Modifier.padding(start = 6.dp)) }
        Muted(stringResource(R.string.g4_loc_sources), Modifier.padding(top = 6.dp))
    }
}

/** The second line of a place: where it is, and where it came from when it's Bucks' own. */
internal fun placeDetail(h: MapServices.PlaceHit): String = when (h.source) {
    "POST" -> Str.get(R.string.g4_loc_detail_post, h.detail)
    "PEOPLE" -> Str.get(R.string.g4_loc_detail_pinned, h.detail)
    "BUCKS" -> Str.get(R.string.g4_loc_detail_bucks, h.detail).trimStart(' ', '·')
    else -> h.detail
}
