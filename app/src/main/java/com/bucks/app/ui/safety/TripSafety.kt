package com.bucks.app.ui.safety

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material.icons.rounded.Sos
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.BackendSafety
import com.bucks.app.data.LatLng
import com.bucks.app.data.RideAlert
import com.bucks.app.data.SosQueueRow
import com.bucks.app.data.SosResult
import com.bucks.app.data.TrustedContact
import com.bucks.app.ui.components.*
import com.bucks.app.ui.dial
import com.bucks.app.ui.shareText
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Trip safety (supabase/migrations/trip_safety.sql, docs/SAFETY.md): the SOS sheet on every trip screen (riders and drivers), the live
 * trip link, the "Are you OK?" card, trusted contacts in Settings → Safety, and the staff SOS queue. SOS always works without the
 * server too: the phone dials 112 and the SMS app opens with a message, whether or not Bucks could be reached.
 */
object TripSafety {
    fun tripUrl(token: String) = "https://infin8sync69-source.github.io/bucks-Mobile/trip/#$token"
    fun mapUrl(p: LatLng) = "https://maps.google.com/?q=%.6f,%.6f".format(java.util.Locale.ROOT, p.lat, p.lng)

    /** One SMS to several people, written by the phone's own SMS app (no permission; the person presses send). */
    fun textMany(ctx: Context, phones: List<String>, body: String) {
        val to = phones.joinToString(";") { it.filter { c -> c.isDigit() || c == '+' } }
        runCatching { ctx.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$to")).putExtra("sms_body", body).putExtra(Intent.EXTRA_TEXT, body)) }
            .onFailure { shareText(ctx, body) }
    }

    /** Fetches the live link for [taskId] and shares [text] with it; without one (offline, demo), shares [fallback]. */
    suspend fun shareTrip(ctx: Context, taskId: String?, cloud: Boolean, fallback: String, text: (String) -> String) {
        val token = if (cloud && taskId != null) runCatching { BackendSafety.tripShareLink(taskId) }.getOrNull() else null
        shareText(ctx, token?.let { text(tripUrl(it)) } ?: fallback)
    }
}

/** The SOS button for a trip screen. [here] is read when it is pressed. */
@Composable
fun SosAction(taskId: String?, cloud: Boolean, here: () -> LatLng?) {
    var open by remember { mutableStateOf(false) }
    IconAction(Icons.Rounded.Sos, stringResource(R.string.sf_sos)) { open = true }
    if (open) SosSheet(taskId, cloud, here) { open = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SosSheet(taskId: String?, cloud: Boolean, here: () -> LatLng?, onDismiss: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var result by remember { mutableStateOf<SosResult?>(null) }
    var failed by remember { mutableStateOf(false) }
    val at = remember { here() }
    LaunchedEffect(Unit) {
        if (!cloud) { failed = true; return@LaunchedEffect }
        runCatching { BackendSafety.raiseSos(taskId, at?.lat, at?.lng) }.onSuccess { result = it }.onFailure { failed = true }
    }
    // Without the server: still a message with the location, for the SMS app.
    val offline = "SOS: I need help." + (at?.let { " My location: ${TripSafety.mapUrl(it)}" } ?: "") + " If you can't reach me, call 112."
    val message = result?.message?.takeIf { it.isNotBlank() } ?: offline
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = Gutter).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.sf_sos_title), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            Text(when { result != null -> stringResource(R.string.sf_sos_sent); failed -> stringResource(R.string.sf_sos_failed); else -> stringResource(R.string.sf_sos_sending) },
                style = MaterialTheme.typography.bodyMedium, color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            Button({ dial(ctx, "112") }, Modifier.fillMaxWidth().height(56.dp), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError)) {
                Text(stringResource(R.string.sf_call_112), style = MaterialTheme.typography.titleMedium)
            }
            val contacts = result?.contacts.orEmpty()
            if (contacts.isNotEmpty()) PrimaryButton(stringResource(R.string.sf_text_contacts, contacts.size)) { TripSafety.textMany(ctx, contacts.map { it.phone }, message) }
            else { GhostButton(stringResource(R.string.sf_text_someone)) { shareText(ctx, message) }; Muted(stringResource(R.string.sf_add_contacts_hint)) }
            if (result?.shareToken != null) GhostButton(stringResource(R.string.sf_share_live)) { shareText(ctx, message) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                result?.let { r -> TextButton({ scope.launch { runCatching { BackendSafety.cancelSos(r.sosId) }; onDismiss() } }) { Text(stringResource(R.string.sf_im_safe)) } } ?: Spacer(Modifier)
                TextButton(onDismiss) { Text(stringResource(R.string.sf_close)) }
            }
        }
    }
}

