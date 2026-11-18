package com.bucks.app.ui.screens

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import com.bucks.app.data.Str
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.bucks.app.data.PhoneContact
import com.bucks.app.data.PhoneContacts
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.Invite
import com.bucks.app.ui.components.*
import kotlinx.coroutines.launch

/**
 * Contacts: the phone's address book, searchable, with what each person has (numbers, emails, organisation, address), a way to call,
 * message or email them through the phone's own apps, and Invite for people who aren't on Bucks yet. Sync (Bucks people) is separate.
 * The address book is read here on the phone and never uploaded as a whole; only the details a person chooses to keep with a
 * Bucks person (ContactLinkSheet) are saved, to their own account.
 */
@Composable
fun ContactsScreen(vm: BucksViewModel, onBack: () -> Unit, onSync: () -> Unit, onOpenChat: (String) -> Unit = {}, onMap: () -> Unit = {}) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) }
    var denied by remember { mutableStateOf(false) }
    var contacts by remember { mutableStateOf<List<PhoneContact>?>(null) }
    var q by rememberSaveable { mutableStateOf("") }; var open by rememberSaveable { mutableStateOf<Long?>(null) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; denied = !ok }
    LaunchedEffect(granted) { if (granted) contacts = PhoneContacts.load(ctx) }
    // People I attached contact details to are recognised here by their number, so a phonebook entry shows "On Bucks" and can be messaged.
    val social = vm.social; var attachFor by remember { mutableStateOf<PhoneContact?>(null) }
    LaunchedEffect(Unit) { social.refreshSyncs(); social.refreshLinks() }
    val byPhone = remember(social.links, social.synced) { buildMap<String, com.bucks.app.data.ProfileRow> { social.synced.forEach { p -> social.links[p.id]?.phones?.forEach { put(tail10(it), p) } } } }
    fun reload() { scope.launch { contacts = null; contacts = PhoneContacts.load(ctx) } }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g2_contacts_title), onBack = onBack, actions = {
            if (granted) IconButton(onClick = { reload() }) { Icon(Icons.Rounded.Refresh, stringResource(R.string.g2_cd_contacts_refresh)) }
            IconButton(onClick = onSync) { Icon(Icons.Rounded.PersonAddAlt, stringResource(R.string.g2_cd_synced_people)) }
        })
        if (!granted) {
            Column(Modifier.padding(Gutter)) {
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(icon = Icons.Rounded.Group, size = 48)
                        Column(Modifier.padding(start = 14.dp)) { Text(stringResource(R.string.g2_contacts_bring_title), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g2_contacts_bring_body)) }
                    }
                    Muted(stringResource(R.string.g2_contacts_disclosure), Modifier.padding(top = 12.dp))
                    PrimaryButton(stringResource(if (denied) R.string.g2_allow_in_settings else R.string.g2_allow_contacts), Modifier.padding(top = 14.dp)) {
                        if (denied) ctx.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", ctx.packageName, null))) else ask.launch(Manifest.permission.READ_CONTACTS)
                    }
                }
                if (denied) Muted(stringResource(R.string.g2_contacts_denied), Modifier.padding(top = 10.dp))
            }
            return@ContentColumn
        }
        attachFor?.let { PickSyncedPerson(vm, it) { attachFor = null } }
        val all = contacts
        if (all == null) { CenteredBox { BucksLoader() }; return@ContentColumn }
        BucksField(q, { q = it }, placeholder = stringResource(R.string.g2_contacts_search_hint), modifier = Modifier.padding(horizontal = Gutter, vertical = 4.dp), keyboard = KeyboardOptions(keyboardType = KeyboardType.Text))
        val shown = remember(all, q) { val t = q.trim().lowercase(); if (t.isBlank()) all else { val d = t.filter { it.isDigit() }; all.filter { c -> t in c.haystack || (d.length >= 3 && c.digits.any { d in it }) } } }
        Muted(if (q.isBlank()) pluralStringResource(R.plurals.g2_contacts_count, all.size, all.size) else stringResource(R.string.g2_contacts_shown_of, shown.size, all.size), Modifier.padding(horizontal = Gutter, vertical = 4.dp))
        if (all.isEmpty()) Column(Modifier.padding(Gutter)) { Text(stringResource(R.string.g2_contacts_none), style = MaterialTheme.typography.titleMedium); Muted(stringResource(R.string.g2_contacts_none_body), Modifier.padding(top = 4.dp)) }
        else if (shown.isEmpty()) Muted(stringResource(R.string.g2_nobody_matches, q.trim()), Modifier.padding(Gutter))
        LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            items(shown, key = { it.id }) { c -> ContactRow(c, expanded = open == c.id, onToggle = { open = if (open == c.id) null else c.id }, scope = scope,
                person = c.phones.firstNotNullOfOrNull { byPhone[tail10(it)] }, onMessage = { p -> social.openDirect(p.id, onOpenChat) }, onAttach = { attachFor = c }, onMap = onMap); Divider() }
        }
    }
}

