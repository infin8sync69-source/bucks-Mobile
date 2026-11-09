package com.bucks.app.ui.social

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Analytics
import com.bucks.app.data.BackendFeedback
import com.bucks.app.data.FeedbackRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.launch

private val STATUS = mapOf("OPEN" to "Open", "PLANNED" to "Planned", "IN_PROGRESS" to "In progress", "DONE" to "Done", "DECLINED" to "Not planned")
private val CATEGORY = mapOf("IDEA" to "Idea", "BUG" to "Bug", "OTHER" to "Other")

/**
 * Feedback board: suggest ideas, report bugs, upvote what matters and see what the team is doing. Staff can set a status and a
 * public note on each post.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackBoardScreen(vm: BucksViewModel, onBack: () -> Unit) {
    val reporter = LocalReporter.current
    val scope = rememberCoroutineScope()
    var sort by rememberSaveable { mutableStateOf("TOP") }; var filter by rememberSaveable { mutableStateOf("ALL") }
    var rows by remember { mutableStateOf<List<FeedbackRow>?>(null) }; var composing by remember { mutableStateOf(false) }
    var staffFor by remember { mutableStateOf<FeedbackRow?>(null) }; var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { vm.services.checkStaff() }
    LaunchedEffect(sort, filter, tick) {
        rows = null
        rows = runCatching { when (filter) { "MINE" -> BackendFeedback.list(sort, mine = true); "ALL" -> BackendFeedback.list(sort); else -> BackendFeedback.list(sort, status = filter) } }
            .getOrElse { vm.toast("Couldn't load the board. Check your connection."); emptyList() }
    }
    fun vote(r: FeedbackRow) = scope.launch {
        val on = !r.voted
        rows = rows?.map { if (it.id == r.id) it.copy(voted = on, votes = it.votes + if (on) 1 else -1) else it }
        runCatching { BackendFeedback.vote(r.id, on) }.onSuccess { n -> rows = rows?.map { if (it.id == r.id) it.copy(votes = n) else it } }
            .onFailure { rows = rows?.map { if (it.id == r.id) r else it }; vm.toast("Couldn't save your vote.") }
    }
    Scaffold(containerColor = MaterialTheme.colorScheme.background,
        topBar = { BucksTopBar("Feedback board", onBack = onBack) },
        floatingActionButton = { ExtendedFloatingActionButton(onClick = { composing = true }, icon = { Icon(Icons.Rounded.Lightbulb, null) }, text = { Text("Suggest") }) }) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                Muted("Tell us what would make Bucks better. Vote for the ideas you want most; the team reads every post.", Modifier.padding(horizontal = Gutter, vertical = 4.dp))
                Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("ALL" to "All", "PLANNED" to "Planned", "IN_PROGRESS" to "In progress", "DONE" to "Done", "MINE" to "Mine").forEach { (k, l) -> FilterChip(filter == k, { filter = k }, { Text(l) }) }
                }
                SingleChoiceSegmentedButtonRow(Modifier.padding(horizontal = Gutter).fillMaxWidth()) {
                    listOf("TOP" to "Most votes", "NEW" to "Newest").forEachIndexed { i, (k, l) -> SegmentedButton(sort == k, { sort = k }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(l) } }
                }
            }
            when {
                rows == null -> item { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                rows!!.isEmpty() -> item { Muted(if (filter == "MINE") "You haven't posted yet. Tap Suggest to share an idea." else "Nothing here yet. Be the first to suggest something.", Modifier.padding(Gutter)) }
                else -> items(rows!!, key = { it.id }) { r -> FeedbackCard(r, staff = vm.services.isStaff, onVote = { vote(r) }, onStaff = { staffFor = r },
                    onDelete = { scope.launch { runCatching { BackendFeedback.delete(r.id) }.onSuccess { rows = rows?.filterNot { it.id == r.id } }.onFailure { vm.toast("Couldn't delete it.") } } },
                    onReport = reporter?.let { rep -> { rep(ReportTarget("FEEDBACK", r.id, null, r.authorName)) } }) }
            }
        }
    }
    if (composing) ComposeFeedbackSheet(vm, onDismiss = { composing = false }) { composing = false; sort = "NEW"; filter = "ALL"; tick++ }
    staffFor?.let { r -> StaffStatusSheet(vm, r, onDismiss = { staffFor = null }) { staffFor = null; tick++ } }
}

@Composable
private fun FeedbackCard(r: FeedbackRow, staff: Boolean, onVote: () -> Unit, onStaff: () -> Unit, onDelete: () -> Unit, onReport: (() -> Unit)? = null) {
    var menu by remember { mutableStateOf(false) }
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
            // The vote box: big target, clear state, count announced.
            Column(Modifier.width(56.dp).clip(MaterialTheme.shapes.medium).background(if (r.voted) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer)
                .clickable(role = Role.Button, onClickLabel = if (r.voted) "Remove your vote" else "Vote for this", onClick = onVote).padding(vertical = 10.dp)
                .semantics(mergeDescendants = true) { contentDescription = "${r.votes} votes" + if (r.voted) ", you voted" else "" }, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.KeyboardArrowUp, null, tint = if (r.voted) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${r.votes}", style = MaterialTheme.typography.titleMedium, color = if (r.voted) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface)
            }
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    when (r.status) { "DONE" -> PillGood(STATUS[r.status]!!); "PLANNED", "IN_PROGRESS" -> PillPurple(STATUS[r.status]!!); "DECLINED" -> PillGrey(STATUS[r.status]!!); else -> PillGrey(STATUS[r.status] ?: r.status) }
                    Spacer(Modifier.width(6.dp)); PillGrey(CATEGORY[r.category] ?: r.category)
                    Spacer(Modifier.weight(1f))
                    if (r.isMine || staff || onReport != null) Box {
                        IconButton({ menu = true }, Modifier.size(48.dp)) { Icon(Icons.Rounded.MoreHoriz, "More options") }
                        DropdownMenu(menu, { menu = false }) {
                            if (staff) DropdownMenuItem({ Text("Set status") }, { menu = false; onStaff() })
                            if (!r.isMine && onReport != null) DropdownMenuItem({ Text("Report") }, { menu = false; onReport() }, leadingIcon = { Icon(Icons.Rounded.OutlinedFlag, null) })
                            if (r.isMine || staff) DropdownMenuItem({ Text("Delete", color = MaterialTheme.colorScheme.error) }, { menu = false; onDelete() })
                        }
                    }
                }
                Text(r.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 6.dp))
                if (r.body.isNotBlank()) Text(r.body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp))
                if (r.staffNote.isNotBlank()) Row(Modifier.padding(top = 8.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.secondaryContainer).padding(10.dp)) {
                    Icon(Icons.Rounded.Verified, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
                    Text("Bucks team: ${r.staffNote}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.padding(start = 8.dp))
                }
                Muted("${if (r.isMine) "You" else r.authorName} · ${ago(r.createdAt)}", Modifier.padding(top = 6.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ComposeFeedbackSheet(vm: BucksViewModel, onDismiss: () -> Unit, onPosted: () -> Unit) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }; var body by remember { mutableStateOf("") }; var category by remember { mutableStateOf("IDEA") }; var busy by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Gutter).padding(bottom = 28.dp).imePadding()) {
            Text("Share feedback", style = MaterialTheme.typography.titleLarge)
            Row(Modifier.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { CATEGORY.forEach { (k, l) -> FilterChip(category == k, { category = k }, { Text(l) }) } }
            BucksField(title, { title = it.take(100) }, if (category == "BUG") "What went wrong?" else "Your idea in a line", if (category == "BUG") "Photos don't load in chat" else "Let me pin a post to my profile")
            BucksField(body, { body = it.take(1000) }, "More detail (optional)", if (category == "BUG") "What you did, what you expected, what happened" else "Why it would help", singleLine = false, minLines = 3)
            Muted("Everyone on the board can read this. Don't include phone numbers or anything private.", Modifier.padding(top = 4.dp))
            PrimaryButton(if (busy) "Posting…" else "Post", Modifier.padding(top = 16.dp), enabled = title.trim().length >= 4 && !busy) {
                busy = true
                scope.launch {
                    runCatching { BackendFeedback.post(title.trim(), body.trim(), category) }
                        .onSuccess { Analytics.log(Analytics.FEEDBACK, "category" to category); vm.toast("Thanks! Your post is on the board."); onPosted() }
                        .onFailure { e -> vm.toast(Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message.orEmpty())?.groupValues?.get(1) ?: "Couldn't post. Try again.") }
                    busy = false
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StaffStatusSheet(vm: BucksViewModel, r: FeedbackRow, onDismiss: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf(r.status) }; var note by remember { mutableStateOf(r.staffNote) }
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) {
        Column(Modifier.padding(horizontal = Gutter).padding(bottom = 28.dp).imePadding()) {
            Text("Set status", style = MaterialTheme.typography.titleLarge)
            Text(r.title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { STATUS.forEach { (k, l) -> FilterChip(status == k, { status = k }, { Text(l) }) } }
            BucksField(note, { note = it.take(500) }, "Public note (optional)", "Coming in the next update", Modifier.padding(top = 12.dp), singleLine = false, minLines = 2)
            PrimaryButton("Save", Modifier.padding(top = 12.dp)) {
                scope.launch { runCatching { BackendFeedback.setStatus(r.id, status, note.trim()) }.onSuccess { onSaved() }.onFailure { vm.toast("Couldn't save.") } }
            }
        }
    }
}
