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
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import com.bucks.app.data.Str

/*
 * Picking what a page is (ui/PageTypes.kt): first the group (shops, local services, companies, NGOs and groups, institutions),
 * then the type inside it. The type decides the catalogue, the primary button and the tabs, so the owner sees what people
 * will get on each card before choosing.
 */

/** One line of examples under a group card. */
internal fun pageGroupExamples(key: String): String = when (key) {
    "SHOPS" -> Str.get(R.string.g6_pg_ex_shops)
    "LOCAL_SERVICES" -> Str.get(R.string.g6_pg_ex_local)
    "COMPANIES" -> Str.get(R.string.g6_pg_ex_companies)
    "COMMUNITY" -> Str.get(R.string.g6_pg_ex_community)
    "INSTITUTIONS" -> Str.get(R.string.g6_pg_ex_institutions)
    else -> ""
}

/** What people do on a page of this type, from its primary button. */
internal fun pageTypeOutcome(t: PageType): String = when (t.cta) {
    "CART" -> Str.get(R.string.g6_pg_out_cart)
    "BOOK" -> Str.get(R.string.g6_pg_out_book)
    "QUOTE" -> Str.get(R.string.g6_pg_out_quote)
    "ENQUIRE" -> Str.get(R.string.g6_pg_out_enquire)
    "VOLUNTEER" -> Str.get(R.string.g6_pg_out_volunteer)
    "JOIN" -> Str.get(R.string.g6_pg_out_join)
    "HIRE" -> Str.get(R.string.g6_pg_out_hire)
    else -> Str.get(R.string.g6_pg_out_info)
}

/** The label over the category field, by group: shops keep "Type of business". */
internal fun pageCategoryLabel(t: PageType): String = when (t.group) {
    "SHOPS" -> Str.get(R.string.g6_pg_cat_shops)
    "LOCAL_SERVICES" -> Str.get(R.string.g6_pg_cat_local)
    "COMPANIES" -> Str.get(R.string.g6_pg_cat_companies)
    "COMMUNITY" -> Str.get(R.string.g6_pg_cat_community)
    else -> Str.get(R.string.g6_pg_cat_institutions)
}

/** What a page of this type calls its photos tab; the same words the public profile uses (discover/ListingProfileScreen.kt). */
internal fun pagePhotosLabel(t: PageType): String = when {
    t.group == "LOCAL_SERVICES" -> Str.get(R.string.g6_pg_photos_gallery)
    t.group == "COMPANIES" -> Str.get(R.string.g6_pg_photos_work)
    t.key == "SCHOOL_COLLEGE" -> Str.get(R.string.g6_pg_photos_campus)
    else -> Str.get(R.string.g6_pg_photos)
}

/** The registration number field's label for a type (institutions quote an affiliation, the rest a registration). */
internal fun pageRegistrationLabel(t: PageType): String = if (t.key == "SCHOOL_COLLEGE") Str.get(R.string.g6_pg_affiliation_no) else Str.get(R.string.g6_pg_registration_no)

/**
 * Two steps in one sheet: the group, then the type. [initialGroup] opens straight on step 2 (a Home tile for that group, or
 * "Change" on a page that already has a type); [selected] is ticked. [onSkill], when given, adds "Just my skill" to step 1.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PageTypePickerSheet(initialGroup: String? = null, selected: String? = null, onSkill: (() -> Unit)? = null, onPick: (PageType) -> Unit, onDismiss: () -> Unit) {
    var group by remember { mutableStateOf(PageTypes.group(initialGroup)) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.fillMaxHeight(0.92f).padding(horizontal = Gutter)) {
            val g = group
            if (g == null) {
                Text(stringResource(R.string.g6_pg_what), style = MaterialTheme.typography.titleLarge)
                Muted(stringResource(R.string.g6_pg_what_hint), Modifier.padding(top = 2.dp, bottom = 10.dp))
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(PageTypes.groups, key = { it.key }) { pg -> GroupCard(pg) { group = pg } }
                    if (onSkill != null) item(key = "skill") {
                        BucksCard(onClick = onSkill, padding = 14) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Avatar(icon = Icons.Rounded.Handyman, size = 44)
                                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(stringResource(R.string.g6_pg_skill), style = MaterialTheme.typography.titleSmall); Muted(stringResource(R.string.g6_pg_skill_hint)) }
                                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    item(key = "end") { Spacer(Modifier.height(24.dp)) }
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { group = null }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.g6_cd_all_groups)) }
                    Column(Modifier.weight(1f)) { Text(g.label, style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g6_pg_kind_hint)) }
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
                if (selected) Icon(Icons.Rounded.Check, stringResource(R.string.g6_cd_selected), tint = MaterialTheme.colorScheme.primary)
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
            Muted(if (locked) stringResource(R.string.g6_pg_locked) else t.blurb)
        }
        if (!locked) SmallButton(stringResource(R.string.g6_change), tonal = true, onClick = onChange)
    }
}
