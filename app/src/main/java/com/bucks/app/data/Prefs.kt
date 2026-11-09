package com.bucks.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.StringRes
import com.bucks.app.R
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Appearance and data preferences. These stay on the phone (they describe this device, not the
 * person), so they work signed out and in demo mode. Privacy and notification settings live in
 * Supabase (user_settings) because the server enforces them.
 */
object Prefs {
    enum class Theme(@StringRes private val labelRes: Int) { SYSTEM(R.string.g1_theme_system), LIGHT(R.string.g1_theme_light), DARK(R.string.g1_theme_dark); val label: String get() = Str.get(labelRes) }
    enum class TextSize(@StringRes private val labelRes: Int, val scale: Float) { SMALL(R.string.g1_text_small, 0.9f), NORMAL(R.string.g1_text_normal, 1f), LARGE(R.string.g1_text_large, 1.15f), HUGE(R.string.g1_text_huge, 1.3f); val label: String get() = Str.get(labelRes) }
    enum class MediaDownload(@StringRes private val labelRes: Int) { WIFI(R.string.g1_media_wifi), ALWAYS(R.string.g1_media_always), NEVER(R.string.g1_media_ask); val label: String get() = Str.get(labelRes) }

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
        sp.getString("country", null)?.let { Money.country = Countries.of(it) }
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
    /** The one-time "counts show after you vote" hint was seen (dismissed, or the person voted). */
    var voteHintSeen: Boolean
        get() = if (::sp.isInitialized) sp.getBoolean("vote_hint_seen", false) else true
        set(v) { if (::sp.isInitialized) sp.edit().putBoolean("vote_hint_seen", v).apply() }
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
    /** App language: applied through AppCompat (see data/Locales.kt); kept here too so the server profile can be told. */
    fun chooseLanguage(tag: String) { language = tag; languageChosen = true; sp.edit().putString("language", tag).putBoolean("languageChosen", true).apply(); AppLanguages.apply(tag) }
    /** Onboarding: the language screen shows until a language is picked once. */
    var languageChosen: Boolean get() = ::sp.isInitialized && sp.getBoolean("languageChosen", false); private set(v) { sp.edit().putBoolean("languageChosen", v).apply() }
    /** The country picked at sign-in (ISO code), or null before that; drives the dial code, currency and UPI. */
    var countryIso: String? get() = if (::sp.isInitialized) sp.getString("country", null) else null; set(v) { sp.edit().putString("country", v).apply(); v?.let { Money.country = Countries.of(it) } }
    /** The terms version accepted on the phone screen (sent to the server after sign-in), or null. */
    var acceptedTerms: String? get() = if (::sp.isInitialized) sp.getString("acceptedTerms", null) else null; set(v) { sp.edit().putString("acceptedTerms", v).apply() }
    /** Set when a date of birth under 18 was entered: sign-up stays closed on this phone (no back-button retry). */
    var ageBlocked: Boolean get() = ::sp.isInitialized && sp.getBoolean("ageBlocked", false); set(v) { sp.edit().putBoolean("ageBlocked", v).apply() }
    /** Launches since install: the notification prompt waits for the second visit instead of greeting a new person. */
    val launches: Int get() = if (::sp.isInitialized) sp.getInt("launches", 0) else 0
    fun countLaunch() { if (::sp.isInitialized) sp.edit().putInt("launches", launches + 1).apply() }
}
