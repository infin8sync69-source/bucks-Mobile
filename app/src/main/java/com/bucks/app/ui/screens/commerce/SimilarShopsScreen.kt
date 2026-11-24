package com.bucks.app.ui.screens.commerce

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Storefront
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Backend
import com.bucks.app.data.Money
import com.bucks.app.data.Recovery
import com.bucks.app.data.SimilarShop
import com.bucks.app.data.orderAlternatives
import com.bucks.app.data.recoveryChoice
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.formatDistance
import kotlinx.coroutines.CancellationException

/**
 * Swarm Phase 1: "Similar shops nearby" for an order a shop turned down (order_alternatives: up to 3 other shops near the drop that
 * list the same items). Opened from the order page or the recovery notification. A tap opens the shop; ordering there is the usual
 * cart and confirm sheet. Nothing is ordered for the buyer.
 */
@Composable
fun SimilarShopsScreen(vm: BucksViewModel, orderId: String, onBack: () -> Unit, onOpenListing: (String) -> Unit) {
    var shops by remember { mutableStateOf<List<SimilarShop>?>(null) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(orderId) { runCatching { Backend.recoveryChoice(Recovery.ORDER, orderId, Recovery.SIMILAR_SHOPS) } }
    LaunchedEffect(orderId, attempt) {
        failed = false
        val r = runCatching { Backend.orderAlternatives(orderId) }
        r.exceptionOrNull()?.let { if (it is CancellationException) throw it }
        shops = r.getOrNull(); failed = r.isFailure
    }
    Column(Modifier.fillMaxSize()) {
        BucksTopBar(stringResource(R.string.sw_similar_title), onBack = onBack)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Muted(stringResource(R.string.sw_similar_sub))
            val list = shops
            when {
                failed -> { Muted(stringResource(R.string.sw_similar_failed), Modifier.padding(top = 16.dp)); PrimaryButton(stringResource(R.string.sw_try_again), Modifier.padding(top = 12.dp)) { attempt++ } }
                list == null -> CircularProgressIndicator(Modifier.padding(top = 24.dp))
                list.isEmpty() -> Muted(stringResource(R.string.sw_similar_none), Modifier.padding(top = 16.dp))
                else -> list.forEach { s ->
                    Spacer(Modifier.height(12.dp))
                    BucksCard(onClick = { onOpenListing(s.listingId) }) {
                        ListRow(s.title, listOf(s.area, formatDistance(s.distanceM)).filter { it.isNotBlank() }.joinToString(" · "),
                            leading = { Avatar(icon = Icons.Rounded.Storefront, photoUrl = s.photoUrl) })
                        Muted(stringResource(R.string.sw_similar_has, s.matchedItems.joinToString(", ")) + (s.minPrice?.let { " · " + stringResource(R.string.sw_similar_from, Money.format(it)) } ?: ""),
                            Modifier.padding(top = 6.dp))
                    }
                }
            }
        }
    }
}
