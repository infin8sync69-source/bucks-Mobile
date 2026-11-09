package com.bucks.app.ui.social

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.bucks.app.data.ReportReason
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.coroutines.launch

/** What is being reported. [kind]: POST, COMMENT, MOMENT, MESSAGE or PROFILE. [ownerId] lets the sheet offer "also block". */
data class ReportTarget(val kind: String, val id: String, val ownerId: String?, val ownerName: String) {
    val noun get() = when (kind) { "POST" -> "post"; "COMMENT" -> "comment"; "MOMENT" -> "moment"; "MESSAGE" -> "message"; else -> "account" }
}

/**
 * Screens ask for a report through this; the social shell provides it and shows [ReportSheet]. Null (the legacy shell) hides the
 * Report entries rather than offering something that goes nowhere.
 */
val LocalReporter = staticCompositionLocalOf<((ReportTarget) -> Unit)?> { null }

/**
 * Report flow: pick a reason, add detail if you like, optionally block the person too. Reasons that mean someone may be in danger
 * show emergency and helpline numbers straight away, before anything is sent.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportSheet(vm: BucksViewModel, target: ReportTarget, onDismiss: () -> Unit) {
    val safety = vm.safety; val ctx = LocalContext.current
    var reason by remember { mutableStateOf<ReportReason?>(null) }; var detail by remember { mutableStateOf("") }
    // A post only: "it shows my home or where I am". Takes the post off the map at once, then staff review it.
    var mapLocation by remember { mutableStateOf(false) }; var sendingMap by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val canBlock = target.ownerId != null && target.ownerId != vm.social.me?.id
    var alsoBlock by remember { mutableStateOf(target.kind == "PROFILE" || target.kind == "MESSAGE") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Flag, null, tint = MaterialTheme.colorScheme.error)
                Text(if (target.kind == "PROFILE") "Report ${target.ownerName}" else "Report this ${target.noun}", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 10.dp))
            }
            Muted("${target.ownerName.ifBlank { "They" }} won't know who reported them. Our team reviews every report.", Modifier.padding(top = 6.dp, bottom = 12.dp))
            if (target.kind == "POST") Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).selectable(selected = mapLocation, role = Role.RadioButton) { mapLocation = true; reason = null }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = mapLocation, onClick = null)
                Column(Modifier.padding(start = 12.dp)) { Text("It shows my home or where I am", style = MaterialTheme.typography.bodyLarge); Muted("Comes off the map right away while our team checks.") }
            }
            ReportReason.entries.forEach { r ->
                Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).selectable(selected = reason == r, role = Role.RadioButton) { reason = r; mapLocation = false }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = reason == r, onClick = null)
                    Column(Modifier.padding(start = 12.dp)) { Text(r.label, style = MaterialTheme.typography.bodyLarge); if (r.hint.isNotBlank()) Muted(r.hint) }
                }
            }
            if (reason == ReportReason.SELF_HARM || reason == ReportReason.CHILD_SAFETY || reason == ReportReason.VIOLENCE) {
                Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Text("If someone is in danger right now, call for help first.", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onErrorContainer)
                        HelpLine("Emergency", "112", ctx); HelpLine("Childline (children in need)", "1098", ctx); HelpLine("Tele-MANAS (mental health, free, 24×7)", "14416", ctx)
                    }
                }
            }
            if (reason != null || mapLocation) BucksField(detail, { detail = it.take(500) }, "Anything else we should know? (optional)", "What happened", Modifier.padding(top = 14.dp), singleLine = false, minLines = 3)
            if (canBlock) Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).toggleable(alsoBlock, role = Role.Checkbox) { alsoBlock = it }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = alsoBlock, onCheckedChange = null)
                Column(Modifier.padding(start = 12.dp)) { Text("Also block ${target.ownerName.ifBlank { "them" }}", style = MaterialTheme.typography.bodyLarge); Muted("They can't message you, sync with you or see your posts.") }
            }
            PrimaryButton(if (safety.busy || sendingMap) "Sending…" else "Send report", Modifier.padding(top = 14.dp), enabled = (reason != null || mapLocation) && !safety.busy && !sendingMap) {
                if (mapLocation) {
                    sendingMap = true
                    scope.launch {
                        runCatching { com.bucks.app.data.MapBackend.reportLocation(target.id, detail.trim()) }
                            .onSuccess { vm.toast("Thanks. It's off the map while we check."); if (alsoBlock && canBlock) target.ownerId?.let { vm.social.block(it) }; onDismiss() }
                            .onFailure { vm.toast("Couldn't send that. Check your connection and try again.") }
                        sendingMap = false
                    }
                    return@PrimaryButton
                }
                val r = reason ?: return@PrimaryButton
                safety.report(target.kind, target.id, r.name, detail.trim()) {
                    if (alsoBlock && canBlock) target.ownerId?.let { vm.social.block(it) }
                    onDismiss()
                }
            }
        }
    }
}

@Composable
private fun HelpLine(label: String, number: String, ctx: android.content.Context) =
    Row(Modifier.fillMaxWidth().clickable(onClickLabel = "Call $label") { runCatching { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))) } }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Call, null, tint = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.size(18.dp))
        Text("$label · $number", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.padding(start = 10.dp))
    }

