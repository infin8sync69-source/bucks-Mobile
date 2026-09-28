package com.bucks.app.ui.screens.discover

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
 * everything nearby. Kind chips (All / Shops / Pros / Drivers) and radius chips (3 / 10 / 25 km) search at once.
 */
@Composable
fun CloudSearchScreen(vm: BucksViewModel, onBack: () -> Unit, onOpenListing: (String) -> Unit, onRide: (VehicleKind) -> Unit) {
    val d = vm.discover; val s by vm.state.collectAsState()
    val focus = remember { FocusRequester() }
    // A query typed on Home or Services arrives through the view model; take it once, then it's ours.
    LaunchedEffect(Unit) {
        val q = vm.s.query.trim()
        if (q.isNotBlank()) { d.query = q; vm.setQuery("") } else runCatching { focus.requestFocus() }
        d.refreshSyncs()
    }
    LaunchedEffect(d.query) { if (d.query.isNotBlank()) delay(300); d.search() }
    val wantsRide = d.kind == KindFilter.DRIVERS || RIDE_WORDS.containsMatchIn(d.query)

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Search", onBack = onBack)
        Row(Modifier.padding(horizontal = Gutter).fillMaxWidth().height(56.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).padding(start = 18.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, Modifier.size(24.dp)); Spacer(Modifier.width(14.dp))
            BasicTextField(d.query, { d.query = it }, Modifier.weight(1f).focusRequester(focus), singleLine = true, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { d.search() }),
                decorationBox = { inner -> Box { if (d.query.isEmpty()) Text("Shops, pros, drivers or an item, like sugar", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1); inner() } })
            if (d.query.isNotEmpty()) IconButton({ d.clear() }) { Icon(Icons.Rounded.Close, "Clear search", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = Gutter, end = Gutter, top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // Opened from a Services tile: that service is the first chip; tapping it widens the search to everything.
            d.service?.let { key -> com.bucks.app.ui.serviceDef(key)?.let { def -> Chip("${def.label} ✕", selected = true, icon = def.icon) { d.useService(null); d.search() } } }
            KindFilter.entries.forEach { k -> Chip(k.label, selected = d.kind == k && d.service == null, icon = k.kinds?.firstOrNull()?.let { kindIcon(it) }) { d.useService(null); d.selectKind(k); d.search() } }
        }
        d.service?.let { vm.services.state(it) }?.takeIf { it.delivery && !it.deliveryNow }?.let {
            Notice("No Bucks riders are online near you right now. Order for pickup, or from shops with their own riders.", Modifier.padding(start = Gutter, end = Gutter, top = 10.dp))
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = Gutter, end = Gutter, top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Muted("Within"); RADIUS_CHOICES.forEach { km -> Chip("$km km", selected = d.radiusKm == km) { d.setRadius(km) } }
        }
        // Fixed-height slot so the list doesn't jump while a search runs.
        Box(Modifier.fillMaxWidth().height(12.dp).padding(horizontal = Gutter, vertical = 4.dp)) { if (d.searching) LinearProgressIndicator(Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.primary) }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (!s.locationGranted) item { Notice("Turn on location to see what's near you. Until then, results are around Jayanagar.", Modifier.padding(horizontal = Gutter, vertical = 4.dp)) }
            if (wantsRide) item { RideBanner(onRide) }
            item {
                Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (d.query.isBlank()) "Everything nearby" else "Results for “${d.query.trim()}”", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    if (d.results.isNotEmpty()) Muted("${d.results.size} within ${d.radiusKm} km")
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
        Text("Need a ride now?", style = MaterialTheme.typography.titleMedium)
        Muted("Bucks rings the nearest online rider. Pay after the trip, cash or UPI.", Modifier.padding(top = 2.dp))
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton("Book an auto") { onRide(VehicleKind.AUTO) }; SmallButton("Book a cab", tonal = true) { onRide(VehicleKind.CAB) }
        }
    }
}

/** No results: says why and offers the next step (widen the radius, drop the kind filter, or list yourself). */
@Composable
private fun EmptyResults(vm: BucksViewModel) {
    val d = vm.discover; val wider = d.widerRadius; val q = d.query.trim()
    Column(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Rounded.SearchOff, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if (q.isBlank()) "Nothing listed within ${d.radiusKm} km yet" else "No results for “$q” within ${d.radiusKm} km", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
        Muted(when {
            wider != null -> "Widen the search to see more."
            q.isBlank() -> "Be the first: list your shop, skill or vehicle from Menu > Bucks Pro."
            else -> "Try another word, like the item you need (sugar, tap repair), or a category (grocery, electrician)."
        }, Modifier.padding(top = 6.dp), align = TextAlign.Center)
        if (wider != null) SmallButton("Search within $wider km", Modifier.padding(top = 14.dp)) { d.setRadius(wider) }
        if (d.kind != KindFilter.ALL) TextButton({ d.selectKind(KindFilter.ALL) }) { Text("Show shops, pros and drivers") }
    }
}
