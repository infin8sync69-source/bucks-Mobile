package com.bucks.app.data

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import java.util.Locale

/**
 * Translated text outside composables (view model toasts, labels built in data classes). Inside a @Composable use
 * stringResource(R.string.x) instead. Reads the language chosen in the app (AppLanguages), which below Android 13 the application
 * context alone wouldn't reflect.
 */
object Str {
    private lateinit var app: Context
    private var cached: Pair<String, Context>? = null
    fun init(ctx: Context) { app = ctx.applicationContext }

    private fun ctx(): Context {
        val tag = AppLanguages.current().tag
        cached?.takeIf { it.first == tag }?.let { return it.second }
        val conf = Configuration(app.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) }
        return app.createConfigurationContext(conf).also { cached = tag to it }
    }

    // Before init (JVM unit tests, very early startup) there are no resources: an empty string instead of a crash.
    fun get(@StringRes id: Int, vararg args: Any): String { if (!::app.isInitialized) return ""
        return if (args.isEmpty()) ctx().getString(id) else ctx().getString(id, *args) }
    fun plural(@PluralsRes id: Int, count: Int, vararg args: Any): String { if (!::app.isInitialized) return ""
        return ctx().resources.getQuantityString(id, count, *(if (args.isEmpty()) arrayOf<Any>(count) else args)) }
}
