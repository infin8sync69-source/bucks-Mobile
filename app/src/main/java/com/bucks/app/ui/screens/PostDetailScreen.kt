package com.bucks.app.ui.screens

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
        BucksTopBar("Post", onBack = onBack)
        val p = post
        when {
            p != null -> Column(Modifier.verticalScroll(rememberScrollState()).padding(Gutter)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(vm.social.nameOf(p.authorId)), size = 40)
                    Column(Modifier.padding(start = 10.dp)) { Text(vm.social.nameOf(p.authorId), style = MaterialTheme.typography.titleMedium); Muted(ago(p.createdAt)) }
                }
                if (p.body.isNotBlank()) Text(p.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 12.dp))
                PostMedia(vm, p.media)
                Muted("${p.up} recommended · ${p.comments} comment${if (p.comments == 1) "" else "s"}", Modifier.padding(top = 12.dp))
                SmallButton("Comments", Modifier.padding(top = 10.dp), tonal = true) { comments = true }
            }
            state == "loading" -> CenteredLoading()
            else -> Column(Modifier.padding(Gutter)) { Text(if (state == "error") "Couldn't load this post" else "This post is gone", style = MaterialTheme.typography.titleMedium)
                Muted(if (state == "error") "Check your connection and try again." else "It was deleted, or you can no longer see it.", Modifier.padding(top = 4.dp)) }
        }
    }
    if (comments && post != null) CloudCommentsSheet(vm, postId) { comments = false }
}
