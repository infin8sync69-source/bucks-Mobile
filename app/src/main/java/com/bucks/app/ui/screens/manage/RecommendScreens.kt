package com.bucks.app.ui.screens.manage

import com.bucks.app.data.Str
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
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
        BucksTopBar(stringResource(R.string.g7_rec_get_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(l?.title ?: stringResource(R.string.g7_rec_your_listing), style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            if (l != null && l.status == "LIVE") {
                Spacer(Modifier.height(24.dp)); Avatar(icon = Icons.Rounded.Check, size = 72)
                Text(stringResource(R.string.g7_rec_live), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 14.dp))
                Muted(pluralStringResource(R.plurals.g7_rec_live_body, n, n, l.title), Modifier.padding(top = 6.dp), TextAlign.Center)
                SmallButton(stringResource(R.string.g7_rec_back_listings), Modifier.padding(top = 20.dp), onClick = onBack)
            } else {
                Muted(stringResource(R.string.g7_rec_ask_scan), Modifier.padding(top = 4.dp, bottom = 16.dp), TextAlign.Center)
                Box(Modifier.size(260.dp).clip(MaterialTheme.shapes.medium).background(Color.White).padding(10.dp), contentAlignment = Alignment.Center) {
                    if (qr != null) Image(qr.asImageBitmap(), stringResource(R.string.g7_cd_rec_qr), Modifier.fillMaxSize()) else BucksLoader(Modifier.align(Alignment.Center))
                }
                Text(stringResource(R.string.g7_rec_n_of, n, NEEDED), style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold), modifier = Modifier.padding(top = 16.dp))
                Muted(if (n == 0) stringResource(R.string.g7_rec_none) else pluralStringResource(R.plurals.g7_rec_people_have, n))
                LinearProgressIndicator(progress = { (n.toFloat() / NEEDED).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).height(8.dp).clip(CircleShape))
                Muted(stringResource(R.string.g7_rec_code_changes), Modifier.padding(top = 10.dp), TextAlign.Center)
                Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SmallButton(stringResource(R.string.g7_rec_share_help), Modifier.weight(1f)) {
                        shareText(ctx, Str.plural(R.plurals.g7_rec_share_text, NEEDED, l?.title ?: Str.get(R.string.g7_rec_my_work), NEEDED))
                    }
                    SmallButton(stringResource(R.string.g7_rec_new_code), Modifier.weight(0.7f), tonal = true) { m.refreshToken(listingId) }
                }
                SectionTitle(stringResource(R.string.g7_rec_who_can_you), Modifier.padding(top = 24.dp, bottom = 4.dp))
                RecommendRules()
                Notice(pluralStringResource(R.plurals.g7_rec_ask_regulars, NEEDED, NEEDED), Modifier.padding(top = 12.dp))
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
        val at = fix ?: run { vm.toast(Str.get(R.string.g7_rec_need_location)); return }
        scanQr(ctx, onResult = { raw ->
            when (val s = BucksQr.parse(raw)) {
                is BucksQr.Scanned.Recommendation -> m.recommend(s.token, at) { result = it }
                is BucksQr.Scanned.BucksId -> vm.toast(Str.get(R.string.g7_rec_is_bucks_id))
                else -> vm.toast(Str.get(R.string.g7_rec_not_code))
            }
        }, onError = { vm.toast(it) })
    }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g7_rec_scan_title), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(icon = Icons.Rounded.QrCodeScanner, size = 72)
                Text(stringResource(R.string.g7_rec_scan_code), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 14.dp))
                Muted(stringResource(R.string.g7_rec_scan_body), Modifier.padding(top = 6.dp), TextAlign.Center)
            }
            if (!st.locationGranted) Notice(stringResource(R.string.g7_rec_location_off), Modifier.padding(top = 14.dp))
            else if (fix == null) Notice(stringResource(R.string.g7_rec_waiting_location), Modifier.padding(top = 14.dp))
            PrimaryButton(stringResource(R.string.g7_rec_open_scanner), Modifier.padding(top = 16.dp), enabled = fix != null) { scan() }
            result?.let { n ->
                BucksCard(Modifier.padding(top = 14.dp), tint = true) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.ArrowUpward, null, tint = MaterialTheme.colorScheme.onPrimaryContainer); Text("  " + stringResource(R.string.g7_rec_thanks, n, NEEDED), style = MaterialTheme.typography.titleMedium) }
                    Muted(if (n >= NEEDED) stringResource(R.string.g7_rec_they_live) else pluralStringResource(R.plurals.g7_rec_they_need, NEEDED - n, NEEDED - n), Modifier.padding(top = 4.dp))
                }
            }
            SectionTitle(stringResource(R.string.g7_rec_who_can), Modifier.padding(top = 24.dp, bottom = 4.dp))
            RecommendRules()
            Notice(stringResource(R.string.g7_rec_only_known), Modifier.padding(top = 12.dp))
            Spacer(Modifier.height(16.dp))
        }
    }
}
