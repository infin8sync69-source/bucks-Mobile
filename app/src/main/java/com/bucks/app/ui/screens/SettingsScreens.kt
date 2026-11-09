package com.bucks.app.ui.screens

import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Prefs
import com.bucks.app.data.SettingsRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.VOICE_LANGS
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive

/* ---------- reusable rows ---------- */

@Composable fun SettingRow(icon: ImageVector, label: String, detail: String? = null, onClick: () -> Unit) { ListRow(label, detail, leading = { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, trailing = { Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }, onClick = onClick); Divider() }
@Composable fun ToggleRow(label: String, detail: String? = null, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(label, style = MaterialTheme.typography.titleMedium); detail?.let { Muted(it) } }; Switch(on, onChange) }
    Divider()
}
/** A titled group of radio choices. */
@Composable fun <T> ChoiceGroup(title: String, detail: String? = null, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Column(Modifier.padding(vertical = 8.dp)) { Text(title, style = MaterialTheme.typography.titleMedium); detail?.let { Muted(it) }
        options.forEach { (v, l) -> Row(Modifier.fillMaxWidth().clickable { onSelect(v) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { RadioButton(v == selected, { onSelect(v) }); Text(l, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 4.dp)) } } }
    Divider()
}

/* ---------- hub ---------- */

/** Settings home. [identity] is the Bucks ID card (cloud) or the demo verification card. */
@Composable
fun SettingsHub(vm: BucksViewModel, identity: @Composable () -> Unit, onOpen: (String) -> Unit, onEditProfile: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit, showToast: (String) -> Unit) {
    val s by vm.state.collectAsState(); val cloud = vm.social.enabled
    var deleteDialog by remember { mutableStateOf(false) }
    val privacyOffline = stringResource(R.string.g1_set_privacy_offline); val notifsOffline = stringResource(R.string.g1_set_notifs_offline); val rulesText = stringResource(R.string.g1_set_rules_text)
    SectionTitle(stringResource(R.string.g1_set_identity), Modifier.padding(bottom = 10.dp)); identity()
    SectionTitle(stringResource(R.string.g1_set_preferences), Modifier.padding(top = 22.dp, bottom = 6.dp))
    SettingRow(Icons.Rounded.Person, stringResource(R.string.g1_set_edit_profile), onClick = onEditProfile)
    if (cloud) SettingRow(Icons.Rounded.Sync, stringResource(R.string.g1_set_sync), stringResource(R.string.g1_set_sync_detail)) { onOpen(Routes.SYNC) }
    SettingRow(Icons.Rounded.Lock, stringResource(R.string.g1_set_privacy), if (cloud) stringResource(R.string.g1_set_privacy_detail) else stringResource(R.string.g1_set_privacy_signed_out)) { if (cloud) onOpen(Routes.SETTINGS_PRIVACY) else showToast(privacyOffline) }
    SettingRow(Icons.Rounded.Notifications, stringResource(R.string.g1_set_notifs), stringResource(R.string.g1_set_notifs_detail)) { if (cloud) onOpen(Routes.SETTINGS_NOTIFS) else showToast(notifsOffline) }
    SettingRow(Icons.Rounded.Palette, stringResource(R.string.g1_set_appearance), stringResource(R.string.g1_set_appearance_detail)) { onOpen(Routes.SETTINGS_APPEARANCE) }
    if (cloud) { SettingRow(Icons.Rounded.Block, stringResource(R.string.g1_set_blocked)) { onOpen(Routes.SETTINGS_BLOCKED) }; SettingRow(Icons.Rounded.Place, stringResource(R.string.g1_set_map), stringResource(R.string.g1_set_map_detail)) { onOpen(Routes.SETTINGS_MAP) }; SettingRow(Icons.Rounded.Favorite, stringResource(R.string.g1_set_close), stringResource(R.string.g1_set_close_detail)) { onOpen(Routes.SETTINGS_CLOSE) } }
    LaunchedEffect(cloud) { if (cloud) vm.services.checkStaff() }
    if (vm.services.isStaff) SettingRow(Icons.Rounded.FactCheck, stringResource(R.string.g1_set_review_docs), stringResource(R.string.g1_set_review_docs_detail)) { onOpen(Routes.STAFF_REVIEW) }
    if (vm.dispatch.enabled) ListRow(stringResource(R.string.g1_set_payment_qr), stringResource(R.string.g1_set_payment_qr_detail), leading = { Avatar(icon = Icons.Rounded.QrCode2) }, trailing = { Icon(Icons.Rounded.ChevronRight, null) }) { onOpen(Routes.PAYMENT_QR) }
    VoiceAiCard(vm)
    SectionTitle(stringResource(R.string.g1_set_about), Modifier.padding(top = 22.dp, bottom = 6.dp))
    val ctx = androidx.compose.ui.platform.LocalContext.current
    SettingRow(Icons.Rounded.SystemUpdate, stringResource(R.string.g1_set_app_version), stringResource(if (com.bucks.app.data.AppUpdate.enabled) (if (vm.updates.checking) R.string.g1_set_build_checking else R.string.g1_set_build_switch) else R.string.g1_set_build_play, com.bucks.app.data.AppUpdate.currentBuild.toString())) { onOpen(com.bucks.app.ui.nav.Routes.APP_VERSIONS) }
    SettingRow(Icons.Rounded.Gavel, stringResource(R.string.g1_set_rules)) { showToast(rulesText) }
    SectionTitle(stringResource(R.string.g1_set_account), Modifier.padding(top = 22.dp, bottom = 6.dp))
    SettingRow(Icons.Rounded.Logout, stringResource(R.string.g1_set_logout), onClick = onLogout)
    SettingRow(Icons.Rounded.DeleteOutline, stringResource(R.string.g1_set_delete_account)) { deleteDialog = true }
    if (deleteDialog) AlertDialog(onDismissRequest = { deleteDialog = false }, title = { Text(stringResource(R.string.g1_set_delete_title)) },
        text = { Text(if (cloud) stringResource(R.string.g1_set_delete_body_cloud) else stringResource(R.string.g1_set_delete_body_local)) },
        confirmButton = { TextButton(onClick = { deleteDialog = false; vm.deleteAccount(); onDeleted() }) { Text(stringResource(R.string.g1_action_delete), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deleteDialog = false }) { Text(stringResource(R.string.g1_action_cancel)) } })
}

/* ---------- pages ---------- */

@Composable
fun PrivacyScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; val saved = social.settings ?: SettingsRow(social.me?.id ?: "")
    var row by remember(saved) { mutableStateOf(saved) }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g1_set_privacy), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ChoiceGroup(stringResource(R.string.g1_priv_message), stringResource(R.string.g1_priv_message_detail), listOf("SYNCED" to stringResource(R.string.g1_priv_synced_with), "EVERYONE" to stringResource(R.string.g1_priv_everyone), "NOBODY" to stringResource(R.string.g1_priv_nobody_new)), row.whoCanMessage) { row = row.copy(whoCanMessage = it) }
            ChoiceGroup(stringResource(R.string.g1_priv_sync), null, listOf("EVERYONE" to stringResource(R.string.g1_priv_everyone), "NOBODY" to stringResource(R.string.g1_priv_nobody)), row.whoCanSync) { row = row.copy(whoCanSync = it) }
            ChoiceGroup(stringResource(R.string.g1_priv_moments), stringResource(R.string.g1_priv_moments_detail), listOf("SYNCED" to stringResource(R.string.g1_priv_synced_people), "LOCAL" to stringResource(R.string.g1_priv_local), "CLOSE" to stringResource(R.string.g1_priv_close_only)), row.momentsAudience) { row = row.copy(momentsAudience = it) }
            ToggleRow(stringResource(R.string.g1_priv_receipts), stringResource(R.string.g1_priv_receipts_detail), row.readReceipts) { row = row.copy(readReceipts = it) }
            ToggleRow(stringResource(R.string.g1_priv_online), null, row.showOnline) { row = row.copy(showOnline = it) }
            ToggleRow(stringResource(R.string.g1_priv_suggest), stringResource(R.string.g1_priv_suggest_detail), row.discoverable) { row = row.copy(discoverable = it) }
            Muted(stringResource(R.string.g1_priv_phone_note), Modifier.padding(top = 12.dp))
            PrimaryButton(stringResource(R.string.g1_action_save), Modifier.padding(top = 20.dp), enabled = row != saved) { social.saveSettings(row) }
        }
    }
}

