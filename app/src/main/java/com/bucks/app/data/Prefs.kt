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
    }

    var theme by mutableStateOf(Theme.SYSTEM); private set
    var textSize by mutableStateOf(TextSize.NORMAL); private set
    var mediaDownload by mutableStateOf(MediaDownload.WIFI); private set
    var reduceMotion by mutableStateOf(false); private set
    var dataSaver by mutableStateOf(false); private set
    var language by mutableStateOf("en"); private set

    fun setTheme(t: Theme) { theme = t; sp.edit().putString("theme", t.name).apply() }
    fun setTextSize(t: TextSize) { textSize = t; sp.edit().putString("text", t.name).apply() }
    fun setMediaDownload(m: MediaDownload) { mediaDownload = m; sp.edit().putString("media", m.name).apply() }
    fun setReduceMotion(v: Boolean) { reduceMotion = v; sp.edit().putBoolean("reduceMotion", v).apply() }
    fun setDataSaver(v: Boolean) { dataSaver = v; sp.edit().putBoolean("dataSaver", v).apply() }
    fun setLanguage(tag: String) { language = tag; sp.edit().putString("language", tag).apply() }

    val LANGUAGES = listOf("en" to "English", "kn" to "ಕನ್ನಡ", "hi" to "हिन्दी", "ta" to "தமிழ்", "te" to "తెలుగు", "ml" to "മലയാളം")
}
