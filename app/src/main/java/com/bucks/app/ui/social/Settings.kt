package com.bucks.app.ui.social

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import com.bucks.app.data.Str
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bucks.app.BuildConfig
import com.bucks.app.data.ReportReason
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.screens.ago

/** Settings for the social app: account, privacy and safety, notifications, appearance, help and legal, then sign-out and deletion. */
@Composable
fun SocialSettingsScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit, onEditProfile: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit) {
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_settings), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 32.dp)) { SettingsList(vm, onOpen, onEditProfile, onLogout, onDeleted) }
    }
}

/**
 * The one list of settings, shown in Profile > Settings and at the Settings route: account, privacy and safety, app, help and legal,
 * Bucks team tools, then sign-out and deletion. Edge to edge (each row has its own gutter).
 */
@Composable
fun SettingsList(vm: BucksViewModel, onOpen: (String) -> Unit, onEditProfile: () -> Unit, onLogout: () -> Unit, onDeleted: () -> Unit) {
    val ctx = LocalContext.current; val social = vm.social
    var deleteDialog by remember { mutableStateOf(false) }; var logoutDialog by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { vm.services.checkStaff() }
        Column {
            Group(stringResource(R.string.g2_set_account))
            Item(Icons.Rounded.Person, stringResource(R.string.g2_set_edit_profile), stringResource(R.string.g2_set_edit_profile_d), onClick = onEditProfile)
            Item(Icons.Rounded.Sync, stringResource(R.string.g2_set_synced), null) { onOpen(Routes.SYNC) }
            Group(stringResource(R.string.g2_set_privacy_safety))
            Item(Icons.Rounded.Shield, stringResource(R.string.g2_set_safety), stringResource(R.string.g2_set_safety_d)) { onOpen(Routes.SAFETY_CENTER) }
            Item(Icons.Rounded.Lock, stringResource(R.string.g2_set_privacy), stringResource(R.string.g2_set_privacy_d)) { onOpen(Routes.SETTINGS_PRIVACY) }
            Item(Icons.Rounded.Block, stringResource(R.string.g2_set_blocked), null) { onOpen(Routes.SETTINGS_BLOCKED) }
            Item(Icons.Rounded.Place, stringResource(R.string.g2_set_map), stringResource(R.string.g2_set_map_d)) { onOpen(Routes.SETTINGS_MAP) }
            Item(Icons.Rounded.Favorite, stringResource(R.string.g2_close_friends), stringResource(R.string.g2_set_close_d)) { onOpen(Routes.SETTINGS_CLOSE) }
            Group(stringResource(R.string.g2_set_app))
            Item(Icons.Rounded.Notifications, stringResource(R.string.g2_notifications), stringResource(R.string.g2_set_notifs_d)) { onOpen(Routes.SETTINGS_NOTIFS) }
            Item(Icons.Rounded.Language, stringResource(R.string.g2_set_language), com.bucks.app.data.AppLanguages.current().native) { onOpen(Routes.LANGUAGE) }
            Item(Icons.Rounded.Palette, stringResource(R.string.g2_set_appearance), stringResource(R.string.g2_set_appearance_d)) { onOpen(Routes.SETTINGS_APPEARANCE) }
            com.bucks.app.ui.screens.VoiceAiCard(vm, Modifier.padding(horizontal = Gutter))
            Item(Icons.Rounded.SystemUpdate, stringResource(R.string.g2_set_versions), when {
                !com.bucks.app.data.AppUpdate.enabled -> stringResource(R.string.g2_set_versions_play, com.bucks.app.data.AppUpdate.currentBuild.toString())
                vm.updates.available != null -> stringResource(R.string.g2_set_versions_ready, com.bucks.app.data.AppUpdate.currentBuild.toString(), vm.updates.available?.build.toString())
                else -> stringResource(R.string.g2_set_versions_switch, com.bucks.app.data.AppUpdate.currentBuild.toString()) }) { onOpen(Routes.APP_VERSIONS) }
            Group(stringResource(R.string.g2_set_help_legal))
            Item(Icons.Rounded.HelpOutline, stringResource(R.string.g2_set_help), stringResource(R.string.g2_set_help_d)) { onOpen(Routes.HELP) }
            Item(Icons.Rounded.Lightbulb, stringResource(R.string.g2_set_feedback), stringResource(R.string.g2_set_feedback_d)) { onOpen(Routes.FEEDBACK) }
            Item(Icons.Rounded.Gavel, stringResource(R.string.g2_set_guidelines), null) { Legal.open(ctx, Legal.GUIDELINES) }
            Item(Icons.Rounded.PrivacyTip, stringResource(R.string.g2_set_privacy_policy), null) { Legal.open(ctx, Legal.PRIVACY) }
            Item(Icons.Rounded.Description, stringResource(R.string.g2_set_terms), null) { Legal.open(ctx, Legal.TERMS) }
            if (vm.services.isStaff) {
                Group(stringResource(R.string.g2_set_team))
                Item(Icons.Rounded.FactCheck, stringResource(R.string.g2_set_review_reports), stringResource(R.string.g2_set_review_reports_d)) { onOpen(Routes.STAFF_REPORTS) }
                Item(Icons.Rounded.VerifiedUser, stringResource(R.string.g2_staff_title), stringResource(R.string.g2_set_review_docs_d)) { onOpen(Routes.STAFF_REVIEW) }
            }
            Group(stringResource(R.string.g2_set_account_actions))
            Item(Icons.AutoMirrored.Rounded.Logout, stringResource(R.string.g2_set_log_out), null) { logoutDialog = true }
            Item(Icons.Rounded.DeleteOutline, stringResource(R.string.g2_set_delete_account), stringResource(R.string.g2_set_delete_account_d), danger = true) { deleteDialog = true }
            Muted("Bucks ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})" + (social.me?.let { " · ${it.shortCode}" } ?: ""), Modifier.padding(horizontal = Gutter, vertical = 16.dp))
        }
    if (logoutDialog) AlertDialog(onDismissRequest = { logoutDialog = false }, title = { Text(stringResource(R.string.g2_set_log_out_q)) }, text = { Text(stringResource(R.string.g2_set_log_out_body)) },
        confirmButton = { TextButton({ logoutDialog = false; onLogout() }) { Text(stringResource(R.string.g2_set_log_out)) } }, dismissButton = { TextButton({ logoutDialog = false }) { Text(stringResource(R.string.g2_cancel)) } })
    if (deleteDialog) AlertDialog(onDismissRequest = { deleteDialog = false }, icon = { Icon(Icons.Rounded.Warning, null, tint = MaterialTheme.colorScheme.error) }, title = { Text(stringResource(R.string.g2_set_delete_q)) },
        text = { Text(stringResource(R.string.g2_set_delete_body)) },
        confirmButton = { TextButton({ deleteDialog = false; vm.deleteAccount(); onDeleted() }) { Text(stringResource(R.string.g2_set_delete_mine), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ deleteDialog = false }) { Text(stringResource(R.string.g2_cancel)) } })
}