// Keys the notify Edge Function checks (supabase/functions/notify/index.ts, NotifyKey); a missing key means on, except offers.
private val NOTIFY_KEYS = listOf("messages" to R.string.g1_notify_messages, "sync_requests" to R.string.g1_notify_sync, "moments" to R.string.g1_notify_moments, "comments" to R.string.g1_notify_comments, "my_orders" to R.string.g1_notify_my_orders, "my_trips" to R.string.g1_notify_my_trips, "orders" to R.string.g1_notify_orders, "tasks" to R.string.g1_notify_tasks, "offers" to R.string.g1_notify_offers)

@Composable
fun NotificationsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; val saved = social.settings ?: SettingsRow(social.me?.id ?: "")
    var row by remember(saved) { mutableStateOf(saved) }
    fun on(k: String) = row.notify[k]?.jsonPrimitive?.booleanOrNull ?: (k != "offers")
    fun set(k: String, v: Boolean) { row = row.copy(notify = JsonObject(row.notify + (k to JsonPrimitive(v)))) }
    val quiet = row.quietHours; var qOn by remember(saved) { mutableStateOf(quiet != null) }
    var from by remember(saved) { mutableStateOf(quiet?.get("from")?.jsonPrimitive?.content ?: "22:00") }; var to by remember(saved) { mutableStateOf(quiet?.get("to")?.jsonPrimitive?.content ?: "07:00") }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g1_set_notifs), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            PhoneNotificationStatus()
            NOTIFY_KEYS.forEach { (k, l) -> ToggleRow(stringResource(l), null, on(k)) { set(k, it) } }
            ToggleRow(stringResource(R.string.g1_notif_quiet), stringResource(R.string.g1_notif_quiet_detail), qOn) { qOn = it }
            if (qOn) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) { BucksField(from, { from = it.take(5) }, stringResource(R.string.g1_notif_from), "22:00", Modifier.weight(1f)); BucksField(to, { to = it.take(5) }, stringResource(R.string.g1_notif_to), "07:00", Modifier.weight(1f)) }
            PrimaryButton(stringResource(R.string.g1_action_save), Modifier.padding(top = 20.dp)) {
                val q = if (qOn && Regex("^\\d{2}:\\d{2}$").matches(from) && Regex("^\\d{2}:\\d{2}$").matches(to)) JsonObject(mapOf("from" to JsonPrimitive(from), "to" to JsonPrimitive(to))) else null
                social.saveSettings(row.copy(quietHours = q)) }
            Muted(stringResource(R.string.g1_notif_note), Modifier.padding(top = 12.dp))
        }
    }
}

