package com.bucks.app.ui.screens.discover

import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.components.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.cancellation.CancellationException

/*
 * Showcase documents on a profile (docs/SHOWCASE_DOCS, migration showcase_docs.sql). Not the compliance documents Bucks staff check for
 * go-live. Visibility is decided by the server per document; the app only asks and shows what comes back. A document is "Checked by
 * Bucks" only when staff flagged it; viewer opinions are a separate, clearly labelled signal.
 */

/** The sentence we wrote on the server, or a generic one. */
private fun friendly(e: Throwable) = Regex("\"message\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(e.message ?: "")?.groupValues?.get(1)?.replace("\\\"", "\"")?.takeIf { it.isNotBlank() }
    ?: Str.get(R.string.g1_err_generic)

internal fun docKindIcon(kind: String): ImageVector = when (kind) { "LICENCE", "CERTIFICATE" -> Icons.Rounded.Shield; "AFFILIATION" -> Icons.Rounded.Public; else -> Icons.Rounded.Description }
internal fun docVisibilityLabel(v: String) = when (v) { "PUBLIC" -> Str.get(R.string.g1_doc_vis_public); "PRIVATE" -> Str.get(R.string.g1_doc_vis_team); else -> Str.get(R.string.g1_doc_vis_request) }

/** Opens the registry's own search in the browser. Nothing is copied or checked for the person. */
internal fun openOfficialSite(ctx: Context, vm: BucksViewModel, registry: String?) {
    val url = Registries.url(registry) ?: return
    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }.onFailure { vm.toast(Str.get(R.string.g1_doc_no_app)) }
}

/** The pills every document row shows: who can open it, whether it has lapsed, and whether Bucks checked it (never implied otherwise). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun DocPills(d: ShowcaseDoc, modifier: Modifier = Modifier, selfLabelled: Boolean = false) = FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
    PillGrey(docVisibilityLabel(d.visibility))
    if (selfLabelled) PillGrey(stringResource(R.string.g1_doc_self_labelled))
    if (d.expired) PillBad(stringResource(R.string.g1_doc_expired)) else d.expiresOn?.let { PillGrey(stringResource(R.string.g1_doc_valid_till, humanDate(it))) }
    if (d.bucksChecked) PillGood(stringResource(R.string.g1_doc_checked)) else PillGrey(stringResource(R.string.g1_doc_not_checked))
}

/** "3 of 4 viewers say it looks genuine", only once at least 3 viewers gave an opinion. */
internal fun docOpinionLine(d: ShowcaseDoc): String? = if (d.checks >= 3) Str.plural(R.plurals.g1_doc_opinions, d.checks, d.checksUp, d.checks) else null

/** A 48dp-high button with an optional icon. */
@Composable
internal fun DocButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, tonal: Boolean = false, enabled: Boolean = true, icon: ImageVector? = null) {
    val content: @Composable RowScope.() -> Unit = {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)) }
        Text(text, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (tonal) FilledTonalButton(onClick, modifier.heightIn(min = 48.dp), enabled = enabled, shape = MaterialTheme.shapes.small, content = content)
    else Button(onClick, modifier.heightIn(min = 48.dp), enabled = enabled, shape = MaterialTheme.shapes.small, content = content)
}

/** How many documents I can see on this profile (null while loading, or when they could not be loaded), for the header chip. */
@Composable
fun rememberShowcaseCount(listingId: String): State<Int?> = produceState<Int?>(null, listingId) {
    value = try { Backend.showcaseDocs(listingId).size } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
}

/**
 * The profile's Documents block (About tab). Hidden when there is nothing to show and I am not on the team. Locked documents show who issued
 * them and let me ask the owner; the file itself is only ever fetched through [ShowcaseDocViewer].
 */
