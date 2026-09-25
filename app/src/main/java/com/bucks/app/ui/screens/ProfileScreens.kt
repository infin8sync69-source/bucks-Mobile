package com.bucks.app.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.status
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun handleOf(name: String) = "@" + name.trim().lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')

/** Cover band with the avatar overlapping its bottom edge. No cover photos exist yet, so a primary gradient stands in (same purples as before in light mode, theme-aware in dark). */
@Composable
fun ProfileCover(initials: String, icon: ImageVector? = null, onBack: (() -> Unit)? = null) = Box(Modifier.fillMaxWidth().height(170.dp)) {
    Box(Modifier.fillMaxWidth().height(140.dp).background(Brush.linearGradient(listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimaryContainer))))
    if (onBack != null) IconButton(onClick = onBack, modifier = Modifier.padding(8.dp)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", tint = MaterialTheme.colorScheme.onPrimary) }
    Box(Modifier.padding(start = Gutter).align(Alignment.BottomStart).size(96.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface).padding(4.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
        if (icon != null) Icon(icon, null, Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer) else Text(initials, style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

@Composable
fun SoftButton(text: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) = Row(modifier.minimumInteractiveComponentSize().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Icon(icon, null, Modifier.size(18.dp)); Text(text, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = 6.dp)) }

@Composable
fun HashTag(t: String) = Box(Modifier.clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal = 10.dp, vertical = 3.dp)) { Text("#" + t.replace(" ", ""), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimaryContainer) }

@Composable
fun BrandTabs(tabs: List<String>, selected: Int, onSelect: (Int) -> Unit) = ScrollableTabRow(selected, containerColor = MaterialTheme.colorScheme.surface, edgePadding = Gutter,
    indicator = { pos -> TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(pos[selected]), height = 3.dp, color = MaterialTheme.colorScheme.primary) }, divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) }) {
    tabs.forEachIndexed { i, l -> Tab(i == selected, onClick = { onSelect(i) }, selectedContentColor = MaterialTheme.colorScheme.onSurface, unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        text = { Text(l, style = MaterialTheme.typography.titleSmall.copy(fontWeight = if (i == selected) FontWeight.SemiBold else FontWeight.Normal)) }) }
}

private data class FileEntry(val a: Attachment, val size: Long, val at: Long)
private fun sizeOf(ctx: Context, uri: String): Long = runCatching { ctx.contentResolver.query(Uri.parse(uri), arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c -> if (c.moveToFirst()) c.getLong(0) else 0L } }.getOrNull() ?: 0L
private fun humanSize(b: Long) = when { b >= 1_048_576 -> "%.2f MB".format(b / 1_048_576.0); b >= 1024 -> "${b / 1024} KB"; b > 0 -> "$b B"; else -> "—" }
private val DATE = SimpleDateFormat("MMM d, yyyy", Locale.ENGLISH)

