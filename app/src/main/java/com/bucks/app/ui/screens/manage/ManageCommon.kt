package com.bucks.app.ui.screens.manage

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.bucks.app.data.Picked
import com.bucks.app.data.Upload
import com.bucks.app.ui.MyListings
import com.bucks.app.ui.components.*
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import java.io.ByteArrayOutputStream

/* Shared bits for the Manage screens: category lists, details helpers, small composables. */

/** Every category a business can pick, across its service (ui/Services.kt SERVICE_CATALOG). Pharmacy is left out on purpose: selling medicines online needs its own licensing. */
internal val BUSINESS_CATEGORIES = com.bucks.app.ui.BUSINESS_SERVICES.flatMap { com.bucks.app.ui.serviceDef(it)!!.categories }
internal val SKILL_CATEGORIES = listOf("Plumber", "Electrician", "Tutor", "Doctor", "Carpenter", "Painter", "Cleaner", "Driver", "Designer", "Software developer", "Other")
internal val LANGUAGES = listOf("Kannada", "English", "Hindi", "Tamil", "Telugu", "Malayalam", "Urdu")
internal val LEVELS = listOf("Amateur", "Intermediate", "Expert")
internal val UNITS = listOf("1 kg", "500 g", "1 piece", "1 plate", "1 litre", "per hour", "per visit", "per day")
internal val VEHICLE_KINDS = listOf("AUTO" to "Auto", "CAB" to "Cab", "BIKE" to "Bike (delivery only)")
internal val NEEDED: Int get() = MyListings.NEEDED

internal fun JsonObject.str(k: String): String = (this[k] as? JsonPrimitive)?.contentOrNull ?: ""
internal fun JsonObject.bool(k: String): Boolean = (this[k] as? JsonPrimitive)?.booleanOrNull ?: false
internal fun JsonObject.int(k: String): Int? = (this[k] as? JsonPrimitive)?.intOrNull
internal fun JsonObject.strings(k: String): List<String> = (this[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()

internal fun kindLabel(kind: String) = when (kind) { "BUSINESS" -> "Business"; "SKILL" -> "Skill"; "DRIVER" -> "Driver"; "ASSET" -> "Asset"; else -> "Listing" }
internal fun vehicleKindLabel(k: String) = when (k) { "AUTO" -> "Auto"; "CAB" -> "Cab"; "BIKE" -> "Bike"; else -> k }
internal fun vehicleIcon(k: String): ImageVector = when (k) { "BIKE" -> Icons.Rounded.TwoWheeler; "AUTO" -> Icons.Rounded.ElectricRickshaw; else -> Icons.Rounded.LocalTaxi }
internal fun listingIcon(kind: String, category: String): ImageVector = when (kind) {
    "DRIVER" -> Icons.Rounded.LocalTaxi
    "BUSINESS" -> categoryIcon(category).let { if (it == Icons.Rounded.Handyman) Icons.Rounded.Storefront else it }
    "ASSET" -> assetIcon(category)
    else -> categoryIcon(category)
}
/** What a listing's online switch means to its owner. */
internal fun onlineLabel(kind: String, on: Boolean) = when (kind) {
    "BUSINESS" -> if (on) "Open for orders" else "Closed"
    "SKILL" -> if (on) "Taking requests" else "Not taking requests"
    "ASSET" -> if (on) "Available" else "Not available"
    else -> if (on) "Available" else "Unavailable"
}
internal fun roleLabel(role: String, vehicle: Boolean) = when (role) {
    "OWNER" -> "Owner"
    "ADMIN" -> if (vehicle) "Driver" else "Admin"
    "STORE_RIDER" -> "Store rider"
    else -> role
}
internal fun roleExplain(role: String, vehicle: Boolean) = when (role) {
    "OWNER" -> "Can do everything, including deleting it."
    "ADMIN" -> if (vehicle) "Can go online with this vehicle and take rides or deliveries." else "Runs it with you: edits details, products, accepts orders and posts jobs. Cannot delete it or invite people."
    "STORE_RIDER" -> "Delivers your orders. Cash-on-delivery orders go only to store riders."
    else -> ""
}

/** A photo from a public bucket, or an icon on a tinted square when there is none. */
@Composable
internal fun PhotoOrIcon(url: String?, icon: ImageVector, size: Int = 56, shape: Shape = MaterialTheme.shapes.medium) {
    if (url.isNullOrBlank()) Box(Modifier.size(size.dp).clip(shape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Icon(icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size((size * 0.5).dp)) }
    else AsyncImage(url, null, Modifier.size(size.dp).clip(shape).background(MaterialTheme.colorScheme.surfaceContainer), contentScale = ContentScale.Crop)
}

/**
 * A listing or product photo as JPEG. Upload.read leaves GIFs untouched (chat wants them animated), but the listing-media
 * bucket only takes JPEG, PNG and WebP, so a GIF's first frame is re-encoded here; null when it cannot be decoded.
 */
internal fun Picked.asListingPhoto(): Picked? {
    if (mime != "image/gif") return this
    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    val out = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 82, it) }.toByteArray()
    return Picked(out, name.substringBeforeLast('.') + ".jpg", "image/jpeg")
}

/** Opens the system photo picker; [onPicked] gets the compressed bytes and the preview URI, [onUnusable] runs when the file cannot be read. Returns the launch action. */
@Composable
internal fun rememberImagePicker(onUnusable: () -> Unit = {}, onPicked: (Picked, Uri) -> Unit): () -> Unit {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { u -> Upload.read(ctx, u)?.asListingPhoto()?.let { onPicked(it, u) } ?: onUnusable() } }
    return { launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
}

/** The hub could not load (no network, expired session): say so and offer a retry, never an empty state that invites a duplicate listing. */
@Composable
internal fun LoadError(message: String, modifier: Modifier = Modifier, onRetry: () -> Unit) {
    BucksCard(modifier) {
        Text("Couldn't load your listings", style = MaterialTheme.typography.titleMedium)
        Muted(message, Modifier.padding(top = 4.dp))
        SmallButton("Try again", Modifier.padding(top = 12.dp), tonal = true, onClick = onRetry)
    }
}

/** Current photo (or the newly picked one) with Add / Change / Remove. */
@Composable
internal fun PhotoField(label: String, url: String?, preview: Uri?, icon: ImageVector, onPick: () -> Unit, onClear: (() -> Unit)? = null) {
    Column(Modifier.padding(bottom = 14.dp)) {
        Label(label)
        Row(verticalAlignment = Alignment.CenterVertically) {
            val model: Any? = preview ?: url?.takeIf { it.isNotBlank() }
            if (model == null) Box(Modifier.size(72.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onPick), contentAlignment = Alignment.Center) { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(30.dp)) }
            else AsyncImage(model, null, Modifier.size(72.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onPick), contentScale = ContentScale.Crop)
            Column(Modifier.padding(start = 14.dp)) {
                SmallButton(if (model == null) "Add photo" else "Change photo", tonal = true, onClick = onPick)
                if (preview != null && onClear != null) TextButton(onClick = onClear, contentPadding = PaddingValues(0.dp)) { Text("Remove") }
            }
        }
    }
}

