package com.bucks.app.data

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/** A position and whether it comes from a mock provider (a fake-location app). */
data class Fix(val at: LatLng, val mocked: Boolean)

/** Where the phone is right now: permission and switch checks, and a fresh fix with a timeout. */
object Here {
    /** API 31 has Location.isMock; before that only isFromMockProvider says so. */
    @Suppress("DEPRECATION")
    fun looksMocked(l: Location): Boolean = if (Build.VERSION.SDK_INT >= 31) l.isMock else l.isFromMockProvider

    fun fixOf(l: Location) = Fix(LatLng(l.latitude, l.longitude), looksMocked(l))

    fun hasPermission(ctx: Context) = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** The phone's location switch (Settings > Location). */
    fun switchedOn(ctx: Context): Boolean = runCatching { ctx.getSystemService(LocationManager::class.java)?.let { LocationManagerCompat.isLocationEnabled(it) } == true }.getOrDefault(true)

    /** A fix taken now; null without permission, with location switched off, when Play services fails (ApiException is not a RuntimeException), or when none arrives within [timeoutMs]. A cancelled caller is not swallowed. */
    suspend fun fresh(ctx: Context, timeoutMs: Long = 8_000): Fix? {
        if (!hasPermission(ctx) || !switchedOn(ctx)) return null
        val cancel = CancellationTokenSource()
        return try {
            withTimeoutOrNull(timeoutMs) { LocationServices.getFusedLocationProviderClient(ctx).getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cancel.token).await() }?.let(::fixOf)
        } catch (e: CancellationException) { throw e } catch (_: SecurityException) { null } catch (_: Exception) { null } finally { cancel.cancel() }
    }
}
