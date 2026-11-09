package com.bucks.app.ui.screens

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.bucks.app.R
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.PIN_TRIES
import com.bucks.app.ui.isCash
import com.bucks.app.ui.payWord
import com.bucks.app.ui.dial
import com.bucks.app.ui.sms
import com.bucks.app.ui.shareText
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.upiPayLink
import com.bucks.app.ui.upiPayee
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.ui.components.*
import com.bucks.app.ui.screens.manage.onlineLabel
import com.bucks.app.ui.screens.manage.studioIcon
import com.bucks.app.ui.theme.status
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** Pickup (green dot) / drop (red dot) rows used by both sides of a ride. */
@Composable
fun RoutePoints(pickup: String, drop: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) = Column(modifier.fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 12.dp, vertical = 8.dp)) {
    listOf(pickup to MaterialTheme.status.good, drop to MaterialTheme.status.bad).forEachIndexed { i, (t, c) -> Row(Modifier.padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(c)); Text(t, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f).padding(start = 10.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (i == 0) trailing?.invoke() } }
}

private fun metres(km: Double) = if (km < 1) Str.get(R.string.g7_dist_m, (km * 1000).toInt()) else Str.get(R.string.g7_dist_km, km.toString())

/**
 * The incoming request card, shown over whichever screen a driver on duty is on. Accept before the countdown runs out; the bar on the
 * button drains with it while the label stays a solid, readable colour. The request details are a live region, so TalkBack reads a new
 * request out; the countdown is not (it would be read every second). [busy]: the claim is with the server.
 */
@Composable
fun RideRequestCard(dr: DriverRide, onAccept: () -> Unit, onDecline: () -> Unit, modifier: Modifier = Modifier, busy: Boolean = false) {
    // Slides up with a small overshoot; the countdown bar drains smoothly instead of in 1-second steps.
    val left by animateFloatAsState(dr.secondsLeft / 15f, tween(1000, easing = LinearEasing), label = "countdown")
    val urgent = dr.secondsLeft <= 5
    // Bikes carry goods only, so a bike request is always a delivery: pick up at the shop, drop at the customer.
    val delivery = dr.kind == VehicleKind.BIKE
    val requestDesc = if (delivery) stringResource(R.string.g7_drv_new_delivery_request) else stringResource(R.string.g7_drv_new_ride_request, dr.kind.label)
    val acceptLabel = stringResource(R.string.g7_drv_accept_request); val acceptingLabel = stringResource(R.string.g7_drv_accepting)
    // Never wider than a phone card (tablets, landscape), and never taller than the screen: the details scroll, the Accept button stays put.
    Surface(modifier.popIn().widthIn(max = 520.dp).fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), shape = MaterialTheme.shapes.large, border = BorderStroke(2.dp, MaterialTheme.colorScheme.primary), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp) {
        Column(Modifier.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { BrandPill(if (delivery) stringResource(R.string.g7_drv_delivery) else dr.kind.label); Spacer(Modifier.weight(1f)); IconButton(onDecline) { Icon(Icons.Rounded.Close, stringResource(R.string.g7_drv_cd_decline)) } }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(end = 12.dp).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Assertive; contentDescription = requestDesc }) {
                Text(Money.format(animatedInt(dr.fare)), style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold))
                if (delivery) Text(stringResource(R.string.g7_drv_delivery_for, dr.pickupAt.substringBefore(" · ")), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 4.dp))
                Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(dr.customer), size = 36)
                    Column(Modifier.padding(start = 10.dp)) { Text(dr.customer, style = MaterialTheme.typography.titleSmall); TrustBadge(dr.customerTrust, compact = true) } }
                RoutePoints(if (delivery) stringResource(R.string.g7_drv_collect_at, dr.pickupAt) else dr.pickupAt, if (delivery) stringResource(R.string.g7_drv_deliver_to, dr.dropAt) else dr.dropAt)
                Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) { Muted(if (delivery) stringResource(R.string.g7_drv_shop_dist, metres(dr.pickupKm)) else stringResource(R.string.g7_drv_pickup_dist, metres(dr.pickupKm))); Muted(stringResource(R.string.g7_drv_drop_dist, stringResource(R.string.g7_dist_km, dr.km.toString()))) }
            }
            // The whole button is the accept target; the thin bar along its foot is the countdown, so the label keeps a solid, readable background.
            Box(Modifier.padding(end = 12.dp).breathe(amount = if (urgent) 0.035f else 0.015f, periodMs = if (urgent) 450 else 900).fillMaxWidth().height(48.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary)
                .clickable(enabled = !busy, role = Role.Button, onClickLabel = acceptLabel, onClick = withHaptic(onAccept)).semantics { contentDescription = if (busy) acceptingLabel else acceptLabel }) {
                Text(if (busy) stringResource(R.string.g7_drv_accepting_dots) else stringResource(R.string.g7_drv_accept_countdown, dr.secondsLeft), color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge, modifier = Modifier.align(Alignment.Center).clearAndSetSemantics { })
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(left).height(4.dp).background(MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.75f)).clearAndSetSemantics { })
            }
        }
    }
}

