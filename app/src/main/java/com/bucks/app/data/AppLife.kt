package com.bucks.app.data

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.bucks.app.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What has to outlive any screen or ViewModel: a scope for work that must finish after they are gone (presence off,
 * closing realtime channels) and whether the app is on screen (the ring only needs a notification when it is not).
 */
object AppLife {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    @Volatile var app: Application? = null; private set
    private var started = 0
    private val _foreground = MutableStateFlow(false)
    /** True while an activity of this app is started (visible). A rotation does not flip it. */
    val foreground: StateFlow<Boolean> = _foreground.asStateFlow()
    val isForeground get() = _foreground.value

    fun init(app: Application) {
        this.app = app
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) { if (++started == 1) { _foreground.value = true; RingAlert.cancel() } }
            override fun onActivityStopped(activity: Activity) { started = (started - 1).coerceAtLeast(0); if (started == 0 && !activity.isChangingConfigurations) _foreground.value = false }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }
}

/**
 * Tells an online driver about a ringing request. In the app: a short buzz (the card is on screen). Otherwise a heads-up
 * notification on the "Rides and deliveries" channel, which carries the ringtone and vibration (Push.ensureChannels); it
 * repeats until the request is accepted, passed, expired or cancelled, and times out on its own. No full-screen intent
 * (Google Play restricts them), so a locked phone shows the heads-up and the driver taps it.
 */
object RingAlert {
    private const val NOTIF_ID = 0x5121

    enum class Problem(val message: String) {
        OFF("Notifications are off for Bucks, so a ride request can't ring you while the app isn't open."),
        CHANNEL("The \"Rides and deliveries\" notifications are switched off, so a ride request can't ring you while the app isn't open."),
        QUIET("The \"Rides and deliveries\" notifications are set to silent, so a request may not pop up or ring while the app isn't open.")
    }

    fun ring(dr: DriverRide) {
        val app = AppLife.app ?: return
        if (AppLife.isForeground) buzz(app) else post(app, dr)
    }

    fun cancel() { val app = AppLife.app ?: return; runCatching { NotificationManagerCompat.from(app).cancel(NOTIF_ID) } }

    /** Why a request could not alert the driver in the background (null when it can). Android 13+ needs the POST_NOTIFICATIONS permission. */
    fun problem(ctx: Context): Problem? {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return Problem.OFF
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return Problem.OFF
        Push.ensureChannels(ctx)
        val importance = ctx.getSystemService(NotificationManager::class.java)?.getNotificationChannel(Push.CH_TASKS)?.importance ?: return null
        return when { importance == NotificationManager.IMPORTANCE_NONE -> Problem.CHANNEL; importance < NotificationManager.IMPORTANCE_HIGH -> Problem.QUIET; else -> null }
    }

    /** The system screen where the driver fixes [p]: the app's notification settings, or that one channel's. */
    fun settingsIntent(ctx: Context, p: Problem): Intent {
        val i = if (p == Problem.OFF) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS) else Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID, Push.CH_TASKS)
        return i.putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun buzz(ctx: Context) {
        runCatching { ContextCompat.getSystemService(ctx, Vibrator::class.java)?.takeIf { it.hasVibrator() }?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 220, 120, 220), -1)) }
    }

    @SuppressLint("MissingPermission")
    private fun post(ctx: Application, dr: DriverRide) {
        if (problem(ctx) == Problem.OFF) return
        val open = Intent(ctx, MainActivity::class.java).apply { action = Intent.ACTION_VIEW; addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP); putExtra(Push.EXTRA_ROUTE, "home") }
        val tap = PendingIntent.getActivity(ctx, NOTIF_ID, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val delivery = dr.kind == VehicleKind.BIKE
        val away = if (dr.pickupKm < 1) "${(dr.pickupKm * 1000).toInt()} m" else "${dr.pickupKm} km"
        val secs = dr.secondsLeft.coerceAtLeast(5)
        val n = NotificationCompat.Builder(ctx, Push.CH_TASKS)
            .setSmallIcon(com.bucks.app.R.drawable.ic_stat_bucks).setColor(0xFF811FF0.toInt())
            .setContentTitle("${if (delivery) "New delivery" else "New ride request"} · ₹${dr.fare}").setContentText("${dr.pickupAt.substringBefore(" · ")} · $away away · tap to accept")
            .setContentIntent(tap).setAutoCancel(true).setCategory(NotificationCompat.CATEGORY_EVENT).setPriority(NotificationCompat.PRIORITY_MAX).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setTimeoutAfter(secs * 1000L).setWhen(System.currentTimeMillis() + secs * 1000L).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
            .build().also { it.flags = it.flags or Notification.FLAG_INSISTENT }
        NotificationManagerCompat.from(ctx).notify(NOTIF_ID, n)
    }
}
