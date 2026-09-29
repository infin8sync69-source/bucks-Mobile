package com.bucks.app.ui.screens

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
 * The address book is read here on the phone and never uploaded.
 */
@Composable
fun ContactsScreen(vm: BucksViewModel, onBack: () -> Unit, onSync: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) }
    var denied by remember { mutableStateOf(false) }
    var contacts by remember { mutableStateOf<List<PhoneContact>?>(null) }
    var q by rememberSaveable { mutableStateOf("") }; var open by rememberSaveable { mutableStateOf<Long?>(null) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; denied = !ok }
    LaunchedEffect(granted) { if (granted) contacts = PhoneContacts.load(ctx) }
    fun reload() { scope.launch { contacts = null; contacts = PhoneContacts.load(ctx) } }

    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar("Contacts", onBack = onBack, actions = {
            if (granted) IconButton(onClick = { reload() }) { Icon(Icons.Rounded.Refresh, "Refresh from phonebook") }
            IconButton(onClick = onSync) { Icon(Icons.Rounded.PersonAddAlt, "People I synced with") }
        })
        if (!granted) {
            Column(Modifier.padding(Gutter)) {
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(icon = Icons.Rounded.Group, size = 48)
                        Column(Modifier.padding(start = 14.dp)) { Text("Bring in your phonebook", style = MaterialTheme.typography.titleMedium); Muted("See everyone you know in one searchable list, call or message them, and invite them to Bucks.") }
                    }
                    Muted("Your contacts are read on this phone and shown only to you. Bucks doesn't upload or store them.", Modifier.padding(top = 12.dp))
                    PrimaryButton(if (denied) "Allow in Settings" else "Allow contacts", Modifier.padding(top = 14.dp)) {
                        if (denied) ctx.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", ctx.packageName, null))) else ask.launch(Manifest.permission.READ_CONTACTS)
                    }
                }
                if (denied) Muted("Contacts permission is off. Turn it on in the app's settings, then come back.", Modifier.padding(top = 10.dp))
            }
            return@ContentColumn
        }
        val all = contacts
        if (all == null) { CenteredBox { BucksLoader() }; return@ContentColumn }
        BucksField(q, { q = it }, placeholder = "Search name, number, email, company, place", modifier = Modifier.padding(horizontal = Gutter, vertical = 4.dp), keyboard = KeyboardOptions(keyboardType = KeyboardType.Text))
        val shown = remember(all, q) { val t = q.trim().lowercase(); if (t.isBlank()) all else { val d = t.filter { it.isDigit() }; all.filter { c -> t in c.haystack || (d.length >= 3 && c.digits.any { d in it }) } } }
        Muted(if (q.isBlank()) "${all.size} contact${if (all.size == 1) "" else "s"}" else "${shown.size} of ${all.size}", Modifier.padding(horizontal = Gutter, vertical = 4.dp))
        if (all.isEmpty()) Column(Modifier.padding(Gutter)) { Text("No contacts found", style = MaterialTheme.typography.titleMedium); Muted("Your phonebook is empty or has no numbers. Add contacts in your Phone app and tap refresh.", Modifier.padding(top = 4.dp)) }
        else if (shown.isEmpty()) Muted("Nobody matches \"${q.trim()}\".", Modifier.padding(Gutter))
        LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            items(shown, key = { it.id }) { c -> ContactRow(c, expanded = open == c.id, onToggle = { open = if (open == c.id) null else c.id }, scope = scope); Divider() }
        }
    }
}

@Composable
private fun CenteredBox(content: @Composable () -> Unit) = Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { content() }

@Composable
private fun ContactRow(c: PhoneContact, expanded: Boolean, onToggle: () -> Unit, scope: kotlinx.coroutines.CoroutineScope) {
    val ctx = LocalContext.current
    var inviteMenu by remember { mutableStateOf(false) }
    fun start(i: Intent) { runCatching { ctx.startActivity(i) }.onFailure { android.widget.Toast.makeText(ctx, "No app on this phone can do that.", android.widget.Toast.LENGTH_SHORT).show() } }
    val first = c.phones.firstOrNull()
    fun invite(via: String) = scope.launch {
        val link = Invite.link(); val text = "Hi ${c.name.substringBefore(' ')}, I'm on Bucks: rides, food, shops, skills and homes near you, run by locals. Join here: $link" +
            if (Invite.PLAY_URL.isBlank()) "\n(Allow \"install unknown apps\" when asked; Bucks isn't on the Play Store yet.)" else ""
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
                Muted(listOfNotNull(c.org.ifBlank { null }, first).joinToString(" · ").ifBlank { c.emails.firstOrNull().orEmpty() }, maxLines = 1)
            }
            Box {
                SmallButton("Invite", tonal = true) { inviteMenu = true }
                DropdownMenu(inviteMenu, { inviteMenu = false }) {
                    if (first != null) { DropdownMenuItem({ Text("By SMS") }, { inviteMenu = false; invite("SMS") }, leadingIcon = { Icon(Icons.Rounded.Sms, null) }); DropdownMenuItem({ Text("On WhatsApp") }, { inviteMenu = false; invite("WA") }, leadingIcon = { Icon(Icons.Rounded.Send, null) }) }
                    DropdownMenuItem({ Text("Other app…") }, { inviteMenu = false; invite("ANY") }, leadingIcon = { Icon(Icons.Rounded.IosShare, null) })
                }
            }
        }
        if (expanded) Column(Modifier.padding(start = 56.dp, top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            c.phones.forEach { p -> DetailRow(Icons.Rounded.Call, p, actions = {
                IconButton({ start(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${PhoneContacts.dialable(p)}"))) }) { Icon(Icons.Rounded.Call, "Call $p", tint = MaterialTheme.colorScheme.primary) }
                IconButton({ start(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${PhoneContacts.dialable(p)}"))) }) { Icon(Icons.Rounded.Sms, "Message $p", tint = MaterialTheme.colorScheme.primary) } }) }
            c.emails.forEach { e -> DetailRow(Icons.Rounded.MailOutline, e, actions = { IconButton({ start(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$e"))) }) { Icon(Icons.Rounded.Send, "Email $e", tint = MaterialTheme.colorScheme.primary) } }) }
            if (c.org.isNotBlank()) DetailRow(Icons.Rounded.Work, listOfNotNull(c.org, c.title.ifBlank { null }).joinToString(" · "))
            if (c.address.isNotBlank()) DetailRow(Icons.Rounded.LocationOn, c.address, actions = { IconButton({ start(Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=${Uri.encode(c.address)}"))) }) { Icon(Icons.Rounded.Place, "Show on map", tint = MaterialTheme.colorScheme.primary) } })
        }
    }
}

@Composable
private fun DetailRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, actions: @Composable RowScope.() -> Unit = {}) = Row(verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f).padding(horizontal = 10.dp)); actions()
}
