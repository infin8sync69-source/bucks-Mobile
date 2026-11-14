package com.bucks.app.ui.screens.manage

import androidx.annotation.StringRes
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.ListingRow
import com.bucks.app.data.VehicleRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.MyListings
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ListingSwitch

/** What the Studio hub filters by. DRIVING holds the driver profile and the vehicles. */
private enum class StudioFilter(@StringRes val label: Int) { ALL(R.string.g1_studio_filter_all), BUSINESS(R.string.g1_studio_filter_business), SKILL(R.string.g1_studio_filter_skill), ASSET(R.string.g1_studio_filter_asset), DRIVING(R.string.g1_studio_filter_driving) }

/** What "Create" offers: kind to open, title, one line, icon. */
internal data class CreateOption(val kind: String, @StringRes val title: Int, @StringRes val detail: Int, val icon: ImageVector)
internal val CREATE_OPTIONS = listOf(
    CreateOption("BUSINESS", R.string.g1_create_business, R.string.g1_create_business_detail, Icons.Rounded.Storefront),
    CreateOption("SKILL", R.string.g1_create_skill, R.string.g1_create_skill_detail, Icons.Rounded.Handyman),
    CreateOption("ASSET", R.string.g1_create_asset, R.string.g1_create_asset_detail, Icons.Rounded.Apartment),
    CreateOption("VEHICLE", R.string.g1_create_vehicle, R.string.g1_create_vehicle_detail, Icons.Rounded.TwoWheeler),
    CreateOption("DRIVER", R.string.g1_create_driver, R.string.g1_create_driver_detail, Icons.Rounded.LocalTaxi),
)

