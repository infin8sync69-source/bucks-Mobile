package com.bucks.app.ui.screens

import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.filled.Star
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bucks.app.data.*
import com.bucks.app.ui.BucksViewModel
import com.bucks.app.ui.dial
import com.bucks.app.ui.sms
import com.bucks.app.ui.shareText
import com.bucks.app.ui.nav.Routes
import com.bucks.app.ui.upiPayLink
import com.bucks.app.ui.upiPayee
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.ui.components.*
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

private fun metres(km: Double) = if (km < 1) "${(km * 1000).toInt()}m" else "${km}km"

/** The incoming ride card on Home (driver online). Accept before the countdown runs out. */
@Composable
fun RideRequestCard(dr: DriverRide, onAccept: () -> Unit, onDecline: () -> Unit, modifier: Modifier = Modifier) {
    // Slides up with a small overshoot; the countdown bar drains smoothly instead of in 1-second steps.
    val left by animateFloatAsState(dr.secondsLeft / 15f, tween(1000, easing = LinearEasing), label = "countdown")
    val urgent = dr.secondsLeft <= 5
    // Bikes carry goods only, so a bike request is always a delivery: pick up at the shop, drop at the customer.
    val delivery = dr.kind == VehicleKind.BIKE
    Surface(modifier.popIn().fillMaxWidth().padding(horizontal = 16.dp), shape = MaterialTheme.shapes.large, border = BorderStroke(2.dp, MaterialTheme.colorScheme.primary), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { BrandPill(if (delivery) "Delivery" else dr.kind.label); Spacer(Modifier.weight(1f)); IconButton(onDecline, Modifier.size(28.dp)) { Icon(Icons.Rounded.Close, "Decline") } }
            Text("₹${animatedInt(dr.fare)}", style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(top = 8.dp))
            if (delivery) Text("Delivery for ${dr.pickupAt.substringBefore(" · ")}", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 4.dp))
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Avatar(initials(dr.customer), size = 36)
                Column(Modifier.padding(start = 10.dp)) { Text(dr.customer, style = MaterialTheme.typography.titleSmall); TrustBadge(dr.customerTrust, compact = true) } }
            RoutePoints(if (delivery) "Collect at ${dr.pickupAt}" else dr.pickupAt, if (delivery) "Deliver to ${dr.dropAt}" else dr.dropAt)
            Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) { Muted("${if (delivery) "Shop" else "Pickup"}: ${metres(dr.pickupKm)}"); Muted("Drop: ${dr.km}km") }
            // Accept button doubles as the countdown: the darker part shrinks as time runs out.
            Box(Modifier.breathe(amount = if (urgent) 0.035f else 0.015f, periodMs = if (urgent) 450 else 900).fillMaxWidth().height(44.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.55f)).clickable(onClick = withHaptic(onAccept))) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(left).background(MaterialTheme.colorScheme.primary))
                Text("Accept · ${dr.secondsLeft}s", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge, modifier = Modifier.align(Alignment.Center))
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
    Text("bucks", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp)) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnlineSheet(vm: BucksViewModel, onDismiss: () -> Unit, onListings: () -> Unit, onEarnings: () -> Unit) {
    val s by vm.state.collectAsState(); val v = s.pro?.vehicle
    ModalBottomSheet(onDismissRequest = onDismiss) { Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
        Text("You're online", style = MaterialTheme.typography.titleLarge); Muted("Only online listings receive rides, orders and service requests.")
        Column(Modifier.padding(vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (v != null) OnlineRow(v.kind.icon, "${v.model} · ${v.plate}", if (s.vehicleOnline) "Receiving ride requests" else "Offline", s.vehicleOnline) { vm.setVehicleOnline(v.id, it) }
            s.businesses.forEachIndexed { i, b -> OnlineRow(categoryIcon(b.category), b.name, if (b.online) "Open for orders" else "Closed", b.online) { vm.setBusinessOnline(i, it) } }
            s.pro?.skillListings.orEmpty().forEach { k -> OnlineRow(categoryIcon(k.name), k.name, if (k.online) "Taking service requests" else "Offline", k.online) { vm.setSkillOnline(k.name, it) } }
        }
        if (s.mockLocation) Notice("Mock location is on. Turn it off to take rides.", Modifier.padding(bottom = 10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BucksCard(Modifier.weight(1f), onClick = { onDismiss(); onEarnings() }, padding = 14) { Text("₹${s.earnings}", style = MaterialTheme.typography.titleLarge); Muted("Today") }
            BucksCard(Modifier.weight(1f), onClick = { onDismiss(); onListings() }, padding = 14) { Text("${s.incoming.size}", style = MaterialTheme.typography.titleLarge); Muted("Incoming") } }
        // Cloud drivers get paid through the UPI QR they upload; the rider's app opens it with the fare filled in.
        if (vm.dispatch.enabled && v != null) { val link = vm.dispatch.paymentLink
            LaunchedEffect(Unit) { if (!vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
            Row(Modifier.padding(top = 12.dp).fillMaxWidth().clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceContainer).clickable { onDismiss(); vm.open(Routes.PAYMENT_QR) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.QrCode2, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f).padding(start = 12.dp)) { Text("Payment QR", style = MaterialTheme.typography.titleSmall)
                    Muted(when { link == null && !vm.dispatch.paymentLinkLoaded -> "Checking…"; link == null -> "Not set. Customers pay in cash until you add one."; else -> upiPayee(link)?.let { "Customers pay ${it.first} by UPI" } ?: "UPI set up" }) }
                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } }
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (s.vehicleOnline && !vm.dispatch.enabled) TintButton("Simulate a ride request", Modifier.weight(1f)) { onDismiss(); vm.simulateRing() }
            if (s.businesses.any { it.online } || s.pro?.skillListings?.any { it.online } == true) TintButton("Simulate an order", Modifier.weight(1f)) { onDismiss(); vm.simulateIncoming() } }
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
    var pin by remember(dr.id) { mutableStateOf("") }; var cash by remember(dr.id) { mutableStateOf(false) }; var stars by remember(dr.id) { mutableIntStateOf(0) }; var cancel by remember { mutableStateOf(false) }
    // With cloud dispatch the server checks the PIN; the field clears once the trip has really started, so a wrong PIN stays for a retry.
    LaunchedEffect(dr.status) { if (dr.status == DriverRideStatus.IN_RIDE) pin = "" }
    val delivery = dr.kind == VehicleKind.BIKE
    val noPhone = { vm.toast("The customer's number isn't available yet. Try again in a moment.") }
    val me = dr.driver ?: Geo.CENTER; val pickup = dr.pickup ?: me; val drop = dr.drop ?: me
    fun lerp(a: LatLng, b: LatLng, t: Float) = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
    val (from, to, car) = when (dr.status) {
        DriverRideStatus.TO_PICKUP -> Triple(me, pickup, lerp(me, pickup, dr.progress))
        DriverRideStatus.ARRIVED -> Triple(pickup, pickup, pickup)
        else -> Triple(pickup, drop, lerp(pickup, drop, dr.progress)) }
    Column(Modifier.fillMaxSize().imePadding()) {
        if (dr.status != DriverRideStatus.DONE) Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(car, "You", MeColor, true), pinAt(to, "", MaterialTheme.colorScheme.primary)), route = if (from != to && car != to) listOf(car, to) else emptyList())
            MapAttribution(Modifier.align(Alignment.BottomEnd).padding(8.dp))
        }
        Surface(Modifier.fillMaxWidth().then(if (dr.status == DriverRideStatus.DONE) Modifier.weight(1f) else Modifier), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
            Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when (dr.status) {
                    DriverRideStatus.TO_PICKUP -> {
                        Text(if (delivery) "Delivery for ${dr.pickupAt.substringBefore(" · ")}" else dr.customer, style = MaterialTheme.typography.titleMedium)
                        if (delivery) Muted("Order for ${dr.customer}${dr.pickupAt.substringAfter(" · ", "").let { if (it.isBlank()) "" else " · $it" }}", Modifier.padding(top = 2.dp))
                        Row(Modifier.padding(top = 4.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { Muted("${maxOf(1, ((1 - dr.progress) * dr.pickupKm * 4).toInt())} mins"); Muted("${if (delivery) "Shop" else "Pickup"}: ${metres(dr.pickupKm * (1 - dr.progress))}") }
                        MessageBar("Message your customer", onCall = { if (cloud) { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) } else onCall(dr.customer, "+91 98450 00000") }) { if (cloud) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) } else onChatWith(dr.customer, "Customer") }
                        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) { TextButton({ cancel = true }) { Text(if (delivery) "Cancel delivery" else "Cancel ride", color = MaterialTheme.colorScheme.error) }; TextButton({ vm.driverNext() }, enabled = !vm.dispatch.busy) { Text(if (delivery) "I'm at the shop" else "I've arrived") } }
                    }
                    DriverRideStatus.ARRIVED -> {
                        Text(if (delivery) "Enter the pickup PIN" else "Enter customer's PIN", style = MaterialTheme.typography.titleMedium)
                        PinBoxes(pin, Modifier.padding(top = 20.dp, bottom = 8.dp), onDone = { if (pin.length == 4 && vm.driverNext(pin) && !cloud) pin = "" }) { pin = it }
                        Muted(when { cloud && delivery -> "Call the customer for their 4-digit PIN before you leave the shop; it confirms you have their order."
                                     cloud -> "Ask the customer to read out the 4-digit PIN on their screen."; else -> "Demo build: the customer's PIN is ${dr.pin}" }, Modifier.padding(bottom = 14.dp))
                        if (cloud) MessageBar("Message your customer", onCall = { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) }) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) }
                        DarkButton(if (vm.dispatch.busy) "Checking…" else "Confirm PIN", Modifier.padding(top = if (cloud) 14.dp else 0.dp), enabled = pin.length == 4 && !vm.dispatch.busy) { if (vm.driverNext(pin) && !cloud) pin = "" }
                    }
                    DriverRideStatus.IN_RIDE -> {
                        Text(dr.customer, style = MaterialTheme.typography.titleMedium)
                        Muted(if (dr.progress >= 1f) "Arrived at destination" else "On the way to ${dr.dropAt}", Modifier.padding(top = 4.dp))
                        Muted(if (dr.progress >= 1f) "Dropping off" else "${"%.1f".format((1 - dr.progress) * dr.km)} km left", Modifier.padding(bottom = 14.dp))
                        if (cloud) Box(Modifier.padding(bottom = 14.dp)) { MessageBar("Message your customer", onCall = { if (dr.customerPhone.isBlank()) noPhone() else dial(ctx, dr.customerPhone) }) { if (dr.customerPhone.isBlank()) noPhone() else sms(ctx, dr.customerPhone) } }
                        DarkButton(if (delivery) "Delivered · end trip" else "End ride", enabled = !vm.dispatch.busy) { vm.driverNext() }
                    }
                    DriverRideStatus.DONE -> PaymentPanel(vm, dr, cash) { cash = it }
                    DriverRideStatus.RATE -> {
                        Text("Rate your customer", style = MaterialTheme.typography.titleMedium)
                        Avatar(initials(dr.customer), size = 48); Text(dr.customer, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                        Row(Modifier.padding(vertical = 14.dp)) { (1..5).forEach { i -> IconButton({ stars = i }) { Icon(if (i <= stars) Icons.Filled.Star else Icons.Rounded.StarOutline, "$i star${if (i > 1) "s" else ""}", Modifier.size(34.dp), tint = if (i <= stars) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant) } } }
                        DarkButton("Submit", enabled = stars > 0) { vm.driverRateCustomer(stars) }
                    }
                    DriverRideStatus.RINGING -> {}
                }
            }
        }
    }
    if (cancel) AlertDialog(onDismissRequest = { cancel = false }, title = { Text(if (delivery) "Cancel this delivery?" else "Cancel this ride?") }, text = { Text("The ${if (delivery) "order" else "customer"} goes to the next rider. Cancelling after accepting counts against your recommendations.") }, confirmButton = { TextButton(onClick = { cancel = false; vm.driverCancel() }) { Text(if (delivery) "Cancel delivery" else "Cancel ride", color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton(onClick = { cancel = false }) { Text(if (delivery) "Keep delivery" else "Keep ride") } })
}

@Composable
private fun PaymentPanel(vm: BucksViewModel, dr: DriverRide, cash: Boolean, onCash: (Boolean) -> Unit) {
    if (vm.dispatch.enabled) { CloudPaymentPanel(vm, dr, cash, onCash); return }
    val s by vm.state.collectAsState(); val upi = s.pro?.upiId.orEmpty(); var entry by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Total payable ₹${dr.fare}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
        if (upi.isNotBlank()) {
            // Standard UPI deep link: any UPI app can scan it and pay the driver directly.
            val link = "upi://pay?pa=${Uri.encode(upi)}&pn=${Uri.encode(s.user?.name ?: "Bucks driver")}&am=${dr.fare}&cu=INR&tn=${Uri.encode("Bucks ride ${dr.id.takeLast(6)}")}"
            val bmp = remember(link) { qr(link) }
            Box(Modifier.size(200.dp).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).padding(10.dp)) { Image(bmp.asImageBitmap(), "UPI QR for ₹${dr.fare} to $upi", Modifier.fillMaxSize()) }
            Muted(upi, Modifier.padding(top = 6.dp))
        } else Column(Modifier.fillMaxWidth()) {
            Muted("Add your UPI ID to show a payment QR customers can scan.", Modifier.padding(bottom = 8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(entry, { entry = it }, placeholder = { Text("name@okaxis") }, singleLine = true, modifier = Modifier.weight(1f), shape = MaterialTheme.shapes.small); Spacer(Modifier.width(8.dp)); SmallButton("Save") { vm.setUpi(entry) } }
        }
        Row(Modifier.fillMaxWidth().padding(top = 24.dp).clip(MaterialTheme.shapes.small).border(1.dp, if (cash) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).clickable { onCash(!cash) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Payments, null, tint = MaterialTheme.status.good); Text("Pay cash", Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); RadioButton(cash, { onCash(!cash) }) }
        Spacer(Modifier.height(20.dp))
        DarkButton("Proceed", enabled = cash || upi.isNotBlank()) { vm.driverPaid(if (cash) "cash" else "UPI") }
    }
}