@Composable
private fun Group(title: String) = Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = Gutter, end = Gutter, top = 24.dp, bottom = 4.dp).semantics { heading() })

@Composable
private fun Item(icon: ImageVector, title: String, detail: String?, danger: Boolean = false, onClick: () -> Unit) =
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).heightIn(min = 56.dp).padding(horizontal = Gutter, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.padding(start = 18.dp).weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }

/** What protects people on Bucks, what applies to me, and where my reports stand. */
@Composable
fun SafetyCenterScreen(vm: BucksViewModel, onBack: () -> Unit, onOpen: (String) -> Unit) {
    val ctx = LocalContext.current; val safety = vm.safety
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_set_safety), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (safety.isMinor) SafetyNote(stringResource(if (safety.isChild) R.string.g2_safety_child else R.string.g2_safety_teen))
            Text(stringResource(R.string.g2_safety_how), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
            Rule(Icons.Rounded.Lock, stringResource(R.string.g2_rule_reach), stringResource(R.string.g2_rule_reach_d))
            Rule(Icons.Rounded.OutlinedFlag, stringResource(R.string.g2_rule_report), stringResource(R.string.g2_rule_report_d))
            Rule(Icons.Rounded.Block, stringResource(R.string.g2_rule_block), stringResource(R.string.g2_rule_block_d))
            Rule(Icons.Rounded.NearMe, stringResource(R.string.g2_rule_location), stringResource(R.string.g2_rule_location_d))
            Rule(Icons.Rounded.FamilyRestroom, stringResource(R.string.g2_rule_minors), stringResource(R.string.g2_rule_minors_d))
            Spacer(Modifier.height(12.dp))
            Item(Icons.Rounded.Lock, stringResource(R.string.g2_set_privacy_settings), null) { onOpen(Routes.SETTINGS_PRIVACY) }
            Item(Icons.Rounded.Block, stringResource(R.string.g2_set_blocked), null) { onOpen(Routes.SETTINGS_BLOCKED) }
            Item(Icons.Rounded.Place, stringResource(R.string.g2_set_map), stringResource(R.string.g2_set_map_d)) { onOpen(Routes.SETTINGS_MAP) }
            Item(Icons.Rounded.ChildCare, stringResource(R.string.g2_set_child_safety), null) { Legal.open(ctx, Legal.CHILD_SAFETY) }
            Item(Icons.Rounded.Gavel, stringResource(R.string.g2_set_guidelines), null) { Legal.open(ctx, Legal.GUIDELINES) }
            Text(stringResource(R.string.g2_safety_help_now), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 20.dp).semantics { heading() })
            Muted(stringResource(R.string.g2_safety_helplines), Modifier.padding(top = 6.dp))
        }
    }
}

