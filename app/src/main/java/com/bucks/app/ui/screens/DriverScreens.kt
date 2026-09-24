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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
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
import com.bucks.app.ui.components.*
import com.bucks.app.ui.theme.Bad
import com.bucks.app.ui.theme.Brand
import com.bucks.app.ui.theme.Good
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** Pickup (green dot) / drop (red dot) rows used by both sides of a ride. */
@Composable
fun RoutePoints(pickup: String, drop: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) = Column(modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 12.dp, vertical = 8.dp)) {
    listOf(pickup to Good, drop to Bad).forEach { (t, c) -> Row(Modifier.padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(c)); Text(t, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f).padding(start = 10.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (c == Good) trailing?.invoke() } }
}

@Composable
fun TrustMini(up: Int) = Row(Modifier.clip(CircleShape).background(Good.copy(alpha = 0.12f)).padding(horizontal = 5.dp), verticalAlignment = Alignment.CenterVertically) { Text("$up ↑", fontSize = 9.sp, color = Good) }

private fun metres(km: Double) = if (km < 1) "${(km * 1000).toInt()}m" else "${km}km"

/** The incoming ride card on Home (driver online). Accept before the countdown runs out. */
@Composable
fun RideRequestCard(dr: DriverRide, onAccept: () -> Unit, onDecline: () -> Unit, modifier: Modifier = Modifier) {
    Surface(modifier.fillMaxWidth().padding(horizontal = 16.dp), shape = RoundedCornerShape(16.dp), border = BorderStroke(2.dp, Brand), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { BrandPill(dr.kind.label); Spacer(Modifier.weight(1f)); IconButton(onDecline, Modifier.size(28.dp)) { Icon(Icons.Rounded.Close, "Decline") } }
            Text("₹${dr.fare}", style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(top = 8.dp))
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Avatar(initials(dr.customer), size = 36); TrustMini(dr.customerTrust.up) }
                Text(dr.customer, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 10.dp)) }
            RoutePoints(dr.pickupAt, dr.dropAt)
            Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) { Muted("Pickup: ${metres(dr.pickupKm)}"); Muted("Drop: ${dr.km}km") }
            // Accept button doubles as the countdown: the darker part shrinks as time runs out.
            Box(Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(8.dp)).background(Brand.copy(alpha = 0.55f)).clickable(onClick = withHaptic(onAccept))) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(dr.secondsLeft / 15f).background(Brand))
                Text("Accept · ${dr.secondsLeft}s", color = Color.White, style = MaterialTheme.typography.labelLarge, modifier = Modifier.align(Alignment.Center))
            }
        }
    }
}

/** Round "bucks" button shown on Home while any listing is online. */
@Composable
fun OnlineFab(modifier: Modifier = Modifier, onClick: () -> Unit) = Box(modifier.size(72.dp).shadow(10.dp, CircleShape).clip(CircleShape).background(Brand).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
    Text("bucks", color = Color.White, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp)) }

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
        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (s.vehicleOnline) TintButton("Simulate a ride request", Modifier.weight(1f)) { onDismiss(); vm.simulateRing() }
            if (s.businesses.any { it.online } || s.pro?.skillListings?.any { it.online } == true) TintButton("Simulate an order", Modifier.weight(1f)) { onDismiss(); vm.simulateIncoming() } }
    } }
}

@Composable
private fun OnlineRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String, on: Boolean, onToggle: (Boolean) -> Unit) = Row(verticalAlignment = Alignment.CenterVertically) {
    ListingThumb(icon, size = 44); Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis); Muted(detail) }; ListingSwitch(on, onToggle) }

