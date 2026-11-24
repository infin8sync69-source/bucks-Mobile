package com.bucks.app.ui.screens.manage

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
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
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.ListingSwitch

private val TABS = listOf(R.string.g2_ml_tab_businesses, R.string.g2_ml_tab_skills, R.string.g2_driver, R.string.g2_ml_tab_vehicles)
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
                     onOpenProfile: (listingId: String) -> Unit, onScan: (() -> Unit)? = null, onDocs: (listingId: String) -> Unit = {}) {
    val m = vm.myListings
    var tab by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { m.refresh(); if (vm.dispatch.enabled && !vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
    // Buyers pay a shop order by UPI to the owner's payment QR (contact_for_order); without one the Pay button is off.
    val noUpi = vm.dispatch.enabled && vm.dispatch.paymentLinkLoaded && vm.dispatch.paymentLink == null
    val kind = KINDS[tab.coerceIn(0, 2)]
    val rows = m.listings.filter { it.kind == kind }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g2_ml_title), onBack = onBack, actions = {
            IconButton(onClick = onInvites) { BadgedBox(badge = { if (m.pendingCount > 0) Badge { Text("${m.pendingCount}") } }) { Icon(Icons.Rounded.MailOutline, stringResource(R.string.g2_cd_invites)) } }
        })
        PrimaryTabRow(selectedTabIndex = tab, containerColor = MaterialTheme.colorScheme.surface, divider = { Divider() }) {
            TABS.forEachIndexed { i, l -> Tab(selected = tab == i, onClick = { if (i == 3) onVehicles() else tab = i }, text = { Text(stringResource(l), style = MaterialTheme.typography.labelLarge) }) }
        }
        if (m.loading && !m.loaded) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // A failed load is not "no business yet": that empty state, with its big Add button, would invite a duplicate listing.
            val err = m.error
            if (err != null && !m.loaded && rows.isEmpty()) item { LoadError(err) { m.refresh() } }
            if (rows.isEmpty() && m.loaded) item { EmptyListings(kind) { onEdit(kind, null) } }
            items(rows, key = { it.id }) { l -> ListingManageCard(m, l, onEdit = { onEdit(l.kind, l.id) }, onItems = { onItems(l.id) }, onMembers = { onMembers(l.id) }, onRecommend = { onRecommend(l.id) }, onOrders = { onOrders(l.id) }, onJobs = { onJobs(l.id) }, onOpenProfile = { onOpenProfile(l.id) }, onDocs = { onDocs(l.id) },
                onPaymentQr = if (noUpi && l.kind == "BUSINESS" && m.isOwner(l.id)) ({ vm.open(Routes.PAYMENT_QR) }) else null) }
            if (rows.isNotEmpty() && kind != "DRIVER") item { GhostButton(stringResource(if (kind == "BUSINESS") R.string.g2_ml_add_another_business else R.string.g2_ml_add_another_skill)) { onEdit(kind, null) } }
            if (m.loaded) item {
                BucksCard(tint = true) {
                    Text(stringResource(R.string.g2_ml_recommend_local), style = MaterialTheme.typography.titleMedium)
                    Muted(stringResource(R.string.g2_ml_recommend_local_body, NEEDED), Modifier.padding(top = 4.dp))
                    if (onScan != null) SmallButton(stringResource(R.string.g2_ml_scan_code), Modifier.padding(top = 10.dp), onClick = onScan)
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
                Text(stringResource(R.string.g2_ml_no_business), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(R.string.g2_ml_no_business_body, NEEDED), Modifier.padding(top = 4.dp))
                PrimaryButton(stringResource(R.string.g2_ml_add_business), Modifier.padding(top = 14.dp), onClick = onCreate)
            }
            "SKILL" -> {
                Text(stringResource(R.string.g2_ml_no_skills), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(R.string.g2_ml_no_skills_body, NEEDED), Modifier.padding(top = 4.dp))
                PrimaryButton(stringResource(R.string.g2_ml_add_skill), Modifier.padding(top = 14.dp), onClick = onCreate)
            }
            else -> {
                Text(stringResource(R.string.g2_ml_no_driver), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(R.string.g2_ml_no_driver_body, NEEDED), Modifier.padding(top = 4.dp))
                PrimaryButton(stringResource(R.string.g2_ml_create_driver), Modifier.padding(top = 14.dp), onClick = onCreate)
            }
        }
    }
}