@Composable
private fun Rule(icon: ImageVector, title: String, text: String) = Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.Top) {
    Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
    Column(Modifier.padding(start = 14.dp)) { Text(title, style = MaterialTheme.typography.titleSmall); Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

private val FAQ = listOf(
    R.string.g2_faq_sync_q to R.string.g2_faq_sync_a,
    R.string.g2_faq_who_q to R.string.g2_faq_who_a,
    R.string.g2_faq_find_q to R.string.g2_faq_find_a,
    R.string.g2_faq_bother_q to R.string.g2_faq_bother_a,
    R.string.g2_faq_dob_q to R.string.g2_faq_dob_a,
    R.string.g2_faq_delete_q to R.string.g2_faq_delete_a,
)

/** Help: common questions, how to reach us, and the grievance officer required by the IT Rules 2021. */
@Composable
fun HelpScreen(vm: BucksViewModel, onBack: () -> Unit, onFeedback: () -> Unit = {}) {
    val ctx = LocalContext.current
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_set_help), onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Text(stringResource(R.string.g2_help_common), style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            FAQ.forEach { (q, a) -> FaqItem(stringResource(q), stringResource(a)) }
            Text(stringResource(R.string.g2_help_contact), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 24.dp).semantics { heading() })
            if (Legal.supportEmail.isNotBlank()) {
                Item(Icons.Rounded.Email, stringResource(R.string.g2_help_email), Legal.supportEmail) { Legal.emailSupport(ctx, Str.get(R.string.g2_help_email_subject)) }
                Item(Icons.Rounded.BugReport, stringResource(R.string.g2_help_report_problem), stringResource(R.string.g2_help_report_problem_d)) { Legal.emailSupport(ctx, Str.get(R.string.g2_help_problem_subject)) }
            } else Muted(stringResource(R.string.g2_help_use_report), Modifier.padding(top = 8.dp))
            Item(Icons.Rounded.Lightbulb, stringResource(R.string.g2_set_feedback), stringResource(R.string.g2_help_feedback_d), onClick = onFeedback)
            Text(stringResource(R.string.g2_help_grievance), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp).semantics { heading() })
            Muted(stringResource(R.string.g2_help_grievance_body), Modifier.padding(top = 6.dp))
            if (Legal.grievanceOfficer.isNotBlank()) Text(Legal.grievanceOfficer, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 8.dp))
            Item(Icons.Rounded.OpenInNew, stringResource(R.string.g2_help_grievance_details), null) { Legal.open(ctx, Legal.GRIEVANCE) }
            Item(Icons.Rounded.DeleteOutline, stringResource(R.string.g2_help_account_deletion), null) { Legal.open(ctx, Legal.DELETE_ACCOUNT) }
        }
    }
}

