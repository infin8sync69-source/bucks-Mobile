package com.bucks.app.ui.screens.discover

import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.SearchOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.data.VehicleKind
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.KindFilter
import com.bucks.app.ui.RADIUS_CHOICES
import com.bucks.app.ui.components.*
import kotlinx.coroutines.delay

private val RIDE_WORDS = Regex("\\b(auto|cab|taxi|ride|rickshaw)\\b", RegexOption.IGNORE_CASE)

/**
 * Cloud search over live listings near me. Typing searches after a 300 ms pause; an empty query browses
 * everything nearby. Group chips (All / Shops / Local services / Companies / NGOs and groups / Institutions / Pros / Buy & rent / Drivers)
 * and radius chips (3 / 10 / 25 km) search at once.
 */
@Composable
fun CloudSearchScreen(vm: BucksViewModel, onBack: () -> Unit, onOpenListing: (String) -> Unit, onRide: (VehicleKind) -> Unit, onPlace: () -> Unit = {}) {
    val d = vm.discover; val s by vm.state.collectAsState()
    val focus = remember { FocusRequester() }
    var pickArea by remember { mutableStateOf(false) }
    // Say it instead of typing (in the voice language set in Settings): the words become the search.
    val (voice, listen) = com.bucks.app.ui.rememberVoiceInput(s.voiceLang, onResult = { heard -> d.query = heard }, onError = { vm.toast(it) })
    // A query typed on Home or Services arrives through the view model; take it once, then it's ours.
    LaunchedEffect(Unit) {
        val q = vm.s.query.trim()
        if (q.isNotBlank()) { d.query = q; vm.setQuery("") } else runCatching { focus.requestFocus() }
        d.refreshSyncs()
    }
    LaunchedEffect(d.query) { if (d.query.isNotBlank()) delay(300); d.search() }
    // Places (streets, landmarks, towns) from the map search sit under the same bar; tapping one opens it on the map with directions.
    var places by remember { mutableStateOf<List<com.bucks.app.data.MapServices.PlaceHit>>(emptyList()) }
    LaunchedEffect(d.query) {
        places = emptyList(); val q = d.query.trim(); if (q.length < 3) return@LaunchedEffect
        delay(600); places = com.bucks.app.data.MapServices.search(q, s.me ?: vm.mePos).take(4)
    }
    val wantsRide = d.kind == KindFilter.DRIVERS || RIDE_WORDS.containsMatchIn(d.query)

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g1_search_title), onBack = onBack)
        Row(Modifier.padding(horizontal = Gutter).fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(start = 18.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.size(24.dp)); Spacer(Modifier.width(14.dp))
            BasicTextField(d.query, { d.query = it }, Modifier.weight(1f).focusRequester(focus), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { d.search() }),
                decorationBox = { inner -> Box { if (d.query.isEmpty()) Text(if (voice.listening) voice.partial.ifBlank { stringResource(R.string.g1_search_listening) } else stringResource(R.string.g1_search_hint), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1); inner() } })
            if (d.query.isNotEmpty()) IconButton({ d.clear() }) { Icon(Icons.Rounded.Close, stringResource(R.string.g1_cd_clear_search), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            else IconButton(onClick = listen) { Icon(if (voice.listening) Icons.Rounded.GraphicEq else Icons.Rounded.Mic, stringResource(R.string.g1_cd_voice_search), tint = if (voice.listening) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = Gutter, end = Gutter, top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // Opened from a Services tile: that service is the first chip; tapping it widens the search to everything.
            d.service?.let { key -> com.bucks.app.ui.serviceDef(key)?.let { def -> Chip(stringResource(R.string.g1_search_chip_remove, def.label), selected = true, icon = def.icon) { d.useService(null); d.search() } } }
            KindFilter.entries.forEach { k -> Chip(k.label, selected = d.kind == k && d.service == null, icon = k.icon) { d.useService(null); d.selectKind(k); d.search() } }
        }
        d.service?.let { vm.services.state(it) }?.takeIf { it.delivery && !it.deliveryNow }?.let {
            Notice(stringResource(R.string.g1_search_no_riders), Modifier.padding(start = Gutter, end = Gutter, top = 10.dp))
        }
        if (pickArea) AreaSheet(d.area?.first ?: "", s.me, s.hereLabel, onPick = { label, at -> pickArea = false; d.chooseArea(label, at) }) { pickArea = false }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = Gutter, end = Gutter, top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // Where to search: near me, or any area picked by name (tier 2/3 towns, a relative's locality).
            Chip(d.area?.let { stringResource(R.string.g1_search_chip_remove, it.first) } ?: stringResource(R.string.g1_search_near_me), selected = d.area != null, icon = androidx.compose.material.icons.Icons.Rounded.Place) { if (d.area != null) d.chooseArea(null, null) else pickArea = true }
            Muted(stringResource(R.string.g1_search_within)); RADIUS_CHOICES.forEach { km -> Chip(stringResource(R.string.g1_search_km, km), selected = d.radiusKm == km) { d.setRadius(km) } }
        }
        // Fixed-height slot so the list doesn't jump while a search runs.
        Box(Modifier.fillMaxWidth().height(12.dp).padding(horizontal = Gutter, vertical = 4.dp)) { if (d.searching) LinearProgressIndicator(Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.primary) }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (!s.locationGranted) item { Notice(stringResource(R.string.g1_search_location_off), Modifier.padding(horizontal = Gutter, vertical = 4.dp)) }
            if (wantsRide) item { RideBanner(onRide) }
            if (places.isNotEmpty()) {
                item { Text(stringResource(R.string.g1_search_places), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = Gutter, vertical = 8.dp)) }
                items(places, key = { "p" + it.name + it.at.lat + it.at.lng }) { h ->
                    ListRow(h.name, h.detail, leading = { Avatar(icon = Icons.Rounded.Place, size = 40) }, trailing = { Muted(stringResource(R.string.g1_search_directions)) }, onClick = { com.bucks.app.ui.screens.MapsPick.place = h; onPlace() })
                    Divider()
                }
            }
            item {
                Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (d.query.isBlank()) stringResource(R.string.g1_search_everything) else stringResource(R.string.g1_search_results_for, d.query.trim()), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    if (d.results.isNotEmpty()) Muted(d.area?.let { pluralStringResource(R.plurals.g1_search_count_area, d.results.size, d.results.size, d.radiusKm, it.first) } ?: pluralStringResource(R.plurals.g1_search_count, d.results.size, d.results.size, d.radiusKm))
                }
            }
            items(d.results, key = { it.id }) { h -> Box(Modifier.padding(start = Gutter, end = Gutter, bottom = 12.dp)) { ListingCard(h) { onOpenListing(h.id) } } }
            if (d.searched && !d.searching && d.results.isEmpty()) item { EmptyResults(vm) }
        }
    }
}