@Composable
fun ShowcaseDocsSection(vm: BucksViewModel, listingId: String, mine: Boolean, onManage: () -> Unit, modifier: Modifier = Modifier) {
    val m = vm.myListings
    LaunchedEffect(mine) { if (mine && !m.loaded) m.refresh() }
    val team = mine && m.canManage(listingId)
    var docs by remember(listingId) { mutableStateOf<List<ShowcaseDoc>?>(null) }
    var failed by remember(listingId) { mutableStateOf(false) }
    var reload by remember(listingId) { mutableIntStateOf(0) }
    var viewing by remember(listingId) { mutableStateOf<ShowcaseDoc?>(null) }
    var requesting by remember(listingId) { mutableStateOf<ShowcaseDoc?>(null) }
    LaunchedEffect(listingId, reload) {
        try { docs = Backend.showcaseDocs(listingId); failed = false } catch (e: CancellationException) { throw e } catch (e: Exception) { failed = true }
    }
    val list = docs
    if (list == null) {
        // Nothing while loading for a visitor (most profiles have no documents, so no flash); the team always sees the block.
        if (team && !failed) Column(modifier.fillMaxWidth().padding(horizontal = Gutter).padding(top = 8.dp)) { SkeletonBox(Modifier.width(120.dp).height(18.dp)); Spacer(Modifier.height(10.dp)); SkeletonBox(Modifier.fillMaxWidth().height(96.dp)) }
        else if (failed) Row(modifier.fillMaxWidth().padding(horizontal = Gutter), verticalAlignment = Alignment.CenterVertically) {
            Muted(stringResource(R.string.g1_doc_load_failed), Modifier.weight(1f)); TextButton({ failed = false; reload++ }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.g1_action_try_again)) } }
        return
    }
    if (list.isEmpty() && !team) return

    Column(modifier.fillMaxWidth().padding(horizontal = Gutter).padding(top = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.g1_doc_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (list.isNotEmpty()) Muted("${list.size}")
        }
        Muted(if (team) stringResource(R.string.g1_doc_note_team) else stringResource(R.string.g1_doc_note_visitor), Modifier.padding(top = 2.dp))
        if (list.isEmpty()) Muted(stringResource(R.string.g1_doc_empty), Modifier.padding(top = 10.dp))
        list.forEach { d -> ShowcaseDocCard(vm, d, Modifier.padding(top = 10.dp), onOpen = { viewing = d }, onRequest = { requesting = d }) }
        if (team) DocButton(stringResource(R.string.g1_doc_manage), onManage, Modifier.padding(top = 12.dp), tonal = true, icon = Icons.Rounded.Edit)
    }
    viewing?.let { d -> ShowcaseDocViewer(vm, d, team, onClose = { viewing = null }, onChanged = { reload++ }) }
    requesting?.let { d -> RequestAccessSheet(vm, d, onDone = { requesting = null; reload++ }, onDismiss = { requesting = null }) }
}

@Composable
private fun ShowcaseDocCard(vm: BucksViewModel, d: ShowcaseDoc, modifier: Modifier, onOpen: () -> Unit, onRequest: () -> Unit) = BucksCard(modifier, padding = 14) {
    val ctx = LocalContext.current
    Row(verticalAlignment = Alignment.Top) {
        Avatar(icon = docKindIcon(d.kind), size = 40)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(d.title, style = MaterialTheme.typography.titleSmall)
            Muted(listOfNotNull(ShowcaseKinds.label(d.kind), d.issuer.ifBlank { null }).joinToString(" · "))
        }
        if (!d.canOpen) Icon(Icons.Rounded.Lock, stringResource(R.string.g1_cd_locked), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    DocPills(d, Modifier.padding(top = 10.dp))
    if (d.number.isNotBlank()) Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.g1_doc_number, d.number), style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f, fill = false))
        if (Registries.url(d.registry) != null) TextButton({ openOfficialSite(ctx, vm, d.registry) }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.g1_doc_official_site)) }
    }
    docOpinionLine(d)?.let { Muted(it, Modifier.padding(top = 4.dp)) }
    Box(Modifier.padding(top = 8.dp)) {
        when {
            d.canOpen -> DocButton(stringResource(R.string.g1_doc_open), onOpen, icon = Icons.Rounded.Visibility)
            d.myRequest == "PENDING" -> DocButton(stringResource(R.string.g1_doc_requested), {}, tonal = true, enabled = false)
            d.myRequest == "DECLINED" -> DocButton(stringResource(R.string.g1_doc_declined), {}, tonal = true, enabled = false)
            d.visibility == "ON_REQUEST" -> DocButton(stringResource(R.string.g1_doc_request), onRequest, tonal = true, icon = Icons.Rounded.Lock)
            else -> Muted(stringResource(R.string.g1_doc_unavailable))
        }
    }
}

