package com.bucks.app.ui.screens.commerce

import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.data.CloudOrderRow
import com.bucks.app.data.OrderLine
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Locale

/* ---------- words the buyer and the shopkeeper see ---------- */

fun rupees(n: Int): String = "₹" + "%,d".format(n)

/** Short order id for receipts and UPI notes: the last 6 characters, upper case. */
fun shortOrderId(id: String) = id.replace("-", "").takeLast(6).uppercase()

fun deliveryModeLabel(mode: String) = when (mode) { "STORE_RIDER" -> "Store's own rider"; "PICKUP" -> "Pick up from the shop"; else -> "Delivery by a Bucks rider" }
fun paymentLabel(payment: String) = if (payment == "COD") "Cash on delivery" else "UPI"

/** Buyer-facing status, in plain words. */
fun orderStatusLabel(status: String, mode: String = "MARKETPLACE") = when (status) {
    "PLACED" -> "Waiting for the shop"
    "ACCEPTED" -> "Accepted"
    "READY" -> if (mode == "PICKUP") "Ready to collect" else "Packed"
    "PICKED_UP" -> "On the way"
    "DELIVERED" -> if (mode == "PICKUP") "Collected" else "Delivered"
    "REJECTED" -> "Not accepted"
    "CANCELLED" -> "Cancelled"
    else -> status.lowercase().replaceFirstChar { it.uppercase() }
}
fun orderDone(status: String) = status in setOf("DELIVERED", "REJECTED", "CANCELLED")
fun orderLive(status: String) = status in setOf("PLACED", "ACCEPTED", "READY", "PICKED_UP")

@Composable
fun OrderStatusPill(status: String, mode: String = "MARKETPLACE") = when (status) {
    "DELIVERED" -> PillGood(orderStatusLabel(status, mode))
    "REJECTED", "CANCELLED" -> PillBad(orderStatusLabel(status, mode))
    "PLACED" -> PillWarn(orderStatusLabel(status, mode))
    else -> PillPurple(orderStatusLabel(status, mode))
}

/** "2 × Toor dal, 1 × Rice" for list rows. */
fun orderLinesSummary(lines: List<OrderLine>) = lines.joinToString(", ") { "${it.qty} × ${it.name}" }

@Composable
fun OrderLineRow(line: OrderLine) = Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
    Text("${line.name} × ${line.qty}", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
    Text(rupees(line.price * line.qty), style = MaterialTheme.typography.titleSmall)
}

/**
 * Subtotal, delivery fee (and who it is paid to) and what goes to the shop. A marketplace rider's fee is paid to the rider at the
 * door, never through the shop, so it is shown under the shop's amount instead of inside it ([CloudOrderRow.feeAtDoor]).
 * [forShop] words it for the shop owner or admin looking at their own order.
 */
@Composable
fun OrderTotals(o: CloudOrderRow, forShop: Boolean = false) {
    Row(Modifier.padding(top = 6.dp)) { Muted("Items", Modifier.weight(1f)); Muted(rupees(o.subtotal)) }
    if (o.deliveryMode != "PICKUP") Row(Modifier.padding(top = 4.dp)) {
        Muted(if (o.feeAtDoor > 0) "Delivery fee · to the rider" else "Delivery fee", Modifier.weight(1f))
        Muted(if (o.feePaidBy == "VENDOR") "${rupees(o.deliveryFee)} · ${if (forShop) "paid by you" else "paid by the shop"}" else rupees(o.deliveryFee))
    }
    Divider()
    Row(Modifier.padding(top = 8.dp)) {
        Text(when {
            forShop -> if (o.payment == "COD") "Customer pays in cash" else "Customer pays you"
            o.payment == "COD" -> "To pay in cash"
            o.feeAtDoor > 0 -> "To pay the shop"
            else -> "To pay"
        }, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Text(rupees(o.toShop), style = MaterialTheme.typography.titleLarge)
    }
    if (o.feeAtDoor > 0) Muted(if (forShop) "The customer pays the rider's ${rupees(o.feeAtDoor)} fee to the rider at the door." else "+ ${rupees(o.feeAtDoor)} to the rider at the door (UPI or cash).", Modifier.padding(top = 4.dp))
    else if (forShop && o.feePaidBy == "VENDOR" && o.deliveryMode == "MARKETPLACE") Muted("Free delivery: hand the rider ${rupees(o.deliveryFee)} when they collect it.", Modifier.padding(top = 4.dp))
}

/* ---------- time ---------- */

/** Epoch millis from a Postgres timestamp ("2025-01-02 10:11:12.345+00", "...+00:00" or "...Z"); 0 when unreadable. */
fun epochMillis(iso: String): Long {
    val t = iso.trim().replace(" ", "T").let { if (it.endsWith("Z") || Regex("[+-]\\d\\d(:?\\d\\d)?$").containsMatchIn(it)) it else it + "Z" }
        .let { if (Regex("[+-]\\d\\d$").containsMatchIn(it)) it + ":00" else it }
    return runCatching { OffsetDateTime.parse(t).toInstant().toEpochMilli() }.recoverCatching { Instant.parse(t).toEpochMilli() }.getOrDefault(0L)
}

fun mmss(millis: Long): String { val s = (millis / 1000).coerceAtLeast(0); return String.format(Locale.US, "%d:%02d", s / 60, s % 60) }

/* ---------- listing details flags ---------- */

fun JsonObject.flag(key: String): Boolean = runCatching { val p = this[key]?.jsonPrimitive; p != null && (p.booleanOrNull ?: p.content.equals("true", ignoreCase = true)) }.getOrDefault(false)

/* ---------- UPI and phone ---------- */

/** The shop's upi://pay link with the amount and a note filled in (am and tn replaced if present, cu=INR added if missing). */
fun upiPayUri(base: String, amount: Int, note: String): String {
    val u = Uri.parse(base.trim())
    val b = Uri.Builder().scheme(u.scheme ?: "upi").authority(u.authority ?: "pay")
    val keep = runCatching { u.queryParameterNames }.getOrDefault(emptySet()).filter { it != "am" && it != "tn" }
    keep.forEach { k -> runCatching { u.getQueryParameter(k) }.getOrNull()?.let { b.appendQueryParameter(k, it) } }
    if ("cu" !in keep) b.appendQueryParameter("cu", "INR")
    b.appendQueryParameter("am", String.format(Locale.US, "%d.00", amount))
    b.appendQueryParameter("tn", note)
    return b.build().toString()
}

/** Opens the UPI app chooser; false when no UPI app is installed. */
fun openUpi(ctx: Context, uri: String): Boolean = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri))); true }.getOrDefault(false)

/** A short ring and buzz for a new order while the inbox is open; no permission needed for the default notification sound. */
fun alertNewOrder(ctx: Context) {
    runCatching { RingtoneManager.getRingtone(ctx, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))?.play() }
    runCatching {
        val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                          else @Suppress("DEPRECATION") (ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300), -1)) else @Suppress("DEPRECATION") v.vibrate(600)
    }
}