@Composable
fun AppearanceScreen(onBack: () -> Unit) {
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g1_set_appearance), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            ChoiceGroup(stringResource(R.string.g1_app_theme), null, Prefs.Theme.entries.map { it to it.label }, Prefs.theme) { Prefs.chooseTheme(it) }
            ChoiceGroup(stringResource(R.string.g1_app_text_size), null, Prefs.TextSize.entries.map { it to it.label }, Prefs.textSize) { Prefs.chooseTextSize(it) }
            ToggleRow(stringResource(R.string.g1_app_motion), stringResource(R.string.g1_app_motion_detail), Prefs.reduceMotion) { Prefs.enableReduceMotion(it) }
            ChoiceGroup(stringResource(R.string.g1_app_download), stringResource(R.string.g1_app_download_detail), Prefs.MediaDownload.entries.map { it to it.label }, Prefs.mediaDownload) { Prefs.chooseMediaDownload(it) }
            ToggleRow(stringResource(R.string.g1_app_data_saver), stringResource(R.string.g1_app_data_saver_detail), Prefs.dataSaver) { Prefs.enableDataSaver(it) }
            ToggleRow(stringResource(R.string.g1_app_usage), stringResource(R.string.g1_app_usage_detail), Prefs.shareUsage) { Prefs.enableShareUsage(it) }
            ChoiceGroup(stringResource(R.string.g1_app_language), stringResource(R.string.g1_app_language_detail), com.bucks.app.data.AppLanguages.all.map { it.tag to it.native }, com.bucks.app.data.AppLanguages.current().tag) { Prefs.chooseLanguage(it) }
        }
    }
}

