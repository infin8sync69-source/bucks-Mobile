package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.shareText
import kotlinx.coroutines.delay

/**
 * The owner's side of the community cap: a QR code that neighbours scan in person. The token
 * behind it lasts 2 minutes on the server, so a new one is fetched every 90 seconds while open.
 */
@Composable
fun RecommendShowScreen(vm: BucksViewModel, listingId: String, onBack: () -> Unit) {
    val m = vm.myListings; val ctx = LocalContext.current
    LaunchedEffect(listingId) { if (!m.loaded) m.refresh(); while (true) { m.refreshToken(listingId); delay(90_000) } }
    DisposableEffect(listingId) { onDispose { m.clearToken() } }
    val l = m.listing(listingId); val n = m.recommendations[listingId] ?: 0; val token = m.token
    val qr = remember(token) { token?.let { qrBitmap(BucksQr.forRecommendation(it), 640) } }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Get recommended", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(l?.title ?: "Your listing", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            if (l != null && l.status == "LIVE") {
                Spacer(Modifier.height(24.dp)); Avatar(icon = Icons.Rounded.Check, size = 72)
                Text("You're live", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 14.dp))
                Muted("$n people nearby recommended ${l.title}. Customers nearby can find it now. Switch it on from My listings to start taking work.", Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton("Back to my listings", Modifier.padding(top = 20.dp), onClick = onBack)
            } else {
                Muted("Ask someone nearby to open Bucks and scan this", Modifier.padding(top = 4.dp, bottom = 16.dp), TextAlign.Center)
                Box(Modifier.size(260.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(10.dp), contentAlignment = Alignment.Center) {
                    if (qr != null) Image(qr.asImageBitmap(), "Recommendation QR code", Modifier.fillMaxSize()) else BucksLoader(Modifier.align(Alignment.Center))
                }
                Text("$n of $NEEDED", style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold), modifier = Modifier.padding(top = 16.dp))
                Muted(if (n == 0) "No recommendations yet" else "people nearby have recommended you")
                LinearProgressIndicator(progress = { (n.toFloat() / NEEDED).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).height(8.dp).clip(CircleShape))
                Muted("The code changes every 90 seconds. Keep this screen open while they scan; the count updates on its own.", Modifier.padding(top = 10.dp), TextAlign.Center)
                Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SmallButton("Share how to help", Modifier.weight(1f)) {
                        shareText(ctx, "I've listed ${l?.title ?: "my work"} on Bucks and need $NEEDED people nearby to recommend it before it goes live. If you live within 3 km and have had Bucks for over 2 weeks, come by and scan the code on my phone: open Bucks, My listings, Recommend a local. Thank you!")
                    }
                    SmallButton("New code", Modifier.weight(0.7f), tonal = true) { m.refreshToken(listingId) }
                }
                SectionTitle("Who can recommend you", Modifier.padding(top = 24.dp, bottom = 4.dp))
                RecommendRules()
                Notice("Ask regular customers and people nearby who know your work. When $NEEDED have scanned, the listing goes live on its own and you'll see it under My listings.", Modifier.padding(top = 12.dp))
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** The neighbour's side: scan the code an owner shows and recommend them, if the server's rules allow. */
@Composable
fun RecommendScanScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val m = vm.myListings; val ctx = LocalContext.current; val st by vm.state.collectAsState()
    var result by remember { mutableStateOf<Int?>(null) }
    // The scanner needs a real location fix: the server's "in person" check compares where the scanner stands with the
    // listing, and the map's default centre would pass it for every listing within 3 km of Jayanagar, photo of the code or not.
    val fix = st.me
    fun scan() {
        val at = fix ?: run { vm.toast("Turn on location first. Recommendations only count when you scan in person, near their shop."); return }
        scanQr(ctx, onResult = { raw ->
            when (val s = BucksQr.parse(raw)) {
                is BucksQr.Scanned.Recommendation -> m.recommend(s.token, at) { result = it }
                is BucksQr.Scanned.BucksId -> vm.toast("That's someone's Bucks ID for syncing, not a recommendation code. Ask them to open Get recommended.")
                else -> vm.toast("That isn't a Bucks recommendation code.")
            }
        }, onError = { vm.toast(it) })
    }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Recommend a local", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.QrCodeScanner, size = 72)
                Text("Scan their code", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 14.dp))
                Muted("Ask the shop owner, driver or worker to open Get recommended on their phone, then scan the code it shows. Your recommendation helps them go live for everyone nearby.", Modifier.padding(top = 6.dp), TextAlign.Center)
            }
            if (!st.locationGranted) Notice("Turn on location for Bucks first. Recommendations only count when you scan in person, near their shop.", Modifier.padding(top = 14.dp))
            else if (fix == null) Notice("Waiting for your location… The scanner opens once Bucks knows where you are, so the recommendation counts as in person.", Modifier.padding(top = 14.dp))
            PrimaryButton("Open the scanner", Modifier.padding(top = 16.dp), enabled = fix != null) { scan() }
            result?.let { n ->
                BucksCard(Modifier.padding(top = 14.dp), tint = true) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ThumbUp, null, tint = MaterialTheme.colorScheme.onPrimaryContainer); Text("  Thanks, that's $n of $NEEDED", style = MaterialTheme.typography.titleMedium) }
                    Muted(if (n >= NEEDED) "They're live on Bucks now. Neighbours can find and order from them." else "They need ${NEEDED - n} more. Know someone else nearby who rates them? Tell them.", Modifier.padding(top = 4.dp))
                }
            }
            SectionTitle("Who can recommend", Modifier.padding(top = 24.dp, bottom = 4.dp))
            RecommendRules()
            Notice("Recommend only people whose work you know. One recommendation per listing; it's how your neighbourhood decides who gets listed.", Modifier.padding(top = 12.dp))
            Spacer(Modifier.height(16.dp))
        }
    }
}
