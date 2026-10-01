package com.bucks.app.ui

import android.content.Context
import com.bucks.app.data.AppUpdate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Invite people to Bucks through any app (WhatsApp, SMS, Telegram…). There is no Play Store listing yet, so the link is the
 * newest pilot APK of this branch; when Bucks is on Play, set [PLAY_URL] and every invite uses it instead.
 */
object Invite {
    const val PLAY_URL = ""
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
