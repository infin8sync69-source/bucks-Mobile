package com.bucks.app.ui.components

import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.drawable.GradientDrawable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import com.bucks.app.R
import androidx.compose.ui.res.stringResource
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.MyLocation
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

/** What a map shows: its south, west, north and east edges. */
data class MapBounds(val s: Double, val w: Double, val n: Double, val e: Double)

/** Lets a screen move and zoom the map it shows (my-location button, zoom buttons, following a moving position) and read what it shows. */
class MapCommands {
    internal var view: MapView? = null
    fun zoomIn() { view?.controller?.zoomIn() }
    fun zoomOut() { view?.controller?.zoomOut() }
    fun moveTo(at: LatLng, zoom: Double? = null) { view?.let { v -> zoom?.let { v.controller.setZoom(it) }; v.controller.animateTo(GeoPoint(at.lat, at.lng)) } }
    /** The area on screen now; null before the map has been laid out. */
    fun bounds(): MapBounds? = view?.takeIf { it.width > 0 && it.height > 0 }?.boundingBox?.let { MapBounds(it.latSouth, it.lonWest, it.latNorth, it.lonEast) }
}

/** A pin's marker image, at least 48 dp square so a small dot is still easy to tap. A [badge] is a rounded label, otherwise a dot with a white ring. */
private fun pinIcon(ctx: android.content.Context, p: MapPin, density: Float, surface: Int, tappable: Boolean): android.graphics.drawable.Drawable {
    val fill = p.color.toArgb()
    if (p.badge == null && !tappable) {
        val px = ((if (p.big) 18 else 12) * density).toInt()
        return GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(fill); setStroke((2.5f * density).toInt(), android.graphics.Color.WHITE); setSize(px, px) }
    }
    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    val touch = 48 * density
    if (p.badge == null) {
        val r = (if (p.big) 9f else 6f) * density; val ring = 2.5f * density
        val bmp = android.graphics.Bitmap.createBitmap(touch.toInt(), touch.toInt(), android.graphics.Bitmap.Config.ARGB_8888)
        val c = android.graphics.Canvas(bmp); val mid = touch / 2
        paint.color = android.graphics.Color.WHITE; c.drawCircle(mid, mid, r + ring, paint)
        paint.color = fill; c.drawCircle(mid, mid, r, paint)
        return android.graphics.drawable.BitmapDrawable(ctx.resources, bmp)
    }
    paint.textSize = 13 * density; paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
    val h = 26 * density; val w = maxOf(paint.measureText(p.badge) + 18 * density, h)
    val bw = maxOf(w + 4 * density, touch); val bh = touch
    val bmp = android.graphics.Bitmap.createBitmap(bw.toInt(), bh.toInt(), android.graphics.Bitmap.Config.ARGB_8888)
    val c = android.graphics.Canvas(bmp)
    val rect = android.graphics.RectF((bw - w) / 2, (bh - h) / 2, (bw + w) / 2, (bh + h) / 2)
    paint.style = android.graphics.Paint.Style.FILL; paint.color = if (p.selected) fill else surface; c.drawRoundRect(rect, h / 2, h / 2, paint)
    paint.style = android.graphics.Paint.Style.STROKE; paint.strokeWidth = 2 * density; paint.color = fill; c.drawRoundRect(rect, h / 2, h / 2, paint)
    paint.style = android.graphics.Paint.Style.FILL; paint.color = if (p.selected) android.graphics.Color.WHITE else fill; paint.textAlign = android.graphics.Paint.Align.CENTER
    c.drawText(p.badge, rect.centerX(), rect.centerY() - (paint.descent() + paint.ascent()) / 2, paint)
    return android.graphics.drawable.BitmapDrawable(ctx.resources, bmp)
}

/**
 * Real street map. Pins keep the app's 0–100 percent coordinates and are projected through [Geo.fromPercent].
 * [recentre]: follow my pin (the big one) whenever it moves; false centres on it once, then the person owns the camera. Home passes
 *   "my position isn't known yet", so it follows the placeholder until the first real fix, centres there, and stops.
 * [onPinTap]: called for pins that have an id. [onMyLocation]: adds a "my location" button above the zoom buttons ([locating] shows it busy).
 */