private fun qr(text: String, size: Int = 512): Bitmap { val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    return Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565).apply { for (x in 0 until size) for (y in 0 until size) setPixel(x, y, if (m[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE) } }

/** Driver's active trip: to pick-up → PIN → drop → payment → rate customer. */
@Composable
fun DriverTripScreen(vm: BucksViewModel, onChatWith: (String, String) -> Unit, onCall: (String, String) -> Unit) {
    val s by vm.state.collectAsState(); val dr = s.driverRide ?: return
    var pin by remember(dr.id) { mutableStateOf("") }; var cash by remember(dr.id) { mutableStateOf(false) }; var stars by remember(dr.id) { mutableIntStateOf(0) }; var cancel by remember { mutableStateOf(false) }
    val me = dr.driver ?: Geo.CENTER; val pickup = dr.pickup ?: me; val drop = dr.drop ?: me
    fun lerp(a: LatLng, b: LatLng, t: Float) = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
    val (from, to, car) = when (dr.status) {
        DriverRideStatus.TO_PICKUP -> Triple(me, pickup, lerp(me, pickup, dr.progress))
        DriverRideStatus.ARRIVED -> Triple(pickup, pickup, pickup)
        else -> Triple(pickup, drop, lerp(pickup, drop, dr.progress)) }
    Column(Modifier.fillMaxSize().imePadding()) {
        if (dr.status != DriverRideStatus.DONE) Box(Modifier.weight(1f).fillMaxWidth()) {
            BucksMap(Modifier.fillMaxSize(), listOf(pinAt(car, "You", MeColor, true), pinAt(to, "", Brand)), route = if (from != to && car != to) listOf(car, to) else emptyList())
            MapAttribution(Modifier.align(Alignment.BottomStart).padding(8.dp))
        }
        Surface(Modifier.fillMaxWidth().then(if (dr.status == DriverRideStatus.DONE) Modifier.weight(1f) else Modifier), color = MaterialTheme.colorScheme.surface, shadowElevation = 12.dp, shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)) {
            Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when (dr.status) {
                    DriverRideStatus.TO_PICKUP -> {
                        Text(dr.customer, style = MaterialTheme.typography.titleMedium)
                        Row(Modifier.padding(top = 4.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) { Muted("${maxOf(1, ((1 - dr.progress) * dr.pickupKm * 4).toInt())} mins"); Muted("Pickup: ${metres(dr.pickupKm * (1 - dr.progress))}") }
                        MessageBar("Message your customer", onCall = { onCall(dr.customer, "+91 98450 00000") }) { onChatWith(dr.customer, "Customer") }
                        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) { TextButton({ cancel = true }) { Text("Cancel ride", color = Bad) }; TextButton({ vm.driverNext() }) { Text("I've arrived", color = Brand) } }
                    }
                    DriverRideStatus.ARRIVED -> {
                        Text("Enter Customer's Pin", style = MaterialTheme.typography.titleMedium)
                        PinBoxes(pin, Modifier.padding(top = 20.dp, bottom = 8.dp), onDone = { if (pin.length == 4 && vm.driverNext(pin)) pin = "" }) { pin = it }
                        Muted("Demo build: the customer's PIN is ${dr.pin}", Modifier.padding(bottom = 14.dp))
                        DarkButton("Confirm Pin", enabled = pin.length == 4) { if (vm.driverNext(pin)) pin = "" }
                    }
                    DriverRideStatus.IN_RIDE -> {
                        Text(dr.customer, style = MaterialTheme.typography.titleMedium)
                        Muted(if (dr.progress >= 1f) "Arrived at destination" else "On the way to ${dr.dropAt}", Modifier.padding(top = 4.dp))
                        Muted(if (dr.progress >= 1f) "Dropping off" else "${"%.1f".format((1 - dr.progress) * dr.km)} km left", Modifier.padding(bottom = 14.dp))
                        DarkButton("End ride") { vm.driverNext() }
                    }
                    DriverRideStatus.DONE -> PaymentPanel(vm, dr, cash) { cash = it }
                    DriverRideStatus.RATE -> {
                        Text("Rate your customer", style = MaterialTheme.typography.titleMedium)
                        Avatar(initials(dr.customer), size = 48); Text(dr.customer, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 6.dp))
                        Row(Modifier.padding(vertical = 14.dp)) { (1..5).forEach { i -> IconButton({ stars = i }) { Icon(if (i <= stars) Icons.Filled.Star else Icons.Rounded.StarOutline, "$i star${if (i > 1) "s" else ""}", Modifier.size(34.dp), tint = if (i <= stars) Color(0xFF15111C) else MaterialTheme.colorScheme.onSurfaceVariant) } } }
                        DarkButton("Submit", enabled = stars > 0) { vm.driverRateCustomer(stars) }
                    }
                    DriverRideStatus.RINGING -> {}
                }
            }
        }
    }
    if (cancel) AlertDialog(onDismissRequest = { cancel = false }, title = { Text("Cancel this ride?") }, text = { Text("The customer goes to the next rider. Cancelling after accepting counts against your recommendations.") }, confirmButton = { TextButton(onClick = { cancel = false; vm.driverCancel() }) { Text("Cancel ride", color = Bad) } }, dismissButton = { TextButton(onClick = { cancel = false }) { Text("Keep ride") } })
}

