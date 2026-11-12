package com.bucks.app.data

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics

/**
 * Product analytics (Firebase Analytics) and crash reports (Crashlytics).
 *
 * Privacy rules, the same in code as in the Data safety form:
 *  - Collection starts OFF (manifest) and is switched on only for adults who haven't opted out (Settings → Appearance and data).
 *    Under-18s are never tracked: India's DPDP Act forbids tracking or behavioural monitoring of children.
 *  - No advertising ID (AD_ID permission removed in the manifest), no user ID, no names, numbers, message or post text in events.
 *  - Crash reports stay on for everyone (they describe the app, not the person) and carry no user identifier.
 *
 * Events are a small fixed list (the funnel from sign-up to first post, sync and message), so the dashboard answers: do people get
 * through onboarding, do they connect, do they come back.
 */
object Analytics {
    private var fa: FirebaseAnalytics? = null
    private var allowed = false

    fun init(ctx: Context) {
        if (FirebaseApp.getApps(ctx).isEmpty()) return
        fa = FirebaseAnalytics.getInstance(ctx).also { it.setAnalyticsCollectionEnabled(false) }
        runCatching { FirebaseCrashlytics.getInstance().setCrashlyticsCollectionEnabled(true) }
    }

    /** Called whenever the age band or the person's choice changes. [band]: ADULT, TEEN, CHILD or UNKNOWN (not known yet: stay off). */
    fun configure(band: String, optedIn: Boolean) {
        allowed = band == "ADULT" && optedIn
        fa?.setAnalyticsCollectionEnabled(allowed)
        if (!allowed) fa?.resetAnalyticsData()
    }

    fun log(event: String, vararg params: Pair<String, Any?>) {
        val a = fa ?: return; if (!allowed) return
        a.logEvent(event, Bundle().apply { params.forEach { (k, v) -> when (v) { is String -> putString(k, v.take(100)); is Int -> putLong(k, v.toLong()); is Long -> putLong(k, v); is Boolean -> putLong(k, if (v) 1 else 0); else -> {} } } })
    }
    fun screen(name: String) = log(FirebaseAnalytics.Event.SCREEN_VIEW, FirebaseAnalytics.Param.SCREEN_NAME to name)

    /** A handled error worth seeing in Crashlytics (never with personal data in the message). */
    fun recordError(e: Throwable) { runCatching { FirebaseCrashlytics.getInstance().recordException(e) } }

    // The event names, in one place so the dashboard and the code agree.
    const val SIGN_UP = "sign_up"; const val LOGIN = "login"; const val ONBOARDING_DONE = "onboarding_done"
    const val POST_CREATED = "post_created"; const val MOMENT_CREATED = "moment_created"; const val COMMENT = "comment_added"
    const val SYNC_REQUESTED = "sync_requested"; const val SYNC_ACCEPTED = "sync_accepted"; const val MESSAGE_SENT = "message_sent"
    const val GROUP_CREATED = "group_created"; const val SEARCH = "search"; const val REPORT = "report_filed"; const val FEEDBACK = "feedback_posted"
    // The rest of the journeys (revision 1): commerce, rides, hiring, pages, Explore. Counts and kinds only, never names, prices of one person or text.
    const val ORDER_PLACED = "order_placed"; const val RIDE_REQUESTED = "ride_requested"; const val JOB_APPLIED = "job_applied"; const val LISTING_CREATED = "listing_created"
    const val RECOMMEND_GIVEN = "recommend_given"; const val POST_VOTE = "post_vote"; const val EXPLORE_FILTER = "explore_filter"; const val EXPLORE_OPEN = "explore_open"
    const val ABOUT_DONE = "onboarding_about_done"; const val ABOUT_SKIPPED = "onboarding_about_skipped"; const val PEOPLE_RESULT_TAP = "people_result_tap"
}