/** Round "bucks" button shown on Home while any listing is online. */
@Composable
fun OnlineFab(modifier: Modifier = Modifier, onClick: () -> Unit) = PulseRings(modifier.size(104.dp), periodMs = 2600) { OnlineFabCore(onClick) }
/** Round "bucks" button; the rings around it say "you're live and receiving". */
@Composable
private fun OnlineFabCore(onClick: () -> Unit) = Box(Modifier.size(72.dp).shadow(10.dp, CircleShape).clip(CircleShape).background(MaterialTheme.colorScheme.primary).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
    BucksWordmark(height = 15.dp, color = MaterialTheme.colorScheme.onPrimary, contentDescription = stringResource(R.string.g7_drv_cd_go_online)) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnlineSheet(vm: BucksViewModel, onDismiss: () -> Unit, onListings: () -> Unit, onEarnings: () -> Unit) {
    // Cloud builds: the vehicle comes from My vehicles on the server (checked ones only); demo builds use the local one.
    val s by vm.state.collectAsState(); val cloud = vm.dispatch.enabled; val v = if (cloud) null else s.pro?.vehicle; val cv = vm.cloudVehicle
    ModalBottomSheet(onDismissRequest = onDismiss, dragHandle = { SheetCloseHandle(onDismiss) }) { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
        Text(if (vm.providerOnline) stringResource(R.string.g7_drv_you_online) else stringResource(R.string.g7_drv_you_offline), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g7_drv_online_only_note))
        Column(Modifier.padding(vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (v != null) OnlineRow(v.kind.icon, "${v.model} · ${v.plate}", if (s.vehicleOnline) stringResource(R.string.g7_drv_receiving_rides) else stringResource(R.string.g7_drv_offline), s.vehicleOnline) { vm.setVehicleOnline(v.id, it) }
            if (cv != null) { val k = runCatching { VehicleKind.valueOf(cv.kind) }.getOrDefault(VehicleKind.AUTO)
                OnlineRow(k.icon, "${cv.model.ifBlank { k.label }} · ${cv.plate}", when { s.vehicleOnline -> if (k == VehicleKind.BIKE) stringResource(R.string.g7_drv_receiving_deliveries) else stringResource(R.string.g7_drv_receiving_rides); s.online -> stringResource(R.string.g7_drv_going_online); else -> stringResource(R.string.g7_drv_offline) }, s.vehicleOnline) { vm.setOnline(it, cv.plate) } }
            s.businesses.forEachIndexed { i, b -> OnlineRow(categoryIcon(b.category), b.name, if (b.online) stringResource(R.string.g7_drv_open_for_orders) else stringResource(R.string.g7_drv_closed), b.online) { vm.setBusinessOnline(i, it) } }
            s.pro?.skillListings.orEmpty().forEach { k -> OnlineRow(categoryIcon(k.name), k.name, if (k.online) stringResource(R.string.g7_drv_taking_services) else stringResource(R.string.g7_drv_offline), k.online) { vm.setSkillOnline(k.name, it) } }
            // Cloud builds: my live shops and pro profiles, switched on and off here and in the Studio.
            vm.myListings.listings.filter { it.status == "LIVE" && (it.kind == "BUSINESS" || it.kind == "SKILL") }.forEach { l ->
                OnlineRow(studioIcon(l), l.title, onlineLabel(l.kind, l.online), l.online) { vm.myListings.setOnline(l.id, it) } }
        }
        if (s.mockLocation) Notice(stringResource(R.string.g7_drv_mock_location), Modifier.padding(bottom = 10.dp))
        // A request rings a driver outside the app only through a notification: say so when they can't.
        val ctx = LocalContext.current; var alertProblem by remember { mutableStateOf(RingAlert.problem(ctx)) }
        LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { alertProblem = RingAlert.problem(ctx) }
        if (s.vehicleOnline) alertProblem?.let { p -> Column(Modifier.padding(bottom = 10.dp)) { Notice(p.message); SmallButton(stringResource(R.string.g7_drv_notification_settings), Modifier.padding(top = 8.dp), tonal = true) { runCatching { ctx.startActivity(RingAlert.settingsIntent(ctx, p)) } } } }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BucksCard(Modifier.weight(1f), onClick = { onDismiss(); onEarnings() }, padding = 14) { Text(Money.format(s.earnings), style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g7_drv_today)) }
            BucksCard(Modifier.weight(1f), onClick = { onDismiss(); onListings() }, padding = 14) { Text("${s.incoming.size}", style = MaterialTheme.typography.titleLarge); Muted(stringResource(R.string.g7_drv_incoming)) } }
        // Cloud drivers get paid through the UPI QR they upload; the rider's app opens it with the fare filled in.
        if (cloud && cv != null) { val link = vm.dispatch.paymentLink
            LaunchedEffect(Unit) { if (!vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
            Row(Modifier.padding(top = 12.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable { onDismiss(); vm.open(Routes.PAYMENT_QR) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f).padding(start = 12.dp)) { Text(stringResource(R.string.g7_drv_payment_qr), style = MaterialTheme.typography.titleSmall)
                    Muted(when { link == null && !vm.dispatch.paymentLinkLoaded -> stringResource(R.string.g7_drv_checking); link == null -> stringResource(R.string.g7_drv_qr_not_set); else -> upiPayee(link)?.let { stringResource(R.string.g7_drv_customers_pay_upi, it.first) } ?: stringResource(R.string.g7_drv_upi_set_up) }) }
                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (vm.demoTools && s.vehicleOnline) TintButton("Simulate a ride request", Modifier.weight(1f)) { onDismiss(); vm.simulateRing() }
            if (vm.demoTools && (s.businesses.any { it.online } || s.pro?.skillListings?.any { it.online } == true)) TintButton("Simulate an order", Modifier.weight(1f)) { onDismiss(); vm.simulateIncoming() } }
    } }
}

@Composable
private fun OnlineRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String, on: Boolean, onToggle: (Boolean) -> Unit) = Row(verticalAlignment = Alignment.CenterVertically) {
    ListingThumb(icon, size = 44); Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(detail) }; ListingSwitch(on, onToggle) }