/**
 * The Studio: everything I run on Bucks in one place, as cards in a grid that grows to 2-3 columns on wide screens.
 * Each card opens its dashboard; live ones switch on and off right from the card. "Create" starts any new listing or vehicle;
 * a business first picks its page type (ui/PageTypes.kt), which [onCreate] gets as [typeKey] (null for every other kind).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudioScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (listingId: String) -> Unit, onCreate: (kind: String, typeKey: String?) -> Unit, onVehicle: (id: String) -> Unit,
                 onVehicles: () -> Unit, onInvites: () -> Unit, onScan: () -> Unit, onBucksId: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refresh() }
    var filter by rememberSaveable { mutableStateOf(StudioFilter.ALL) }
    var creating by remember { mutableStateOf(false) }
    var pickingType by remember { mutableStateOf(false) }
    // A business is not created until it has a type; everything else goes straight to its form.
    val create: (String) -> Unit = { kind -> if (kind == "BUSINESS") pickingType = true else onCreate(kind, null) }
    val listings = m.listings.filter { l -> when (filter) { StudioFilter.ALL -> true; StudioFilter.DRIVING -> l.kind == "DRIVER"; else -> l.kind == filter.name } }
    val vehicles = if (filter == StudioFilter.ALL || filter == StudioFilter.DRIVING) m.vehicles else emptyList()
    val live = m.listings.count { it.status == "LIVE" }; val pending = m.listings.count { it.status == "PENDING" }; val on = m.listings.count { it.status == "LIVE" && it.online }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            BucksTopBar("Bucks Pro", onBack = onBack, actions = {
                IconButton(onClick = onScan) { Icon(Icons.Rounded.QrCodeScanner, stringResource(R.string.g1_cd_recommend)) }
                IconButton(onClick = onInvites) { BadgedBox(badge = { if (m.pendingCount > 0) Badge { Text("${m.pendingCount}") } }) { Icon(Icons.Rounded.MailOutline, stringResource(R.string.g1_cd_invites)) } }
            })
            if (m.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                LazyVerticalGrid(GridCells.Adaptive(300.dp), Modifier.widthIn(max = 1200.dp).fillMaxSize(), contentPadding = PaddingValues(start = Gutter, end = Gutter, top = 4.dp, bottom = 96.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    full {
                        Column {
                            Text(stringResource(R.string.g1_studio_title), style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold))
                            Muted(if (m.listings.isEmpty() && m.vehicles.isEmpty()) stringResource(R.string.g1_studio_intro)
                                  else listOfNotNull(stringResource(R.string.g1_studio_live, live), if (pending > 0) stringResource(R.string.g1_studio_pending, pending) else null, if (live > 0) stringResource(R.string.g1_studio_open, on) else null, if (m.vehicles.isNotEmpty()) pluralStringResource(R.plurals.g1_studio_vehicles, m.vehicles.size, m.vehicles.size) else null).joinToString(" · "),
                                  Modifier.padding(top = 2.dp))
                        }
                    }
                    full {
                        Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StudioFilter.entries.forEach { f ->
                                val n = when (f) { StudioFilter.ALL -> m.listings.size + m.vehicles.size; StudioFilter.DRIVING -> m.listings.count { it.kind == "DRIVER" } + m.vehicles.size; else -> m.listings.count { it.kind == f.name } }
                                Chip(if (n > 0) stringResource(R.string.g1_studio_filter_count, stringResource(f.label), n) else stringResource(f.label), selected = filter == f) { filter = f }
                            }
                        }
                    }
                    if (m.invites.isNotEmpty()) full {
                        BucksCard(tint = true, onClick = onInvites) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.MailOutline, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(pluralStringResource(R.plurals.g1_studio_invites, m.invites.size, m.invites.size), style = MaterialTheme.typography.titleSmall); Muted(stringResource(R.string.g1_studio_invites_note)) }
                                Icon(Icons.Rounded.ChevronRight, null)
                            }
                        }
                    }
                    val err = m.error
                    if (err != null && !m.loaded) full { LoadError(err) { m.refresh() } }
                    else if (m.loaded && listings.isEmpty() && vehicles.isEmpty()) full { StudioEmpty(filter, create) }
                    items(listings, key = { it.id }) { l -> ListingStreamCard(m, l) { onOpen(l.id) } }
                    items(vehicles, key = { "v-" + it.id }) { v -> VehicleStreamCard(m, v) { onVehicle(v.id) } }
                    if (vehicles.isNotEmpty()) full { GhostButton(stringResource(R.string.g1_studio_vehicles_btn), onClick = onVehicles) }
                    if (m.loaded) full {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            BucksCard(Modifier.weight(1f), onClick = onBucksId) {
                                Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                                Text(stringResource(R.string.g1_studio_pro_id), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp)); Muted(stringResource(R.string.g1_studio_pro_id_note))
                            }
                            BucksCard(Modifier.weight(1f), onClick = onScan) {
                                Icon(Icons.Rounded.ArrowUpward, null, tint = MaterialTheme.colorScheme.primary)
                                Text(stringResource(R.string.g1_studio_recommend), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp)); Muted(stringResource(R.string.g1_studio_recommend_note))
                            }
                        }
                    }
                }
            }
        }
        ExtendedFloatingActionButton(onClick = { creating = true }, icon = { Icon(Icons.Rounded.Add, null) }, text = { Text(stringResource(R.string.g1_studio_create)) },
            containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(Gutter))
    }
    if (creating) CreateSheet(hasDriver = m.driverProfile() != null, onDismiss = { creating = false }) { kind -> creating = false; create(kind) }
    if (pickingType) PageTypePickerSheet(onSkill = { pickingType = false; onCreate("SKILL", null) }, onPick = { t -> pickingType = false; onCreate("BUSINESS", t.key) }, onDismiss = { pickingType = false })
}

private fun LazyGridScope.full(content: @Composable () -> Unit) = item(span = { GridItemSpan(maxLineSpan) }) { content() }

@Composable
private fun StudioEmpty(filter: StudioFilter, onCreate: (String) -> Unit) = BucksCard {
    val (title, text, kind) = when (filter) {
        StudioFilter.BUSINESS -> Triple(stringResource(R.string.g1_studio_empty_business), stringResource(R.string.g1_studio_empty_business_body), "BUSINESS")
        StudioFilter.SKILL -> Triple(stringResource(R.string.g1_studio_empty_skill), stringResource(R.string.g1_studio_empty_skill_body), "SKILL")
        StudioFilter.ASSET -> Triple(stringResource(R.string.g1_studio_empty_asset), stringResource(R.string.g1_studio_empty_asset_body), "ASSET")
        StudioFilter.DRIVING -> Triple(stringResource(R.string.g1_studio_empty_driving), stringResource(R.string.g1_studio_empty_driving_body), "VEHICLE")
        StudioFilter.ALL -> Triple(stringResource(R.string.g1_studio_empty_all), stringResource(R.string.g1_studio_empty_all_body), "")
    }
    Text(title, style = MaterialTheme.typography.titleMedium); Muted(text, Modifier.padding(top = 4.dp))
    if (kind.isNotBlank()) PrimaryButton(stringResource(R.string.g1_studio_create), Modifier.padding(top = 14.dp)) { onCreate(kind) }
    else Column(Modifier.padding(top = 10.dp)) { CREATE_OPTIONS.filter { it.kind != "DRIVER" }.forEach { o -> CreateRow(o) { onCreate(o.kind) } } }
}

@Composable
private fun CreateRow(o: CreateOption, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(o.icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(stringResource(o.title), style = MaterialTheme.typography.titleSmall); Muted(stringResource(o.detail)) }
    Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CreateSheet(hasDriver: Boolean, onDismiss: () -> Unit, onPick: (String) -> Unit) = ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
    Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
        Text(stringResource(R.string.g1_studio_create), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g1_studio_create_q), Modifier.padding(bottom = 8.dp))
        CREATE_OPTIONS.filter { it.kind != "DRIVER" || !hasDriver }.forEach { o -> CreateRow(o) { onPick(o.kind) } }
    }
}

@Composable
private fun ListingStreamCard(m: MyListings, l: ListingRow, onClick: () -> Unit) {
    val recs = m.recommendations[l.id] ?: 0; val role = m.roleIn(l.id)
    BucksCard(onClick = onClick, padding = 0) {
        Box {
            ListingCover(l, Modifier.fillMaxWidth().height(124.dp))
            Row(Modifier.padding(10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Pill(PageTypes.of(l)?.label ?: kindLabel(l.kind), MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.onSurface)
                if (role != null && role != "OWNER") Pill(roleLabel(role, false), MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.onSurface)
            }
        }
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(l.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Muted(listOfNotNull(if (l.kind == "ASSET") assetPriceLine(l.details) else l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                }
                if (l.status == "LIVE" && m.canManage(l.id)) ListingSwitch(l.online) { m.setOnline(l.id, it) }
            }
            Row(Modifier.padding(top = 8.dp)) { ListingStatusPill(l, recs) }
            if (l.status == "PENDING") LinearProgressIndicator(progress = { (recs.toFloat() / NEEDED).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).height(4.dp).clip(CircleShape))
        }
    }
}

@Composable
private fun VehicleStreamCard(m: MyListings, v: VehicleRow, onClick: () -> Unit) {
    val docs = m.vehicleDocs[v.id].orEmpty(); val needed = vehicleDocKinds(v.kind).count { it.required }
    val have = vehicleDocKinds(v.kind).count { k -> k.required && docs.any { it.kind == k.key } }
    BucksCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(icon = vehicleIcon(v.kind), size = 48)
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(v.model.ifBlank { vehicleKindLabel(v.kind) }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted("${vehicleKindLabel(v.kind)} · ${v.plate}")
            }
            Pill(stringResource(R.string.g1_studio_vehicle), MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            when (v.status) { "ACTIVE" -> PillGood(stringResource(R.string.g1_studio_v_active)); "SUSPENDED" -> PillBad(stringResource(R.string.g1_studio_v_suspended)); else -> if (have < needed) PillWarn(stringResource(R.string.g1_studio_v_docs, have, needed)) else PillWarn(stringResource(R.string.g1_studio_v_checking)) }
            if (v.ownerId != m.me?.id) PillGrey(stringResource(R.string.g1_studio_v_you_drive))
        }
    }
}
