package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.ListingRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.MyListings
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ListingSwitch

private val TABS = listOf("Businesses", "Skills", "Driver", "Vehicles")
private val KINDS = listOf("BUSINESS", "SKILL", "DRIVER")

/**
 * The owner's hub: everything they run on Bucks, by kind. Pending listings show how many of the
 * 7 recommendations they have and a way to collect more; live ones get the open / online switch.
 * [onScan] opens the scanner for recommending someone else's listing (optional; the integrator wires it).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MyListingsScreen(vm: BucksViewModel, onBack: () -> Unit, onEdit: (kind: String, id: String?) -> Unit, onItems: (listingId: String) -> Unit, onMembers: (listingId: String) -> Unit,
                     onRecommend: (listingId: String) -> Unit, onOrders: (listingId: String) -> Unit, onJobs: (listingId: String) -> Unit, onVehicles: () -> Unit, onInvites: () -> Unit,
                     onOpenProfile: (listingId: String) -> Unit, onScan: (() -> Unit)? = null) {
    val m = vm.myListings
    var tab by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { m.refresh() }
    val kind = KINDS[tab.coerceIn(0, 2)]
    val rows = m.listings.filter { it.kind == kind }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("My listings", onBack = onBack, actions = {
            IconButton(onClick = onInvites) { BadgedBox(badge = { if (m.pendingCount > 0) Badge { Text("${m.pendingCount}") } }) { Icon(Icons.Rounded.MailOutline, "Invites") } }
        })
        PrimaryTabRow(selectedTabIndex = tab, containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) {
            TABS.forEachIndexed { i, l -> Tab(selected = tab == i, onClick = { if (i == 3) onVehicles() else tab = i }, text = { Text(l, style = MaterialTheme.typography.labelLarge) }) }
        }
        if (m.loading && !m.loaded) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // A failed load is not "no business yet": that empty state, with its big Add button, would invite a duplicate listing.
            val err = m.error
            if (err != null && !m.loaded && rows.isEmpty()) item { LoadError(err) { m.refresh() } }
            if (rows.isEmpty() && m.loaded) item { EmptyListings(kind) { onEdit(kind, null) } }
            items(rows, key = { it.id }) { l -> ListingManageCard(m, l, onEdit = { onEdit(l.kind, l.id) }, onItems = { onItems(l.id) }, onMembers = { onMembers(l.id) }, onRecommend = { onRecommend(l.id) }, onOrders = { onOrders(l.id) }, onJobs = { onJobs(l.id) }, onOpenProfile = { onOpenProfile(l.id) }) }
            if (rows.isNotEmpty() && kind != "DRIVER") item { GhostButton(if (kind == "BUSINESS") "Add another business" else "Add another skill") { onEdit(kind, null) } }
            if (m.loaded) item {
                BucksCard(tint = true) {
                    Text("Recommend a neighbour", style = MaterialTheme.typography.titleMedium)
                    Muted("Know a shop, driver or worker nearby who does good work? Scan the code on their phone and help them go live. $NEEDED recommendations from neighbours take a listing live.", Modifier.padding(top = 4.dp))
                    if (onScan != null) SmallButton("Scan their code", Modifier.padding(top = 10.dp), onClick = onScan)
                }
            }
            item { Spacer(Modifier.height(12.dp)) }
        }
    }
}

@Composable
private fun EmptyListings(kind: String, onCreate: () -> Unit) {
    BucksCard {
        when (kind) {
            "BUSINESS" -> {
                Text("No business yet", style = MaterialTheme.typography.titleMedium)
                Muted("Add your shop, restaurant, pharmacy or any business. Put your products in with prices so customers nearby can order. It goes live once $NEEDED neighbours recommend it by scanning your QR code in person.", Modifier.padding(top = 4.dp))
                PrimaryButton("Add a business", Modifier.padding(top = 14.dp), onClick = onCreate)
            }
            "SKILL" -> {
                Text("No skills yet", style = MaterialTheme.typography.titleMedium)
                Muted("Add what you do: plumber, electrician, tutor, doctor, carpenter, designer. Each skill is its own listing with services and prices. It goes live once $NEEDED neighbours recommend you.", Modifier.padding(top = 4.dp))
                PrimaryButton("Add a skill", Modifier.padding(top = 14.dp), onClick = onCreate)
            }
            else -> {
                Text("No driver profile yet", style = MaterialTheme.typography.titleMedium)
                Muted("Create your driver profile to take auto and cab rides or bike deliveries. You have one driver profile; add the vehicles you drive under Vehicles. It goes live once $NEEDED neighbours recommend you.", Modifier.padding(top = 4.dp))
                PrimaryButton("Create your driver profile", Modifier.padding(top = 14.dp), onClick = onCreate)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ListingManageCard(m: MyListings, l: ListingRow, onEdit: () -> Unit, onItems: () -> Unit, onMembers: () -> Unit, onRecommend: () -> Unit, onOrders: () -> Unit, onJobs: () -> Unit, onOpenProfile: () -> Unit) {
    val role = m.roleIn(l.id); val manage = m.canManage(l.id); val recs = m.recommendations[l.id] ?: 0
    BucksCard {
        Row(verticalAlignment = Alignment.Top) {
            PhotoOrIcon(l.photoUrl, listingIcon(l.kind, l.category))
            Column(Modifier.weight(1f).padding(start = 14.dp)) {
                Text(l.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted(listOfNotNull(l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    when (l.status) { "LIVE" -> PillGood("Live"); "SUSPENDED" -> PillBad("Suspended"); else -> PillWarn("$recs of $NEEDED recommendations") }
                    if (role != null && role != "OWNER") PillGrey(roleLabel(role, false))
                }
            }
        }
        when (l.status) {
            "PENDING" -> {
                Muted(if (recs == 0) "Not visible to customers yet. Ask $NEEDED neighbours who know your work to scan your code." else "${(NEEDED - recs).coerceAtLeast(0)} more neighbours need to scan your code before customers can find you.", Modifier.padding(top = 10.dp))
                if (manage) PrimaryButton("Get recommended", Modifier.padding(top = 10.dp), onClick = onRecommend)
            }
            "LIVE" -> Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                    Text(onlineLabel(l.kind, l.online), style = MaterialTheme.typography.titleSmall)
                    Muted(if (l.online) "Shown first in search; customers can reach you now." else "Hidden until you switch it on.")
                }
                if (manage) ListingSwitch(l.online) { m.setOnline(l.id, it) }
            }
            else -> Notice("This listing is suspended and hidden from customers. Contact Bucks support to sort it out.", Modifier.padding(top = 10.dp))
        }
        FlowRow(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (manage) SmallButton("Edit", tonal = true, onClick = onEdit)
            if (manage && l.kind == "BUSINESS") SmallButton("Products", tonal = true, onClick = onItems)
            if (manage && l.kind == "SKILL") SmallButton("Services", tonal = true, onClick = onItems)
            if (l.kind != "DRIVER") SmallButton("Members", tonal = true, onClick = onMembers)
            if (manage && l.kind == "BUSINESS") { SmallButton("Orders", tonal = true, onClick = onOrders); SmallButton("Jobs", tonal = true, onClick = onJobs) }
            SmallButton("View profile", tonal = true, onClick = onOpenProfile)
        }
    }
}
