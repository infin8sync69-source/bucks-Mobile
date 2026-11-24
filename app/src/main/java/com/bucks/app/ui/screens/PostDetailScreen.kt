package com.bucks.app.ui.screens

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import com.bucks.app.R
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bucks.app.data.Backend
import com.bucks.app.data.PostRow
import com.bucks.app.data.postById
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.manage.CenteredLoading

/** One post with its photos and its comments; where a comment, like or reply notification opens. */
@Composable
fun PostDetailScreen(vm: BucksViewModel, postId: String, onBack: () -> Unit) {
    var post by remember { mutableStateOf<PostRow?>(null) }; var state by remember { mutableStateOf("loading") }; var comments by remember { mutableStateOf(true) }
    LaunchedEffect(postId) {
        val p = runCatching { Backend.postById(postId) }.onFailure { state = "error" }.getOrNull()
        if (p == null && state != "error") state = "gone"
        p?.let { vm.social.namesFor(listOf(it.authorId)); post = it; state = "ok" }
    }
    ContentColumn(Modifier.fillMaxHeight()) {
        BucksTopBar(stringResource(R.string.g2_post_title), onBack = onBack)
        val p = post
        when {
            p != null -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(vm.social.nameOf(p.authorId)), size = 40, photoUrl = vm.social.photoOf(p.authorId))
                    Column(Modifier.padding(start = 10.dp)) { Text(vm.social.nameOf(p.authorId), style = MaterialTheme.typography.titleMedium); Muted(ago(p.createdAt)) }
                }
                if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 12.dp))
                PostMedia(vm, p.media)
                Muted(pluralStringResource(R.plurals.g2_post_counts, p.comments, p.up, p.comments), Modifier.padding(top = 12.dp))
                SmallButton(stringResource(R.string.g2_comments), Modifier.padding(top = 10.dp), tonal = true) { comments = true }
            }
            state == "loading" -> CenteredLoading()
            else -> Column(Modifier.padding(Gutter)) { Text(stringResource(if (state == "error") R.string.g2_post_load_failed else R.string.g2_post_gone), style = MaterialTheme.typography.titleMedium)
                Muted(stringResource(if (state == "error") R.string.g2_check_connection else R.string.g2_post_gone_detail), Modifier.padding(top = 4.dp)) }
        }
    }
    if (comments && post != null) CloudCommentsSheet(vm, postId) { comments = false }
}
