package com.bucks.app.data

import android.app.Activity
import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthInvalidCredentialsException
import com.google.firebase.auth.PhoneAuthCredential
import com.google.firebase.auth.PhoneAuthOptions
import com.google.firebase.auth.PhoneAuthProvider
import java.util.concurrent.TimeUnit

/**
 * Firebase phone sign-in. Enabled only when app/google-services.json was present at build time; otherwise
 * [enabled] is false and the app keeps its on-device demo behaviour. Everything else (drivers, rides,
 * deliveries) lives in Supabase: see [Backend] and ui/Dispatch.kt.
 */
object Cloud {
    var enabled = false; private set
    fun init(ctx: Context) { enabled = FirebaseApp.getApps(ctx).isNotEmpty() }

    private val auth get() = FirebaseAuth.getInstance()
    val uid: String? get() = if (enabled) auth.currentUser?.uid else null

    // ---------- phone sign-in ----------
    private var verificationId: String? = null
    private var resendToken: PhoneAuthProvider.ForceResendingToken? = null

    /** Sends an SMS code to [phone] (10 digits, India). Some devices verify instantly, which calls [onSignedIn] without a code. */
    fun sendCode(activity: Activity, phone: String, resend: Boolean, onSent: () -> Unit, onSignedIn: () -> Unit, onError: (String) -> Unit) {
        val callbacks = object : PhoneAuthProvider.OnVerificationStateChangedCallbacks() {
            override fun onVerificationCompleted(credential: PhoneAuthCredential) = signIn(credential, onSignedIn, onError)
            override fun onVerificationFailed(e: FirebaseException) = onError(errorText(e))
            override fun onCodeSent(id: String, token: PhoneAuthProvider.ForceResendingToken) { verificationId = id; resendToken = token; onSent() }
        }
        val options = PhoneAuthOptions.newBuilder(auth).setPhoneNumber("+91$phone").setTimeout(60L, TimeUnit.SECONDS).setActivity(activity).setCallbacks(callbacks)
        if (resend) resendToken?.let { options.setForceResendingToken(it) }
        PhoneAuthProvider.verifyPhoneNumber(options.build())
    }
    fun verifyCode(code: String, onSignedIn: () -> Unit, onError: (String) -> Unit) {
        val id = verificationId ?: return onError("Tap Resend code to get a new code.")
        signIn(PhoneAuthProvider.getCredential(id, code), onSignedIn, onError)
    }
    private fun signIn(credential: PhoneAuthCredential, onSignedIn: () -> Unit, onError: (String) -> Unit) {
        auth.signInWithCredential(credential).addOnSuccessListener { onSignedIn() }.addOnFailureListener { onError(errorText(it)) }
    }
    private fun errorText(e: Exception) = when (e) {
        is FirebaseAuthInvalidCredentialsException -> "That code or number isn't valid. Check it and try again."
        is FirebaseTooManyRequestsException -> "Too many attempts from this phone. Try again later."
        else -> "Couldn't verify right now. Check your connection and try again."
    }
    fun signOut() { if (enabled) auth.signOut() }

    /**
     * Removes the Firebase account. Firebase may ask for a fresh sign-in first. Nothing on Supabase goes with it: call
     * `Backend.deleteMyAccount()` (delete_my_account in dispatch.sql) first, while this user can still sign the request.
     */
    fun deleteAccount(onDone: (Boolean) -> Unit) {
        val user = if (enabled) auth.currentUser else null
        if (user == null) { onDone(true); return }
        user.delete().addOnSuccessListener { onDone(true) }.addOnFailureListener { onDone(false) }
    }
}
