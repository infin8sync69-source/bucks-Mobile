package com.bucks.app.ui.social

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
    val ctx = LocalContext.current; val social = vm.social
    var deleteDialog by remember { mutableStateOf(false) }; var logoutDialog by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { vm.services.checkStaff() }
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Settings", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 32.dp)) {
            Group("Account")
            Item(Icons.Rounded.Person, "Edit profile", "Name, area and bio", onClick = onEditProfile)
            Item(Icons.Rounded.QrCode2, "Bucks ID", "Your card and QR for syncing") { onOpen(Routes.BUCKS_ID) }
            Item(Icons.Rounded.Sync, "Synced people and requests", null) { onOpen(Routes.SYNC) }
            Group("Privacy and safety")
            Item(Icons.Rounded.Shield, "Safety centre", "How Bucks keeps you safe, and your reports") { onOpen(Routes.SAFETY_CENTER) }
            Item(Icons.Rounded.Lock, "Privacy", "Who can message you, sync with you and see your Moments") { onOpen(Routes.SETTINGS_PRIVACY) }
            Item(Icons.Rounded.Block, "Blocked people", null) { onOpen(Routes.SETTINGS_BLOCKED) }
            Item(Icons.Rounded.Place, "Posts on the map", "Whether your posts show as places on the map") { onOpen(Routes.SETTINGS_MAP) }
            Item(Icons.Rounded.Favorite, "Close friends", "Who sees Moments you share with close friends") { onOpen(Routes.SETTINGS_CLOSE) }
            Group("App")
            Item(Icons.Rounded.Notifications, "Notifications", "What Bucks tells you about, and quiet hours") { onOpen(Routes.SETTINGS_NOTIFS) }
            Item(Icons.Rounded.Palette, "Appearance and data", "Theme, text size, motion, media on mobile data") { onOpen(Routes.SETTINGS_APPEARANCE) }
            Item(Icons.Rounded.SystemUpdate, "App versions", "Build ${com.bucks.app.data.AppUpdate.currentBuild}" + when {
                !com.bucks.app.data.AppUpdate.enabled -> " · updates through the Play Store"
                vm.updates.available != null -> " · build ${vm.updates.available?.build} is ready"
                else -> " · switch to the latest build" }) { onOpen(Routes.APP_VERSIONS) }
            Group("Help and legal")
            Item(Icons.Rounded.HelpOutline, "Help and support", "Questions, contact us, grievance officer") { onOpen(Routes.HELP) }
            Item(Icons.Rounded.Lightbulb, "Feedback board", "Suggest ideas, report bugs, vote on what's next") { onOpen(Routes.FEEDBACK) }
            Item(Icons.Rounded.Gavel, "Community guidelines", null) { Legal.open(ctx, Legal.GUIDELINES) }
            Item(Icons.Rounded.PrivacyTip, "Privacy policy", null) { Legal.open(ctx, Legal.PRIVACY) }
            Item(Icons.Rounded.Description, "Terms of use", null) { Legal.open(ctx, Legal.TERMS) }
            if (vm.services.isStaff) {
                Group("Bucks team")
                Item(Icons.Rounded.FactCheck, "Review reports", "Reported posts, messages and accounts") { onOpen(Routes.STAFF_REPORTS) }
                Item(Icons.Rounded.VerifiedUser, "Review documents and vehicles", "Shop and pro documents, and vehicles waiting to go online") { onOpen(Routes.STAFF_REVIEW) }
            }
            Group("Account actions")
            Item(Icons.AutoMirrored.Rounded.Logout, "Log out", null) { logoutDialog = true }
            Item(Icons.Rounded.DeleteOutline, "Delete account", "Removes your profile, posts, Moments and messages", danger = true) { deleteDialog = true }
            Muted("Bucks ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})" + (social.me?.let { " · ${it.shortCode}" } ?: ""), Modifier.padding(horizontal = Gutter, vertical = 16.dp))
        }
    }
    if (logoutDialog) AlertDialog(onDismissRequest = { logoutDialog = false }, title = { Text("Log out?") }, text = { Text("You can sign back in any time with your mobile number.") },
        confirmButton = { TextButton({ logoutDialog = false; onLogout() }) { Text("Log out") } }, dismissButton = { TextButton({ logoutDialog = false }) { Text("Cancel") } })
    if (deleteDialog) AlertDialog(onDismissRequest = { deleteDialog = false }, icon = { Icon(Icons.Rounded.Warning, null, tint = MaterialTheme.colorScheme.error) }, title = { Text("Delete your account?") },
        text = { Text("This permanently removes your profile, phone number, posts, Moments, comments and messages, and your sign-in. It can't be undone.") },
        confirmButton = { TextButton({ deleteDialog = false; vm.deleteAccount(); onDeleted() }) { Text("Delete my account", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ deleteDialog = false }) { Text("Cancel") } })
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
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Safety centre", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            if (safety.isMinor) SafetyNote(if (safety.isChild) "Your account is managed with a parent. Only approved syncs can message you." else "Teen protections are on for your account.")
            Text("How Bucks keeps you safe", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
            Rule(Icons.Rounded.Lock, "You decide who reaches you", "By default only people you've synced with can message you. Change it in Privacy.")
            Rule(Icons.Rounded.OutlinedFlag, "Report anything", "Every post, comment, Moment, message and profile has Report. Reports are private and our team reviews each one.")
            Rule(Icons.Rounded.Block, "Block in one tap", "A blocked person can't message you, sync with you or see your posts. They aren't told.")
            Rule(Icons.Rounded.NearMe, "Your exact location stays private", "Nearby uses an area of about 2 km. Your home is never shown.")
            Rule(Icons.Rounded.FamilyRestroom, "Extra care for under-18s", "Teens are private by default, adults they don't know can't find them, and a parent or guardian agrees when they join.")
            Spacer(Modifier.height(12.dp))
            Item(Icons.Rounded.Lock, "Privacy settings", null) { onOpen(Routes.SETTINGS_PRIVACY) }
            Item(Icons.Rounded.Block, "Blocked people", null) { onOpen(Routes.SETTINGS_BLOCKED) }
            Item(Icons.Rounded.Place, "Posts on the map", "Whether your posts show as places on the map") { onOpen(Routes.SETTINGS_MAP) }
            Item(Icons.Rounded.ChildCare, "Child safety standards", null) { Legal.open(ctx, Legal.CHILD_SAFETY) }
            Item(Icons.Rounded.Gavel, "Community guidelines", null) { Legal.open(ctx, Legal.GUIDELINES) }
            Text("Need help now?", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 20.dp).semantics { heading() })
            Muted("Emergency 112 · Childline 1098 · Tele-MANAS (mental health, free, 24×7) 14416 · Cyber crime helpline 1930", Modifier.padding(top = 6.dp))
        }
    }
}

