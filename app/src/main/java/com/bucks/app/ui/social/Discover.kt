package com.bucks.app.ui.social

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
    }
    val pending = remember(social.synced, social.incoming) { mutableStateMapOf<String, Boolean>() }
    fun syncState(id: String) = when { social.synced.any { it.id == id } -> "SYNCED"; social.incoming.any { it.id == id } -> "INCOMING"; pending[id] == true -> "SENT"; else -> "NONE" }
    Column(Modifier.fillMaxSize()) {
        Text("Discover", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.statusBarsPadding().padding(start = Gutter, end = Gutter, top = 12.dp).semantics { heading() })
        OutlinedTextField(q, { q = it.take(60) }, Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 12.dp), placeholder = { Text("Search names or a Bucks ID") },
            leadingIcon = { Icon(Icons.Rounded.Search, null) }, trailingIcon = { if (q.isNotEmpty()) IconButton({ q = "" }) { Icon(Icons.Rounded.Close, "Clear search") } },
            singleLine = true, shape = MaterialTheme.shapes.extraLarge, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (hits != null || searching) {
                if (searching && hits == null) item { LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Gutter)) }
                hits?.let { list ->
                    if (list.isEmpty()) item { Muted("No one found for \"${q.trim()}\". Check the spelling, or ask them for their Bucks ID.", Modifier.padding(Gutter)) }
                    items(list, key = { it.id }) { h ->
                        PersonListRow(h.name, listOfNotNull(h.area.ifBlank { null }, if (h.mutual > 0) "${h.mutual} mutual" else null).joinToString(" · ").ifBlank { "Bucks ID ${h.shortCode}" },
                            onClick = { onOpenPerson(h.id) }) { SyncButton(if (h.synced) "SYNCED" else syncState(h.id)) { pending[h.id] = true; social.syncWith(h.id, h.name) } }
                    }
                }
            } else {
                if (safety.isMinor) item { SafetyNote(if (safety.isChild) "Only people your parent approves can sync with you." else "For your safety, adults you aren't connected to can't find you in search or suggestions.") }
                if (social.incoming.isNotEmpty()) {
                    item { SectionHeader("Sync requests", "${social.incoming.size}") }
                    items(social.incoming, key = { "in-" + it.id }) { p ->
                        PersonListRow(p.name, p.area.ifBlank { "Wants to sync with you" }, onClick = { onOpenPerson(p.id) }) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                FilledTonalButton({ social.acceptSync(p.id) }, contentPadding = PaddingValues(horizontal = 14.dp)) { Text("Accept") }
                                IconButton({ social.unsync(p.id) }) { Icon(Icons.Rounded.Close, "Decline ${p.name}") }
                            }
                        }
                    }
                }
                item { SectionHeader("Find your friends", null) }
                item {
                    Row(Modifier.padding(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FindCard(Icons.Rounded.Contacts, "From contacts", "See who's already here", Modifier.weight(1f), onContacts)
                        FindCard(Icons.Rounded.QrCode2, "Bucks ID", "Type or scan a code", Modifier.weight(1f), onBucksId)
                    }
                }
                item { SectionHeader("People you may know", null) }
                if (social.suggestions.isEmpty()) item { Muted("Suggestions appear as you sync with people. Friends of friends and people near you show up here.", Modifier.padding(horizontal = Gutter)) }
                else item {
                    LazyRow(contentPadding = PaddingValues(horizontal = Gutter), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(social.suggestions, key = { it.id }) { p ->
                            SuggestionTile(p.name, if (p.mutual > 0) "${p.mutual} mutual" else p.area.ifBlank { "Near you" }, syncState(p.id), onOpen = { onOpenPerson(p.id) }) { pending[p.id] = true; social.syncWith(p.id, p.name) }
                        }
                    }
                }
                if (social.synced.isNotEmpty()) {
                    item { SectionHeader("Synced", "${social.synced.size}") }
                    items(social.synced.take(20), key = { "s-" + it.id }) { p -> PersonListRow(p.name, p.area.ifBlank { "Synced" }, onClick = { onOpenPerson(p.id) }) { Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
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
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = "Open $name's profile", onClick = onClick).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
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
    "SYNCED" -> AssistChip(onClick = {}, label = { Text("Synced") }, leadingIcon = { Icon(Icons.Rounded.Check, null, Modifier.size(16.dp)) })
    "SENT" -> AssistChip(onClick = {}, label = { Text("Requested") }, enabled = false)
    "INCOMING" -> FilledTonalButton(onSync, contentPadding = PaddingValues(horizontal = 14.dp)) { Text("Accept") }
    else -> Button(onSync, contentPadding = PaddingValues(horizontal = 16.dp), shape = MaterialTheme.shapes.large) { Text("Sync") }
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