@Composable
private fun CenteredBox(content: @Composable () -> Unit) = Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { content() }

@Composable
private fun ContactRow(c: PhoneContact, expanded: Boolean, onToggle: () -> Unit, scope: kotlinx.coroutines.CoroutineScope, person: com.bucks.app.data.ProfileRow?, onMessage: (com.bucks.app.data.ProfileRow) -> Unit, onAttach: () -> Unit, onMap: () -> Unit) {
    val ctx = LocalContext.current
    var inviteMenu by remember { mutableStateOf(false) }
    fun start(i: Intent) { runCatching { ctx.startActivity(i) }.onFailure { android.widget.Toast.makeText(ctx, Str.get(R.string.g2_no_app_for_that), android.widget.Toast.LENGTH_SHORT).show() } }
    val first = c.phones.firstOrNull()
    fun invite(via: String) = scope.launch {
        val link = Invite.link(); val text = Str.get(R.string.g2_invite_text, c.name.substringBefore(' '), link) +
            if (Invite.PLAY_URL.isBlank()) "\n" + Str.get(R.string.g2_invite_sideload_note) else ""
        val num = first?.let { PhoneContacts.dialable(it) }
        when {
            via == "SMS" && num != null -> start(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$num")).putExtra("sms_body", text))
            via == "WA" && num != null -> start(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/${num.filter { it.isDigit() }}?text=${Uri.encode(text)}")))
            else -> start(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))
        }
    }
    Column(Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(horizontal = Gutter, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(c.initials, size = 44)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(c.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                Muted(listOfNotNull(if (person != null) stringResource(R.string.g2_on_bucks_as, person.name) else null, c.org.ifBlank { null }, first).joinToString(" · ").ifBlank { c.emails.firstOrNull().orEmpty() }, maxLines = 1)
            }
            if (person != null) SmallButton(stringResource(R.string.g2_message), tonal = true) { onMessage(person) } else Box {
                SmallButton(stringResource(R.string.g2_invite), tonal = true) { inviteMenu = true }
                DropdownMenu(inviteMenu, { inviteMenu = false }) {
                    if (first != null) { DropdownMenuItem({ Text(stringResource(R.string.g2_invite_sms)) }, { inviteMenu = false; invite("SMS") }, leadingIcon = { Icon(Icons.Rounded.Sms, null) }); DropdownMenuItem({ Text(stringResource(R.string.g2_invite_whatsapp)) }, { inviteMenu = false; invite("WA") }, leadingIcon = { Icon(Icons.Rounded.Send, null) }) }
                    DropdownMenuItem({ Text(stringResource(R.string.g2_invite_other)) }, { inviteMenu = false; invite("ANY") }, leadingIcon = { Icon(Icons.Rounded.IosShare, null) })
                }
            }
        }
        if (expanded) Column(Modifier.padding(start = 56.dp, top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (person == null) SmallButton(stringResource(R.string.g2_attach_synced), tonal = true, onClick = onAttach)
            c.phones.forEach { p -> DetailRow(Icons.Rounded.Call, p, actions = {
                IconButton({ start(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${PhoneContacts.dialable(p)}"))) }) { Icon(Icons.Rounded.Call, stringResource(R.string.g2_cd_call, p), tint = MaterialTheme.colorScheme.primary) }
                IconButton({ start(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${PhoneContacts.dialable(p)}"))) }) { Icon(Icons.Rounded.Sms, stringResource(R.string.g2_cd_message_to, p), tint = MaterialTheme.colorScheme.primary) } }) }
            c.emails.forEach { e -> DetailRow(Icons.Rounded.MailOutline, e, actions = { IconButton({ start(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$e"))) }) { Icon(Icons.Rounded.Send, stringResource(R.string.g2_cd_email, e), tint = MaterialTheme.colorScheme.primary) } }) }
            if (c.org.isNotBlank()) DetailRow(Icons.Rounded.Work, listOfNotNull(c.org, c.title.ifBlank { null }).joinToString(" · "))
            if (c.address.isNotBlank()) DetailRow(Icons.Rounded.LocationOn, c.address, actions = { IconButton({ com.bucks.app.ui.screens.MapsPick.query = c.address; onMap() }) { Icon(Icons.Rounded.Place, stringResource(R.string.g2_cd_show_on_map), tint = MaterialTheme.colorScheme.primary) } })
        }
    }
}

@Composable
private fun DetailRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, actions: @Composable RowScope.() -> Unit = {}) = Row(verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(horizontal = 10.dp)); actions()
}