private fun qr(text: String, size: Int = 512): Bitmap { val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val px = IntArray(size * size) { i -> if (m[i % size, i / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    return Bitmap.createBitmap(px, size, size, Bitmap.Config.RGB_565) }

/** Driver's active trip: to pick-up → PIN → drop → payment → rate customer. */
@Composable
fun DriverTripScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit) {
    val s by vm.state.collectAsState(); val dr = s.driverRide ?: return
    val ctx = LocalContext.current; val cloud = vm.dispatch.enabled
    var pin by remember(dr.id) { mutableStateOf("") }; var cash by remember(dr.id) { mutableStateOf(false) }; var stars by remember(dr.id) { mutableIntStateOf(0) }; var rateNote by remember(dr.id) { mutableStateOf("") }; var rateReason by remember(dr.id) { mutableStateOf<String?>(null) }
    var cancel by remember { mutableStateOf(false) }; var endAsk by remember { mutableStateOf(false) }
    // With cloud dispatch the server checks the PIN; the field clears once the trip has really started, so a wrong PIN stays for a retry.
    LaunchedEffect(dr.status) { if (dr.status == DriverRideStatus.IN_RIDE) pin = "" }
    val delivery = dr.kind == VehicleKind.BIKE
    val noPhone = { vm.toast(Str.get(R.string.g7_drv_no_phone)) }
    val me = dr.driver ?: Geo.CENTER; val pickup = dr.pickup ?: me; val drop = dr.drop ?: me
    fun lerp(a: LatLng, b: LatLng, t: Float) = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
    val (from, to, car) = when (dr.status) {
        DriverRideStatus.TO_PICKUP -> Triple(me, pickup, lerp(me, pickup, dr.progress))
        DriverRideStatus.ARRIVED -> Triple(pickup, pickup, pickup)
        else -> Triple(pickup, drop, lerp(pickup, drop, dr.progress)) }
    val working = vm.dispatch.busy || vm.dispatch.handingBack
    Column(Modifier.fillMaxSize().imePadding()) {
        if (dr.status != DriverRideStatus.DONE) Box(Modifier.weight(1f).fillMaxWidth()) {
            val road = rememberRoadRoute(car.takeIf { from != to && car != to }, to)
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(car, stringResource(R.string.g7_drv_you), MeColor, true), pinAt(to, "", MaterialTheme.colorScheme.primary)), route = if (from != to && car != to) road?.points ?: listOf(car, to) else emptyList())
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp))
            // Turn-by-turn inside Bucks (the Maps screen starts guiding straight away).
            if (from != to) SmallButton(road?.let { stringResource(R.string.g7_drv_navigate_min, it.minutes) } ?: stringResource(R.string.g7_drv_navigate), Modifier.align(Alignment.TopEnd).padding(12.dp)) { vm.openMapsTo(if (dr.status == DriverRideStatus.TO_PICKUP) dr.pickupAt else dr.dropAt, to, autoStart = true) }
        }
        Surface(Modifier.fillMaxWidth().then(if (dr.status == DriverRideStatus.DONE) Modifier.weight(1f) else Modifier), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
            // Scrolls, so the buttons stay reachable at large text sizes and on small phones.
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when (dr.status) {
                    DriverRideStatus.TO_PICKUP -> {
                        Text(if (delivery) stringResource(R.string.g7_drv_delivery_for, dr.pickupAt.substringBefore(" · ")) else dr.customer, style = MaterialTheme.typography.titleMedium)
                        if (delivery) Muted(dr.pickupAt.substringAfter(" · ", "").let { if (it.isBlank()) stringResource(R.string.g7_drv_order_for, dr.customer) else stringResource(R.string.g7_drv_order_for_detail, dr.customer, it) }, Modifier.padding(top = 2.dp))
                        Row(Modifier.padding(top = 4.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { Muted(stringResource(R.string.g7_drv_minutes, maxOf(1, ((1 - dr.progress) * dr.pickupKm * 4).toInt()))); Muted(if (delivery) stringResource(R.string.g7_drv_shop_dist, metres(dr.pickupKm * (1 - dr.progress))) else stringResource(R.string.g7_drv_pickup_dist, metres(dr.pickupKm * (1 - dr.progress)))) }
                        MessageBar(stringResource(R.string.g7_drv_message_customer), onCall = { if (cloud) { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) } else onCall(dr.customer, "+91 98450 00000") }) { if (cloud) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) } else onChatWith(dr.customer, "Customer") }
                        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) { TextButton({ cancel = true }, enabled = !working) { Text(if (delivery) stringResource(R.string.g7_drv_cancel_delivery) else stringResource(R.string.g7_drv_cancel_ride), color = MaterialTheme.colorScheme.error) }; TextButton({ vm.driverNext() }, enabled = !working) { Text(if (working) stringResource(R.string.g7_drv_working) else if (delivery) stringResource(R.string.g7_drv_at_shop) else stringResource(R.string.g7_drv_arrived)) } }
                    }
                    DriverRideStatus.ARRIVED -> {
                        val left = (PIN_TRIES - dr.pinAttempts).coerceAtLeast(0)
                        Text(if (delivery) stringResource(R.string.g7_drv_enter_pickup_pin) else stringResource(R.string.g7_drv_enter_customer_pin), style = MaterialTheme.typography.titleMedium)
                        PinBoxes(pin, Modifier.padding(top = 20.dp, bottom = 8.dp), onDone = { if (pin.length == 4 && !dr.pinLocked && vm.driverNext(pin) && !cloud) pin = "" }) { if (!dr.pinLocked) pin = it }
                        // Wrong PINs keep the boxes filled and count down; the fifth locks the trip (the server says so) and only a hand-back is left.
                        if (cloud && dr.pinAttempts > 0) Text(if (dr.pinLocked) stringResource(R.string.g7_drv_pin_locked) else pluralStringResource(R.plurals.g7_drv_pin_wrong, left, left),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 8.dp).semantics { liveRegion = LiveRegionMode.Polite })
                        Muted(when { cloud && delivery -> stringResource(R.string.g7_drv_pin_hint_delivery)
                                     cloud -> stringResource(R.string.g7_drv_pin_hint_cloud); vm.demoTools -> "Demo build: the customer's PIN is ${dr.pin}"; else -> stringResource(R.string.g7_drv_pin_hint) }, Modifier.padding(bottom = 14.dp))
                        if (cloud) MessageBar(stringResource(R.string.g7_drv_message_customer), onCall = { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) }) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) }
                        DarkButton(if (vm.dispatch.busy) stringResource(R.string.g7_drv_checking) else stringResource(R.string.g7_drv_confirm_pin), Modifier.padding(top = if (cloud) 14.dp else 0.dp), enabled = pin.length == 4 && !working && !dr.pinLocked) { if (vm.driverNext(pin) && !cloud) pin = "" }
                        // The server lets a trip go back to other riders until the PIN is in.
                        TextButton({ cancel = true }, Modifier.padding(top = 4.dp), enabled = !working) { Text(if (delivery) stringResource(R.string.g7_drv_cant_collect) else stringResource(R.string.g7_drv_customer_absent), color = MaterialTheme.colorScheme.error) }
                    }
                    DriverRideStatus.IN_RIDE -> {
                        Text(dr.customer, style = MaterialTheme.typography.titleMedium)
                        Muted(if (dr.progress >= 1f) stringResource(R.string.g7_drv_at_destination) else stringResource(R.string.g7_drv_on_way_to, dr.dropAt), Modifier.padding(top = 4.dp))
                        Muted(if (dr.progress >= 1f) stringResource(R.string.g7_drv_dropping_off) else stringResource(R.string.g7_drv_km_left, "%.1f".format((1 - dr.progress) * dr.km)), Modifier.padding(bottom = 14.dp))
                        if (cloud) Box(Modifier.padding(bottom = 14.dp)) { MessageBar(stringResource(R.string.g7_drv_message_customer), onCall = { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) }) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) } }
                        DarkButton(if (working) stringResource(R.string.g7_drv_working) else if (delivery) stringResource(R.string.g7_drv_delivered_end) else stringResource(R.string.g7_drv_end_ride), enabled = !working) { endAsk = true }
                    }
                    DriverRideStatus.DONE -> PaymentPanel(vm, dr, cash) { cash = it }
                    DriverRideStatus.RATE -> {
                        Text(stringResource(R.string.g7_drv_recommend_customer), style = MaterialTheme.typography.titleMedium)
                        Avatar(initials(dr.customer), size = 48); Text(dr.customer, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                        // Recommendations are an upvote or a downvote everywhere; 5 and 1 keep driverRateCustomer's up/down split.
                        Row(Modifier.padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            listOf(5 to true, 1 to false).forEach { (v, up) -> val on = stars == v; val c = if (up) MaterialTheme.status.good else MaterialTheme.status.bad
                                OutlinedButton({ stars = v }, colors = ButtonDefaults.outlinedButtonColors(containerColor = if (on) c.copy(alpha = 0.14f) else androidx.compose.ui.graphics.Color.Transparent, contentColor = c)) {
                                    Icon(if (up) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward, if (up) stringResource(R.string.g7_cd_vote_up) else stringResource(R.string.g7_cd_vote_down), Modifier.size(24.dp)) } } }
                        // A down needs a reason; it goes on the customer's record with Bucks (profile_votes), never shown to them by name.
                        if (stars == 1) { Text(stringResource(R.string.g7_drv_what_wrong), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(bottom = 6.dp)); ReasonChips(rateReason) { rateReason = it } }
                        if (stars > 0) BucksField(rateNote, { rateNote = it.take(500) }, stringResource(R.string.g7_drv_tell_more), if (stars == 5) stringResource(R.string.g7_drv_tell_more_good) else stringResource(R.string.g7_drv_tell_more_bad), singleLine = false, minLines = 2)
                        DarkButton(stringResource(R.string.g7_drv_submit), enabled = stars > 0 && (stars == 5 || rateReason != null)) { vm.driverRateCustomer(stars, rateNote, rateReason) }
                    }
                    DriverRideStatus.RINGING -> {}
                }
            }
        }
    }
    if (endAsk) AlertDialog(onDismissRequest = { endAsk = false }, title = { Text(if (delivery) stringResource(R.string.g7_drv_end_title_delivery) else stringResource(R.string.g7_drv_end_title_ride)) },
        text = { Text(if (delivery) stringResource(R.string.g7_drv_end_body_delivery) else stringResource(R.string.g7_drv_end_body_ride, Money.format(dr.fare))) },
        confirmButton = { TextButton({ endAsk = false; vm.driverNext() }) { Text(if (delivery) stringResource(R.string.g7_drv_yes_delivered) else stringResource(R.string.g7_drv_end_ride)) } }, dismissButton = { TextButton({ endAsk = false }) { Text(stringResource(R.string.g7_drv_not_yet)) } })
    if (cancel) DriverCancelSheet(vm, delivery, atPickup = dr.status == DriverRideStatus.ARRIVED) { cancel = false }
}