/** Ask the owner to share a locked document. The owner sees my name, whether I ordered or follow the page, and this message. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RequestAccessSheet(vm: BucksViewModel, d: ShowcaseDoc, onDone: () -> Unit, onDismiss: () -> Unit) {
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(Modifier.padding(Gutter).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
            Text(stringResource(R.string.g1_doc_ask_title, d.title), style = MaterialTheme.typography.titleLarge)
            Muted(stringResource(R.string.g1_doc_ask_body), Modifier.padding(top = 4.dp))
            OutlinedTextField(message, { message = it.take(200) }, Modifier.padding(top = 12.dp).fillMaxWidth(), placeholder = { Text(stringResource(R.string.g1_doc_ask_hint)) }, minLines = 2, maxLines = 4, supportingText = { Text("${message.length}/200") })
            DocButton(if (busy) stringResource(R.string.g1_doc_sending) else stringResource(R.string.g1_doc_request), {
                scope.launch {
                    busy = true
                    try {
                        val status = Backend.requestDocAccess(d.id, message.trim())
                        vm.toast(if (status == "APPROVED") Str.get(R.string.g1_doc_already_open) else Str.get(R.string.g1_doc_request_sent))
                        onDone()
                    } catch (e: CancellationException) { throw e } catch (e: Exception) { vm.toast(friendly(e)) }
                    busy = false
                }
            }, Modifier.padding(top = 8.dp).fillMaxWidth(), enabled = !busy)
        }
    }
}

/**
 * Full-screen reader for one document. The window is secure (no screenshots or screen recording), the file is fetched with my own sign-in
 * each time, and a faint watermark with my name and today's date lies over it. Viewers can give an opinion once it is open; the team cannot.
 */