@Composable
fun BlockedScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; LaunchedEffect(Unit) { social.refreshBlocked() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g1_set_blocked), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (social.blocked.isEmpty()) Muted(stringResource(R.string.g1_blocked_empty))
            social.blocked.forEach { p -> PersonRow(p, trailing = { SmallButton(stringResource(R.string.g1_blocked_unblock), tonal = true) { social.unblock(p.id) } }) }
        }
    }
}

@Composable
fun CloseFriendsScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val social = vm.social; LaunchedEffect(Unit) { social.refreshSyncs() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g1_set_close), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Muted(stringResource(R.string.g1_close_note), Modifier.padding(bottom = 8.dp))
            if (social.synced.isEmpty()) Muted(stringResource(R.string.g1_close_empty))
            social.synced.forEach { p -> val on = p.id in social.closeFriends; PersonRow(p, trailing = { Checkbox(on, { social.setClose(p.id, it) }) }) }
        }
    }
}

/**
 * Whether this phone lets Bucks show notifications, with the fix and a test. The server can send a notification perfectly and the phone
 * still show nothing when Android has notifications switched off for the app (or, on Android 13+, permission was never granted).
 */
@Composable
private fun PhoneNotificationStatus() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var enabled by remember { mutableStateOf(androidx.core.app.NotificationManagerCompat.from(ctx).areNotificationsEnabled()) }
    val ask = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { enabled = androidx.core.app.NotificationManagerCompat.from(ctx).areNotificationsEnabled() }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) { val o = androidx.lifecycle.LifecycleEventObserver { _, e -> if (e == androidx.lifecycle.Lifecycle.Event.ON_RESUME) enabled = androidx.core.app.NotificationManagerCompat.from(ctx).areNotificationsEnabled() }; lifecycle.addObserver(o); onDispose { lifecycle.removeObserver(o) } }
    val testTitle = stringResource(R.string.g1_notif_test_title); val testBody = stringResource(R.string.g1_notif_test_body)
    BucksCard(Modifier.padding(bottom = 16.dp), tint = !enabled) {
        Text(if (enabled) stringResource(R.string.g1_notif_on) else stringResource(R.string.g1_notif_off), style = MaterialTheme.typography.titleSmall)
        Muted(if (enabled) stringResource(R.string.g1_notif_on_detail) else stringResource(R.string.g1_notif_off_detail), Modifier.padding(top = 4.dp))
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!enabled) SmallButton(stringResource(R.string.g1_notif_turn_on)) {
                if (android.os.Build.VERSION.SDK_INT >= 33) ask.launch(android.Manifest.permission.POST_NOTIFICATIONS) else ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName))
            }
            SmallButton(stringResource(R.string.g1_notif_phone_settings), tonal = true) { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName)) }
            if (enabled) SmallButton(stringResource(R.string.g1_notif_send_test), tonal = true) { com.bucks.app.data.Push.show(ctx, "social", testTitle, testBody, null, false) }
        }
    }
}

/** Voice language and whether free-form commands go to the cloud; in both settings lists. */
@Composable fun VoiceAiCard(vm: BucksViewModel, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsState()
    SectionTitle(stringResource(R.string.g1_voice_title), modifier.padding(top = 22.dp, bottom = 10.dp))
    BucksCard { Text(stringResource(R.string.g1_voice_language), style = MaterialTheme.typography.titleSmall); Row(Modifier.padding(top = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { VOICE_LANGS.forEach { (tag, label) -> Chip(label, selected = s.voiceLang == tag) { vm.setVoiceLang(tag) } } }
        Divider(); Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(stringResource(R.string.g1_voice_cloud), style = MaterialTheme.typography.titleSmall); Muted(if (vm.cloudEnabled) stringResource(R.string.g1_voice_cloud_on) else stringResource(R.string.g1_voice_cloud_off)) }; Icon(if (vm.cloudEnabled) Icons.Rounded.CloudDone else Icons.Rounded.CloudOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
}
