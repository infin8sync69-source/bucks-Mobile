package com.bucks.app.ui.social

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bucks.app.data.BackendSafety
import com.bucks.app.data.PersonHit
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.coroutines.delay

/**
 * Discover: find people. Search by name or Bucks ID; with no search, sync requests waiting for me, people I may know, and the
 * ways to find friends (phone contacts, a Bucks ID or its QR).
 */
@Composable
fun DiscoverScreen(vm: BucksViewModel, onOpenPerson: (String) -> Unit, onContacts: () -> Unit, onBucksId: () -> Unit) {
    val social = vm.social; val safety = vm.safety; val focus = LocalFocusManager.current
    var q by rememberSaveable { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<PersonHit>?>(null) }; var searching by remember { mutableStateOf(false) }
    LaunchedEffect(social.me?.id) { if (social.me != null) { social.refreshSuggestions(); social.refreshSyncs() } }
    // Search as you type, after a short pause.
    LaunchedEffect(q) {
        val t = q.trim(); if (t.length < 2) { hits = null; return@LaunchedEffect }
        delay(300); searching = true
        hits = runCatching { BackendSafety.searchPeople(t) }.getOrElse { emptyList() }; searching = false
        com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.SEARCH, "results" to (hits?.size ?: 0))
    }
    val pending = remember(social.synced, social.incoming) { mutableStateMapOf<String, Boolean>() }
    fun syncState(id: String) = when { social.synced.any { it.id == id } -> "SYNCED"; social.incoming.any { it.id == id } -> "INCOMING"; pending[id] == true -> "SENT"; else -> "NONE" }
    Column(Modifier.fillMaxSize()) {
        Text(stringResource(R.string.g8_discover), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.statusBarsPadding().padding(start = Gutter, end = Gutter, top = 12.dp).semantics { heading() })
        OutlinedTextField(q, { q = it.take(60) }, Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp), placeholder = { Text(stringResource(R.string.g8_search_people_hint)) },
            leadingIcon = { Icon(Icons.Rounded.Search, null) }, trailingIcon = { if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, stringResource(R.string.g8_cd_clear_search)) } },
            singleLine = true, shape = MaterialTheme.shapes.extraLarge, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (hits != null || searching) {
                if (searching && hits == null) item { LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Gutter)) }
                hits?.let { list ->
                    if (list.isEmpty()) item { Muted(stringResource(R.string.g8_no_one_found, q.trim()), Modifier.padding(Gutter)) }
                    items(list, key = { it.id }) { h ->
                        PersonListRow(h.name, listOfNotNull(h.area.ifBlank { null }, if (h.mutual > 0) pluralStringResource(R.plurals.g8_mutual, h.mutual, h.mutual) else null).joinToString(" · ").ifBlank { stringResource(R.string.g8_bucks_id_code, h.shortCode) },
                            onClick = { onOpenPerson(h.id) }) { SyncButton(if (h.synced) "SYNCED" else syncState(h.id)) { pending[h.id] = true; social.syncWith(h.id, h.name) } }
                    }
                }
            } else {
                if (safety.isMinor) item { SafetyNote(if (safety.isChild) stringResource(R.string.g8_safety_child) else stringResource(R.string.g8_safety_teen)) }
                if (social.incoming.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.g8_sync_requests), "${social.incoming.size}") }
                    items(social.incoming, key = { "in-" + it.id }) { p ->
                        PersonListRow(p.name, p.area.ifBlank { stringResource(R.string.g8_wants_to_sync) }, onClick = { onOpenPerson(p.id) }) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                FilledTonalButton({ social.acceptSync(p.id) }, contentPadding = PaddingValues(horizontal = 14.dp)) { Text(stringResource(R.string.g8_accept)) }
                                IconButton({ social.unsync(p.id) }) { Icon(Icons.Rounded.Close, stringResource(R.string.g8_cd_decline_name, p.name)) }
                            }
                        }
                    }
                }
                item { SectionHeader(stringResource(R.string.g8_find_friends), null) }
                item {
                    Row(Modifier.padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FindCard(Icons.Rounded.Contacts, stringResource(R.string.g8_from_contacts), stringResource(R.string.g8_from_contacts_sub), Modifier.weight(1f), onContacts)
                        FindCard(Icons.Rounded.QrCode2, "Bucks ID", stringResource(R.string.g8_type_or_scan), Modifier.weight(1f), onBucksId)
                    }
                }
                item { SectionHeader(stringResource(R.string.g8_people_you_may_know), null) }
                if (social.suggestions.isEmpty()) item { Muted(stringResource(R.string.g8_suggestions_empty), Modifier.padding(horizontal = Gutter)) }
                else item {
                    LazyRow(contentPadding = PaddingValues(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(social.suggestions, key = { it.id }) { p ->
                            SuggestionTile(p.name, if (p.mutual > 0) pluralStringResource(R.plurals.g8_mutual, p.mutual, p.mutual) else p.area.ifBlank { stringResource(R.string.g8_near_you) }, syncState(p.id), onOpen = { onOpenPerson(p.id) }) { pending[p.id] = true; social.syncWith(p.id, p.name) }
                        }
                    }
                }
                if (social.synced.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.g8_synced), "${social.synced.size}") }
                    items(social.synced.take(20), key = { "s-" + it.id }) { p -> PersonListRow(p.name, p.area.ifBlank { stringResource(R.string.g8_synced) }, onClick = { onOpenPerson(p.id) }) { Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
                }
            }
        }
    }
}

