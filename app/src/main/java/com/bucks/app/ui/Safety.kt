package com.bucks.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.bucks.app.data.Backend
import com.bucks.app.data.BackendSafety
import com.bucks.app.data.ReportQueueRow
import com.bucks.app.data.SafetyRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Age band, guardian consent and reporting (supabase/migrations/social_safety.sql). The server enforces every rule; this class
 * only knows enough to show the right screens: whether the person still has to give a date of birth or a guardian's consent,
 * and which band they're in so the app can explain what's different for them.
 */
class Safety(private val scope: CoroutineScope, private val toast: (String) -> Unit) {
    /** Null until loaded (or in demo builds). */
    var state by mutableStateOf<SafetyRow?>(null); private set
    var busy by mutableStateOf(false); private set
    var queue by mutableStateOf<List<ReportQueueRow>>(emptyList()); private set

    val band get() = state?.ageBand ?: "UNKNOWN"
    /** Analytics follows the band and the person's choice (see data/Analytics.kt). */
    fun applyAnalytics() = com.bucks.app.data.Analytics.configure(band, com.bucks.app.data.Prefs.shareUsage)
    val isMinor get() = band == "TEEN" || band == "CHILD"
    val isChild get() = band == "CHILD"
    /** The next onboarding step the server still needs, or null when the person can use the app. */
    val pendingStep: String? get() = state?.let { s -> when { !s.birthDateSet -> STEP_BIRTH; s.guardianConsent == false -> STEP_GUARDIAN; else -> null } }

    fun refresh(then: () -> Unit = {}) = scope.launch {
        if (!Backend.enabled) { then(); return@launch }
        // Retry: while state is null the onboarding gate can't tell an adult from someone who hasn't given a date of birth yet.
        for (wait in longArrayOf(0, 2_000, 5_000, 15_000, 30_000)) {
            if (wait > 0) kotlinx.coroutines.delay(wait)
            if (runCatching { BackendSafety.mySafety() }.onSuccess { state = it }.isSuccess) break
        }
        applyAnalytics()
        then()
    }
    fun signedOut() { state = null; queue = emptyList(); applyAnalytics() }

    /** [isoDate]: yyyy-MM-dd. [onDone] gets the band (CHILD, TEEN, ADULT); on failure the server's sentence is shown. */
    fun setBirthDate(isoDate: String, onDone: (String) -> Unit) = scope.launch {
        busy = true
        try { val band = BackendSafety.setBirthDate(isoDate); state = (state ?: SafetyRow()).copy(ageBand = band, birthDateSet = true, guardianConsent = if (band == "ADULT") null else false); applyAnalytics(); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.SIGN_UP); onDone(band) }
        catch (e: Exception) { toast(friendly(e)) }
        finally { busy = false }
    }

    fun recordConsent(name: String, phone: String, relation: String, onDone: () -> Unit) = scope.launch {
        busy = true
        try { BackendSafety.recordGuardianConsent(name, phone, relation); state = state?.copy(guardianConsent = true); onDone() }
        catch (e: Exception) { toast(friendly(e)) }
        finally { busy = false }
    }

    fun report(kind: String, targetId: String, reason: String, detail: String, onDone: () -> Unit = {}) = scope.launch {
        busy = true
        try { BackendSafety.report(kind, targetId, reason, detail); com.bucks.app.data.Analytics.log(com.bucks.app.data.Analytics.REPORT, "kind" to kind, "reason" to reason); toast("Thanks for telling us. Our team will review it."); onDone() }
        catch (e: Exception) { toast(friendly(e)) }
        finally { busy = false }
    }

    fun refreshQueue() = scope.launch { runCatching { BackendSafety.reportQueue() }.onSuccess { queue = it }.onFailure { toast(friendly(it)) } }
    fun review(id: String, action: String) = scope.launch {
        try { BackendSafety.reviewReport(id, action); queue = queue.filterNot { it.id == id }; toast(when (action) { "REMOVE" -> "Removed."; "BAN" -> "Removed and the account is suspended."; else -> "Dismissed." }) }
        catch (e: Exception) { toast(friendly(e)) }
    }

    private fun friendly(e: Throwable): String {
        val m = e.message ?: return "Something went wrong. Try again."
        return Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(m)?.groupValues?.get(1)?.replaceFirstChar { it.uppercase() }
            ?: "Couldn't reach Bucks. Check your connection and try again."
    }

    companion object { const val STEP_BIRTH = "birth"; const val STEP_GUARDIAN = "guardian" }
}
