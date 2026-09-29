package com.bucks.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.bucks.app.data.ContactLinkRow
import com.bucks.app.data.PhoneContact
import com.bucks.app.data.PhoneContacts
import com.bucks.app.data.ProfileRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*

/** How well a phonebook name matches a Bucks name: the number of name words they share. */
private fun nameScore(a: String, b: String): Int { val x = a.lowercase().split(" ", ".").filter { it.length > 1 }; val y = b.lowercase(); return x.count { it in y } }

/** Splits "9845012345, 080 2222 3333" or one per line into a clean list. */
private fun splitList(text: String, max: Int = 5) = text.split(',', '\n', ';').map { it.trim() }.filter { it.isNotBlank() }.distinct().take(max)

/** The last 10 digits of a number, to tell whether two entries are the same phone. */
internal fun tail10(p: String) = p.filter { it.isDigit() }.takeLast(10)

/**
 * Attach contact details to a person I'm synced with: their number, email, organisation, place and a note. Private: only I see it,
 * and it doesn't change their Bucks profile. The details can come from my phonebook (the best match is offered first) or be typed.
 * [prefill] starts the form from a phonebook contact (the Contacts screen uses this).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactLinkSheet(vm: BucksViewModel, person: ProfileRow, prefill: PhoneContact? = null, onDismiss: () -> Unit) {
    val social = vm.social; val ctx = LocalContext.current
    val existing = social.links[person.id]
    var phones by remember { mutableStateOf((existing?.phones ?: prefill?.phones).orEmpty().joinToString(", ")) }
    var emails by remember { mutableStateOf((existing?.emails ?: prefill?.emails).orEmpty().joinToString(", ")) }
    var org by remember { mutableStateOf(existing?.org ?: prefill?.org.orEmpty()) }
    var title by remember { mutableStateOf(existing?.title ?: prefill?.title.orEmpty()) }
    var address by remember { mutableStateOf(existing?.address ?: prefill?.address.orEmpty()) }
    var note by remember { mutableStateOf(existing?.note.orEmpty()) }
    var picking by remember { mutableStateOf(false) }
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; if (ok) picking = true else vm.toast("Contacts permission is off. You can still type the details.") }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Text("Contact details for ${person.name}", style = MaterialTheme.typography.titleLarge)
            Muted("Only you can see this. It doesn't change ${person.name.substringBefore(' ')}'s Bucks profile, and they aren't told.", Modifier.padding(top = 2.dp, bottom = 12.dp))
            SmallButton("Pick from my phonebook", Modifier.padding(bottom = 12.dp), tonal = true) { if (granted) picking = true else ask.launch(Manifest.permission.READ_CONTACTS) }
            BucksField(phones, { phones = it.take(200) }, "Mobile numbers", "98450 12345, 080 2222 3333", keyboard = KeyboardOptions(keyboardType = KeyboardType.Phone))
            BucksField(emails, { emails = it.take(300) }, "Emails", "name@example.com", keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                BucksField(org, { org = it.take(120) }, "Organisation", "Bala Electricals", Modifier.weight(1f))
                BucksField(title, { title = it.take(120) }, "Role", "Owner", Modifier.weight(1f))
            }
            BucksField(address, { address = it.take(300) }, "Location", "JP Nagar 2nd Phase, Bengaluru")
            BucksField(note, { note = it.take(500) }, "Note", "Met at the market, does home visits", singleLine = false, minLines = 2)
            val bad = splitList(emails).firstOrNull { !it.contains('@') || !it.contains('.') }
            PrimaryButton("Save", enabled = bad == null) {
                social.saveLink(ContactLinkRow(person.id, splitList(phones).map { it.take(40) }, splitList(emails).map { it.take(120) }, org.trim(), title.trim(), address.trim(), note.trim()), then = onDismiss)
            }
            if (bad != null) Muted("\"$bad\" isn't an email address.", Modifier.padding(top = 6.dp))
            if (existing != null) BadButton("Remove these details", Modifier.padding(top = 4.dp)) { social.removeLink(person.id); onDismiss() }
        }
    }
    if (picking) PhonebookPicker(person.name, onDismiss = { picking = false }) { c ->
        phones = c.phones.joinToString(", "); emails = c.emails.joinToString(", "); if (c.org.isNotBlank()) org = c.org; if (c.title.isNotBlank()) title = c.title; if (c.address.isNotBlank()) address = c.address
        picking = false
    }
}

/** A searchable phonebook list; the contacts whose names best match [forName] come first. */
@Composable
private fun PhonebookPicker(forName: String, onDismiss: () -> Unit, onPick: (PhoneContact) -> Unit) {
    val ctx = LocalContext.current
    var all by remember { mutableStateOf<List<PhoneContact>?>(null) }; var q by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { all = PhoneContacts.load(ctx) }
    val list = all
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Pick from phonebook") }, confirmButton = { TextButton(onDismiss) { Text("Cancel") } }, text = {
        Column(Modifier.heightIn(max = 420.dp)) {
            BucksField(q, { q = it }, placeholder = "Search name, number or company")
            when {
                list == null -> Box(Modifier.fillMaxWidth().padding(24.dp)) { BucksLoader() }
                else -> {
                    val t = q.trim().lowercase(); val d = t.filter { it.isDigit() }
                    val shown = list.filter { t.isBlank() || t in it.haystack || (d.length >= 3 && it.digits.any { x -> d in x }) }
                        .sortedWith(compareByDescending<PhoneContact> { if (t.isBlank()) nameScore(forName, it.name) else 0 }.thenBy { it.name.lowercase() })
                    if (shown.isEmpty()) Muted("Nobody matches.")
                    LazyColumn { items(shown.take(80), key = { it.id }) { c ->
                        val best = t.isBlank() && nameScore(forName, c.name) > 0
                        ListRow(c.name, listOfNotNull(if (best) "Likely match" else null, c.org.ifBlank { null }, c.phones.firstOrNull()).joinToString(" · "), leading = { Avatar(c.initials, size = 36) }, onClick = { onPick(c) })
                        Divider()
                    } }
                }
            }
        }
    })
}

