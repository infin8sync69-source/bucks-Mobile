package com.bucks.app.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalContext
import com.bucks.app.R

/**
 * The driver's ring: while a ride or delivery request is ringing on this phone, the Bucks ride-request tune loops with a repeating buzz,
 * on the ringer volume (silent phones still buzz). Stops the moment the request is accepted, passed, taken by someone else or times out.
 * The same tune plays as the notification sound when the app is closed (data/Push.kt, channel bucks_ride_request).
 */
@Composable
fun RideRingEffect(ringing: Boolean) {
    val ctx = LocalContext.current; val owner = LocalLifecycleOwner.current
    // Only while the app is on screen: with the app closed or in the background the push notification rings instead (same tune), so the two never overlap.
    var visible by remember { mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(owner) {
        val o = LifecycleEventObserver { _, _ -> visible = owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
        owner.lifecycle.addObserver(o); onDispose { owner.lifecycle.removeObserver(o) }
    }
    val active = ringing && visible
    DisposableEffect(active) {
        var player: MediaPlayer? = null; var buzz: Vibrator? = null
        if (active) {
            player = runCatching {
                MediaPlayer().apply {
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    ctx.resources.openRawResourceFd(R.raw.ride_request).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                    isLooping = true; prepare(); start()
                }
            }.getOrNull()
            buzz = runCatching { vibrator(ctx).also { v -> if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400, 600, 1200), 0)) else @Suppress("DEPRECATION") v.vibrate(longArrayOf(0, 600, 400, 600, 1200), 0) } }.getOrNull()
        }
        onDispose { runCatching { player?.stop() }; runCatching { player?.release() }; runCatching { buzz?.cancel() } }
    }
}

private fun vibrator(ctx: Context): Vibrator =
    if (Build.VERSION.SDK_INT >= 31) (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    else @Suppress("DEPRECATION") (ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