@Composable
fun BucksMap(modifier: Modifier = Modifier, pins: List<MapPin>, zoom: Double = 13.0, route: List<LatLng> = emptyList(), circle: Pair<LatLng, Double>? = null, onCenter: ((LatLng) -> Unit)? = null,
    commands: MapCommands? = null, satellite: Boolean = false, onLongPress: ((LatLng) -> Unit)? = null, onUserMove: (() -> Unit)? = null, zoomButtons: Boolean = true,
    recentre: Boolean = true, onPinTap: ((MapPin) -> Unit)? = null, onMyLocation: (() -> Unit)? = null, locating: Boolean = false) {
    val brand = MaterialTheme.colorScheme.primary.toArgb(); val surface = MaterialTheme.colorScheme.surface.toArgb()
    val ctx = LocalContext.current; val density = LocalDensity.current.density
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val map = remember {
        Configuration.getInstance().apply { userAgentValue = ctx.packageName; osmdroidBasePath = File(ctx.cacheDir, "osmdroid"); osmdroidTileCache = File(osmdroidBasePath, "tiles") }
        MapView(ctx).apply { setTileSource(mapTiles(false)); setMultiTouchControls(true); isTilesScaledToDpi = true; zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER); minZoomLevel = 4.0; maxZoomLevel = 19.0; controller.setZoom(zoom) }
    }
    SideEffect { commands?.view = map }
    LaunchedEffect(satellite) { map.setTileSource(mapTiles(satellite)) }
    val moved = rememberUpdatedState(onUserMove); val tap = rememberUpdatedState(onPinTap); val press = rememberUpdatedState(onLongPress)
    DisposableEffect(map) { map.setOnTouchListener { _, e -> if (e.action == android.view.MotionEvent.ACTION_MOVE) moved.value?.invoke(); false }; onDispose { map.setOnTouchListener(null) } }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, e -> when (e) { Lifecycle.Event.ON_RESUME -> map.onResume(); Lifecycle.Event.ON_PAUSE -> map.onPause(); else -> {} } }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer); map.onDetach() }
    }
    val me = pins.firstOrNull { it.big }?.let { it.at ?: Geo.fromPercent(it.x, it.y) }
    // With a route, frame the whole trip; otherwise centre on the user (every time they move, or only the first time without [recentre]).
    val target = route.lastOrNull()
    var centred by remember { mutableStateOf(false) }
    LaunchedEffect(me.takeIf { route.size < 2 && (recentre || !centred) }, target) {
        if (route.size >= 2) map.post { runCatching { map.zoomToBoundingBox(BoundingBox.fromGeoPoints(route.map { GeoPoint(it.lat, it.lng) }).increaseByScale(1.6f), false); if (map.zoomLevelDouble > 16.0) map.controller.setZoom(16.0) } }
        else if (recentre || !centred) { (me ?: Geo.CENTER).let { map.controller.setCenter(GeoPoint(it.lat, it.lng)) }; if (!recentre) centred = true } }
    DisposableEffect(onCenter) {
        val l = onCenter?.let { cb -> object : MapListener { override fun onScroll(e: ScrollEvent?) = true.also { map.mapCenter.let { c -> cb(LatLng(c.latitude, c.longitude)) } }; override fun onZoom(e: ZoomEvent?) = false } }
        l?.let { map.addMapListener(it); map.mapCenter.let { c -> onCenter(LatLng(c.latitude, c.longitude)) } }
        onDispose { l?.let { map.removeMapListener(it) } } }
    // The overlays are rebuilt only when what they draw changes, not on every recomposition (riders refresh every 15 s).
    val drawn = remember { arrayOfNulls<Any>(1) }
    val drawKey = listOf(pins, route, circle, satellite, dark, onLongPress != null, onPinTap != null, brand, surface)
    // + and − buttons (48 dp) so zooming never needs a pinch: one hand, or a first-time smartphone user.
    androidx.compose.foundation.layout.Box(modifier) {
    AndroidView(factory = { map }, modifier = Modifier.matchParentSize().clipToBounds(), update = { mv ->
        if (drawn[0] == drawKey) return@AndroidView
        drawn[0] = drawKey
        mv.overlayManager.tilesOverlay.setColorFilter(if (satellite) null else mutedTiles(dark))
        mv.overlays.clear()
        if (onLongPress != null) mv.overlays.add(org.osmdroid.views.overlay.MapEventsOverlay(object : org.osmdroid.events.MapEventsReceiver {
            override fun singleTapConfirmedHelper(p: GeoPoint?) = false
            override fun longPressHelper(p: GeoPoint?): Boolean { p?.let { press.value?.invoke(LatLng(it.latitude, it.longitude)) }; return true }
        }))
        circle?.let { (c, m) -> mv.overlays.add(Polygon(mv).apply { points = Polygon.pointsAsCircle(GeoPoint(c.lat, c.lng), m); fillPaint.color = (brand and 0x00FFFFFF) or 0x33000000; outlinePaint.color = (brand and 0x00FFFFFF) or 0x66000000; outlinePaint.strokeWidth = 2 * density; setOnClickListener { _, _, _ -> false } }) }
        if (route.size >= 2) mv.overlays.add(Polyline(mv).apply { setPoints(route.map { GeoPoint(it.lat, it.lng) }); outlinePaint.color = brand; outlinePaint.strokeWidth = 5 * density; outlinePaint.strokeCap = android.graphics.Paint.Cap.ROUND; setOnClickListener { _, _, _ -> false } })
        // Drawn last means on top: me, then the selected place.
        pins.sortedWith(compareBy<MapPin>({ it.big }, { it.selected })).forEach { p ->
            val at = p.at ?: Geo.fromPercent(p.x, p.y); val tappable = p.id != null && onPinTap != null
            mv.overlays.add(Marker(mv).apply {
                position = GeoPoint(at.lat, at.lng); title = p.label; setInfoWindow(null); setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                icon = pinIcon(ctx, p, density, surface, tappable)
                setOnMarkerClickListener { _, _ -> if (tappable) { tap.value?.invoke(p); true } else false }
            })
        }
        mv.invalidate()
    })
    if (zoomButtons || onMyLocation != null) androidx.compose.foundation.layout.Column(Modifier.align(androidx.compose.ui.Alignment.CenterEnd).padding(end = 10.dp)) {
        @Composable fun round(label: String, busy: Boolean = false, onClick: () -> Unit, icon: androidx.compose.ui.graphics.vector.ImageVector) =
            androidx.compose.material3.Surface(shape = androidx.compose.foundation.shape.CircleShape, shadowElevation = 4.dp, color = MaterialTheme.colorScheme.surface,
                modifier = Modifier.padding(vertical = 4.dp).size(48.dp).clickable(enabled = !busy, onClickLabel = label, onClick = onClick)) {
                androidx.compose.foundation.layout.Box(contentAlignment = androidx.compose.ui.Alignment.Center) {
                    if (busy) androidx.compose.material3.CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    else androidx.compose.material3.Icon(icon, label, tint = MaterialTheme.colorScheme.onSurface)
                }
            }
        onMyLocation?.let { round(stringResource(R.string.g8_cd_my_location), locating, it, androidx.compose.material.icons.Icons.Rounded.MyLocation) }
        if (zoomButtons) {
            round(stringResource(R.string.g3_cd_zoom_in), onClick = { map.controller.zoomIn() }, icon = androidx.compose.material.icons.Icons.Rounded.Add)
            round(stringResource(R.string.g3_cd_zoom_out), onClick = { map.controller.zoomOut() }, icon = androidx.compose.material.icons.Icons.Rounded.Remove)
        }
    }
    }
}