/** [onPaymentQr] is set for a business I own while I have no payment QR: the card then asks for one. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ListingManageCard(m: MyListings, l: ListingRow, onEdit: () -> Unit, onItems: () -> Unit, onMembers: () -> Unit, onRecommend: () -> Unit, onOrders: () -> Unit, onJobs: () -> Unit, onOpenProfile: () -> Unit, onPaymentQr: (() -> Unit)? = null, onDocs: () -> Unit = {}) {
    val role = m.roleIn(l.id); val manage = m.canManage(l.id); val recs = m.recommendations[l.id] ?: 0
    BucksCard {
        Row(verticalAlignment = Alignment.Top) {
            PhotoOrIcon(l.photoUrl, listingIcon(l.kind, l.category))
            Column(Modifier.weight(1f).padding(start = 14.dp)) {
                Text(l.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Muted(listOfNotNull(l.category.ifBlank { null }, l.area.ifBlank { null }).joinToString(" · "), maxLines = 1)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    when (l.status) { "LIVE" -> PillGood(stringResource(R.string.g2_live)); "SUSPENDED" -> PillBad(stringResource(R.string.g2_suspended)); else -> PillWarn(stringResource(R.string.g2_ml_recs_progress, recs, NEEDED)) }
                    if (role != null && role != "OWNER") PillGrey(roleLabel(role, false))
                }
            }
        }
        when (l.status) {
            "PENDING" -> {
                Muted(if (recs == 0) stringResource(R.string.g2_ml_pending_none, NEEDED) else pluralStringResource(R.plurals.g2_ml_pending_more, (NEEDED - recs).coerceAtLeast(0), (NEEDED - recs).coerceAtLeast(0)), Modifier.padding(top = 10.dp))
                if (manage) PrimaryButton(stringResource(R.string.g2_ml_get_recommended), Modifier.padding(top = 10.dp), onClick = onRecommend)
            }
            "LIVE" -> Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                    Text(onlineLabel(l, l.online), style = MaterialTheme.typography.titleSmall)
                    Muted(stringResource(if (l.online) R.string.g2_ml_online_on else R.string.g2_ml_online_off))
                }
                if (manage) ListingSwitch(l.online) { m.setOnline(l.id, it) }
            }
            else -> Notice(stringResource(R.string.g2_ml_suspended_notice), Modifier.padding(top = 10.dp))
        }
        if (onPaymentQr != null) {
            Notice(stringResource(R.string.g2_ml_upi_notice), Modifier.padding(top = 10.dp))
            SmallButton(stringResource(R.string.g2_ml_add_payment_qr), Modifier.padding(top = 8.dp), onClick = onPaymentQr)
        }
        FlowRow(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (manage) SmallButton(stringResource(R.string.g2_edit), tonal = true, onClick = onEdit)
            if (manage && l.kind == "BUSINESS") SmallButton(stringResource(R.string.g2_ml_products), tonal = true, onClick = onItems)
            if (manage && l.kind == "SKILL") SmallButton(stringResource(R.string.g2_ml_services), tonal = true, onClick = onItems)
            if (manage && l.kind != "DRIVER") SmallButton(stringResource(R.string.g2_ml_documents), tonal = true, onClick = onDocs)
            if (l.kind != "DRIVER") SmallButton(stringResource(R.string.g2_cd_members), tonal = true, onClick = onMembers)
            if (manage && l.kind == "BUSINESS") { SmallButton(stringResource(R.string.g2_ml_orders), tonal = true, onClick = onOrders); SmallButton(stringResource(R.string.g2_ml_jobs), tonal = true, onClick = onJobs) }
            SmallButton(stringResource(R.string.g2_ml_view_profile), tonal = true, onClick = onOpenProfile)
        }
    }
}
