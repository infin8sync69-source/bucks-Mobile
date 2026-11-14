package com.bucks.app.ui

import android.content.Context
import com.bucks.app.BuildConfig
import com.bucks.app.R
import com.bucks.app.data.AppUpdate
import com.bucks.app.data.Str
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
        scope.launch { val url = link(); shareText(ctx, if (PLAY_URL.isBlank()) Str.get(R.string.g4_invite_share_apk, message, url) else Str.get(R.string.g4_invite_share_play, message, url)) }
    }

    /** What to say for a locked service: who we need more of, in plain words. */
    fun forService(label: String, supplyNoun: String) =
        Str.get(R.string.g4_invite_for_service, label, supplyNoun)
}
