package com.bucks.app.ui.nav

import android.net.Uri

object Routes {
    const val SPLASH = "splash"; const val LOGIN = "login"; const val OTP = "otp"; const val SIGNUP_EMAIL = "signupEmail"; const val PROFILE = "profile"
    const val HOME = "home"; const val FEED = "feed"; const val SERVICES = "services"; const val RECOMMENDED = "recommended"; const val ACCOUNT = "account"; const val ACTIVITY = "account?tab=activity"
    const val SEARCH = "search"; const val PROVIDER = "provider/{id}"; const val CART = "cart"; const val ORDER = "order/{id}"; const val REQUEST = "request/{id}"; const val REQUEST_STATUS = "requestStatus/{id}"
    const val DESTINATION = "destination"; const val CHOOSE_RIDE = "chooseRide"; const val CONFIRM_PICKUP = "confirmPickup"; const val SEARCHING = "searching"; const val DRIVER_FOUND = "driverFound"; const val IN_RIDE = "inRide"; const val PAY = "pay"; const val RATE_RIDE = "rateRide"
    const val PRO_CREATE = "proCreate"; const val LISTINGS = "listings"; const val VEHICLE_FORM = "vehicle"; const val ADD_SKILL = "skill"; const val EARNINGS = "earnings"
    const val SYNC = "sync"; const val MOMENTS = "moments/{author}"; const val MOMENT_NEW = "moment/new"
    const val SETTINGS_PRIVACY = "settings/privacy"; const val SETTINGS_NOTIFS = "settings/notifications"; const val SETTINGS_APPEARANCE = "settings/appearance"; const val SETTINGS_BLOCKED = "settings/blocked"; const val SETTINGS_CLOSE = "settings/close"
    fun moments(author: String) = "moments/${Uri.encode(author)}"
    // ---- cloud marketplace (reserved names; each feature owns its screens, see docs/FEATURE_CONTRACT.md) ----
    const val LISTING = "l/{id}"; fun listing(id: String) = "l/${Uri.encode(id)}"                       // universal profile: business / skill / driver
    const val MY_LISTINGS = "my/listings"; const val MY_VEHICLES = "my/vehicles"; const val VEHICLE_STATS = "my/vehicle-stats"
    /** The Studio's dashboard for one of my listings; BUCKS_ID is my ID card. */
    const val STUDIO_LISTING = "studio/{id}"; fun studioListing(id: String) = "studio/${Uri.encode(id)}"; const val BUCKS_ID = "bucks-id"; const val CONTACTS = "contacts"
    const val LISTING_EDIT = "edit-listing?id={id}&kind={kind}&service={service}"
    /** [service]: the Services tile a new business starts under (FOOD, GROCERY, ...), from "List it" on a locked tile. */
    fun listingEdit(id: String?, kind: String, service: String? = null) = "edit-listing?kind=$kind" + (id?.let { "&id=${Uri.encode(it)}" } ?: "") + (service?.let { "&service=$it" } ?: "")
    /** The documents a listing's service needs (services.sql). */
    const val LISTING_DOCS = "listing-docs/{id}"; fun listingDocs(id: String) = "listing-docs/${Uri.encode(id)}"
    /** Bucks staff: documents waiting for review. */
    const val STAFF_REVIEW = "staff/review"
    const val ITEM_EDIT = "edit-item/{listing}?item={item}"; fun itemEdit(listing: String, item: String?) = "edit-item/${Uri.encode(listing)}" + (item?.let { "?item=${Uri.encode(it)}" } ?: "")
    const val VEHICLE_EDIT = "edit-vehicle?id={id}"; fun vehicleEdit(id: String?) = "edit-vehicle" + (id?.let { "?id=${Uri.encode(it)}" } ?: "")
    const val RECOMMEND_SHOW = "recommend/{id}"; fun recommendShow(id: String) = "recommend/${Uri.encode(id)}"; const val RECOMMEND_SCAN = "recommend-scan"
    const val MEMBERS = "members/{id}"; fun members(id: String) = "members/${Uri.encode(id)}"; const val INVITES = "invites"
    const val CLOUD_CART = "cloud-cart"; const val CLOUD_ORDER = "cloud-order/{id}"; fun cloudOrder(id: String) = "cloud-order/${Uri.encode(id)}"
    const val MY_ORDERS = "my/orders"; const val VENDOR_ORDERS = "orders-for/{id}"; fun vendorOrders(id: String) = "orders-for/${Uri.encode(id)}"
    const val DELIVERY_TRACK = "delivery/{id}"; fun deliveryTrack(id: String) = "delivery/${Uri.encode(id)}"
    const val PAYMENT_QR = "my/payment-qr"
    const val LISTING_JOBS = "jobs-of/{id}"; fun listingJobs(id: String) = "jobs-of/${Uri.encode(id)}"; const val JOB = "job/{id}"; fun job(id: String) = "job/${Uri.encode(id)}"
    const val JOB_NEW = "new-job/{id}"; fun jobNew(id: String) = "new-job/${Uri.encode(id)}"; const val MY_APPLICATIONS = "my/applications"; const val JOBS_NEAR = "jobs-near"
    const val GROUP_NEW = "new-group"
    const val MESSAGES = "messages"; const val CREATE_POST = "post/new"; const val CHAT = "chat/{id}"
    fun provider(id: String, tab: String? = null) = "provider/${Uri.encode(id)}" + (if (tab != null) "?tab=$tab" else "")
    fun order(id: String) = "order/${Uri.encode(id)}"
    fun request(id: String) = "request/${Uri.encode(id)}"
    fun requestStatus(id: String) = "requestStatus/${Uri.encode(id)}"
    fun chat(id: String) = "chat/${Uri.encode(id)}"
}
