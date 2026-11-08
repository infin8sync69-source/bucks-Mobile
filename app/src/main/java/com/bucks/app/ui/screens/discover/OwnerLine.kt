package com.bucks.app.ui.screens.discover

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.ListingRow
import com.bucks.app.data.OwnerRow
import com.bucks.app.data.listingOwner
import com.bucks.app.data.livePagesOf
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*
import com.bucks.app.ui.str

/*
 * Every page on Bucks belongs to a real person: "Master plumber · by Raghu Raghavendra", "Raju Kirana Store · by Raj Sukumar".
 * The byline shows who runs the page and how far their identity has been checked (phone today; a photo ID checked by Bucks staff
 * when that happened; face or biometric checks later). Tapping it opens the person: their other pages, how long they have been on
 * Bucks, and a way to message them directly.
 */

/** "By <name>" with the identity level, under a page's title. Loads the owner once per listing. */
@Composable
fun OwnerLine(vm: BucksViewModel, l: ListingRow, modifier: Modifier = Modifier) {
    var owner by remember(l.id) { mutableStateOf<OwnerRow?>(null) }
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(l.id) { owner = runCatching { Backend.listingOwner(l.id) }.getOrNull() }
    val o = owner
    val name = o?.name ?: vm.social.nameOf(l.ownerId).takeIf { it != "…" } ?: "Bucks member"
    Row(modifier.fillMaxWidth().heightIn(min = 44.dp).clip(MaterialTheme.shapes.small).clickable(onClickLabel = "About $name") { open = true }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(name).ifBlank { "?" }, size = 28)
        Text("By $name", style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 8.dp).weight(1f, fill = false))
        Spacer(Modifier.width(8.dp))
        if (o?.idChecked == true) PillGood("ID checked by Bucks") else PillGrey("Phone-verified")
        Icon(Icons.Rounded.ChevronRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (open) OwnerSheet(vm, l, o, onDismiss = { open = false })
}

/** The person behind a page: identity level, time on Bucks, their other live pages, and Message. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OwnerSheet(vm: BucksViewModel, l: ListingRow, owner: OwnerRow?, onDismiss: () -> Unit) {
    val me = vm.social.me?.id
    var pages by remember(l.ownerId) { mutableStateOf<List<ListingRow>?>(null) }
    LaunchedEffect(l.ownerId) { pages = runCatching { Backend.livePagesOf(l.ownerId) }.getOrDefault(emptyList()) }
    val name = owner?.name ?: "Bucks member"
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(initials(name).ifBlank { "?" }, size = 56)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(name, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Muted(listOfNotNull(owner?.shortCode?.takeIf { it.isNotBlank() }?.let { "Bucks ID $it" }, owner?.area?.takeIf { it.isNotBlank() }).joinToString(" · "), maxLines = 1)
                }
            }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (owner?.idChecked == true) PillGood("ID checked by Bucks") else PillGrey("Phone-verified")
                owner?.memberSince?.takeIf { it.length >= 4 }?.let { Muted("On Bucks since ${it.take(4)}") }
            }
            Muted(if (owner?.idChecked == true) "This person signed in with their phone number and Bucks staff checked their photo ID. Face checks come later."
                  else "This person signed in with their phone number. Bucks has not yet checked their photo ID; face checks come later.", Modifier.padding(top = 8.dp))
            val list = pages
            Text("Pages ${name.substringBefore(' ')} runs", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
            when {
                list == null -> Muted("Loading…")
                list.isEmpty() -> Muted("Only this page.")
                else -> list.forEach { x ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(MaterialTheme.shapes.small).clickable(onClickLabel = "Open ${x.title}") { onDismiss(); vm.open(com.bucks.app.ui.nav.Routes.listing(x.id)) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(PageTypes.badgeIcon(x.kind, x.typeKey, x.details.str("ships_india") == "true"), null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(x.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(PageTypes.badge(x.kind, x.typeKey, x.details.str("ships_india") == "true") + (if (x.id == l.id) " · this page" else ""), maxLines = 1) }
                    }
                }
            }
            if (me != null && me != l.ownerId) PrimaryButton("Message ${name.substringBefore(' ')}", Modifier.padding(top = 16.dp)) { onDismiss(); vm.social.openDirect(l.ownerId) { vm.open(com.bucks.app.ui.nav.Routes.chat(it)) } }
        }
    }
}
