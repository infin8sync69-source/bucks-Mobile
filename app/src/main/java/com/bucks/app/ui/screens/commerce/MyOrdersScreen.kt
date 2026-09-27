package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.delay

/** Every order I placed, newest first, with the shop's name, what I paid and where it stands. */
@Composable
fun MyOrdersScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit) {
    val commerce = vm.commerce
    // Refresh on open and every 15 seconds while the list is showing, so an accept or delivery shows up without a tap.
    LaunchedEffect(Unit) { while (true) { commerce.refreshMyOrders(); delay(15_000) } }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("My orders", onBack = onBack, actions = { IconButton({ commerce.refreshMyOrders() }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        when {
            !commerce.myOrdersLoaded -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            commerce.myOrders.isEmpty() -> Column(Modifier.fillMaxWidth().padding(Gutter).padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.ShoppingBag, size = 72)
                Text("No orders yet", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                Muted("Search for groceries, food or anything nearby, open a shop and tap Add. Your orders will show up here.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Find a shop", Modifier.padding(top = 18.dp), onClick = onBack)
            }
            else -> LazyColumn {
                val live = commerce.myOrders.filter { orderLive(it.status) }; val past = commerce.myOrders.filterNot { orderLive(it.status) }
                if (live.isNotEmpty()) item { SectionTitle("In progress", Modifier.padding(horizontal = Gutter).padding(top = 8.dp, bottom = 4.dp)) }
                items(live, key = { it.id }) { o -> OrderListRow(vm, o.id, o.listingId, o.subtotal + if (o.feePaidBy == "BUYER") o.deliveryFee else 0, o.status, o.deliveryMode, o.createdAt) { onOpen(o.id) } }
                if (past.isNotEmpty()) item { SectionTitle("Earlier", Modifier.padding(horizontal = Gutter).padding(top = 16.dp, bottom = 4.dp)) }
                items(past, key = { it.id }) { o -> OrderListRow(vm, o.id, o.listingId, o.subtotal + if (o.feePaidBy == "BUYER") o.deliveryFee else 0, o.status, o.deliveryMode, o.createdAt) { onOpen(o.id) } }
                item { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
}

@Composable
private fun OrderListRow(vm: BucksViewModel, id: String, listingId: String, total: Int, status: String, mode: String, createdAt: String, onClick: () -> Unit) {
    ListRow(vm.commerce.titleOf(listingId), "${ago(createdAt)} · ${deliveryModeLabel(mode)} · ${shortOrderId(id)}", leading = { Avatar(icon = Icons.Rounded.Storefront, tinted = false) },
        trailing = { Column(horizontalAlignment = Alignment.End) { Text(rupees(total), style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(4.dp)); OrderStatusPill(status, mode) } }, onClick = onClick)
    Divider()
}
