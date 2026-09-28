package com.bucks.app.ui.screens.manage

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
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ListingSwitch

/** What the Studio hub filters by. DRIVING holds the driver profile and the vehicles. */
private enum class StudioFilter(val label: String) { ALL("All"), BUSINESS("Businesses"), SKILL("Skills"), ASSET("Assets"), DRIVING("Driving") }

/** What "Create" offers: kind to open, title, one line, icon. */
internal data class CreateOption(val kind: String, val title: String, val detail: String, val icon: ImageVector)
internal val CREATE_OPTIONS = listOf(
    CreateOption("BUSINESS", "Business", "Shop, restaurant, store. Products with prices, orders, delivery.", Icons.Rounded.Storefront),
    CreateOption("SKILL", "Skill profile", "Plumber, tutor, designer. Your services, prices and portfolio.", Icons.Rounded.Handyman),
    CreateOption("ASSET", "Asset to sell, rent or lease", "House, flat, plot, shop, office, vehicle, equipment.", Icons.Rounded.Apartment),
    CreateOption("VEHICLE", "Vehicle", "Bike, auto or cab for rides and deliveries, with its documents.", Icons.Rounded.TwoWheeler),
    CreateOption("DRIVER", "Driver profile", "Take rides and deliveries with a checked vehicle.", Icons.Rounded.LocalTaxi),
)

