package com.bucks.app.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.Picked
import com.bucks.app.data.ProfileMedia
import com.bucks.app.data.Upload
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.MediaViewer
import com.bucks.app.ui.ViewerMedia
import com.bucks.app.ui.components.*
import com.bucks.app.ui.rememberCamera
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The top of every profile, a person's or a page's: the cover photo across the top (a gradient until one is set) and the round
 * profile picture overlapping its bottom edge. Tapping either opens it full screen. When [editable], a camera button on each
 * offers: choose from the gallery, take a photo, view, remove. [onPick] gets the photo already turned upright and resized.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileMediaHeader(
    vm: BucksViewModel, name: String, photoUrl: String?, coverUrl: String?,
    editable: Boolean = false, busy: ProfileMedia.Slot? = null,
    onPick: (ProfileMedia.Slot, Picked) -> Unit = { _, _ -> }, onRemove: (ProfileMedia.Slot) -> Unit = {},
    fallbackIcon: ImageVector? = null, coverHeight: Dp = 150.dp, avatarSize: Dp = 96.dp,
    topStart: @Composable () -> Unit = {}, topEnd: @Composable () -> Unit = {},
) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var viewing by remember { mutableStateOf<ProfileMedia.Slot?>(null) }
    var menu by remember { mutableStateOf<ProfileMedia.Slot?>(null) }
    var picking by remember { mutableStateOf(ProfileMedia.Slot.PHOTO) }
    fun accept(uri: Uri) {
        val slot = picking
        scope.launch {
            // A cover is shown full width, a profile picture never larger than a phone's width.
            val picked = withContext(Dispatchers.IO) { Upload.read(ctx, uri, maxPx = if (slot == ProfileMedia.Slot.COVER) 1920 else 1080) }
            if (picked == null || !picked.isImage) vm.toast("Couldn't open that photo. Try another one.") else onPick(slot, picked)
        }
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let(::accept) }
    val camera = rememberCamera(onError = { vm.toast(it) }, onPhoto = { accept(it) }, onVideo = {})
    val urlOf = { s: ProfileMedia.Slot -> if (s == ProfileMedia.Slot.PHOTO) photoUrl else coverUrl }
    fun tap(s: ProfileMedia.Slot) { when { urlOf(s) != null -> viewing = s; editable -> menu = s } }

    Box(Modifier.fillMaxWidth().height(coverHeight + avatarSize / 2)) {
        // Cover
        Box(Modifier.fillMaxWidth().height(coverHeight).background(Brush.linearGradient(listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimaryContainer)))
            .clickable(enabled = coverUrl != null || editable, role = Role.Image, onClickLabel = if (coverUrl != null) "View cover photo" else "Add a cover photo") { tap(ProfileMedia.Slot.COVER) }) {
            coverUrl?.let { AsyncImage(it, "Cover photo", Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            // Keeps the back and menu buttons readable over a bright photo.
            Box(Modifier.fillMaxWidth().height(72.dp).background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))))
            if (busy == ProfileMedia.Slot.COVER) CircularProgressIndicator(Modifier.align(Alignment.Center).size(32.dp), color = Color.White, strokeWidth = 3.dp)
            if (editable) EditBadge("Change cover photo", Modifier.align(Alignment.BottomEnd).padding(10.dp)) { menu = ProfileMedia.Slot.COVER }
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(4.dp)) { topStart(); Spacer(Modifier.weight(1f)); topEnd() }
        // Profile picture
        Box(Modifier.padding(start = Gutter).align(Alignment.BottomStart)) {
            Box(Modifier.size(avatarSize).clip(CircleShape).background(MaterialTheme.colorScheme.background).padding(4.dp).clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer)
                .clickable(enabled = photoUrl != null || editable, role = Role.Image, onClickLabel = if (photoUrl != null) "View profile picture" else "Add a profile picture") { tap(ProfileMedia.Slot.PHOTO) },
                contentAlignment = Alignment.Center) {
                if (fallbackIcon != null) Icon(fallbackIcon, null, Modifier.size(avatarSize * 0.45f), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                else Text(initials(name.ifBlank { "?" }), style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                photoUrl?.let { AsyncImage(it, "Profile picture", Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                if (busy == ProfileMedia.Slot.PHOTO) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(28.dp), color = Color.White, strokeWidth = 3.dp) }
            }
            if (editable) EditBadge("Change profile picture", Modifier.align(Alignment.BottomEnd)) { menu = ProfileMedia.Slot.PHOTO }
        }
    }

    menu?.let { slot ->
        val what = if (slot == ProfileMedia.Slot.PHOTO) "profile picture" else "cover photo"
        val has = urlOf(slot) != null
        ModalBottomSheet(onDismissRequest = { menu = null }) {
            Column(Modifier.padding(bottom = 24.dp)) {
                Text(what.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
                SheetAction(Icons.Rounded.PhotoLibrary, "Choose from gallery") { menu = null; picking = slot; gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                SheetAction(Icons.Rounded.PhotoCamera, "Take a photo") { menu = null; picking = slot; camera.takePhoto() }
                if (has) SheetAction(Icons.Rounded.Fullscreen, "View $what") { menu = null; viewing = slot }
                if (has) SheetAction(Icons.Rounded.Delete, "Remove $what", danger = true) { menu = null; onRemove(slot) }
            }
        }
    }
    viewing?.let(urlOf)?.let { url -> MediaViewer(vm, listOf(ViewerMedia.Url(url)), title = name.ifBlank { null }) { viewing = null } }
}

@Composable
private fun EditBadge(label: String, modifier: Modifier, onClick: () -> Unit) =
    Box(modifier.size(36.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface).border(2.dp, MaterialTheme.colorScheme.background, CircleShape)
        .clickable(onClickLabel = label, role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(Icons.Rounded.CameraAlt, label, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurface)
    }

@Composable
private fun SheetAction(icon: ImageVector, text: String, danger: Boolean = false, onClick: () -> Unit) {
    val c = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 24.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = c); Text(text, color = c, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 16.dp))
    }
}