@Composable
private fun Rule(icon: ImageVector, title: String, text: String) = Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.Top) {
    Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
    Column(Modifier.padding(start = 14.dp)) { Text(title, style = MaterialTheme.typography.titleSmall); Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

private val FAQ = listOf(
    "What is a sync?" to "A sync is a two-way connection, like a friend request. Once you're synced you see each other's posts for syncs, and you can message each other.",
    "Who can see my posts?" to "You choose for each post: Synced only, Nearby (people within about 5 km), or Everyone. Moments last 24 hours and go to syncs or close friends.",
    "How do I find my friends?" to "Open Discover. Search a name, check your phone contacts, or scan their Bucks ID QR from their profile.",
    "Someone is bothering me. What can I do?" to "Open their profile or the message, tap ⋯ and choose Block or Report. They aren't told who reported them.",
    "Why do you ask for my date of birth?" to "People under 18 get extra privacy and safety settings, and Indian law needs a parent's consent for them. Your birthday is never shown.",
    "How do I delete my account?" to "Settings → Delete account. Your profile, posts, Moments, comments and messages are removed. You can also ask us from the account deletion page.",
)

/** Help: common questions, how to reach us, and the grievance officer required by the IT Rules 2021. */
@Composable
fun HelpScreen(vm: BucksViewModel, onBack: () -> Unit, onFeedback: () -> Unit = {}) {
    val ctx = LocalContext.current
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Help and support", onBack = onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
            Text("Common questions", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            FAQ.forEach { (q, a) -> FaqItem(q, a) }
            Text("Contact us", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 24.dp).semantics { heading() })
            if (Legal.supportEmail.isNotBlank()) {
                Item(Icons.Rounded.Email, "Email support", Legal.supportEmail) { Legal.emailSupport(ctx, "Help with Bucks") }
                Item(Icons.Rounded.BugReport, "Report a problem with the app", "Tell us what went wrong") { Legal.emailSupport(ctx, "Problem report") }
            } else Muted("Use Report on any post, message or profile, and our team will see it.", Modifier.padding(top = 8.dp))
            Item(Icons.Rounded.Lightbulb, "Feedback board", "Ideas and bugs, voted on by everyone", onClick = onFeedback)
            Text("Grievance officer", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp).semantics { heading() })
            Muted("Under the Information Technology (Intermediary Guidelines) Rules, 2021, you can raise a complaint with our grievance officer. We acknowledge complaints within 24 hours and resolve them within 15 days.", Modifier.padding(top = 6.dp))
            if (Legal.grievanceOfficer.isNotBlank()) Text(Legal.grievanceOfficer, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 8.dp))
            Item(Icons.Rounded.OpenInNew, "Grievance details", null) { Legal.open(ctx, Legal.GRIEVANCE) }
            Item(Icons.Rounded.DeleteOutline, "Account deletion", null) { Legal.open(ctx, Legal.DELETE_ACCOUNT) }
        }
    }
}