/** Choose which synced person a phonebook contact belongs to; the contact's details are attached to them. */
@Composable
fun PickSyncedPerson(vm: BucksViewModel, contact: PhoneContact, onDismiss: () -> Unit) {
    val social = vm.social; var q by remember { mutableStateOf("") }
    val people = social.synced.filter { q.isBlank() || it.name.contains(q.trim(), true) }.sortedWith(compareByDescending<ProfileRow> { nameScore(contact.name, it.name) }.thenBy { it.name.lowercase() })
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Who is ${contact.name}?") }, confirmButton = { TextButton(onDismiss) { Text("Cancel") } }, text = {
        Column(Modifier.heightIn(max = 420.dp)) {
            if (social.synced.isEmpty()) Muted("Sync with them on Bucks first (Menu > Bucks Pro > Bucks ID, or the Sync screen), then attach their contact details here.")
            else {
                Muted("Attach ${contact.name}'s details to a person you're synced with. Only you see them.", Modifier.padding(bottom = 8.dp))
                BucksField(q, { q = it }, placeholder = "Search your synced people")
                LazyColumn { items(people, key = { it.id }) { p ->
                    ListRow(p.name, listOfNotNull(if (nameScore(contact.name, p.name) > 0) "Likely match" else null, p.area.ifBlank { null }).joinToString(" · "), leading = { Avatar(initials(p.name), size = 36) }, onClick = {
                        social.saveLink(ContactLinkRow(p.id, contact.phones.take(5), contact.emails.take(5), contact.org.take(120), contact.title.take(120), contact.address.take(300), social.links[p.id]?.note.orEmpty()), then = onDismiss) })
                    Divider()
                } }
            }
        }
    })
}
