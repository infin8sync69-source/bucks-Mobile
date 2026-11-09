package com.bucks.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Appearance and data preferences. These stay on the phone (they describe this device, not the
 * person), so they work signed out and in demo mode. Privacy and notification settings live in
 * Supabase (user_settings) because the server enforces them.
 */
object Prefs {
    enum class Theme(val label: String) { SYSTEM("Match phone"), LIGHT("Light"), DARK("Dark") }
    enum class TextSize(val label: String, val scale: Float) { SMALL("Small", 0.9f), NORMAL("Normal", 1f), LARGE("Large", 1.15f), HUGE("Huge", 1.3f) }
    enum class MediaDownload(val label: String) { WIFI("Wi-Fi only"), ALWAYS("Always"), NEVER("Ask each time") }

    private lateinit var sp: SharedPreferences
    fun init(ctx: Context) {
        sp = ctx.getSharedPreferences("bucks_prefs", Context.MODE_PRIVATE)
        theme = runCatching { Theme.valueOf(sp.getString("theme", null) ?: "") }.getOrDefault(Theme.SYSTEM)
        textSize = runCatching { TextSize.valueOf(sp.getString("text", null) ?: "") }.getOrDefault(TextSize.NORMAL)
        mediaDownload = runCatching { MediaDownload.valueOf(sp.getString("media", null) ?: "") }.getOrDefault(MediaDownload.WIFI)
        reduceMotion = sp.getBoolean("reduceMotion", false)
        dataSaver = sp.getBoolean("dataSaver", false)
        language = sp.getString("language", "en") ?: "en"
        askedLocationFlag = sp.getBoolean("askedLocation", false)
        shareUsage = sp.getBoolean("shareUsage", true)
    }

    var theme by mutableStateOf(Theme.SYSTEM); private set
    var textSize by mutableStateOf(TextSize.NORMAL); private set
    var mediaDownload by mutableStateOf(MediaDownload.WIFI); private set
    var reduceMotion by mutableStateOf(false); private set
    var dataSaver by mutableStateOf(false); private set
    var language by mutableStateOf("en"); private set

    /** How I last had a shop's order delivered (MARKETPLACE, STORE_RIDER, PICKUP, SHIP) and paid (UPI, COD): preselected next time. */
    fun checkoutMode(listingId: String): String? = if (::sp.isInitialized) sp.getString("mode_$listingId", null) else null
    fun checkoutPayment(listingId: String): String? = if (::sp.isInitialized) sp.getString("pay_$listingId", null) else null
    fun rememberCheckout(listingId: String, mode: String, payment: String) { if (::sp.isInitialized) sp.edit().putString("mode_$listingId", mode).putString("pay_$listingId", payment).apply() }
    /** The cart, kept across app restarts (JSON; prices are checked again by the server when the order is placed). */
    var cartJson: String?
        get() = if (::sp.isInitialized) sp.getString("cart", null) else null
        set(v) { if (::sp.isInitialized) sp.edit().apply { if (v == null) remove("cart") else putString("cart", v) }.apply() }
    /** The store rider a shop last sent, preselected the next time it chooses one (per listing, on this phone). */
    fun lastRider(listingId: String): String? = if (::sp.isInitialized) sp.getString("rider_$listingId", null) else null
    fun rememberRider(listingId: String, riderId: String) { if (::sp.isInitialized) sp.edit().putString("rider_$listingId", riderId).apply() }
    fun chooseTheme(t: Theme) { theme = t; sp.edit().putString("theme", t.name).apply() }
    fun chooseTextSize(t: TextSize) { textSize = t; sp.edit().putString("text", t.name).apply() }
    fun chooseMediaDownload(m: MediaDownload) { mediaDownload = m; sp.edit().putString("media", m.name).apply() }
    fun enableReduceMotion(v: Boolean) { reduceMotion = v; sp.edit().putBoolean("reduceMotion", v).apply() }
    fun enableDataSaver(v: Boolean) { dataSaver = v; sp.edit().putBoolean("dataSaver", v).apply() }
    /** The location explainer was shown once (Continue or Not now); after that the system prompt or Settings decides. */
    private var askedLocationFlag = false
    var askedLocation: Boolean get() = askedLocationFlag; set(v) { askedLocationFlag = v; sp.edit().putBoolean("askedLocation", v).apply() }
    /** Adults can turn off usage analytics (Settings → Appearance and data). Under-18s are never tracked, whatever this says. */
    var shareUsage by mutableStateOf(true); private set
    fun enableShareUsage(v: Boolean) { shareUsage = v; sp.edit().putBoolean("shareUsage", v).apply() }
    fun chooseLanguage(tag: String) { language = tag; sp.edit().putString("language", tag).apply() }

    val LANGUAGES = listOf("en" to "English", "kn" to "ಕನ್ನಡ", "hi" to "हिन्दी", "ta" to "தமிழ்", "te" to "తెలుగు", "ml" to "മലയാളം")
}
