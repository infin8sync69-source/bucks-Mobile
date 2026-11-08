package com.bucks.app.ui.screens.manage

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.ui.PageGroup
import com.bucks.app.ui.PageType
import com.bucks.app.ui.PageTypes
import com.bucks.app.ui.components.*

/*
 * Picking what a page is (ui/PageTypes.kt): first the group (shops, local services, companies, NGOs and groups, institutions),
 * then the type inside it. The type decides the catalogue, the primary button and the tabs, so the owner sees what people
 * will get on each card before choosing.
 */

/** One line of examples under a group card. */
internal fun pageGroupExamples(key: String): String = when (key) {
    "SHOPS" -> "Restaurant, grocery, store, online store"
    "LOCAL_SERVICES" -> "Salon, clinic, repair, coaching, gym"
    "COMPANIES" -> "IT company, firm, manufacturer, freelancer collective"
    "COMMUNITY" -> "NGO, charity, community group"
    "INSTITUTIONS" -> "School, hospital, place of worship, association"
    else -> ""
}

/** What people do on a page of this type, from its primary button. */
internal fun pageTypeOutcome(t: PageType): String = when (t.cta) {
    "CART" -> "People add to cart"
    "BOOK" -> "People book"
    "QUOTE" -> "People ask for a quote"
    "ENQUIRE" -> "People enquire"
    "VOLUNTEER" -> "People volunteer"
    "JOIN" -> "People join"
    "HIRE" -> "People hire you"
    else -> "People see timings and events"
}

/** The label over the category field, by group: shops keep "Type of business". */
internal fun pageCategoryLabel(t: PageType): String = when (t.group) {
    "SHOPS" -> "Type of business"
    "LOCAL_SERVICES" -> "What kind of service"
    "COMPANIES" -> "Field"
    "COMMUNITY" -> "Cause or area"
    else -> "Type of institution"
}

/** What a page of this type calls its photos tab; the same words the public profile uses (discover/ListingProfileScreen.kt). */
internal fun pagePhotosLabel(t: PageType): String = when {
    t.group == "LOCAL_SERVICES" -> "Gallery"
    t.group == "COMPANIES" -> "Work"
    t.key == "SCHOOL_COLLEGE" -> "Campus"
    else -> "Photos"
}

/** The registration number field's label for a type (institutions quote an affiliation, the rest a registration). */
internal fun pageRegistrationLabel(t: PageType): String = if (t.key == "SCHOOL_COLLEGE") "Affiliation number" else "Registration number"

/**
 * Two steps in one sheet: the group, then the type. [initialGroup] opens straight on step 2 (a Home tile for that group, or
 * "Change" on a page that already has a type); [selected] is ticked. [onSkill], when given, adds "Just my skill" to step 1.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PageTypePickerSheet(initialGroup: String? = null, selected: String? = null, onSkill: (() -> Unit)? = null, onPick: (PageType) -> Unit, onDismiss: () -> Unit) {
    var group by remember { mutableStateOf(PageTypes.group(initialGroup)) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxHeight(0.92f).padding(horizontal = Gutter)) {
            val g = group
            if (g == null) {
                Text("What is it?", style = MaterialTheme.typography.titleLarge)
                Muted("Pick the closest group. You choose the exact kind next, and it decides what the page shows and does.", Modifier.padding(top = 2.dp, bottom = 10.dp))
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(PageTypes.groups, key = { it.key }) { pg -> GroupCard(pg) { group = pg } }
                    if (onSkill != null) item(key = "skill") {
                        BucksCard(onClick = onSkill, padding = 14) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Avatar(icon = Icons.Rounded.Handyman, size = 44)
                                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text("Just my skill", style = MaterialTheme.typography.titleSmall); Muted("Plumber, tutor, designer. A profile for you, not a business.") }
                                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    item(key = "end") { Spacer(Modifier.height(24.dp)) }
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { group = null }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "All groups") }
                    Column(Modifier.weight(1f)) { Text(g.label, style = MaterialTheme.typography.titleLarge); Muted("Pick the kind that fits best.") }
                }
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(PageTypes.inGroup(g.key), key = { it.key }) { t -> TypeCard(t, t.key == selected) { onPick(t) } }
                    item(key = "end") { Spacer(Modifier.height(24.dp)) }
                }
            }
        }
    }
}

@Composable
private fun GroupCard(g: PageGroup, onClick: () -> Unit) = BucksCard(onClick = onClick, padding = 14) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(icon = g.icon, size = 44)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(g.label, style = MaterialTheme.typography.titleSmall); Muted(pageGroupExamples(g.key)) }
        Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun TypeCard(t: PageType, selected: Boolean, onClick: () -> Unit) = BucksCard(tint = selected, onClick = onClick, padding = 14) {
    Row(verticalAlignment = Alignment.Top) {
        Avatar(icon = t.icon, size = 44)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(t.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                if (selected) Icon(Icons.Rounded.Check, "Selected", tint = MaterialTheme.colorScheme.primary)
            }
            Muted(t.blurb)
            Row(Modifier.padding(top = 8.dp)) { PillPurple(pageTypeOutcome(t)) }
        }
    }
}

/** A compact card with the page's type and, while it can still change, a button to pick another. */
@Composable
internal fun PageTypeCard(t: PageType, locked: Boolean, onChange: () -> Unit) = BucksCard(Modifier.padding(bottom = 14.dp), padding = 12) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(icon = t.icon, size = 40)
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(t.label, style = MaterialTheme.typography.titleSmall)
            Muted(if (locked) "Fixed now that the page is live." else t.blurb)
        }
        if (!locked) SmallButton("Change", tonal = true, onClick = onChange)
    }
}
