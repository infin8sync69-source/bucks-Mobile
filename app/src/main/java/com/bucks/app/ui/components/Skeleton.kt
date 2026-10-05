package com.bucks.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage

/*
 * Skeleton loading: grey shapes with a soft moving highlight where content will appear, so a screen has its final shape at once
 * and nothing jumps when data or photos arrive. Used with small first payloads (slim catalogue, small photos) to keep slow
 * networks usable. Screen readers hear one "Loading" instead of a list of empty boxes.
 */

/** A soft highlight sweeping across the shape. */
fun Modifier.shimmer(): Modifier = composed {
    val base = MaterialTheme.colorScheme.surfaceContainer; val light = MaterialTheme.colorScheme.surfaceContainerHigh
    val t = rememberInfiniteTransition(label = "shimmer")
    val x by t.animateFloat(0f, 1f, infiniteRepeatable(tween(1300, easing = LinearEasing), RepeatMode.Restart), label = "shimmerX")
    background(Brush.linearGradient(listOf(base, light, base), start = Offset(x * 900f - 300f, 0f), end = Offset(x * 900f, 300f)))
}

@Composable
fun SkeletonBox(modifier: Modifier = Modifier, shape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(8.dp)) = Box(modifier.clip(shape).shimmer())

@Composable
fun SkeletonLines(lines: Int = 3, modifier: Modifier = Modifier) = Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
    repeat(lines) { i -> SkeletonBox(Modifier.fillMaxWidth(if (i == lines - 1) 0.6f else 1f).height(12.dp), RoundedCornerShape(6.dp)) }
}

/** A photo that shows a shimmering box while it downloads, then the picture; a plain box when it fails. */
@Composable
fun ShimmerImage(url: String?, description: String?, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop) {
    if (url == null) { Box(modifier.background(MaterialTheme.colorScheme.surfaceContainer)); return }
    SubcomposeAsyncImage(url, description, modifier, contentScale = contentScale,
        loading = { Box(Modifier.fillMaxSize().shimmer()) },
        error = { Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer)) })
}

/** Cards where the product grid will be. */
@Composable
fun ProductGridSkeleton(rows: Int = 3, modifier: Modifier = Modifier) = Column(modifier.semantics { contentDescription = "Loading products" }.clearAndSetSemantics { contentDescription = "Loading products" }) {
    repeat(rows) {
        Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(2) {
                Column(Modifier.weight(1f)) {
                    SkeletonBox(Modifier.fillMaxWidth().aspectRatio(1f), RoundedCornerShape(12.dp))
                    SkeletonBox(Modifier.padding(top = 8.dp).fillMaxWidth(0.9f).height(14.dp), RoundedCornerShape(6.dp))
                    SkeletonBox(Modifier.padding(top = 6.dp).fillMaxWidth(0.5f).height(14.dp), RoundedCornerShape(6.dp))
                    SkeletonBox(Modifier.padding(top = 8.dp).fillMaxWidth().height(40.dp), RoundedCornerShape(10.dp))
                }
            }
        }
    }
}

/** The whole store profile before it arrives: cover, name, stats, buttons, tabs and the first cards. */
@Composable
fun ProfileSkeleton(modifier: Modifier = Modifier) = Column(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "Loading" }) {
    SkeletonBox(Modifier.fillMaxWidth().height(140.dp), RoundedCornerShape(0.dp))
    Column(Modifier.padding(horizontal = Gutter)) {
        Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            SkeletonBox(Modifier.size(64.dp), CircleShape)
            Column(Modifier.padding(start = 12.dp).weight(1f)) { SkeletonBox(Modifier.fillMaxWidth(0.6f).height(20.dp), RoundedCornerShape(6.dp)); SkeletonBox(Modifier.padding(top = 8.dp).fillMaxWidth(0.4f).height(12.dp), RoundedCornerShape(6.dp)) }
        }
        Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { repeat(3) { SkeletonBox(Modifier.width(72.dp).height(34.dp), RoundedCornerShape(6.dp)) } }
        Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) { SkeletonBox(Modifier.weight(1f).height(44.dp), RoundedCornerShape(10.dp)); SkeletonBox(Modifier.weight(1f).height(44.dp), RoundedCornerShape(10.dp)); SkeletonBox(Modifier.size(44.dp), RoundedCornerShape(10.dp)) }
        Row(Modifier.padding(top = 18.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) { repeat(5) { SkeletonBox(Modifier.width(52.dp).height(16.dp), RoundedCornerShape(6.dp)) } }
        ProductGridSkeleton(rows = 2)
    }
}
