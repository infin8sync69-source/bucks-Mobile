package com.bucks.app.ui.screens.commerce

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bucks.app.data.CloudOrderRow
import com.bucks.app.ui.components.*

/** Couriers a shop is likely to use; "Other" asks for a name, "Self delivery" means the shop delivers it itself. */
private val CARRIERS = listOf("Delhivery", "DTDC", "Blue Dart", "India Post", "Ecom Express", "XpressBees", "Shadowfax", "Self delivery", "Other")

/** The shop hands an accepted order to a carrier: which one, the tracking number and (optionally) a link the customer can open. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ShipSheet(onDismiss: () -> Unit, onShip: (carrier: String, tracking: String, url: String) -> Unit) {
    var pick by remember { mutableStateOf("Delhivery") }; var other by remember { mutableStateOf("") }; var tracking by remember { mutableStateOf("") }; var url by remember { mutableStateOf("") }
    val carrier = if (pick == "Other") other.trim() else pick
    val urlOk = url.isBlank() || Regex("https?://\\S+").matches(url.trim())
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Text("Mark as shipped", style = MaterialTheme.typography.titleLarge)
            Muted("The customer is told and sees the carrier and tracking number.", Modifier.padding(top = 4.dp, bottom = 8.dp))
            Label("Carrier")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { CARRIERS.forEach { c -> Chip(c, selected = pick == c) { pick = c } } }
            Spacer(Modifier.height(12.dp))
            if (pick == "Other") BucksField(other, { other = it.take(60) }, "Carrier name", "e.g. Local courier")
            if (pick != "Self delivery") {
                BucksField(tracking, { tracking = it.take(60) }, "Tracking number", "Optional but helps the customer")
                BucksField(url, { url = it.take(300) }, "Tracking link (optional)", "https://…", keyboard = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Uri))
                if (!urlOk) Muted("The link must start with http:// or https://", Modifier.padding(bottom = 8.dp))
            } else Muted("You'll deliver it yourself, so no tracking number is needed. Mark it delivered once it reaches them.", Modifier.padding(bottom = 8.dp))
            Button({ onShip(carrier, if (pick == "Self delivery") "" else tracking.trim(), if (pick == "Self delivery") "" else url.trim()) }, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = carrier.isNotBlank() && urlOk) { Text("Mark shipped") }
        }
    }
}

/** Carrier and tracking for a shipped order, with a Copy button and a link that opens the carrier's tracking page. */
@Composable
fun ShipmentCard(o: CloudOrderRow, modifier: Modifier = Modifier) {
    if (!o.shipped || o.carrier.isBlank()) return
    val ctx = LocalContext.current
    BucksCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.LocalShipping, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(if (o.carrier.equals("Self delivery", true)) "Delivered by the shop" else "Shipped with ${o.carrier}", style = MaterialTheme.typography.titleMedium)
                if (o.trackingNo.isNotBlank()) Muted("Tracking ${o.trackingNo}")
                o.shippedAt?.let { Muted("Shipped ${com.bucks.app.ui.screens.ago(it)}") }
            }
        }
        if (o.trackingNo.isNotBlank() || o.trackingUrl.isNotBlank()) Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (o.trackingNo.isNotBlank()) SmallButton("Copy number", tonal = true) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Tracking number", o.trackingNo)); android.widget.Toast.makeText(ctx, "Tracking number copied", android.widget.Toast.LENGTH_SHORT).show() }
            if (o.trackingUrl.isNotBlank()) SmallButton("Track shipment") { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(o.trackingUrl))) } }
        }
    }
}

/** Where a shipped order goes, as the shop writes it on the parcel and the buyer confirms it. */
@Composable
fun ShipToCard(o: CloudOrderRow, modifier: Modifier = Modifier) {
    if (!o.shipped || o.shipToText.isBlank()) return
    BucksCard(modifier) {
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Rounded.LocationOn, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.padding(start = 12.dp)) { Text("Ship to", style = MaterialTheme.typography.titleMedium); Text(o.shipToText, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 4.dp)) }
        }
    }
}
