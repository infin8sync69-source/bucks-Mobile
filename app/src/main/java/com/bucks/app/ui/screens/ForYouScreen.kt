package com.bucks.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.data.ForYouBackend
import com.bucks.app.data.ForYouItem
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.manage.PhotoOrIcon

/**
 * For you: only what the people I'm synced with recommend: posts at least two of them voted up, and shops, pros and products they
 * recommended or rated up. Counts only, never who. Filters: All, Posts, Places, Products.
 */
@Composable
fun CloudForYouScreen(vm: BucksViewModel, onMenu: () -> Unit, onMessages: () -> Unit, onListing: (String) -> Unit, onFindPeople: () -> Unit) {
    var items by remember { mutableStateOf<List<ForYouItem>?>(null) }; var failed by remember { mutableStateOf(false) }
    var filter by remember { mutableStateOf("ALL") }; var open by remember { mutableStateOf<ForYouItem?>(null) }
    LaunchedEffect(vm.social.me?.id) { runCatching { ForYouBackend.items() }.onSuccess { items = it; failed = false }.onFailure { failed = true; items = emptyList() } }
    val shown = items.orEmpty().filter { when (filter) { "POST" -> it.kind == "POST"; "LISTING" -> it.kind == "LISTING"; "PRODUCT" -> it.kind == "PRODUCT"; else -> true } }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("For you", onMenu = onMenu, unread = vm.social.unread, onChat = onMessages)
        Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("ALL" to "All", "POST" to "Posts", "LISTING" to "Places", "PRODUCT" to "Products").forEach { (k, l) -> Chip(l, selected = filter == k) { filter = k } }
        }
        when {
            items == null -> LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Gutter))
            failed -> Notice("Couldn't load what your synced people recommend. Check your connection.", Modifier.padding(Gutter))
            items!!.isEmpty() -> Column(Modifier.padding(Gutter)) {
                Text("Nothing yet", style = MaterialTheme.typography.titleMedium)
                Muted("Shops, pros, products and posts your synced people recommend show up here.", Modifier.padding(top = 4.dp))
                SmallButton("Find people to sync with", Modifier.padding(top = 12.dp), tonal = true, onClick = onFindPeople)
            }
            shown.isEmpty() -> Muted("Nothing in this filter yet.", Modifier.padding(Gutter))
            else -> LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                items(shown, key = { it.kind + it.id }) { r ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).clickable { if (r.kind == "POST" && r.listingId == null) open = r else r.listingId?.let(onListing) }
                        .padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        val icon = when (r.kind) { "POST" -> Icons.Rounded.Article; "PRODUCT" -> Icons.Rounded.ShoppingBag; else -> Icons.Rounded.Storefront }
                        if (r.kind == "POST" && r.photoUrl != null) SignedImage(vm, "posts", r.photoUrl, Modifier.size(56.dp)) else PhotoOrIcon(r.photoUrl, icon, size = 56)
                        Column(Modifier.weight(1f).padding(start = 14.dp)) {
                            Text(r.title, style = MaterialTheme.typography.titleSmall, maxLines = 1)
                            if (r.subtitle.isNotBlank()) Muted(r.subtitle, maxLines = 2)
                            Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.ThumbUp, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
                                Text(" Recommended by ${r.recommenders} you're synced with", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
    open?.let { p -> AlertDialog(onDismissRequest = { open = null }, title = { Text(p.title) }, text = { Text(p.subtitle) },
        confirmButton = { TextButton({ open = null }) { Text("Close") } }) }
}
