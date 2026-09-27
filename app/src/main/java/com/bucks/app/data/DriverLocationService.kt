package com.bucks.app.data

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * Foreground service (type=location) that streams the driver's position while they are on duty.
 * Required by Play policy for continuous location; declared in the manifest. Positions go to
 * [DriverLocationService.position] for the UI and, when Supabase is configured, to the server through
 * `update_location` at most every 5 seconds (it moves the car on the rider's screen and keeps presence fresh).
 */
class DriverLocationService : Service() {
    private lateinit var client: FusedLocationProviderClient
    /** Server pushes run here, off the main thread; cancelled in [onDestroy] so nothing outlives the service. */
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var lastPush = 0L
    private val callback = object : LocationCallback() { override fun onLocationResult(r: LocationResult) { r.lastLocation?.let { l ->
        val p = LatLng(l.latitude, l.longitude); position.value = p; mocked.value = (Build.VERSION.SDK_INT >= 31 && l.isMock)
        val now = System.currentTimeMillis()
        if (Backend.enabled && now - lastPush >= PUSH_EVERY_MS) { lastPush = now; io.launch { runCatching { Backend.updateLocation(p) } } }
    } } }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() { super.onCreate(); client = LocationServices.getFusedLocationProviderClient(this) }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "On duty", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE)
        val n: Notification = NotificationCompat.Builder(this, CHANNEL).setContentTitle("You're online on Bucks").setContentText("Sharing your location so nearby customers can ring you").setSmallIcon(android.R.drawable.ic_menu_mylocation).setOngoing(true).setContentIntent(open).build()
        // Android 14 throws if location permission was revoked; stop quietly instead of crashing.
        try { if (Build.VERSION.SDK_INT >= 29) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION) else startForeground(1, n) } catch (_: Exception) { stopSelf(); return START_NOT_STICKY }
        try { client.requestLocationUpdates(LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L).setMinUpdateDistanceMeters(15f).build(), callback, Looper.getMainLooper()) } catch (_: SecurityException) { stopSelf() }
        // Not sticky: after process death the online flag is gone, so a restarted service would track with no owner.
        return START_NOT_STICKY
    }
    override fun onDestroy() { client.removeLocationUpdates(callback); io.cancel(); super.onDestroy() }
    companion object {
        const val CHANNEL = "bucks_on_duty"
        private const val PUSH_EVERY_MS = 5_000L
        val position = MutableStateFlow<LatLng?>(null)
        val mocked = MutableStateFlow(false)
        fun start(ctx: Context) { runCatching { ctx.startForegroundService(Intent(ctx, DriverLocationService::class.java)) } }
        fun stop(ctx: Context) { ctx.stopService(Intent(ctx, DriverLocationService::class.java)) }
    }
}
