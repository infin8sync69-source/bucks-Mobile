package com.bucks.app.data

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.bucks.app.MainActivity
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Firebase Cloud Messaging on the phone. The server side (supabase/functions/notify) sends data-only messages with
 * the keys type, title, body, route and quiet, so this class draws every notification itself and the tap opens the
 * right screen. Registered in AndroidManifest.xml; it only ever runs when Firebase is configured for the build.
 */
class BucksMessagingService : FirebaseMessagingService() {
    override fun onCreate() { super.onCreate(); Push.ensureChannels(this) }

    /** FCM hands out a new token on first start and now and then afterwards; the server needs the current one. */
    override fun onNewToken(token: String) { Push.register(token) }

    override fun onMessageReceived(message: RemoteMessage) {
        val d = message.data
        val title = d["title"] ?: message.notification?.title ?: return
        val body = d["body"] ?: message.notification?.body ?: ""
        Push.show(this, type = d["type"] ?: "social", title = title, body = body, route = Push.safeRoute(d["route"]), quiet = d["quiet"] == "true")
    }
}

/**
 * Token registration and notification channels. Call [registerIfSignedIn] once the person is signed in (Social.signedIn),
 * [unregister] before signing out, and [ensureChannels] at app start so the channels show up in Android settings even
 * before the first notification arrives.
 */
object Push {
    /** Intent extra a tapped notification carries; MainActivity reads it and BucksAppUi navigates there once. */
    const val EXTRA_ROUTE = "route"
    const val CH_MESSAGES = "bucks_messages"
    const val CH_ORDERS = "bucks_orders"
    const val CH_TASKS = "bucks_tasks"
    const val CH_SOCIAL = "bucks_social"
    /** Quiet hours: the server marks a message quiet=true and it lands here, with no sound and no heads-up banner. */
    const val CH_QUIET = "bucks_quiet"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var registered: String? = null

    /** Creates the channels (a no-op once they exist). Android keeps a channel's importance as first created. */
    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        val ring = NotificationChannel(CH_TASKS, "Rides and deliveries", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Your rider is on the way, has arrived, or your order is out for delivery"
            // A ringtone rather than the short notification sound: this is the one you must not miss.
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            enableVibration(true); vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 600)
            enableLights(true); lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        val orders = NotificationChannel(CH_ORDERS, "Orders", NotificationManager.IMPORTANCE_HIGH).apply { description = "New orders for your shop and updates on orders you placed"; enableVibration(true) }
        val messages = NotificationChannel(CH_MESSAGES, "Messages", NotificationManager.IMPORTANCE_HIGH).apply { description = "Chats with people, shops and pros"; enableVibration(true) }
        val social = NotificationChannel(CH_SOCIAL, "Sync, Moments and comments", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Sync requests, new Moments from synced people, comments on your posts" }
        val quiet = NotificationChannel(CH_QUIET, "Quiet hours", NotificationManager.IMPORTANCE_LOW).apply { description = "Notifications that arrive during your quiet hours: shown silently"; setSound(null, null); enableVibration(false) }
        nm.createNotificationChannels(listOf(ring, orders, messages, social, quiet))
    }

    /** After sign-in: fetch this phone's FCM token and store it against my profile. Does nothing in the demo build or when signed out. */
    fun registerIfSignedIn() {
        if (!Backend.enabled || FirebaseAuth.getInstance().currentUser == null) return
        scope.launch { runCatching { register(FirebaseMessaging.getInstance().token.await()) } }
    }

    internal fun register(token: String) {
        if (token.isBlank()) return
        scope.launch { runCatching { if (Backend.enabled && FirebaseAuth.getInstance().currentUser != null) { Backend.registerDeviceToken(token); registered = token } } }
    }

    /**
     * Before sign-out: remove this phone from my profile and retire the token at FCM, so nothing addressed to me reaches
     * the next person who signs in here. Firebase issues a fresh token on the next [registerIfSignedIn].
     */
    fun unregister() {
        if (!Backend.enabled) return
        val token = registered; registered = null
        scope.launch {
            if (token != null) runCatching { Backend.unregisterDeviceToken(token) }
            runCatching { FirebaseMessaging.getInstance().deleteToken().await() }
        }
    }

    /** Only routes the app knows how to open; anything else opens the app on its usual first screen. */
    fun safeRoute(route: String?): String? {
        val r = route?.trim()?.takeIf { it.isNotBlank() && it.length <= 200 && !it.contains('\n') } ?: return null
        val exact = setOf("home", "feed", "sync", "messages", "invites", "my/orders", "my/applications", "my/listings", "jobs-near")
        val prefixes = listOf("chat/", "cloud-order/", "orders-for/", "delivery/", "moments/", "l/", "job/", "jobs-of/", "members/")
        return if (r in exact || prefixes.any { r.startsWith(it) && r.length > it.length }) r else null
    }

    /** The route from a launch intent, if a notification started or re-opened the app. */
    fun routeFrom(intent: Intent?): String? = safeRoute(intent?.getStringExtra(EXTRA_ROUTE))

    /** Draws one notification. Same type and route replace each other (a chat shows only its latest message). */
    @SuppressLint("MissingPermission")
    fun show(ctx: Context, type: String, title: String, body: String, route: String?, quiet: Boolean) {
        ensureChannels(ctx)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
        val channel = when { quiet -> CH_QUIET; type == "messages" -> CH_MESSAGES; type == "orders" -> CH_ORDERS; type == "tasks" -> CH_TASKS; else -> CH_SOCIAL }
        val icon = when (type) { "messages" -> android.R.drawable.ic_dialog_email; "orders" -> android.R.drawable.ic_menu_agenda; "tasks" -> android.R.drawable.ic_menu_mylocation; else -> android.R.drawable.ic_dialog_info }
        val id = (type + ":" + (route ?: "")).hashCode()
        val open = Intent(ctx, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            route?.let { putExtra(EXTRA_ROUTE, it) }
        }
        val tap = PendingIntent.getActivity(ctx, id, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(icon).setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(tap).setAutoCancel(true).setShowWhen(true).setGroup(type)
            .setPriority(when { quiet -> NotificationCompat.PRIORITY_LOW; type == "tasks" -> NotificationCompat.PRIORITY_MAX; else -> NotificationCompat.PRIORITY_HIGH })
            .setCategory(when (type) { "messages" -> NotificationCompat.CATEGORY_MESSAGE; "tasks" -> NotificationCompat.CATEGORY_STATUS; else -> NotificationCompat.CATEGORY_SOCIAL })
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .apply { if (!quiet) setDefaults(if (type == "tasks") NotificationCompat.DEFAULT_LIGHTS else NotificationCompat.DEFAULT_ALL) }
            .build()
        NotificationManagerCompat.from(ctx).notify(id, n)
    }
}
