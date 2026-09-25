package com.bucks.app.ui.nav

import android.net.Uri

object Routes {
    const val SPLASH = "splash"; const val LOGIN = "login"; const val OTP = "otp"; const val SIGNUP_EMAIL = "signupEmail"; const val PROFILE = "profile"
    const val HOME = "home"; const val FEED = "feed"; const val SERVICES = "services"; const val RECOMMENDED = "recommended"; const val ACCOUNT = "account"; const val ACTIVITY = "account?tab=activity"
    const val SEARCH = "search"; const val PROVIDER = "provider/{id}"; const val CART = "cart"; const val ORDER = "order/{id}"; const val REQUEST = "request/{id}"; const val REQUEST_STATUS = "requestStatus/{id}"
    const val DESTINATION = "destination"; const val CHOOSE_RIDE = "chooseRide"; const val CONFIRM_PICKUP = "confirmPickup"; const val SEARCHING = "searching"; const val DRIVER_FOUND = "driverFound"; const val IN_RIDE = "inRide"; const val PAY = "pay"; const val RATE_RIDE = "rateRide"
    const val PRO_CREATE = "proCreate"; const val LISTINGS = "listings"; const val VEHICLE_FORM = "vehicle"; const val ADD_SKILL = "skill"; const val EARNINGS = "earnings"
    const val MESSAGES = "messages"; const val CREATE_POST = "post/new"; const val CHAT = "chat/{id}"
    fun provider(id: String, tab: String? = null) = "provider/${Uri.encode(id)}" + (if (tab != null) "?tab=$tab" else "")
    fun order(id: String) = "order/${Uri.encode(id)}"
    fun request(id: String) = "request/${Uri.encode(id)}"
    fun requestStatus(id: String) = "requestStatus/${Uri.encode(id)}"
    fun chat(id: String) = "chat/${Uri.encode(id)}"
}