@Composable
fun ShowcaseDocViewer(vm: BucksViewModel, doc: ShowcaseDoc, mine: Boolean, onClose: () -> Unit, onChanged: () -> Unit) {
    val ctx = LocalContext.current
    var pages by remember(doc.id) { mutableStateOf<List<Bitmap>?>(null) }
    var error by remember(doc.id) { mutableStateOf<String?>(null) }
    var opened by remember(doc.id) { mutableStateOf(false) }
    var attempt by remember(doc.id) { mutableIntStateOf(0) }
    // open_showcase_doc counts a view each call, so a retry reuses the first answer instead of logging another look.
    var granted by remember(doc.id) { mutableStateOf<Pair<String, String>?>(null) }
    LaunchedEffect(doc.id, attempt) {
        error = null; pages = null
        try {
            val (path, mime) = granted ?: Backend.openShowcaseDoc(doc.id).let { it.path to it.mime }.also { granted = it }
            val bytes = Backend.downloadShowcaseFile(path)
            val asPdf = mime.ifBlank { doc.mime } == "application/pdf"
            val out = withContext(Dispatchers.IO) { if (asPdf) renderPdf(ctx.cacheDir, bytes) else listOfNotNull(decodeImage(bytes)) }
            if (out.isEmpty()) error = Str.get(R.string.g1_doc_damaged) else { pages = out; opened = true }
        } catch (e: CancellationException) { throw e } catch (e: Throwable) { error = if (e is Exception) friendly(e) else Str.get(R.string.g1_doc_too_large) }
    }
    val whoName = vm.social.me?.name?.ifBlank { null } ?: stringResource(R.string.g1_doc_member)
    val who = vm.social.me?.id?.takeLast(4)?.let { stringResource(R.string.g1_doc_who_id, whoName, it) } ?: whoName
    val mark = stringResource(R.string.g1_doc_watermark, who, java.time.LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy", java.util.Locale.ENGLISH)))
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, securePolicy = SecureFlagPolicy.SecureOn)) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = Gutter, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(doc.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Muted(listOfNotNull(ShowcaseKinds.label(doc.kind), doc.issuer.ifBlank { null }).joinToString(" · "), maxLines = 1)
                }
                IconButton(onClose) { Icon(Icons.Rounded.Close, stringResource(R.string.g1_cd_close)) }
            }
            Box(Modifier.weight(1f).fillMaxWidth().background(Color(0xFF1B1B1B)), contentAlignment = Alignment.Center) {
                val list = pages; val err = error
                when {
                    err != null -> Column(Modifier.padding(Gutter), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(err, color = Color.White, textAlign = TextAlign.Center)
                        DocButton(stringResource(R.string.g1_action_try_again), { attempt++ }, Modifier.padding(top = 12.dp), tonal = true)
                    }
                    list == null -> BucksLoader(color = Color.White, label = stringResource(R.string.g1_cd_opening))
                    doc.isPdf -> {
                        val imgs = remember(list) { list.map { it.asImageBitmap() } }
                        LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(imgs.size) { i -> Image(imgs[i], stringResource(R.string.g1_cd_page_of, i + 1, imgs.size), Modifier.fillMaxWidth().background(Color.White), contentScale = ContentScale.FillWidth) }
                        }
                    }
                    else -> {
                        val img = remember(list) { list[0].asImageBitmap() }
                        var scale by remember { mutableFloatStateOf(1f) }; var dx by remember { mutableFloatStateOf(0f) }; var dy by remember { mutableFloatStateOf(0f) }
                        Image(img, doc.title, Modifier.fillMaxSize()
                            .pointerInput(Unit) { detectTapGestures(onDoubleTap = { scale = 1f; dx = 0f; dy = 0f }) }
                            .pointerInput(Unit) { detectTransformGestures { _, pan, zoom, _ -> scale = (scale * zoom).coerceIn(1f, 5f); if (scale > 1f) { dx += pan.x; dy += pan.y } else { dx = 0f; dy = 0f } } }
                            .graphicsLayer { scaleX = scale; scaleY = scale; translationX = dx; translationY = dy }, contentScale = ContentScale.Fit)
                    }
                }
                if (list != null && err == null) Watermark(mark, Modifier.fillMaxSize())
            }
            if (!mine && opened) OpinionBar(vm, doc, onChanged)
            else Spacer(Modifier.navigationBarsPadding())
        }
    }
}

/** Faint diagonal repeating text over the whole document; it does not take touches. */
@Composable
private fun Watermark(text: String, modifier: Modifier = Modifier) = Canvas(modifier) {
    val dark = android.graphics.Paint().apply { isAntiAlias = true; textSize = 15.sp.toPx(); color = android.graphics.Color.BLACK; alpha = 38 }
    val light = android.graphics.Paint(dark).apply { color = android.graphics.Color.WHITE; alpha = 38 }
    val tw = dark.measureText(text); val gapX = 60.dp.toPx(); val stepY = 110.dp.toPx()
    drawIntoCanvas { c ->
        val n = c.nativeCanvas
        n.save(); n.rotate(-28f, size.width / 2f, size.height / 2f)
        var row = 0; var y = -size.height
        while (y < size.height * 2f) {
            var x = -size.width + (if (row % 2 == 0) 0f else (tw + gapX) / 2f)
            while (x < size.width * 2f) { n.drawText(text, x, y, light); n.drawText(text, x + 1.5f, y + 1.5f, dark); x += tw + gapX }
            y += stepY; row++
        }
        n.restore()
    }
}