@Composable
private fun RideBanner(onRide: (VehicleKind) -> Unit) = Box(Modifier.padding(horizontal = Gutter, vertical = 4.dp)) {
    BucksCard(tint = true) {
        Text(stringResource(R.string.g1_ride_title), style = MaterialTheme.typography.titleMedium)
        Muted(stringResource(R.string.g1_ride_body), Modifier.padding(top = 2.dp))
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton(stringResource(R.string.g1_ride_auto)) { onRide(VehicleKind.AUTO) }; SmallButton(stringResource(R.string.g1_ride_cab), tonal = true) { onRide(VehicleKind.CAB) }
        }
    }
}

/** No results: says why and offers the next step (widen the radius, drop the kind filter, or list yourself). */
@Composable
private fun EmptyResults(vm: BucksViewModel) {
    val d = vm.discover; val wider = d.widerRadius; val q = d.query.trim()
    Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.SearchOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if (q.isBlank()) stringResource(R.string.g1_search_empty_all, d.radiusKm) else stringResource(R.string.g1_search_empty_query, q, d.radiusKm), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
        Muted(when {
            wider != null -> stringResource(R.string.g1_search_empty_widen)
            q.isBlank() -> stringResource(R.string.g1_search_empty_first)
            else -> stringResource(R.string.g1_search_empty_try)
        }, Modifier.padding(top = 6.dp), align = TextAlign.Center)
        if (wider != null) SmallButton(stringResource(R.string.g1_search_wider, wider), Modifier.padding(top = 14.dp)) { d.setRadius(wider) }
        if (d.kind != KindFilter.ALL) TextButton({ d.selectKind(KindFilter.ALL) }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.g1_search_show_all)) }
    }
}

/** Pick an area to search around (LocationPicker in a sheet). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AreaSheet(current: String, fix: com.bucks.app.data.LatLng?, fixLabel: String?, onPick: (String, com.bucks.app.data.LatLng) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            Text(stringResource(R.string.g1_search_area_title), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 12.dp))
            com.bucks.app.ui.screens.LocationPicker(current, fix, fixLabel, onPick)
        }
    }
}
