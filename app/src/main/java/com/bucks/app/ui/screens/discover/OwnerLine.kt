package com.bucks.app.ui.screens.discover

import com.bucks.app.R
import androidx.compose.ui.res.stringResource
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
    val name = o?.name ?: vm.social.nameOf(l.ownerId).takeIf { it != "…" } ?: stringResource(R.string.g5_bucks_member)
    val aboutLabel = stringResource(R.string.g5_cd_about_name, name)
    Row(modifier.fillMaxWidth().heightIn(min = 44.dp).clip(MaterialTheme.shapes.small).clickable(onClickLabel = aboutLabel) { open = true }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(name).ifBlank { "?" }, size = 28)
        Text(stringResource(R.string.g5_by_name, name), style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 8.dp).weight(1f, fill = false))
        Spacer(Modifier.width(8.dp))
        if (o?.idChecked == true) PillGood(stringResource(R.string.g5_id_checked)) else PillGrey(stringResource(R.string.g5_phone_verified))
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
    val name = owner?.name ?: stringResource(R.string.g5_bucks_member)
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(initials(name).ifBlank { "?" }, size = 56)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(name, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Muted(listOfNotNull(owner?.shortCode?.takeIf { it.isNotBlank() }?.let { stringResource(R.string.g5_bucks_id_code, it) }, owner?.area?.takeIf { it.isNotBlank() }).joinToString(" · "), maxLines = 1)
                }
            }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (owner?.idChecked == true) PillGood(stringResource(R.string.g5_id_checked)) else PillGrey(stringResource(R.string.g5_phone_verified))
                owner?.memberSince?.takeIf { it.length >= 4 }?.let { Muted(stringResource(R.string.g5_on_bucks_since, it.take(4))) }
            }
            Muted(stringResource(if (owner?.idChecked == true) R.string.g5_owner_id_checked
                  else R.string.g5_owner_phone_only), Modifier.padding(top = 8.dp))
            val list = pages
            Text(stringResource(R.string.g5_pages_runs, name.substringBefore(' ')), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
            when {
                list == null -> Muted(stringResource(R.string.g5_loading))
                list.isEmpty() -> Muted(stringResource(R.string.g5_only_this_page))
                else -> list.forEach { x ->
                    val openLabel = stringResource(R.string.g5_cd_open_name, x.title)
                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(MaterialTheme.shapes.small).clickable(onClickLabel = openLabel) { onDismiss(); vm.open(com.bucks.app.ui.nav.Routes.listing(x.id)) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(PageTypes.badgeIcon(x.kind, x.typeKey, x.details.str("ships_india") == "true"), null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Column(Modifier.weight(1f).padding(start = 10.dp)) { Text(x.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(PageTypes.badge(x.kind, x.typeKey, x.details.str("ships_india") == "true") + (if (x.id == l.id) " · " + stringResource(R.string.g5_this_page) else ""), maxLines = 1) }
                    }
                }
            }
            if (me != null && me != l.ownerId) PrimaryButton(stringResource(R.string.g5_message_name, name.substringBefore(' ')), Modifier.padding(top = 16.dp)) { onDismiss(); vm.social.openDirect(l.ownerId) { vm.open(com.bucks.app.ui.nav.Routes.chat(it)) } }
        }
    }
}