/** Handing a ride or delivery back: a reason is required so the customer or shop hears why, and it counts against the driver's record. */
@Composable
private fun DriverCancelSheet(vm: BucksViewModel, delivery: Boolean, atPickup: Boolean, onClose: () -> Unit) {
    var busy by remember { mutableStateOf(false) }
    var stats by remember { mutableStateOf<CancelStats?>(null) }
    LaunchedEffect(Unit) { if (vm.cloud) stats = runCatching { Backend.myCancelStats() }.getOrNull() }
    val n = stats?.driverDay ?: 0
    CancelSheet(
        title = if (delivery) stringResource(R.string.g7_drv_handback_title_delivery) else stringResource(R.string.g7_drv_handback_title_ride),
        message = when { atPickup && delivery -> stringResource(R.string.g7_drv_handback_msg_pickup_delivery); atPickup -> stringResource(R.string.g7_drv_handback_msg_pickup_ride); delivery -> stringResource(R.string.g7_drv_handback_msg_delivery); else -> stringResource(R.string.g7_drv_handback_msg_ride) },
        reasons = CancelReasons.driver, requireReason = true, confirmLabel = if (atPickup) stringResource(R.string.g7_drv_hand_back) else if (delivery) stringResource(R.string.g7_drv_cancel_delivery) else stringResource(R.string.g7_drv_cancel_ride), keepLabel = stringResource(R.string.g7_drv_keep_it),
        nudge = when { n >= 2 -> pluralStringResource(R.plurals.g7_drv_handed_back_many, n, n); n == 1 -> stringResource(R.string.g7_drv_handed_back_one); else -> null }, busy = busy,
        onConfirm = { code, note -> busy = true; vm.driverCancel(code, note) { ok -> busy = false; if (ok) onClose() } }, onDismiss = onClose)
}

