package com.bucks.app.ui

import android.content.Context
import com.bucks.app.BuildConfig
import com.bucks.app.data.AppUpdate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Invite people to Bucks through any app (WhatsApp, SMS, Telegram…). Play builds always link to the Play Store listing (Play's
 * policy forbids pointing people at an APK); pilot builds that update themselves (SELF_UPDATE) link to the newest pilot APK.
 */
object Invite {
    val PLAY_URL: String get() = if (BuildConfig.SELF_UPDATE) "" else "https://play.google.com/store/apps/details?id=com.bucks.app"
    private const val RELEASES = "https://github.com/infin8sync69-source/bucks-Mobile/releases"

    suspend fun link(): String = PLAY_URL.ifBlank { null } ?: runCatching { AppUpdate.newest()?.apkUrl }.getOrNull() ?: RELEASES

    /** Shares [message] followed by the download link. */
    fun share(ctx: Context, scope: CoroutineScope, message: String) {
        scope.launch { shareText(ctx, "$message\n\nGet Bucks for Android: ${link()}" + if (PLAY_URL.isBlank()) "\n(Allow \"install unknown apps\" when asked; Bucks isn't on the Play Store yet.)" else "") }
    }

    /** What to say for a locked service: who we need more of, in plain words. */
    fun forService(label: String, supplyNoun: String) =
        "I want $label on Bucks near me, but it needs more $supplyNoun here first. If you're one (or know one), join Bucks and get recommended by locals so it opens for all of us."
}