@Composable
private fun FaqItem(q: String, a: String) {
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize().clickable(role = Role.Button, onClickLabel = if (open) "Hide answer" else "Show answer") { open = !open }.padding(vertical = 12.dp)) {
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
    ContentColumn(Modifier.fillMaxHeight()) { BucksTopBar("Review reports", onBack = onBack, actions = { IconButton({ safety.refreshQueue() }) { Icon(Icons.Rounded.Refresh, "Refresh") } })
        if (safety.queue.isEmpty()) Muted("Nothing waiting. New reports appear here.", Modifier.padding(Gutter))
        LazyColumn(contentPadding = PaddingValues(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(safety.queue, key = { it.id }) { r ->
                val reason = runCatching { ReportReason.valueOf(r.reason) }.getOrNull()
                BucksCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (r.reason == "CHILD_SAFETY" || r.reason == "SELF_HARM") PillBad(reason?.label ?: r.reason) else PillWarn(reason?.label ?: r.reason)
                        Spacer(Modifier.width(8.dp)); PillGrey(r.targetKind.lowercase()); Spacer(Modifier.weight(1f)); Muted(ago(r.createdAt))
                    }
                    Text(r.preview?.ifBlank { null } ?: "(no text: media or removed)", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 10.dp))
                    if (r.detail.isNotBlank()) Muted("Reporter: ${r.detail}", Modifier.padding(top = 6.dp))
                    Muted("By ${r.ownerName ?: "unknown"} · ${r.reporters} report${if (r.reporters == 1) "" else "s"}", Modifier.padding(top = 6.dp))
                    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        r.targetOwner?.let { o -> TextButton({ onOpenPerson(o) }) { Text("Profile") } }
                        Spacer(Modifier.weight(1f))
                        TextButton({ safety.review(r.id, "DISMISS") }) { Text("Dismiss") }
                        if (r.targetKind != "PROFILE") FilledTonalButton({ confirm = r.id to "REMOVE" }) { Text("Remove") }
                        Button({ confirm = r.id to "BAN" }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("Ban") }
                    }
                }
            }
        }
    }
    confirm?.let { (id, action) -> AlertDialog(onDismissRequest = { confirm = null }, title = { Text(if (action == "BAN") "Remove and suspend the account?" else "Remove this content?") },
        text = { Text(if (action == "BAN") "The content comes down and the account can no longer use Bucks." else "It comes down for everyone, and every open report on it is closed.") },
        confirmButton = { TextButton({ safety.review(id, action); confirm = null }) { Text("Confirm", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton({ confirm = null }) { Text("Cancel") } }) }
}
