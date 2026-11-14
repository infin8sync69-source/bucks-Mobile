package com.bucks.app.data

import androidx.annotation.StringRes
import com.bucks.app.R

enum class ProviderType { BUSINESS, SKILL }
enum class Scope { LOCAL, GLOBAL }
enum class VehicleKind(val wheels: String, @StringRes private val labelRes: Int, val farePerKm: Int) {
    BIKE("2", R.string.g3_vehicle_bike, 8), AUTO("3", R.string.g3_vehicle_auto, 12), CAB("4", R.string.g3_vehicle_cab, 18);
    val label: String get() = Str.get(labelRes)
    /** Bikes carry goods only (pick-up and delivery), never passengers. */
    val carriesPassengers get() = this != BIKE
    companion object { val PASSENGER = entries.filter { it.carriesPassengers } }
}

data class Trust(val up: Int, val down: Int) {
    val total get() = up + down
    val pct: Int? get() = if (total == 0) null else (up * 100) / total
}

/** A vote is a signed record tied to a completed transaction; the comment is public. */
data class Comment(val who: String, val text: String, val vote: Int, val voterId: String = "", val verified: Boolean = false, val txnId: String = "", val signature: String = "")
enum class BusinessVariant(@StringRes private val productsRes: Int) {
    RESTAURANT(R.string.g3_variant_menu), SUPERMARKET(R.string.g3_variant_aisles), FURNITURE(R.string.g3_variant_catalogue), ELECTRONICS(R.string.g3_variant_products), GENERAL(R.string.g3_variant_products);
    val productsLabel: String get() = Str.get(productsRes)
}
fun variantFor(category: String): BusinessVariant = when (category.lowercase()) {
    "restaurant", "bakery" -> BusinessVariant.RESTAURANT; "grocery", "vegetables", "pharmacy" -> BusinessVariant.SUPERMARKET
    "furniture", "hardware" -> BusinessVariant.FURNITURE; "electronics", "mobile repair" -> BusinessVariant.ELECTRONICS; else -> BusinessVariant.GENERAL
}
/** tag: "Veg"/"Non-veg" for restaurants, aisle for supermarkets, material/brand for others. detail: unit, size, warranty… */
/** mrp: list price before discount (0 = no discount shown); image: optional photo URL. */
data class Item(val name: String, val price: Int, val tag: String = "", val detail: String = "", val group: String = "", val mrp: Int = 0, val image: String = "")

data class Provider(
    val id: String, val type: ProviderType, val category: String, val name: String,
    val tags: List<String>, val x: Float, val y: Float, val distanceKm: Double,
    val up: Int, val down: Int, val scope: Scope, val bio: String,
    val items: List<Item> = emptyList(), val rate: String? = null, val comments: List<Comment> = emptyList(),
) {
    val trust get() = Trust(up, down)
    val pos: LatLng get() = Geo.fromPercent(x, y)
    val phone: String get() = "+91 98450 ${10000 + Math.floorMod(id.hashCode(), 90000)}"
    val minPrice: Int get() = if (items.isNotEmpty()) items.minOf { it.price } else rate?.filter { it.isDigit() }?.toIntOrNull() ?: 9999
}

data class Driver(
    val id: String, val name: String, val vehicle: VehicleKind, val plate: String, val model: String,
    val x: Float, val y: Float, val distanceKm: Double, val up: Int, val down: Int, val online: Boolean, val phone: String = "",
    /** Real position (cloud builds). x/y are the demo's Bengaluru grid, which clamps anything outside it to its edge. */
    val at: LatLng? = null,
) { val trust get() = Trust(up, down); val pos: LatLng get() = at ?: Geo.fromPercent(x, y) }

data class Post(
    val id: String, val who: String, val ago: String, val text: String,
    val hasImage: Boolean = false, val file: String? = null, val up: Int, val down: Int,
    val comments: List<Pair<String, String>> = emptyList(),
    /** Content URIs of an attached photo / file (posts made on this device). */
    val image: String? = null, val attachment: Attachment? = null, val at: Long = System.currentTimeMillis(),
)

data class Attachment(val uri: String, val name: String, val isImage: Boolean)
data class ChatMessage(val mine: Boolean, val text: String, val attachment: Attachment? = null, val at: Long = System.currentTimeMillis())
data class Chat(val id: String, val who: String, val role: String, val messages: List<ChatMessage>, val unread: Int, val online: Boolean, val phone: String = "+91 98450 00000")

/** Someone nearby you can follow. Following only affects what you see in Discover; it never changes rankings. */
data class Person(val id: String, val name: String, val area: String, val tagline: String, val up: Int, val down: Int, val following: Boolean = false, val distanceKm: Double) { val trust get() = Trust(up, down) }
data class Community(val id: String, val name: String, val description: String, val members: Int, val joined: Boolean = false)

enum class SyncStatus { SYNCED, SYNCING, OFFLINE }
data class LinkedDevice(val id: String, val name: String, val lastSeen: String, val thisDevice: Boolean)

