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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bucks.app.R
import com.bucks.app.data.Str
import com.bucks.app.data.Analytics
import com.bucks.app.data.BackendFeedback
import com.bucks.app.data.FeedbackRow
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.ago
import kotlinx.coroutines.launch

private val STATUS = mapOf("OPEN" to R.string.g4_fb_status_open, "PLANNED" to R.string.g4_fb_status_planned, "IN_PROGRESS" to R.string.g4_fb_status_in_progress, "DONE" to R.string.g4_fb_status_done, "DECLINED" to R.string.g4_fb_status_declined)
private val CATEGORY = mapOf("IDEA" to R.string.g4_fb_cat_idea, "BUG" to R.string.g4_fb_cat_bug, "OTHER" to R.string.g4_fb_cat_other)

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
            .getOrElse { vm.toast(Str.get(R.string.g4_fb_load_failed)); emptyList() }
    }
    fun vote(r: FeedbackRow) = scope.launch {
        val on = !r.voted
        rows = rows?.map { if (it.id == r.id) it.copy(voted = on, votes = it.votes + if (on) 1 else -1) else it }
        runCatching { BackendFeedback.vote(r.id, on) }.onSuccess { n -> rows = rows?.map { if (it.id == r.id) it.copy(votes = n) else it } }
            .onFailure { rows = rows?.map { if (it.id == r.id) r else it }; vm.toast(Str.get(R.string.g4_fb_vote_failed)) }
    }
    Scaffold(containerColor = MaterialTheme.colorScheme.background,
        topBar = { BucksTopBar(stringResource(R.string.g4_fb_title), onBack = onBack) },
        floatingActionButton = { ExtendedFloatingActionButton(onClick = { composing = true }, icon = { Icon(Icons.Rounded.Lightbulb, null) }, text = { Text(stringResource(R.string.g4_fb_suggest)) }) }) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
            item {
                Muted(stringResource(R.string.g4_fb_intro), Modifier.padding(horizontal = Gutter, vertical = 4.dp))
                Row(Modifier.padding(horizontal = Gutter, vertical = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("ALL" to R.string.g4_fb_filter_all, "PLANNED" to R.string.g4_fb_status_planned, "IN_PROGRESS" to R.string.g4_fb_status_in_progress, "DONE" to R.string.g4_fb_status_done, "MINE" to R.string.g4_fb_filter_mine).forEach { (k, l) -> FilterChip(filter == k, { filter = k }, { Text(stringResource(l)) }) }
                }
                SingleChoiceSegmentedButtonRow(Modifier.padding(horizontal = Gutter).fillMaxWidth()) {
                    listOf("TOP" to R.string.g4_fb_sort_top, "NEW" to R.string.g4_fb_sort_new).forEachIndexed { i, (k, l) -> SegmentedButton(sort == k, { sort = k }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(stringResource(l)) } }
                }
            }
            when {
                rows == null -> item { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                rows!!.isEmpty() -> item { Muted(if (filter == "MINE") stringResource(R.string.g4_fb_empty_mine) else stringResource(R.string.g4_fb_empty), Modifier.padding(Gutter)) }
                else -> items(rows!!, key = { it.id }) { r -> FeedbackCard(r, staff = vm.services.isStaff, onVote = { vote(r) }, onStaff = { staffFor = r },
                    onDelete = { scope.launch { runCatching { BackendFeedback.delete(r.id) }.onSuccess { rows = rows?.filterNot { it.id == r.id } }.onFailure { vm.toast(Str.get(R.string.g4_fb_delete_failed)) } } },
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
    val votesCd = if (r.voted) pluralStringResource(R.plurals.g4_cd_fb_votes_mine, r.votes, r.votes) else pluralStringResource(R.plurals.g4_cd_fb_votes, r.votes, r.votes)
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
            // The vote box: big target, clear state, count announced.
            Column(Modifier.width(56.dp).clip(MaterialTheme.shapes.medium).background(if (r.voted) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer)
                .clickable(role = Role.Button, onClickLabel = if (r.voted) stringResource(R.string.g4_fb_unvote) else stringResource(R.string.g4_fb_vote), onClick = onVote).padding(vertical = 10.dp)
                .semantics(mergeDescendants = true) { contentDescription = votesCd }, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.KeyboardArrowUp, null, tint = if (r.voted) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${r.votes}", style = MaterialTheme.typography.titleMedium, color = if (r.voted) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface)
            }
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    when (r.status) { "DONE" -> PillGood(stringResource(STATUS[r.status]!!)); "PLANNED", "IN_PROGRESS" -> PillPurple(stringResource(STATUS[r.status]!!)); "DECLINED" -> PillGrey(stringResource(STATUS[r.status]!!)); else -> PillGrey(STATUS[r.status]?.let { stringResource(it) } ?: r.status) }
                    Spacer(Modifier.width(6.dp)); PillGrey(CATEGORY[r.category]?.let { stringResource(it) } ?: r.category)
                    Spacer(Modifier.weight(1f))
                    if (r.isMine || staff || onReport != null) Box {
                        IconButton({ menu = true }, Modifier.size(48.dp)) { Icon(Icons.Rounded.MoreHoriz, stringResource(R.string.g4_cd_more_options)) }
                        DropdownMenu(menu, { menu = false }) {
                            if (staff) DropdownMenuItem({ Text(stringResource(R.string.g4_fb_set_status)) }, { menu = false; onStaff() })
                            if (!r.isMine && onReport != null) DropdownMenuItem({ Text(stringResource(R.string.g4_fb_report)) }, { menu = false; onReport() }, leadingIcon = { Icon(Icons.Rounded.OutlinedFlag, null) })
                            if (r.isMine || staff) DropdownMenuItem({ Text(stringResource(R.string.g4_fb_delete), color = MaterialTheme.colorScheme.error) }, { menu = false; onDelete() })
                        }
                    }
                }
                Text(r.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 6.dp))
                if (r.body.isNotBlank()) Text(r.body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp))
                if (r.staffNote.isNotBlank()) Row(Modifier.padding(top = 8.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.secondaryContainer).padding(10.dp)) {
                    Icon(Icons.Rounded.Verified, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
                    Text(stringResource(R.string.g4_fb_team_note, r.staffNote), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.padding(start = 8.dp))
                }
                Muted(stringResource(R.string.g4_fb_byline, if (r.isMine) stringResource(R.string.g4_fb_you) else r.authorName, ago(r.createdAt)), Modifier.padding(top = 6.dp))
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
            Text(stringResource(R.string.g4_fb_share_title), style = MaterialTheme.typography.titleLarge)
            Row(Modifier.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { CATEGORY.forEach { (k, l) -> FilterChip(category == k, { category = k }, { Text(stringResource(l)) }) } }
            BucksField(title, { title = it.take(100) }, if (category == "BUG") stringResource(R.string.g4_fb_bug_title) else stringResource(R.string.g4_fb_idea_title), if (category == "BUG") stringResource(R.string.g4_fb_bug_title_hint) else stringResource(R.string.g4_fb_idea_title_hint))
            BucksField(body, { body = it.take(1000) }, stringResource(R.string.g4_fb_detail), if (category == "BUG") stringResource(R.string.g4_fb_bug_detail_hint) else stringResource(R.string.g4_fb_idea_detail_hint), singleLine = false, minLines = 3)
            Muted(stringResource(R.string.g4_fb_public_warning), Modifier.padding(top = 4.dp))
            PrimaryButton(if (busy) stringResource(R.string.g4_fb_posting) else stringResource(R.string.g4_fb_post), Modifier.padding(top = 16.dp), enabled = title.trim().length >= 4 && !busy) {
                busy = true
                scope.launch {
                    runCatching { BackendFeedback.post(title.trim(), body.trim(), category) }
                        .onSuccess { Analytics.log(Analytics.FEEDBACK, "category" to category); vm.toast(Str.get(R.string.g4_fb_posted)); onPosted() }
                        .onFailure { e -> vm.toast(Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(e.message.orEmpty())?.groupValues?.get(1) ?: Str.get(R.string.g4_fb_post_failed)) }
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
            Text(stringResource(R.string.g4_fb_set_status), style = MaterialTheme.typography.titleLarge)
            Text(r.title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
            Row(Modifier.horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { STATUS.forEach { (k, l) -> FilterChip(status == k, { status = k }, { Text(stringResource(l)) }) } }
            BucksField(note, { note = it.take(500) }, stringResource(R.string.g4_fb_note), stringResource(R.string.g4_fb_note_hint), Modifier.padding(top = 12.dp), singleLine = false, minLines = 2)
            PrimaryButton(stringResource(R.string.g4_fb_save), Modifier.padding(top = 12.dp)) {
                scope.launch { runCatching { BackendFeedback.setStatus(r.id, status, note.trim()) }.onSuccess { onSaved() }.onFailure { vm.toast(Str.get(R.string.g4_fb_save_failed)) } }
            }
        }
    }
}