/** Tile attribution required by OpenStreetMap. */
@Composable
fun MapAttribution(modifier: Modifier = Modifier) = Text(if (com.bucks.app.BuildConfig.MAPBOX_TOKEN.isNotBlank()) "© Mapbox © OpenStreetMap" else "© OpenStreetMap contributors", modifier, fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)

/**
 * Road route between two points (MapServices.route), refetched only when either end moves ~200 m, so a moving car does
 * not ask the routing server every few seconds. Null while loading, offline, or when an end is missing: draw a straight line.
 */
@Composable
fun rememberRoadRoute(from: LatLng?, to: LatLng?): com.bucks.app.data.MapServices.RoadRoute? {
    val key = if (from == null || to == null) null else listOf(from.lat, from.lng, to.lat, to.lng).map { Math.round(it * 500) }
    var route by remember { mutableStateOf<com.bucks.app.data.MapServices.RoadRoute?>(null) }
    LaunchedEffect(key) { route = if (from == null || to == null) null else com.bucks.app.data.MapServices.route(from, to) ?: route }
    return route
}

/** Mapbox Streets (or satellite with streets) tiles when a token is built in: sharper, with Indian place names. Else OpenStreetMap's own. */
private fun mapTiles(satellite: Boolean): org.osmdroid.tileprovider.tilesource.ITileSource {
    val token = com.bucks.app.BuildConfig.MAPBOX_TOKEN
    if (token.isBlank()) return TileSourceFactory.MAPNIK
    val style = if (satellite) "satellite-streets-v12" else "streets-v12"
    return object : org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase("Mapbox-$style", 0, 22, 256, ".png", arrayOf("https://api.mapbox.com/styles/v1/mapbox/$style/tiles/256/")) {
        override fun getTileURLString(t: Long): String =
            baseUrl + org.osmdroid.util.MapTileIndex.getZoom(t) + "/" + org.osmdroid.util.MapTileIndex.getX(t) + "/" + org.osmdroid.util.MapTileIndex.getY(t) + "@2x?access_token=" + token
    }
}
