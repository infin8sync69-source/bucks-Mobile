package com.bucks.app.ui.components

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Motion system. Every animation here answers a question for the user: did my tap register, is
 * something happening, what just changed. Loops switch off when the phone's "Remove animations"
 * setting is on; one-shot animations finish instantly.
 */
object Motion {
    const val SHORT = 150; const val MEDIUM = 280; const val LONG = 450
    /** Material 3 "emphasized" curve: quick start, gentle landing. */
    val Emphasized = CubicBezierEasing(0.2f, 0f, 0f, 1f)
}

/** True when the user turned animations off in Accessibility or Developer options. */
@Composable
fun rememberReducedMotion(): Boolean {
    val ctx = LocalContext.current
    return remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f } || com.bucks.app.data.Prefs.reduceMotion
}

/** Shrinks slightly while pressed and springs back: a tap feels physical. */
@Composable
fun Modifier.pressScale(source: InteractionSource, pressed: Float = 0.96f): Modifier {
    val isPressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) pressed else 1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium), label = "press")
    return graphicsLayer { scaleX = scale; scaleY = scale }
}

/** Fades and rises into place, [index] steps after its siblings, so a grid or list assembles in reading order. */
@Composable
fun Modifier.enterStagger(index: Int, step: Int = 40): Modifier {
    val reduced = rememberReducedMotion()
    val p = remember { Animatable(if (reduced) 1f else 0f) }
    LaunchedEffect(Unit) { if (!reduced) { delay(index * step.toLong()); p.animateTo(1f, tween(Motion.MEDIUM, easing = Motion.Emphasized)) } }
    return graphicsLayer { alpha = p.value; translationY = (1f - p.value) * 20.dp.toPx(); val sc = 0.94f + 0.06f * p.value; scaleX = sc; scaleY = sc }
}

/** Pops in with a small overshoot; used for things worth noticing (PIN digits, success marks). */
@Composable
fun Modifier.popIn(index: Int = 0, step: Int = 70): Modifier {
    val reduced = rememberReducedMotion()
    val p = remember { Animatable(if (reduced) 1f else 0f) }
    LaunchedEffect(Unit) { if (!reduced) { delay(index * step.toLong()); p.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMediumLow)) } }
    return graphicsLayer { scaleX = p.value; scaleY = p.value; alpha = p.value.coerceIn(0f, 1f) }
}

/** Shakes sideways each time [trigger] goes up: "no", without a dialog (wrong code, locked tile). */
@Composable
fun Modifier.shakeOn(trigger: Int): Modifier {
    val x = remember { Animatable(0f) }
    LaunchedEffect(trigger) { if (trigger > 0) for (v in listOf(10f, -8f, 6f, -4f, 2f, 0f)) x.animateTo(v, tween(50)) }
    return graphicsLayer { translationX = x.value * density }
}

/** A quick pop each time [count] goes up (a new message, notification or cart piece); nothing when it goes down. */
@Composable
fun Modifier.bumpOnIncrease(count: Int, amount: Float = 0.3f): Modifier {
    val reduced = rememberReducedMotion(); val s = remember { Animatable(1f) }; var last by remember { mutableIntStateOf(count) }
    LaunchedEffect(count) { if (count > last && !reduced) { s.snapTo(1f + amount); s.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium)) }; last = count }
    return graphicsLayer { scaleX = s.value; scaleY = s.value }
}

/** A short ring, like a bell, each time [count] goes up. Swings from the top. */
@Composable
fun Modifier.ringOnIncrease(count: Int): Modifier {
    val reduced = rememberReducedMotion(); val r = remember { Animatable(0f) }; var last by remember { mutableIntStateOf(count) }
    LaunchedEffect(count) { if (count > last && !reduced) for (a in listOf(14f, -11f, 7f, -4f, 0f)) r.animateTo(a, tween(70)); last = count }
    return graphicsLayer { rotationZ = r.value; transformOrigin = TransformOrigin(0.5f, 0.1f) }
}

/** A small hop in the arrow's direction ([dir] -1 down, 1 up) when it becomes [active]: the vote registered. */
@Composable
fun Modifier.nudgeWhen(active: Boolean, dir: Int): Modifier {
    val reduced = rememberReducedMotion(); val y = remember { Animatable(0f) }; var was by remember { mutableIntStateOf(if (active) 1 else 0) }
    LaunchedEffect(active) { if (active && was == 0 && !reduced) { y.animateTo(-4f * dir, tween(Motion.SHORT / 2)); y.animateTo(0f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium)) }; was = if (active) 1 else 0 }
    return graphicsLayer { translationY = y.value * density }
}

/** Gentle scale loop that draws the eye to the one action that matters (accept a ride, you're online). */
@Composable
fun Modifier.breathe(enabled: Boolean = true, amount: Float = 0.04f, periodMs: Int = 900): Modifier {
    val reduced = rememberReducedMotion()
    val t = rememberInfiniteTransition(label = "breathe")
    val s by t.animateFloat(1f, 1f + amount, infiniteRepeatable(tween(periodMs, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "breatheScale")
    return if (!enabled || reduced) this else graphicsLayer { scaleX = s; scaleY = s }
}

/** Radar rings expanding from the centre: "we're ringing drivers near you". */
@Composable
fun PulseRings(modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.primary, rings: Int = 3, periodMs: Int = 2000, content: @Composable BoxScope.() -> Unit = {}) {
    val reduced = rememberReducedMotion()
    val t = rememberInfiniteTransition(label = "pulse")
    val phase by t.animateFloat(0f, 1f, infiniteRepeatable(tween(periodMs, easing = LinearEasing)), label = "pulsePhase")
    Box(modifier.drawBehind {
        if (!reduced) for (i in 0 until rings) { val p = (phase + i.toFloat() / rings) % 1f
            drawCircle(color, radius = size.minDimension / 2f * (0.3f + 0.7f * p), alpha = (1f - p) * 0.35f) }
    }, contentAlignment = Alignment.Center, content = content)
}

/** Counts up to [target] instead of jumping (fares, earnings). */
@Composable
fun animatedInt(target: Int): Int { val v by animateIntAsState(target, tween(Motion.LONG * 2, easing = Motion.Emphasized), label = "count"); return v }