@Composable
private fun PaymentPanel(vm: BucksViewModel, dr: DriverRide, cash: Boolean, onCash: (Boolean) -> Unit) {
    if (vm.dispatch.enabled) { CloudPaymentPanel(vm, dr, cash, onCash); return }
    val s by vm.state.collectAsState(); val upi = s.pro?.upiId.orEmpty(); var entry by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.g7_drv_total_payable, Money.format(dr.fare)), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
        if (upi.isNotBlank()) {
            // Standard UPI deep link: any UPI app can scan it and pay the driver directly.
            val link = "upi://pay?pa=${Uri.encode(upi)}&pn=${Uri.encode(s.user?.name ?: "Bucks driver")}&am=${dr.fare}&cu=INR&tn=${Uri.encode("Bucks ride ${dr.id.takeLast(6)}")}"
            val bmp = remember(link) { qr(link) }
            Box(Modifier.size(200.dp).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).padding(10.dp)) { Image(bmp.asImageBitmap(), stringResource(R.string.g7_drv_cd_upi_qr_to, dr.fare, upi), Modifier.fillMaxSize()) }
            Muted(upi, Modifier.padding(top = 6.dp))
        } else Column(Modifier.fillMaxWidth()) {
            Muted(stringResource(R.string.g7_drv_add_upi_id), Modifier.padding(bottom = 8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(entry, { entry = it }, placeholder = { Text("name@okaxis") }, singleLine = true, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.small); Spacer(Modifier.width(8.dp)); SmallButton(stringResource(R.string.g7_drv_save)) { vm.setUpi(entry) } }
        }
        Row(Modifier.fillMaxWidth().padding(top = 24.dp).clip(MaterialTheme.shapes.small).border(1.dp, if (cash) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).clickable { onCash(!cash) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Payments, null, tint = MaterialTheme.status.good); Text(stringResource(R.string.g7_drv_pay_cash), Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); RadioButton(cash, { onCash(!cash) }) }
        Spacer(Modifier.height(20.dp))
        DarkButton(stringResource(R.string.g7_drv_proceed), enabled = cash || upi.isNotBlank()) { vm.driverPaid(if (cash) "CASH" else "UPI") }
    }
}