data class User(val name: String, val area: String, val bio: String, val phone: String, val up: Int = 0, val down: Int = 0, val email: String = "", val gender: String = "", val interests: List<String> = emptyList(), val id: String = "", val verified: Set<VerificationLevel> = emptySet()) { val trust get() = Trust(up, down) }
enum class ListingMode(@StringRes private val labelRes: Int) {
    TAXI(R.string.g3_mode_taxi), RENTAL(R.string.g3_mode_rental), DELIVERY(R.string.g3_mode_delivery);
    val label: String get() = Str.get(labelRes)
}
/** A listed vehicle. Unverified vehicles show "In Progress" until the community confirms their documents. */
data class Vehicle(val kind: VehicleKind, val model: String, val plate: String, val mode: ListingMode = ListingMode.TAXI, val verified: Boolean = true, val docs: Int = 0) { val id get() = plate }
enum class SkillLevel(@StringRes private val labelRes: Int) {
    AMATEUR(R.string.g3_skill_amateur), INTERMEDIATE(R.string.g3_skill_intermediate), EXPERT(R.string.g3_skill_expert);
    val label: String get() = Str.get(labelRes)
}
data class SkillListing(val name: String, val level: SkillLevel = SkillLevel.AMATEUR, val portfolio: Int = 0, val online: Boolean = true)
data class ProProfile(val vehicles: List<Vehicle> = emptyList(), val skillListings: List<SkillListing> = emptyList(), val rate: String = "", val activeVehicle: String? = null, val upiId: String = "") {
    /** The vehicle used for driver mode: the chosen one if verified, else the first verified one. */
    val vehicle: Vehicle? get() = vehicles.firstOrNull { it.id == activeVehicle && it.verified } ?: vehicles.firstOrNull { it.verified }
    val skills: List<String> get() = skillListings.map { it.name }
}
data class Business(val name: String, val category: String, val scope: Scope, val items: List<Item>, val online: Boolean = true, val area: String = "", val followers: Int = 0)

/** A destination. [x]/[y] place it on the drawn map (clamped to its edges); [at] is the real point when known, and is what a ride is booked to. */
data class Place(val name: String, val x: Float, val y: Float, val km: Double, val at: LatLng? = null)

enum class RideStatus { SEARCHING, MATCHED, ARRIVED, IN_RIDE, COMPLETED, PAID, NO_DRIVER, CANCELLED }
data class Ride(
    val id: String, val kind: VehicleKind, val dest: Place, val fare: Int, val status: RideStatus,
    val pin: String, val driver: Driver? = null, val driverX: Float = 0f, val driverY: Float = 0f,
    val etaMin: Int = 0, val progress: Float = 0f, val paidWith: String? = null, val reason: String? = null, val signature: String = "",
    /** Where the driver really is (cloud builds); driverX/driverY stay for the demo's simulated drive. */
    val driverAt: LatLng? = null,
    /** Where the rider was picked up, as named when booked (cloud builds). */
    val pickupLabel: String = "",
)

/** DONE = collect payment; RATE = rate the customer. */
enum class DriverRideStatus { RINGING, TO_PICKUP, ARRIVED, IN_RIDE, DONE, RATE }
data class DriverRide(
    val id: String, val status: DriverRideStatus, val customer: String, val customerTrust: Trust,
    val pickupAt: String, val dropAt: String, val km: Double, val fare: Int, val pin: String, val secondsLeft: Int, val pickupKm: Double,
    val kind: VehicleKind = VehicleKind.BIKE, val driver: LatLng? = null, val pickup: LatLng? = null, val drop: LatLng? = null, val progress: Float = 0f, val paidWith: String? = null, val customerPhone: String = "",
    /** Wrong PINs tried at the pick-up (the server locks the trip at 5); in cloud builds only. */
    val pinAttempts: Int = 0, val pinLocked: Boolean = false,
)

enum class OrderStatus(@StringRes private val labelRes: Int) {
    REQUESTED(R.string.g3_order_requested), ACCEPTED(R.string.g3_order_accepted), PREPARING(R.string.g3_order_preparing), OUT(R.string.g3_order_out), DELIVERED(R.string.g3_order_delivered);
    val label: String get() = Str.get(labelRes)
}
data class Order(val id: String, val providerId: String, val providerName: String, val total: Int, val items: List<String>, val status: OrderStatus, val signature: String = "")

enum class RequestStatus(@StringRes private val labelRes: Int) {
    SENT(R.string.g3_request_sent), ACCEPTED(R.string.g3_request_accepted), IN_PROGRESS(R.string.g3_request_in_progress), COMPLETED(R.string.g3_request_completed);
    val label: String get() = Str.get(labelRes)
}
data class ServiceRequest(val id: String, val providerId: String, val providerName: String, val category: String, val text: String, val status: RequestStatus, val signature: String = "")

/** Which voters count when a list is sorted. Pure counting over a user-chosen voter set; never a hidden model. */
enum class Lens(@StringRes private val labelRes: Int, @StringRes private val explainRes: Int) {
    ALL(R.string.g3_lens_all, R.string.g3_lens_all_explain), FOLLOWING(R.string.g3_lens_following, R.string.g3_lens_following_explain), VERIFIED(R.string.g3_lens_verified, R.string.g3_lens_verified_explain);
    val label: String get() = Str.get(labelRes)
    val explain: String get() = Str.get(explainRes)
}

/** An action the agent proposed that needs the user's explicit go-ahead before it runs. */
data class PendingAction(val title: String, val summary: String, val amount: Int, val counterparty: String, val counterpartyTrust: Trust?, val needsBiometric: Boolean, val run: () -> Unit)

data class Incoming(val who: String, val text: String)

data class AgentCard(val title: String, val detail: String, val cta: String, val action: AgentAction)
sealed interface AgentAction {
    data class OpenProvider(val id: String, val tab: String? = null) : AgentAction
    data class Request(val providerId: String) : AgentAction
}
data class AgentMessage(val mine: Boolean, val text: String, val cards: List<AgentCard> = emptyList(), val actions: List<String> = emptyList())
