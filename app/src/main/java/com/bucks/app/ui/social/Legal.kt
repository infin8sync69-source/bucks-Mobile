package com.bucks.app.ui.social

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.bucks.app.BuildConfig

/**
 * Public pages the app links to (docs/legal, published by GitHub Pages unless LEGAL_BASE_URL points elsewhere). The same URLs go in
 * the Play listing: privacy policy, account deletion and child safety standards are required fields there.
 */
object Legal {
    const val PRIVACY = "privacy"
    const val TERMS = "terms"
    const val GUIDELINES = "community-guidelines"
    const val CHILD_SAFETY = "child-safety"
    const val DELETE_ACCOUNT = "delete-account"
    const val GRIEVANCE = "grievance"

    fun url(page: String) = "${BuildConfig.LEGAL_BASE_URL.trimEnd('/')}/$page"
    fun open(ctx: Context, page: String) { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url(page)))) } }

    val supportEmail: String get() = BuildConfig.SUPPORT_EMAIL
    val grievanceOfficer: String get() = BuildConfig.GRIEVANCE_OFFICER

    /** Opens the mail app addressed to support, with the build number so a reply can say whether a fix has shipped. */
    fun emailSupport(ctx: Context, subject: String) {
        if (supportEmail.isBlank()) return
        val body = "\n\n---\nBucks ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android ${android.os.Build.VERSION.RELEASE}"
        runCatching { ctx.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).putExtra(Intent.EXTRA_EMAIL, arrayOf(supportEmail)).putExtra(Intent.EXTRA_SUBJECT, subject).putExtra(Intent.EXTRA_TEXT, body)) }
    }
}