/**
 * The Studio: everything I run on Bucks in one place, as cards in a grid that grows to 2-3 columns on wide screens.
 * Each card opens its dashboard; live ones switch on and off right from the card. "Create" starts any new listing or vehicle.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudioScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (listingId: String) -> Unit, onCreate: (kind: String) -> Unit, onVehicle: (id: String) -> Unit,
                 onVehicles: () -> Unit, onInvites: () -> Unit, onScan: () -> Unit, onBucksId: () -> Unit) {
    val m = vm.myListings
    LaunchedEffect(Unit) { m.refresh() }
    var filter by rememberSaveable { mutableStateOf(StudioFilter.ALL) }
    var creating by remember { mutableStateOf(false) }
    val listings = m.listings.filter { l -> when (filter) { StudioFilter.ALL -> true; StudioFilter.DRIVING -> l.kind == "DRIVER"; else -> l.kind == filter.name } }
    val vehicles = if (filter == StudioFilter.ALL || filter == StudioFilter.DRIVING) m.vehicles else emptyList()
    val live = m.listings.count { it.status == "LIVE" }; val pending = m.listings.count { it.status == "PENDING" }; val on = m.listings.count { it.status == "LIVE" && it.online }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            BucksTopBar("Studio", onBack = onBack, actions = {
                IconButton(onClick = onScan) { Icon(Icons.Rounded.QrCodeScanner, "Recommend someone") }
                IconButton(onClick = onInvites) { BadgedBox(badge = { if (m.pendingCount > 0) Badge { Text("${m.pendingCount}") } }) { Icon(Icons.Rounded.MailOutline, "Invites") } }
            })
            if (m.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                LazyVerticalGrid(GridCells.Adaptive(300.dp), Modifier.widthIn(max = 1200.dp).fillMaxSize(), contentPadding = PaddingValues(start = Gutter, end = Gutter, top = 4.dp, bottom = 96.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    full {
                        Column {
                            Text("Your professional space", style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold))
                            Muted(if (m.listings.isEmpty() && m.vehicles.isEmpty()) "Businesses, skills, assets and vehicles you run live here. Your personal profile stays under Profile."
                                  else listOfNotNull("$live live", "$pending waiting to go live".takeIf { pending > 0 }, "$on open now".takeIf { live > 0 }, "${m.vehicles.size} vehicle${if (m.vehicles.size == 1) "" else "s"}".takeIf { m.vehicles.isNotEmpty() }).joinToString(" · "),
                                  Modifier.padding(top = 2.dp))
                        }
                    }
                    full {
                        Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StudioFilter.entries.forEach { f ->
                                val n = when (f) { StudioFilter.ALL -> m.listings.size + m.vehicles.size; StudioFilter.DRIVING -> m.listings.count { it.kind == "DRIVER" } + m.vehicles.size; else -> m.listings.count { it.kind == f.name } }
                                Chip(if (n > 0) "${f.label} $n" else f.label, selected = filter == f) { filter = f }
                            }
                        }
                    }
                    if (m.invites.isNotEmpty()) full {
                        BucksCard(tint = true, onClick = onInvites) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.MailOutline, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text("${m.invites.size} invite${if (m.invites.size == 1) "" else "s"} waiting", style = MaterialTheme.typography.titleSmall); Muted("Someone asked you to help run their listing or drive their vehicle.") }
                                Icon(Icons.Rounded.ChevronRight, null)
                            }
                        }
                    }
                    val err = m.error
                    if (err != null && !m.loaded) full { LoadError(err) { m.refresh() } }
                    else if (m.loaded && listings.isEmpty() && vehicles.isEmpty()) full { StudioEmpty(filter) { kind -> onCreate(kind) } }
                    items(listings, key = { it.id }) { l -> ListingStreamCard(m, l) { onOpen(l.id) } }
                    items(vehicles, key = { "v-" + it.id }) { v -> VehicleStreamCard(m, v) { onVehicle(v.id) } }
                    if (vehicles.isNotEmpty()) full { GhostButton("Vehicles, drivers and earnings", onClick = onVehicles) }
                    if (m.loaded) full {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            BucksCard(Modifier.weight(1f), onClick = onBucksId) {
                                Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                                Text("Bucks ID card", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp)); Muted("Show it so people sync with you.")
                            }
                            BucksCard(Modifier.weight(1f), onClick = onScan) {
                                Icon(Icons.Rounded.ThumbUp, null, tint = MaterialTheme.colorScheme.primary)
                                Text("Recommend a neighbour", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp)); Muted("Scan their code in person.")
                            }
                        }
                    }
                }
            }
        }
        ExtendedFloatingActionButton(onClick = { creating = true }, icon = { Icon(Icons.Rounded.Add, null) }, text = { Text("Create") },
            containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(Gutter))
    }
    if (creating) CreateSheet(hasDriver = m.driverProfile() != null, onDismiss = { creating = false }) { kind -> creating = false; onCreate(kind) }
}

private fun LazyGridScope.full(content: @Composable () -> Unit) = item(span = { GridItemSpan(maxLineSpan) }) { content() }

@Composable
private fun StudioEmpty(filter: StudioFilter, onCreate: (String) -> Unit) = BucksCard {
    val (title, text, kind) = when (filter) {
        StudioFilter.BUSINESS -> Triple("No business yet", "Add your shop or restaurant, put in products with prices, and customers nearby can order.", "BUSINESS")
        StudioFilter.SKILL -> Triple("No skill profile yet", "Show what you do, what you charge and photos of your work. Neighbours request you directly.", "SKILL")
        StudioFilter.ASSET -> Triple("No assets listed", "Sell, rent or lease a house, flat, plot, shop, vehicle or equipment to people nearby.", "ASSET")
        StudioFilter.DRIVING -> Triple("Not driving yet", "Add your vehicle with its documents, then your driver profile, to take rides and deliveries.", "VEHICLE")
        StudioFilter.ALL -> Triple("Start your professional space", "Pick what you want to offer. Every listing goes live once neighbours recommend it in person and Bucks checks any documents it needs.", "")
    }
    Text(title, style = MaterialTheme.typography.titleMedium); Muted(text, Modifier.padding(top = 4.dp))
    if (kind.isNotBlank()) PrimaryButton("Create", Modifier.padding(top = 14.dp)) { onCreate(kind) }
    else Column(Modifier.padding(top = 10.dp)) { CREATE_OPTIONS.filter { it.kind != "DRIVER" }.forEach { o -> CreateRow(o) { onCreate(o.kind) } } }
}

@Composable
private fun CreateRow(o: CreateOption, onClick: () -> Unit) = Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(o.icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) }
    Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(o.title, style = MaterialTheme.typography.titleSmall); Muted(o.detail) }
    Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CreateSheet(hasDriver: Boolean, onDismiss: () -> Unit, onPick: (String) -> Unit) = ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp)) {
        Text("Create", style = MaterialTheme.typography.titleLarge); Muted("What do you want to offer?", Modifier.padding(bottom = 8.dp))
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
                Pill(kindLabel(l.kind), MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.onSurface)
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
            Pill("Vehicle", MaterialTheme.colorScheme.surfaceContainerHigh, MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            when (v.status) { "ACTIVE" -> PillGood("Checked · can go online"); "SUSPENDED" -> PillBad("Suspended"); else -> if (have < needed) PillWarn("$have of $needed documents") else PillWarn("Documents being checked") }
            if (v.ownerId != m.me?.id) PillGrey("You drive it")
        }
    }
}