/**
 * Cloud trip done: show the fare QR from the driver's uploaded UPI code (the customer's app also opens it by itself), or take cash.
 * What the customer taps on their phone is only their word; Bucks can't see the bank or the cash, so the driver checks and then confirms
 * for themselves, once, with the amount in front of them.
 */
@Composable
private fun CloudPaymentPanel(vm: BucksViewModel, dr: DriverRide, cash: Boolean, onCash: (Boolean) -> Unit) {
    val link = vm.dispatch.paymentLink; val delivery = dr.kind == VehicleKind.BIKE
    LaunchedEffect(Unit) { if (!vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
    // Deliveries: the amount at the door comes from the order (free delivery = 0, store-rider COD = the whole bill), not the fee.
    var collect by remember(dr.id) { mutableStateOf<Int?>(if (delivery) null else dr.fare) }
    if (delivery) LaunchedEffect(dr.id) { collect = runCatching { com.bucks.app.data.Backend.taskGeo(dr.id)?.collect }.getOrNull() }
    var confirm by remember(dr.id) { mutableStateOf(false) }
    if (delivery && collect == 0) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.g7_drv_nothing_to_collect), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
            Muted(stringResource(R.string.g7_drv_already_paid, Money.format(dr.fare)), align = TextAlign.Center)
            Spacer(Modifier.height(20.dp))
            DarkButton(stringResource(R.string.g7_drv_done)) { vm.driverPaid("shop") }
        }
        return
    }
    val amount = collect ?: dr.fare
    val theyPaid = dr.paidWith
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(if (delivery) stringResource(R.string.g7_drv_collect_amount, Money.format(amount)) else stringResource(R.string.g7_drv_total_payable, Money.format(amount)), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
        if (delivery && collect == null) Muted(stringResource(R.string.g7_drv_checking_collect), align = TextAlign.Center)
        if (theyPaid != null) { PillWarn(stringResource(R.string.g7_drv_says_paid_by, dr.customer.substringBefore(' '), payWord(theyPaid)))
            Muted(if (isCash(theyPaid)) stringResource(R.string.g7_drv_check_cash) else stringResource(R.string.g7_drv_check_upi), Modifier.padding(top = 6.dp), TextAlign.Center) }
        else Muted(stringResource(R.string.g7_drv_customer_sees_amount, dr.customer.substringBefore(' ')), align = TextAlign.Center)
        Spacer(Modifier.height(14.dp))
        if (link != null) {
            val pay = upiPayLink(link, amount, "Bucks ${if (delivery) "delivery" else "ride"}")
            val bmp = remember(pay) { qr(pay) }
            Box(Modifier.size(200.dp).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).background(androidx.compose.ui.graphics.Color.White).padding(10.dp)) { Image(bmp.asImageBitmap(), stringResource(R.string.g7_drv_cd_upi_qr, amount), Modifier.fillMaxSize()) }
            upiPayee(link)?.let { (pn, pa) -> Muted("$pn · $pa", Modifier.padding(top = 6.dp)) }
        } else Column(Modifier.fillMaxWidth()) {
            Muted(if (vm.dispatch.paymentLinkLoaded) stringResource(R.string.g7_drv_no_upi_qr) else stringResource(R.string.g7_drv_checking_qr), Modifier.padding(bottom = 8.dp))
            if (vm.dispatch.paymentLinkLoaded) SmallButton(stringResource(R.string.g7_drv_add_upi_qr), tonal = true) { vm.open(Routes.PAYMENT_QR) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 24.dp).clip(MaterialTheme.shapes.small).border(1.dp, if (cash) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).clickable { onCash(!cash) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Payments, null, tint = MaterialTheme.status.good); Text(stringResource(R.string.g7_drv_cash_received), Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); RadioButton(cash, { onCash(!cash) }) }
        Spacer(Modifier.height(20.dp))
        DarkButton(if (cash) stringResource(R.string.g7_drv_cash_continue) else stringResource(R.string.g7_drv_upi_continue), enabled = cash || link != null || theyPaid != null) { confirm = true }
        Muted(stringResource(R.string.g7_drv_wait_payment), Modifier.padding(top = 8.dp), TextAlign.Center)
    }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false }, title = { Text(if (cash) stringResource(R.string.g7_drv_confirm_cash_title, Money.format(amount)) else stringResource(R.string.g7_drv_confirm_upi_title, amount)) },
        text = { Text(when { cash && delivery -> stringResource(R.string.g7_drv_confirm_cash_delivery); cash -> stringResource(R.string.g7_drv_confirm_cash_trip); delivery -> stringResource(R.string.g7_drv_confirm_upi_delivery); else -> stringResource(R.string.g7_drv_confirm_upi_trip) }) },
        confirmButton = { TextButton({ confirm = false; vm.driverPaid(if (cash) "CASH" else "UPI") }) { Text(if (cash) stringResource(R.string.g7_drv_yes_cash) else stringResource(R.string.g7_drv_yes_arrived)) } }, dismissButton = { TextButton({ confirm = false }) { Text(stringResource(R.string.g7_drv_not_yet)) } })
}