/** A labelled switch row used in the edit forms. */
@Composable
internal fun SwitchRow(title: String, detail: String?, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) { Text(title, style = MaterialTheme.typography.bodyLarge); if (detail != null) Muted(detail) }
        Switch(checked = on, onCheckedChange = onChange)
    }
}

/** Yes / no before anything is deleted. */
@Composable
internal fun ConfirmDialog(title: String, text: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) =
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(text) },
        confirmButton = { TextButton({ onDismiss(); onConfirm() }) { Text(confirm, color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } })

/** A short explanation with a title and an icon, for empty states and rules. */
@Composable
internal fun InfoRow(icon: ImageVector, title: String, detail: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.Top) {
        Avatar(icon = icon, size = 40)
        Column(Modifier.weight(1f).padding(start = 12.dp)) { Text(title, style = MaterialTheme.typography.titleSmall); Muted(detail) }
    }
}

@Composable
internal fun CenteredLoading() = Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { BucksLoader() }

/** The rules for who may recommend a listing, in plain words. Shown on both recommendation screens. */
@Composable
internal fun RecommendRules() {
    InfoRow(Icons.Rounded.Home, "Lives within 3 km", "Their home on Bucks must be near where the listing is.")
    InfoRow(Icons.Rounded.CalendarMonth, "Account older than 14 days", "New accounts can't recommend yet.")
    InfoRow(Icons.Rounded.QrCodeScanner, "Scanned in person", "They must be standing near the shop or worker while scanning. Photos of the code don't work.")
    InfoRow(Icons.Rounded.Groups, "Not part of the team", "Owners, admins and store riders can't recommend their own listing.")
}