@Composable
private fun PaymentPanel(vm: BucksViewModel, dr: DriverRide, cash: Boolean, onCash: (Boolean) -> Unit) {
    val s by vm.state.collectAsState(); val upi = s.pro?.upiId.orEmpty(); var entry by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Total payable ₹${dr.fare}", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
        if (upi.isNotBlank()) {
            // Standard UPI deep link: any UPI app can scan it and pay the driver directly.
            val link = "upi://pay?pa=${Uri.encode(upi)}&pn=${Uri.encode(s.user?.name ?: "Bucks driver")}&am=${dr.fare}&cu=INR&tn=${Uri.encode("Bucks ride ${dr.id.takeLast(6)}")}"
            val bmp = remember(link) { qr(link) }
            Box(Modifier.size(200.dp).border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(12.dp)).padding(10.dp)) { Image(bmp.asImageBitmap(), "UPI QR for ₹${dr.fare} to $upi", Modifier.fillMaxSize()) }
            Muted(upi, Modifier.padding(top = 6.dp))
        } else Column(Modifier.fillMaxWidth()) {
            Muted("Add your UPI ID to show a payment QR customers can scan.", Modifier.padding(bottom = 8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(entry, { entry = it }, placeholder = { Text("name@okaxis") }, singleLine = true, modifier = Modifier.weight(1f), shape = RoundedCornerShape(10.dp)); Spacer(Modifier.width(8.dp)); SmallButton("Save") { vm.setUpi(entry) } }
        }
        Row(Modifier.fillMaxWidth().padding(top = 24.dp).clip(RoundedCornerShape(10.dp)).border(1.dp, if (cash) Brand else MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp)).clickable { onCash(!cash) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Payments, null, tint = Good); Text("Pay Cash", Modifier.weight(1f).padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium); RadioButton(cash, { onCash(!cash) }, colors = RadioButtonDefaults.colors(selectedColor = Brand)) }
        Spacer(Modifier.height(20.dp))
        DarkButton("Proceed", enabled = cash || upi.isNotBlank()) { vm.driverPaid(if (cash) "cash" else "UPI") }
    }
}

@Composable
fun PinBoxes(value: String, modifier: Modifier = Modifier, onDone: () -> Unit = {}, onChange: (String) -> Unit) = BasicTextField(value, { onChange(it.filter(Char::isDigit).take(4)) }, modifier, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { onDone() }),
    decorationBox = { Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { (0 until 4).forEach { i -> Box(Modifier.size(52.dp).clip(RoundedCornerShape(8.dp)).border(2.dp, if (i == value.length) Brand else Brand.copy(alpha = 0.5f), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
        Text(value.getOrNull(i)?.toString() ?: "", style = MaterialTheme.typography.headlineSmall) } } } })

/** Call button + "message …" pill that opens the chat. */
@Composable
fun MessageBar(hint: String, onCall: () -> Unit, onMessage: () -> Unit) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onCall), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Call, "Call", Modifier.size(20.dp)) }
    Row(Modifier.weight(1f).padding(start = 10.dp).height(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onMessage).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Muted(hint, Modifier.weight(1f)); Icon(Icons.AutoMirrored.Rounded.Send, "Message", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
}
