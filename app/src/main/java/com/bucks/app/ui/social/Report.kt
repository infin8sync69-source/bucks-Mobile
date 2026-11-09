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
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.annotation.StringRes

/** What is being reported. [kind]: POST, COMMENT, MOMENT, MESSAGE, PROFILE, LISTING, REVIEW, JOB or FEEDBACK. [ownerId] lets the sheet offer "also block". */
data class ReportTarget(val kind: String, val id: String, val ownerId: String?, val ownerName: String) {
    /** Sheet title for a report of anything but a profile ("Report this post"). */
    @get:StringRes val titleRes: Int get() = when (kind) { "POST" -> R.string.g6_report_post; "COMMENT" -> R.string.g6_report_comment; "MOMENT" -> R.string.g6_report_moment; "MESSAGE" -> R.string.g6_report_message; "LISTING" -> R.string.g6_report_page; "REVIEW" -> R.string.g6_report_review; "JOB" -> R.string.g6_report_job; "FEEDBACK" -> R.string.g6_report_feedback; else -> R.string.g6_report_account }
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
    val msgMapThanks = stringResource(R.string.g6_report_map_thanks); val msgSendFailed = stringResource(R.string.g6_report_send_failed)
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Flag, null, tint = MaterialTheme.colorScheme.error)
                Text(if (target.kind == "PROFILE") stringResource(R.string.g6_report_name, target.ownerName) else stringResource(target.titleRes), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 10.dp))
            }
            Muted(if (target.ownerName.isBlank()) stringResource(R.string.g6_report_anon) else stringResource(R.string.g6_report_anon_name, target.ownerName), Modifier.padding(top = 6.dp, bottom = 12.dp))
            if (target.kind == "POST") Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).selectable(selected = mapLocation, role = Role.RadioButton) { mapLocation = true; reason = null }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = mapLocation, onClick = null)
                Column(Modifier.padding(start = 12.dp)) { Text(stringResource(R.string.g6_report_map), style = MaterialTheme.typography.bodyLarge); Muted(stringResource(R.string.g6_report_map_hint)) }
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
                        Text(stringResource(R.string.g6_report_danger), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onErrorContainer)
                        HelpLine(stringResource(R.string.g6_help_emergency), "112", ctx); HelpLine(stringResource(R.string.g6_help_childline), "1098", ctx); HelpLine(stringResource(R.string.g6_help_telemanas), "14416", ctx)
                    }
                }
            }
            if (reason != null || mapLocation) BucksField(detail, { detail = it.take(500) }, stringResource(R.string.g6_report_detail_label), stringResource(R.string.g6_report_detail_hint), Modifier.padding(top = 14.dp), singleLine = false, minLines = 3)
            if (canBlock) Row(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).toggleable(alsoBlock, role = Role.Checkbox) { alsoBlock = it }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = alsoBlock, onCheckedChange = null)
                Column(Modifier.padding(start = 12.dp)) { Text(if (target.ownerName.isBlank()) stringResource(R.string.g6_report_block) else stringResource(R.string.g6_report_block_name, target.ownerName), style = MaterialTheme.typography.bodyLarge); Muted(stringResource(R.string.g6_report_block_hint)) }
            }
            PrimaryButton(if (safety.busy || sendingMap) stringResource(R.string.g6_sending) else stringResource(R.string.g6_report_send), Modifier.padding(top = 14.dp), enabled = (reason != null || mapLocation) && !safety.busy && !sendingMap) {
                if (mapLocation) {
                    sendingMap = true
                    scope.launch {
                        runCatching { com.bucks.app.data.MapBackend.reportLocation(target.id, detail.trim()) }
                            .onSuccess { vm.toast(msgMapThanks); if (alsoBlock && canBlock) target.ownerId?.let { vm.social.block(it) }; onDismiss() }
                            .onFailure { vm.toast(msgSendFailed) }
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
    Row(Modifier.fillMaxWidth().clickable(onClickLabel = stringResource(R.string.g6_cd_call, label)) { runCatching { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))) } }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Call, null, tint = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.size(18.dp))
        Text(stringResource(R.string.g6_help_line, label, number), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.padding(start = 10.dp))
    }