/** "Looks genuine" / "Doesn't look right", with an optional comment; a viewer signal, never a Bucks check. I can change or remove mine. */
@Composable
private fun OpinionBar(vm: BucksViewModel, doc: ShowcaseDoc, onChanged: () -> Unit) {
    val scope = rememberCoroutineScope()
    var saved by remember(doc.id) { mutableStateOf(doc.myCheck) }
    var picked by remember(doc.id) { mutableStateOf<Int?>(null) }
    var comment by remember(doc.id) { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val sel = picked ?: saved
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).navigationBarsPadding().imePadding().padding(horizontal = Gutter, vertical = 10.dp)) {
        Muted(stringResource(R.string.g1_doc_opinion_note))
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DocButton(stringResource(R.string.g1_doc_genuine), { picked = 1 }, Modifier.weight(1f), tonal = sel != 1, enabled = !busy)
            DocButton(stringResource(R.string.g1_doc_not_right), { picked = -1 }, Modifier.weight(1f), tonal = sel != -1, enabled = !busy)
        }
        val v = picked
        if (v != null) {
            OutlinedTextField(comment, { comment = it.take(300) }, Modifier.padding(top = 8.dp).fillMaxWidth(), placeholder = { Text(stringResource(R.string.g1_doc_comment_hint)) }, minLines = 2, maxLines = 4, supportingText = { Text("${comment.length}/300") })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                DocButton(if (busy) stringResource(R.string.g1_doc_saving) else stringResource(R.string.g1_doc_save_opinion), {
                    scope.launch {
                        busy = true
                        try { Backend.checkShowcaseDoc(doc.id, v, comment.trim()); saved = v; picked = null; comment = ""; vm.toast(Str.get(R.string.g1_doc_opinion_saved)); onChanged() }
                        catch (e: CancellationException) { throw e } catch (e: Exception) { vm.toast(friendly(e)) }
                        busy = false
                    }
                }, enabled = !busy)
                TextButton({ picked = null }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(stringResource(R.string.g1_action_cancel)) }
            }
        } else if (saved != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Muted(if (saved == 1) stringResource(R.string.g1_doc_my_genuine) else stringResource(R.string.g1_doc_my_not_right), Modifier.weight(1f))
                TextButton({
                    scope.launch {
                        busy = true
                        try { Backend.clearShowcaseCheck(doc.id); saved = null; vm.toast(Str.get(R.string.g1_doc_opinion_removed)); onChanged() }
                        catch (e: CancellationException) { throw e } catch (e: Exception) { vm.toast(friendly(e)) }
                        busy = false
                    }
                }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text(stringResource(R.string.g1_doc_remove_mine), color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

/** Decodes a photo, halving it until neither side is over 2400 px so a big scan cannot exhaust memory. Null when it is not an image. */
private fun decodeImage(bytes: ByteArray): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    var sample = 1
    while (bounds.outWidth / sample > 2400 || bounds.outHeight / sample > 2400) sample *= 2
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
}

/** Renders up to 20 pages, about 1080 px wide, from a PDF written to a throwaway cache file (deleted right after). Call off the main thread. */
private fun renderPdf(dir: File, bytes: ByteArray): List<Bitmap> {
    val file = File.createTempFile("showcase", ".pdf", dir)
    val out = ArrayList<Bitmap>()
    try {
        file.writeBytes(bytes)
        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        try {
            val renderer = PdfRenderer(fd)
            try {
                for (i in 0 until minOf(renderer.pageCount, 20)) {
                    val page = renderer.openPage(i)
                    try {
                        val w = 1080; val h = (w.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(android.graphics.Color.WHITE)
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        out.add(bmp)
                    } finally { page.close() }
                }
            } finally { renderer.close() }
        } finally { fd.close() }
    } finally { file.delete() }
    return out
}
