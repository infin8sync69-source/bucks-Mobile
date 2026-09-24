package com.bucks.app.ui.components

import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.drawable.GradientDrawable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.bucks.app.data.Geo
import com.bucks.app.data.LatLng
import com.bucks.app.ui.theme.Brand
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.util.BoundingBox
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.io.File

/** OpenStreetMap tiles (no API key), desaturated and lifted towards the muted grey basemap of the design; inverted in dark theme. */
private fun mutedTiles(dark: Boolean): ColorMatrixColorFilter {
    val m = ColorMatrix().apply { setSaturation(0.15f) }
    val tone = if (dark) floatArrayOf(-0.85f, 0f, 0f, 0f, 235f, 0f, -0.85f, 0f, 0f, 235f, 0f, 0f, -0.85f, 0f, 240f, 0f, 0f, 0f, 1f, 0f)
               else floatArrayOf(0.9f, 0f, 0f, 0f, 22f, 0f, 0.9f, 0f, 0f, 22f, 0f, 0f, 0.9f, 0f, 26f, 0f, 0f, 0f, 1f, 0f)
    m.postConcat(ColorMatrix(tone)); return ColorMatrixColorFilter(m)
}

/** Real street map. Pins keep the app's 0–100 percent coordinates and are projected through [Geo.fromPercent]. */
@Composable
fun BucksMap(modifier: Modifier = Modifier, pins: List<MapPin>, zoom: Double = 13.0, route: List<LatLng> = emptyList(), circle: Pair<LatLng, Double>? = null, onCenter: ((LatLng) -> Unit)? = null) {
    val brand = Brand.toArgb()
    val ctx = LocalContext.current; val density = LocalDensity.current.density
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val map = remember {
        Configuration.getInstance().apply { userAgentValue = ctx.packageName; osmdroidBasePath = File(ctx.cacheDir, "osmdroid"); osmdroidTileCache = File(osmdroidBasePath, "tiles") }
        MapView(ctx).apply { setTileSource(TileSourceFactory.MAPNIK); setMultiTouchControls(true); isTilesScaledToDpi = true; zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER); minZoomLevel = 10.0; maxZoomLevel = 18.0; controller.setZoom(zoom) }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, e -> when (e) { Lifecycle.Event.ON_RESUME -> map.onResume(); Lifecycle.Event.ON_PAUSE -> map.onPause(); else -> {} } }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer); map.onDetach() }
    }
    val me = pins.firstOrNull { it.big }?.let { it.at ?: Geo.fromPercent(it.x, it.y) }
    // With a route, frame the whole trip; otherwise centre on the user.
    val target = route.lastOrNull()
    LaunchedEffect(me.takeIf { route.size < 2 }, target) {
        if (route.size >= 2) map.post { runCatching { map.zoomToBoundingBox(BoundingBox.fromGeoPoints(route.map { GeoPoint(it.lat, it.lng) }).increaseByScale(1.6f), false); if (map.zoomLevelDouble > 16.0) map.controller.setZoom(16.0) } }
        else (me ?: Geo.CENTER).let { map.controller.setCenter(GeoPoint(it.lat, it.lng)) } }
    DisposableEffect(onCenter) {
        val l = onCenter?.let { cb -> object : MapListener { override fun onScroll(e: ScrollEvent?) = true.also { map.mapCenter.let { c -> cb(LatLng(c.latitude, c.longitude)) } }; override fun onZoom(e: ZoomEvent?) = false } }
        l?.let { map.addMapListener(it); map.mapCenter.let { c -> onCenter(LatLng(c.latitude, c.longitude)) } }
        onDispose { l?.let { map.removeMapListener(it) } } }
    AndroidView(factory = { map }, modifier = modifier.clipToBounds(), update = { mv ->
        mv.overlayManager.tilesOverlay.setColorFilter(mutedTiles(dark))
        mv.overlays.clear()
        circle?.let { (c, m) -> mv.overlays.add(Polygon(mv).apply { points = Polygon.pointsAsCircle(GeoPoint(c.lat, c.lng), m); fillPaint.color = (brand and 0x00FFFFFF) or 0x33000000; outlinePaint.color = (brand and 0x00FFFFFF) or 0x66000000; outlinePaint.strokeWidth = 2 * density; setOnClickListener { _, _, _ -> false } }) }
        if (route.size >= 2) mv.overlays.add(Polyline(mv).apply { setPoints(route.map { GeoPoint(it.lat, it.lng) }); outlinePaint.color = brand; outlinePaint.strokeWidth = 5 * density; outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND; setOnClickListener { _, _, _ -> false } })
        pins.sortedBy { it.big }.forEach { p ->
            val at = p.at ?: Geo.fromPercent(p.x, p.y); val px = ((if (p.big) 18 else 12) * density).toInt()
            mv.overlays.add(Marker(mv).apply {
                position = GeoPoint(at.lat, at.lng); title = p.label; setInfoWindow(null); setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                icon = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(p.color.toArgb()); setStroke((2.5f * density).toInt(), android.graphics.Color.WHITE); setSize(px, px) }
            })
        }
        mv.invalidate()
    })
}

/** Tile attribution required by OpenStreetMap. */
@Composable
fun MapAttribution(modifier: Modifier = Modifier) = Text("© OpenStreetMap contributors", modifier, fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