@Composable
fun SectionHeader(title: String, count: String?) = Row(Modifier.fillMaxWidth().padding(start = Gutter, end = Gutter, top = 22.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
    if (count != null) { Spacer(Modifier.width(8.dp)); PillPurple(count) }
}

@Composable
fun PersonListRow(name: String, sub: String, onClick: () -> Unit, trailing: @Composable () -> Unit) =
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = stringResource(R.string.g8_open_profile_of, name), onClick = onClick).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(initials(name.ifBlank { "?" }), size = 46)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        trailing()
    }

/** NONE: Sync. SENT: Requested. INCOMING: Accept (handled by the caller's request list). SYNCED: Synced, quiet. */
@Composable
fun SyncButton(state: String, onSync: () -> Unit) = when (state) {
    "SYNCED" -> AssistChip(onClick = {}, label = { Text(stringResource(R.string.g8_synced)) }, leadingIcon = { Icon(Icons.Rounded.Check, null, Modifier.size(16.dp)) })
    "SENT" -> AssistChip(onClick = {}, label = { Text(stringResource(R.string.g8_requested)) }, enabled = false)
    "INCOMING" -> FilledTonalButton(onSync, contentPadding = PaddingValues(horizontal = 14.dp)) { Text(stringResource(R.string.g8_accept)) }
    else -> Button(onSync, contentPadding = PaddingValues(horizontal = 16.dp), shape = MaterialTheme.shapes.large) { Text(stringResource(R.string.g8_sync)) }
}

@Composable
private fun SuggestionTile(name: String, sub: String, state: String, onOpen: () -> Unit, onSync: () -> Unit) =
    Surface(onClick = onOpen, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.width(156.dp)) {
        Column(Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(initials(name.ifBlank { "?" }), size = 64)
            Text(name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 10.dp))
            Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(10.dp))
            SyncButton(state, onSync)
        }
    }

@Composable
private fun FindCard(icon: ImageVector, title: String, sub: String, modifier: Modifier, onClick: () -> Unit) =
    Surface(onClick = onClick, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.primaryContainer, modifier = modifier) {
        Column(Modifier.padding(16.dp)) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
            Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.padding(top = 10.dp))
            Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = .8f))
        }
    }

@Composable
fun SafetyNote(text: String) = Row(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 8.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.secondaryContainer).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(Icons.Rounded.Shield, null, tint = MaterialTheme.colorScheme.onSecondaryContainer)
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.padding(start = 12.dp))
}

/** A typed Bucks ID with its spaces or dashes ("h6vf ywyf") is sent as the bare code, which is what the server matches exactly; anything else goes as typed. */
fun peopleQuery(typed: String): String { val bare = typed.filter { it.isLetterOrDigit() }; return if (com.bucks.app.ui.components.BucksQr.looksLikeBucksId(bare)) bare.uppercase() else typed.trim() }

/**
 * A person in search results, as a card: picture, name, Bucks ID, where they are and people in common, with the quick actions under
 * it (Sync or its state, Message once synced, Profile). The whole card opens their profile.
 */
@Composable
fun PersonResultCard(vm: BucksViewModel, h: PersonHit, state: String, modifier: Modifier = Modifier, onOpen: () -> Unit, onSync: () -> Unit, onMessage: () -> Unit) =
    Surface(onClick = onOpen, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainer, modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(initials(h.name.ifBlank { "?" }), size = 48, photoUrl = vm.social.photoOf(h.id))
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(h.name.ifBlank { stringResource(R.string.g8_bucks_id_code, h.shortCode) }, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(stringResource(R.string.g8_bucks_id_code, com.bucks.app.ui.screens.pretty(h.shortCode)), style = MaterialTheme.typography.labelMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), color = MaterialTheme.colorScheme.primary, maxLines = 1)
                    val sub = listOfNotNull(h.area.ifBlank { null }, if (h.mutual > 0) pluralStringResource(R.plurals.g8_mutual, h.mutual, h.mutual) else null).joinToString(" · ")
                    if (sub.isNotBlank()) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                when (state) {
                    "SYNCED" -> QuickAction(Icons.Rounded.ChatBubbleOutline, stringResource(R.string.r1_message), filled = true, onClick = onMessage)
                    "SENT" -> QuickAction(Icons.Rounded.Schedule, stringResource(R.string.g8_requested), enabled = false) {}
                    "INCOMING" -> QuickAction(Icons.Rounded.Check, stringResource(R.string.g8_accept), filled = true, onClick = onSync)
                    else -> QuickAction(Icons.Rounded.Sync, stringResource(R.string.g8_sync), filled = true, onClick = onSync)
                }
                QuickAction(Icons.Rounded.Person, stringResource(R.string.r1_profile), onClick = onOpen)
            }
        }
    }

@Composable
private fun QuickAction(icon: ImageVector, label: String, filled: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val bg = if (filled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest
    val fg = if (filled) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
    Row(Modifier.heightIn(min = 36.dp).clip(CircleShape).background(bg.copy(alpha = if (enabled) 1f else 0.5f)).clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(16.dp), tint = fg); Text(" $label", style = MaterialTheme.typography.labelLarge, color = fg, maxLines = 1)
    }
}
