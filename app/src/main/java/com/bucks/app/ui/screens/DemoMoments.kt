package com.bucks.app.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.bucks.app.data.TrayRow
import com.bucks.app.ui.components.*

/*
 * Moments in the demo build (no backend): the same row of circles the online feed shows at the top, fed by a few sample
 * neighbours and shops, a full-screen viewer and a text composer. Everything stays on the phone and is gone after a restart;
 * the online build stores real Moments for 24 hours (supabase schema: moments, moments_tray, moments_of).
 */

data class DemoSlide(val text: String, val colors: List<Color>, val minutesAgo: Int)
data class DemoAuthor(val id: String, val name: String, val listing: String? = null, val slides: List<DemoSlide>)

private val Grape = listOf(Color(0xFF811FF0), Color(0xFF4A0AA6))
private val Sunset = listOf(Color(0xFFFF7A59), Color(0xFFE0245E))
private val Leaf = listOf(Color(0xFF1FA463), Color(0xFF0B6B3A))
private val Ocean = listOf(Color(0xFF1E88E5), Color(0xFF3949AB))
private val Night = listOf(Color(0xFF2B2440), Color(0xFF15111C))
val MOMENT_COLORS = listOf(Grape, Sunset, Leaf, Ocean, Night)

/** Sample Moments and what I've seen; mine are the ones I add. */
class DemoMoments {
    val authors: SnapshotStateList<DemoAuthor> = mutableStateListOf(
        DemoAuthor("d-lakshmi", "Lakshmi", "Lakshmi Stores", listOf(
            DemoSlide("Fresh Nandini milk and curd just arrived 🥛", Leaf, 25),
            DemoSlide("Sona masoori rice back in stock: ₹62 a kg", Grape, 20))),
        DemoAuthor("d-asha", "Asha", "Asha Biryani House", listOf(
            DemoSlide("Sunday special: mutton dum biryani 🍛\nOrders open till 2 pm", Sunset, 90))),
        DemoAuthor("d-ravi", "Ravi Kumar", null, listOf(
            DemoSlide("Anyone know a good plumber near 4th Block? Kitchen tap leaking", Ocean, 140),
            DemoSlide("Sorted! Manju fixed it in 20 minutes. Recommending him 👍", Leaf, 60))),
        DemoAuthor("d-priya", "Priya S", null, listOf(
            DemoSlide("Jayanagar 4th Block market is packed this evening, go early tomorrow", Night, 200))),
        DemoAuthor("d-suresh", "Suresh", "Suresh Auto", listOf(
            DemoSlide("Online near South End Circle till 10 pm 🛺", Grape, 35))),
    )
    val mine: SnapshotStateList<DemoSlide> = mutableStateListOf()
    val seen: SnapshotStateList<String> = mutableStateListOf()

    fun tray(myName: String): List<TrayRow> =
        (if (mine.isNotEmpty()) listOf(TrayRow("me", myName, "", null, mine.size, 0, "", isMe = true)) else emptyList()) +
            authors.map { a -> TrayRow(a.id, a.name, "", a.listing, a.slides.size, if (a.id in seen) 0 else a.slides.size, "", isMe = false) }
                .sortedByDescending { it.unseen > 0 }
    fun slidesOf(id: String): List<DemoSlide> = if (id == "me") mine else authors.firstOrNull { it.id == id }?.slides.orEmpty()
    fun nameOf(id: String, myName: String): String = if (id == "me") myName else authors.firstOrNull { it.id == id }?.let { it.listing ?: it.name } ?: ""
    fun add(text: String, colors: List<Color>) { mine.add(DemoSlide(text, colors, 0)) }
    /** Who to show after [id]: the next person with something unseen, in tray order. */
    fun nextAfter(id: String): String? { val order = authors.map { it.id }; return order.drop(order.indexOf(id) + 1).firstOrNull { it !in seen } }
}

