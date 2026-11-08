package com.bucks.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

/**
 * "Are you sure, and why?" for cancelling a ride or an order. One tap on "Keep it" keeps everything; cancelling needs a reason when
 * [requireReason] (someone has already accepted), so the other side hears why. Reasons are (code, label) pairs; the codes go to the server
 * (CancelReasons in data/BackendCancel.kt). "OTHER" opens a short note. [nudge] is a gentle reminder, e.g. how often I cancelled today.
 * [onConfirm] is not dismissed for you: close the sheet from the caller once the server accepted, so a refusal leaves it open.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CancelSheet(
    title: String, message: String, reasons: List<Pair<String, String>>, requireReason: Boolean, confirmLabel: String,
    onConfirm: (code: String?, note: String) -> Unit, onDismiss: () -> Unit,
    modifier: Modifier = Modifier, keepLabel: String = "Keep it", reasonTitle: String = "Why are you cancelling?", nudge: String? = null, busy: Boolean = false,
) {
    var sel by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(modifier.padding(horizontal = Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Muted(message, Modifier.padding(top = 4.dp))
            if (nudge != null) Notice(nudge, Modifier.padding(top = 12.dp))
            Text(if (requireReason) reasonTitle else "$reasonTitle (optional)", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
            reasons.forEach { (code, label) ->
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(MaterialTheme.shapes.small).clickable(enabled = !busy) { sel = if (sel == code && !requireReason) null else code },
                    verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = sel == code, onClick = null, modifier = Modifier.padding(horizontal = 8.dp))
                    Text(label, style = MaterialTheme.typography.bodyLarge)
                }
            }
            if (sel == "OTHER") OutlinedTextField(note, { note = it.take(200) }, Modifier.fillMaxWidth().padding(top = 8.dp), placeholder = { Text("Tell them in a few words (optional)") },
                minLines = 2, maxLines = 4, supportingText = { Text("${note.length}/200") })
            PrimaryButton(keepLabel, Modifier.padding(top = 16.dp), enabled = !busy) { onDismiss() }
            TextButton({ onConfirm(sel, note.trim()) }, Modifier.fillMaxWidth().height(48.dp), enabled = !busy && (!requireReason || sel != null),
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                Text(if (busy) "Cancelling…" else confirmLabel, style = MaterialTheme.typography.labelLarge)
            }
            if (requireReason && sel == null) Muted("Pick a reason to cancel.", Modifier.padding(top = 2.dp).align(Alignment.CenterHorizontally))
        }
    }
}