@Composable
private fun FaqItem(q: String, a: String) {
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize().clickable(role = Role.Button, onClickLabel = stringResource(if (open) R.string.g2_cd_hide_answer else R.string.g2_cd_show_answer)) { open = !open }.padding(vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Text(q, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f)); Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null) }
        if (open) Text(a, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
    }
    Divider()
}

/** Staff: the open report queue, most urgent first. Remove takes the content down; Ban also suspends the account. */
@Composable
fun StaffReportsScreen(vm: BucksViewModel, onBack: () -> Unit, onOpenPerson: (String) -> Unit) {
    val safety = vm.safety
    var confirm by remember { mutableStateOf<Pair<String, String>?>(null) }
    LaunchedEffect(Unit) { safety.refreshQueue() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar(stringResource(R.string.g2_set_review_reports), onBack = onBack, actions = { IconButton({ safety.refreshQueue() }) { Icon(Icons.Rounded.Refresh, stringResource(R.string.g2_cd_refresh)) } })
        if (safety.queue.isEmpty()) Muted(stringResource(R.string.g2_reports_empty), Modifier.padding(Gutter))
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(safety.queue, key = { it.id }) { r ->
                val reason = runCatching { ReportReason.valueOf(r.reason) }.getOrNull()
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (r.reason == "CHILD_SAFETY" || r.reason == "SELF_HARM") PillBad(reason?.label ?: r.reason) else PillWarn(reason?.label ?: r.reason)
                        Spacer(Modifier.width(8.dp)); PillGrey(r.targetKind.lowercase()); Spacer(Modifier.weight(1f)); Muted(ago(r.createdAt))
                    }
                    Text(r.preview?.ifBlank { null } ?: stringResource(R.string.g2_reports_no_text), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
                    if (r.detail.isNotBlank()) Muted(stringResource(R.string.g2_reports_reporter, r.detail), Modifier.padding(top = 6.dp))
                    Muted(pluralStringResource(R.plurals.g2_reports_by, r.reporters, r.ownerName ?: stringResource(R.string.g2_unknown), r.reporters), Modifier.padding(top = 6.dp))
                    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        r.targetOwner?.let { o -> TextButton({ onOpenPerson(o) }) { Text(stringResource(R.string.g2_profile)) } }
                        Spacer(Modifier.weight(1f))
                        TextButton({ safety.review(r.id, "DISMISS") }) { Text(stringResource(R.string.g2_dismiss)) }
                        if (r.targetKind != "PROFILE") FilledTonalButton({ confirm = r.id to "REMOVE" }) { Text(stringResource(R.string.g2_remove)) }
                        Button({ confirm = r.id to "BAN" }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.g2_ban)) }
                    }
                }
            }
        }
    }
    confirm?.let { (id, action) -> AlertDialog(onDismissRequest = { confirm = null }, title = { Text(stringResource(if (action == "BAN") R.string.g2_reports_ban_q else R.string.g2_reports_remove_q)) },
        text = { Text(stringResource(if (action == "BAN") R.string.g2_reports_ban_body else R.string.g2_reports_remove_body)) },
        confirmButton = { TextButton({ safety.review(id, action); confirm = null }) { Text(stringResource(R.string.g2_confirm), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ confirm = null }) { Text(stringResource(R.string.g2_cancel)) } }) }
}