/** "Are you OK?" while a ride is in progress: the server's ride_watch flags long stops, a drift off the route, or a silent driver phone. */
@Composable
fun RideCheckCard(taskId: String, cloud: Boolean, here: () -> LatLng?) {
    if (!cloud) return
    val scope = rememberCoroutineScope()
    var alerts by remember(taskId) { mutableStateOf<List<RideAlert>>(emptyList()) }
    var sos by remember { mutableStateOf(false) }
    LaunchedEffect(taskId) { while (true) { alerts = runCatching { BackendSafety.myRideAlerts(taskId) }.getOrDefault(alerts); delay(30_000) } }
    val a = alerts.firstOrNull() ?: return
    Card(Modifier.fillMaxWidth().padding(vertical = 8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer)) {
        Column(Modifier.padding(16.dp).semantics { liveRegion = LiveRegionMode.Assertive }) {
            Text(stringResource(R.string.sf_check_title), style = MaterialTheme.typography.titleMedium)
            Text(when (a.kind) { "STOPPED" -> stringResource(R.string.sf_check_STOPPED); "OFF_ROUTE" -> stringResource(R.string.sf_check_OFF_ROUTE); else -> stringResource(R.string.sf_check_SILENT) }, style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(R.string.sf_check_hint), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp))
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button({ scope.launch { runCatching { BackendSafety.answerRideAlert(taskId, true) }; alerts = emptyList() } }, Modifier.weight(1f)) { Text(stringResource(R.string.sf_check_ok)) }
                Button({ scope.launch { runCatching { BackendSafety.answerRideAlert(taskId, false) } }; alerts = emptyList(); sos = true }, Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError)) { Text(stringResource(R.string.sf_sos)) }
            }
        }
    }
    if (sos) SosSheet(taskId, cloud, here) { sos = false }
}

/** Settings → Safety: add and remove up to 5 trusted contacts. */
@Composable
fun TrustedContactsSection() {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf<List<TrustedContact>>(emptyList()) }
    var name by remember { mutableStateOf("") }; var phone by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }; var busy by remember { mutableStateOf(false) }
    suspend fun reload() { list = runCatching { BackendSafety.trustedContacts() }.getOrDefault(list) }
    LaunchedEffect(Unit) { reload() }
    Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
        Text(stringResource(R.string.sf_contacts_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Muted(stringResource(R.string.sf_contacts_d), Modifier.padding(top = 4.dp))
        list.forEach { c ->
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Text(c.name, style = MaterialTheme.typography.titleSmall); Muted(c.phone) }
                IconButton({ scope.launch { runCatching { BackendSafety.removeTrustedContact(c.id) }; reload() } }) { Icon(Icons.Rounded.Delete, stringResource(R.string.sf_contacts_remove, c.name)) }
            }
        }
        if (list.size >= 5) Muted(stringResource(R.string.sf_contacts_full), Modifier.padding(top = 8.dp))
        else {
            BucksField(name, { name = it.take(60) }, stringResource(R.string.sf_contacts_name), modifier = Modifier.padding(top = 12.dp))
            BucksField(phone, { phone = it.filter { c -> c.isDigit() || c == '+' }.take(13) }, stringResource(R.string.sf_contacts_phone), "98765 43210", Modifier.padding(top = 8.dp))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp)) }
            PrimaryButton(stringResource(R.string.sf_contacts_add), Modifier.padding(top = 10.dp), enabled = !busy && name.isNotBlank() && phone.count { it.isDigit() } >= 10) {
                busy = true; error = null
                scope.launch {
                    runCatching { BackendSafety.addTrustedContact(name.trim(), phone) }
                        .onSuccess { name = ""; phone = ""; reload() }
                        .onFailure { e -> error = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message.orEmpty())?.groupValues?.get(1) ?: e.message }
                    busy = false
                }
            }
        }
    }
}

/** Staff: open SOS alerts with one tap to call the person, open the live trip, or close the alert. */
@Composable
fun StaffSosSection() {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<SosQueueRow>?>(null) }
    LaunchedEffect(Unit) { while (true) { rows = runCatching { BackendSafety.sosQueue() }.getOrDefault(rows ?: emptyList()); delay(20_000) } }
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Text(stringResource(R.string.sf_staff_sos), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        val list = rows.orEmpty()
        if (rows != null && list.isEmpty()) Muted(stringResource(R.string.sf_staff_sos_none), Modifier.padding(top = 4.dp))
        list.forEach { r ->
            Card(Modifier.fillMaxWidth().padding(top = 8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                Column(Modifier.padding(14.dp)) {
                    Text("${r.name.ifBlank { "Someone" }} · ${r.role}", style = MaterialTheme.typography.titleSmall)
                    Muted(listOfNotNull(r.createdAt.take(16).replace('T', ' '), r.vehicle, r.otherName?.let { "with $it" }, r.taskStatus).joinToString(" · "))
                    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        r.phone?.let { p -> SmallButton(stringResource(R.string.sf_staff_call, r.name.substringBefore(' ').ifBlank { "them" })) { dial(ctx, p) } }
                        r.otherPhone?.let { p -> SmallButton(stringResource(R.string.sf_staff_call, r.otherName?.substringBefore(' ') ?: "other"), tonal = true) { dial(ctx, p) } }
                    }
                    Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        r.tripLink?.let { l -> SmallButton(stringResource(R.string.sf_staff_open_trip), tonal = true) { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(l))) } } }
                        if (r.lat != null && r.lng != null) SmallButton(stringResource(R.string.sf_staff_map), tonal = true) { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(TripSafety.mapUrl(LatLng(r.lat, r.lng))))) } }
                        SmallButton(stringResource(R.string.sf_staff_close), tonal = true) { scope.launch { runCatching { BackendSafety.closeSos(r.id, "Handled by staff") }; rows = runCatching { BackendSafety.sosQueue() }.getOrDefault(rows ?: emptyList()) } }
                    }
                }
            }
        }
    }
}