/** Cloud trip done: show the fare QR from the driver's uploaded UPI code (the customer's app also opens it by itself), or take cash. */
@Composable
private fun CloudPaymentPanel(vm: BucksViewModel, dr: DriverRide, cash: Boolean, onCash: (Boolean) -> Unit) {
    val link = vm.dispatch.paymentLink; val delivery = dr.kind == VehicleKind.BIKE
    LaunchedEffect(Unit) { if (!vm.dispatch.paymentLinkLoaded) vm.dispatch.refreshPaymentLink() }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(if (delivery) "Delivered · delivery fee ₹${dr.fare}" else "Total payable ₹${dr.fare}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
        if (dr.paidWith != null) PillGood("Customer paid by ${dr.paidWith}") else Muted("${dr.customer.substringBefore(' ')} sees the fare on their phone and can pay by UPI or cash.", align = TextAlign.Center)
        Spacer(Modifier.height(14.dp))
        if (link != null) {
            val pay = upiPayLink(link, dr.fare, "Bucks ${if (delivery) "delivery" else "ride"}")
            val bmp = remember(pay) { qr(pay) }
            Box(Modifier.size(200.dp).border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).background(androidx.compose.ui.graphics.Color.White).padding(10.dp)) { Image(bmp.asImageBitmap(), "UPI QR for ₹${dr.fare}", Modifier.fillMaxSize()) }
            upiPayee(link)?.let { (pn, pa) -> Muted("$pn · $pa", Modifier.padding(top = 6.dp)) }
        } else Column(Modifier.fillMaxWidth()) {
            Muted(if (vm.dispatch.paymentLinkLoaded) "No UPI QR on your account yet, so this customer pays in cash. Add your QR to get paid by UPI next time." else "Checking your payment QR…", Modifier.padding(bottom = 8.dp))
            if (vm.dispatch.paymentLinkLoaded) SmallButton("Add my UPI QR", tonal = true) { vm.open(Routes.PAYMENT_QR) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 24.dp).clip(MaterialTheme.shapes.small).border(1.dp, if (cash) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small).clickable { onCash(!cash) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Payments, null, tint = MaterialTheme.status.good); Text("Cash received", Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); RadioButton(cash, { onCash(!cash) }) }
        Spacer(Modifier.height(20.dp))
        DarkButton(if (cash) "Cash received · continue" else "UPI received · continue", enabled = cash || link != null || dr.paidWith != null) { vm.driverPaid(if (cash) "cash" else "UPI") }
        Muted("Nothing to collect yet? Wait for the customer; their payment shows up here.", Modifier.padding(top = 8.dp), TextAlign.Center)
    }
}

@Composable
fun PinBoxes(value: String, modifier: Modifier = Modifier, onDone: () -> Unit = {}, onChange: (String) -> Unit) = BasicTextField(value, { onChange(it.filter(Char::isDigit).take(4)) }, modifier, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { onDone() }),
    decorationBox = { Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { (0 until 4).forEach { i -> Box(Modifier.size(52.dp).clip(MaterialTheme.shapes.small).border(2.dp, if (i == value.length) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primary.copy(alpha = 0.5f), MaterialTheme.shapes.small), contentAlignment = Alignment.Center) {
        Text(value.getOrNull(i)?.toString() ?: "", style = MaterialTheme.typography.headlineSmall) } } } })

/** Call button + "message …" pill that opens the chat. */
@Composable
fun MessageBar(hint: String, onCall: () -> Unit, onMessage: () -> Unit) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onCall), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Call, "Call", Modifier.size(20.dp)) }
    Row(Modifier.weight(1f).padding(start = 10.dp).height(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onMessage).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Muted(hint, Modifier.weight(1f)); Icon(Icons.AutoMirrored.Rounded.Send, "Message", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
}