@Composable
fun PinBoxes(value: String, modifier: Modifier = Modifier, onDone: () -> Unit = {}, onChange: (String) -> Unit) = BasicTextField(value, { onChange(it.filter(Char::isDigit).take(4)) }, modifier, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { onDone() }),
    decorationBox = { Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { (0 until 4).forEach { i -> Box(Modifier.defaultMinSize(minWidth = 52.dp, minHeight = 52.dp).clip(MaterialTheme.shapes.small).border(2.dp, if (i == value.length) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primary.copy(alpha = 0.5f), MaterialTheme.shapes.small).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
        Text(value.getOrNull(i)?.toString() ?: "", style = MaterialTheme.typography.headlineSmall) } } } })

/** Call button + "message …" pill that opens the chat. */
@Composable
fun MessageBar(hint: String, onCall: () -> Unit, onMessage: () -> Unit) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onCall), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Call, stringResource(R.string.g7_drv_cd_call), Modifier.size(20.dp)) }
    Row(Modifier.weight(1f).padding(start = 10.dp).height(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onMessage).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Muted(hint, Modifier.weight(1f)); Icon(Icons.AutoMirrored.Rounded.Send, stringResource(R.string.g7_drv_cd_message), Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
}

/** Opens driving directions to [to] in Google Maps, else in any app that takes a map link, else says so. */
fun openNavigation(ctx: android.content.Context, to: LatLng) {
    val nav = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("google.navigation:q=${to.lat},${to.lng}&mode=d")).setPackage("com.google.android.apps.maps")
    val any = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("geo:${to.lat},${to.lng}?q=${to.lat},${to.lng}"))
    runCatching { ctx.startActivity(nav) }.recoverCatching { ctx.startActivity(any) }
        .onFailure { android.widget.Toast.makeText(ctx, Str.get(R.string.g7_drv_install_maps), android.widget.Toast.LENGTH_SHORT).show() }
}