/** Full-screen Moment: bars along the top fill as each slide plays (5 s), tap right for next, left for back, hold to pause. */
@Composable
fun DemoMomentViewer(m: DemoMoments, startId: String, myName: String, onReply: () -> Unit, onClose: () -> Unit) {
    var id by remember { mutableStateOf(startId) }
    val slides = m.slidesOf(id)
    var index by remember(id) { mutableIntStateOf(0) }
    val bar = remember(id, index) { Animatable(0f) }
    var paused by remember { mutableStateOf(false) }
    fun next() {
        if (index < slides.lastIndex) index++
        else { if (id != "me" && id !in m.seen) m.seen.add(id); val n = if (id == "me") null else m.nextAfter(id); if (n != null) id = n else onClose() }
    }
    LaunchedEffect(id, index, paused) {
        if (slides.isEmpty()) { onClose(); return@LaunchedEffect }
        if (!paused) { bar.animateTo(1f, tween(((1f - bar.value) * 5000).toInt(), easing = LinearEasing)); next() }
    }
    val s = slides.getOrNull(index) ?: return
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(s.colors))
            .pointerInput(id, index) { detectTapGestures(onPress = { paused = true; tryAwaitRelease(); paused = false },
                onTap = { o -> if (o.x < size.width / 3f) { if (index > 0) index-- } else next() }) }) {
            Column(Modifier.fillMaxWidth().systemBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    slides.indices.forEach { i ->
                        val f = when { i < index -> 1f; i == index -> bar.value; else -> 0f }
                        Box(Modifier.weight(1f).height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.35f))) {
                            Box(Modifier.fillMaxWidth(f).fillMaxHeight().background(Color.White)) }
                    }
                }
                Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
                        Text(initials(m.nameOf(id, myName)), color = Color.White, style = MaterialTheme.typography.labelLarge) }
                    Column(Modifier.padding(start = 10.dp).weight(1f)) {
                        Text(m.nameOf(id, myName), color = Color.White, style = MaterialTheme.typography.titleSmall)
                        Text(if (s.minutesAgo < 1) "Just now" else if (s.minutesAgo < 60) "${s.minutesAgo} min ago" else "${s.minutesAgo / 60} h ago", color = Color.White.copy(alpha = 0.75f), style = MaterialTheme.typography.labelSmall)
                    }
                    IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, "Close", tint = Color.White) }
                }
            }
            Text(s.text, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, lineHeight = 34.sp, textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 28.dp))
            if (id != "me") Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(16.dp).fillMaxWidth().height(48.dp).clip(CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.6f), CircleShape).clickable(onClick = onReply).padding(horizontal = 18.dp), contentAlignment = Alignment.CenterStart) {
                Text("Reply to ${m.nameOf(id, myName).substringBefore(' ')}…", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** Write a Moment: text on a colour, shared with neighbours for 24 hours. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DemoMomentComposer(onShare: (String, List<Color>) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }; var colors by remember { mutableStateOf(MOMENT_COLORS.first()) }
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
        Text("New moment", style = MaterialTheme.typography.titleLarge)
        Muted("Disappears after 24 hours.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        Box(Modifier.fillMaxWidth().height(180.dp).clip(MaterialTheme.shapes.medium).background(Brush.verticalGradient(colors)).padding(18.dp), contentAlignment = Alignment.Center) {
            Text(text.ifBlank { "What's happening nearby?" }, color = Color.White.copy(alpha = if (text.isBlank()) 0.6f else 1f), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        }
        Row(Modifier.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MOMENT_COLORS.forEach { c -> Box(Modifier.size(32.dp).clip(CircleShape).background(Brush.verticalGradient(c))
                .then(if (c == colors) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier).clickable { colors = c }) }
        }
        BucksField(text, { text = it.take(160) }, placeholder = "Fresh stock, a deal, a question for neighbours", singleLine = false, minLines = 2)
        PrimaryButton("Share for 24 hours", enabled = text.isNotBlank()) { onShare(text.trim(), colors) }
    } }
}