/** The signed-in user's own profile (Account tab): Feed, Media, Files, Posts. */
@Composable
fun PersonalProfile(vm: BucksViewModel, onEditProfile: () -> Unit, onCreatePost: () -> Unit) {
    val s by vm.state.collectAsState(); val posts by vm.repo.posts.collectAsState(); val chats by vm.repo.chats.collectAsState(); val people by vm.repo.people.collectAsState()
    val u = s.user ?: return; val ctx = LocalContext.current
    val mine = posts.filter { it.who == u.name }
    var tab by rememberSaveableInt(0); var comments by remember { mutableStateOf<String?>(null) }
    val media = (mine.mapNotNull { it.image } + chats.flatMap { c -> c.messages.filter { it.mine && it.attachment?.isImage == true }.mapNotNull { it.attachment?.uri } }).distinct()
    val files = remember(mine, chats) { (mine.mapNotNull { p -> p.attachment?.let { it to p.at } } + chats.flatMap { c -> c.messages.filter { it.mine && it.attachment?.isImage == false }.map { it.attachment!! to it.at } })
        .distinctBy { it.first.uri }.map { (a, at) -> FileEntry(a, sizeOf(ctx, a.uri), at) } }
    fun share() = ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "${u.name} (${handleOf(u.name)}) on Bucks · ${u.area}") }, "Share profile"))
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ProfileCover(initials(u.name))
        Column(Modifier.padding(horizontal = Gutter, vertical = 10.dp)) {
            Text(u.name, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)); Muted(handleOf(u.name))
            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.LocationOn, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Muted(" ${u.area}") }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                CountLabel(people.count { it.following } + s.followedProviders.size, "following"); CountLabel(chats.size, "contacts") }
            if (u.bio.isNotBlank()) Text(u.bio, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
            if (u.interests.isNotEmpty()) Row(Modifier.padding(top = 8.dp).horizontalScrollIfNeeded(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { u.interests.forEach { HashTag(it) } }
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) { SoftButton("Edit profile", Icons.Rounded.EditNote, onClick = onEditProfile); SoftButton("Share", Icons.Rounded.IosShare) { share() } }
        }
        BrandTabs(listOf("Feed", "Media", "Files", "Posts"), tab) { tab = it }
        when (tab) {
            0 -> {
                Row(Modifier.padding(horizontal = Gutter, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(initials(u.name), size = 40)
                    Box(Modifier.weight(1f).padding(start = 10.dp).height(40.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable(onClick = onCreatePost).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) { Muted("Share what's on your mind") }
                    IconButton(onClick = onCreatePost, modifier = Modifier.size(48.dp)) { Icon(Icons.Rounded.Add, "Create a post", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                if (mine.isEmpty()) Muted("Nothing here yet. Share what's on your mind above.", Modifier.padding(Gutter))
                mine.forEach { p -> PostCard(p, s.postVotes[p.id] ?: 0, onVote = { vm.votePost(p.id, it) }, onComments = { comments = p.id }, onShare = { sharePost(ctx, p) }, mine = true) }
            }
            1 -> if (media.isEmpty()) Muted("Photos you post or send in chats appear here.", Modifier.padding(Gutter)) else Column(Modifier.padding(2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                media.chunked(3).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { row.forEach { m -> AsyncImage(m, null, Modifier.weight(1f).aspectRatio(1f).clickable { openUri(ctx, m) }, contentScale = ContentScale.Crop) }; repeat(3 - row.size) { Spacer(Modifier.weight(1f)) } } } }
            2 -> Column(Modifier.padding(Gutter), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (files.isEmpty()) Muted("Documents you post or send in chats appear here.")
                files.forEach { f -> FileRow(f.a, humanSize(f.size), DATE.format(Date(f.at))) { openUri(ctx, f.a.uri) } }
                Surface(Modifier.fillMaxWidth().padding(top = 8.dp), shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) { Column(Modifier.padding(16.dp)) {
                    Text("Storage summary", style = MaterialTheme.typography.titleSmall)
                    Row(Modifier.padding(top = 10.dp)) { Column(Modifier.weight(1f)) { Muted("Total files"); Text("${files.size}", style = MaterialTheme.typography.titleMedium) }; Column(Modifier.weight(1f)) { Muted("Total size"); Text(humanSize(files.sumOf { it.size }), style = MaterialTheme.typography.titleMedium) } } } }
            }
            else -> Column(Modifier.padding(Gutter), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TweetComposer(u.name) { vm.addPost(it) }
                mine.filter { it.image == null && it.attachment == null && !it.hasImage }.forEach { p -> Surface(shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) {
                    PostCard(p, s.postVotes[p.id] ?: 0, onVote = { vm.votePost(p.id, it) }, onComments = { comments = p.id }, onShare = { sharePost(ctx, p) }, mine = true, divider = false) } }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
    comments?.let { id -> PostCommentsSheet(vm, id) { comments = null } }
}

@Composable private fun rememberSaveableInt(v: Int) = androidx.compose.runtime.saveable.rememberSaveable { mutableIntStateOf(v) }
@Composable private fun CountLabel(n: Int, label: String) = Row(verticalAlignment = Alignment.Bottom) { Text("$n", style = MaterialTheme.typography.titleMedium); Muted(" $label") }

fun openUri(ctx: Context, uri: String) { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) } }
fun sharePost(ctx: Context, p: Post) = ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "${p.who} on Bucks: ${p.text}") }, "Share post"))

@Composable
private fun FileRow(a: Attachment, size: String, date: String, onOpen: () -> Unit) {
    val ext = a.name.substringAfterLast('.', "").lowercase()
    val (icon, tint) = when (ext) { "pdf" -> Icons.Rounded.PictureAsPdf to MaterialTheme.status.bad; "doc", "docx", "txt" -> Icons.Rounded.Description to MaterialTheme.colorScheme.primary; "zip", "rar" -> Icons.Rounded.FolderZip to MaterialTheme.status.warn; else -> Icons.Rounded.InsertDriveFile to MaterialTheme.colorScheme.primary }
    Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(32.dp), tint = tint)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(a.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted("$size    $date") }
            IconButton(onClick = onOpen) { Icon(Icons.Rounded.OpenInNew, "Open ${a.name}", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun TweetComposer(name: String, onTweet: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    Surface(shape = MaterialTheme.shapes.small, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline), color = MaterialTheme.colorScheme.surface) { Column(Modifier.padding(14.dp)) {
        Row(verticalAlignment = Alignment.Top) { Avatar(initials(name), size = 32)
            BasicTextField(text, { if (it.length <= 280) text = it }, Modifier.weight(1f).padding(start = 10.dp, top = 6.dp).heightIn(min = 48.dp), textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { inner -> Box { if (text.isEmpty()) Muted("What's happening?"); inner() } }) }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End) {
            Muted("${280 - text.length} characters remaining", Modifier.padding(end = 12.dp))
            Button({ onTweet(text.trim()); text = "" }, enabled = text.isNotBlank(), shape = CircleShape, contentPadding = PaddingValues(horizontal = 18.dp)) { Text("Post") }
        }
    } }
}

/** Full-screen composer: text, an optional photo or document, Post. */
@Composable
fun CreatePostScreen(vm: BucksViewModel, onClose: () -> Unit) {
    val ctx = LocalContext.current
    var text by remember { mutableStateOf("") }; var image by remember { mutableStateOf<String?>(null) }; var file by remember { mutableStateOf<Attachment?>(null) }
    fun keep(u: Uri) = runCatching { ctx.contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { u -> u?.let { keep(it); image = it.toString() } }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { u -> u?.let { keep(it); val n = runCatching { ctx.contentResolver.query(it, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } }.getOrNull() ?: "Document"; file = Attachment(it.toString(), n, false) } }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, "Close") }
            Text("Create a post", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f).padding(start = 8.dp))
            Button({ vm.addPost(text.trim(), image, file); onClose() }, enabled = text.isNotBlank() || image != null || file != null, shape = CircleShape) { Text("Post") }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Gutter)) {
            BasicTextField(text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 120.dp).focusRequester(focus), textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { inner -> Box { if (text.isEmpty()) Text("Share what's on your mind", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant); inner() } })
            image?.let { Box(Modifier.padding(top = 12.dp)) { AsyncImage(it, null, Modifier.fillMaxWidth().heightIn(max = 280.dp).clip(MaterialTheme.shapes.medium), contentScale = ContentScale.Crop)
                IconButton({ image = null }, Modifier.align(Alignment.TopEnd)) { Icon(Icons.Rounded.Cancel, "Remove photo", tint = Color.White) } } }
            file?.let { f -> Row(Modifier.padding(top = 12.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Description, null, tint = MaterialTheme.colorScheme.primary); Text(f.name, Modifier.weight(1f).padding(horizontal = 10.dp), maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Rounded.Close, "Remove file", Modifier.clickable { file = null }) } }
        }
        Row(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            IconButton({ pickImage.launch(arrayOf("image/*")) }) { Icon(Icons.Rounded.Image, "Add photo", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            IconButton({ text += if (text.isEmpty() || text.endsWith(" ")) "@" else " @" }) { Icon(Icons.Rounded.PersonAddAlt, "Tag someone", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            IconButton({ pickFile.launch(arrayOf("application/pdf", "application/zip", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "text/plain")) }) { Icon(Icons.Rounded.Add, "Attach a file", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
