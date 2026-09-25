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
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.util.concurrent.TimeUnit

/**
 * Firebase backend for the ride-hailing pilot: phone sign-in, live drivers and ride matching.
 * Enabled only when app/google-services.json was present at build time; otherwise [enabled] is
 * false and the app keeps its on-device demo behaviour.
 *
 * Firestore layout (rules in firestore.rules):
 *  drivers/{uid}  name, phone, kind, model, plate, online, lat, lng, up, down, updatedAt
 *  rides/{id}     riderUid, rider*, pickup*, dest*, km, fare, kind, pin, status, driverUid, driver*, driverLat/Lng
 */
object Cloud {
    var enabled = false; private set
    fun init(ctx: Context) { enabled = FirebaseApp.getApps(ctx).isNotEmpty() }

    private val auth get() = FirebaseAuth.getInstance()
    private val db get() = FirebaseFirestore.getInstance()
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

    /** Removes this user's driver record and their Firebase account. Firebase may ask for a fresh sign-in first. */
    fun deleteAccount(onDone: (Boolean) -> Unit) {
        val user = if (enabled) auth.currentUser else null
        if (user == null) { onDone(true); return }
        db.collection("drivers").document(user.uid).delete()
        user.delete().addOnSuccessListener { onDone(true) }.addOnFailureListener { onDone(false) }
    }

    // ---------- drivers ----------
    fun publishDriver(u: User, v: Vehicle, at: LatLng?, online: Boolean) {
        val id = uid ?: return
        val data = mutableMapOf<String, Any>("name" to u.name, "phone" to u.phone, "kind" to v.kind.name, "model" to v.model, "plate" to v.plate, "online" to online, "updatedAt" to FieldValue.serverTimestamp())
        at?.let { data["lat"] = it.lat; data["lng"] = it.lng }
        db.collection("drivers").document(id).set(data, SetOptions.merge())
    }
    /** Called on every location fix while online; also moves the car on the rider's screen during a trip. */
    fun updateDriverPosition(at: LatLng, rideId: String?) {
        val id = uid ?: return
        db.collection("drivers").document(id).set(mapOf("lat" to at.lat, "lng" to at.lng, "updatedAt" to FieldValue.serverTimestamp()), SetOptions.merge())
        rideId?.let { db.collection("rides").document(it).update(mapOf("driverLat" to at.lat, "driverLng" to at.lng)) }
    }
    /** Online drivers seen in the last 5 minutes (a driver whose app died stops counting). */
    fun listenDrivers(onChange: (List<Driver>) -> Unit): ListenerRegistration =
        db.collection("drivers").whereEqualTo("online", true).addSnapshotListener { snap, _ ->
            snap ?: return@addSnapshotListener
            val fresh = System.currentTimeMillis() - 5 * 60_000L
            onChange(snap.documents.filter { it.id != uid && (it.getTimestamp("updatedAt")?.toDate()?.time ?: 0L) >= fresh }.mapNotNull { driverFrom(it) })
        }
    private fun driverFrom(d: DocumentSnapshot): Driver? {
        val kind = runCatching { VehicleKind.valueOf(d.getString("kind") ?: "") }.getOrNull() ?: return null
        val lat = d.getDouble("lat") ?: return null; val lng = d.getDouble("lng") ?: return null
        val (x, y) = Geo.toPercent(LatLng(lat, lng))
        return Driver(d.id, d.getString("name").orEmpty(), kind, d.getString("plate").orEmpty(), d.getString("model").orEmpty(), x, y, 0.0,
            d.getLong("up")?.toInt() ?: 0, d.getLong("down")?.toInt() ?: 0, true, d.getString("phone").orEmpty())
    }
    fun rateDriver(driverUid: String, up: Boolean) { if (enabled) db.collection("drivers").document(driverUid).update(if (up) "up" else "down", FieldValue.increment(1L)) }

    // ---------- rides ----------
    fun createRide(data: Map<String, Any>): String? {
        val id = uid ?: return null
        val ref = db.collection("rides").document()
        ref.set(data + mapOf("riderUid" to id, "status" to RideStatus.SEARCHING.name, "createdAt" to FieldValue.serverTimestamp()))
        return ref.id
    }
    fun listenRide(id: String, onChange: (Map<String, Any>) -> Unit): ListenerRegistration =
        db.collection("rides").document(id).addSnapshotListener { snap, _ -> snap?.data?.let(onChange) }
    fun updateRide(id: String, fields: Map<String, Any>) { if (enabled) db.collection("rides").document(id).update(fields) }
    /** Clears the driver so the ride rings other drivers again. */
    fun releaseRide(id: String) = updateRide(id, mapOf("status" to RideStatus.SEARCHING.name, "driverUid" to FieldValue.delete(), "driverName" to FieldValue.delete(), "driverPhone" to FieldValue.delete(),
        "driverModel" to FieldValue.delete(), "driverPlate" to FieldValue.delete(), "driverLat" to FieldValue.delete(), "driverLng" to FieldValue.delete()))
    /** Requests waiting for a driver of this vehicle type. */
    fun listenOpenRides(kind: VehicleKind, onChange: (List<Pair<String, Map<String, Any>>>) -> Unit): ListenerRegistration =
        db.collection("rides").whereEqualTo("status", RideStatus.SEARCHING.name).whereEqualTo("kind", kind.name).addSnapshotListener { snap, _ ->
            snap ?: return@addSnapshotListener
            onChange(snap.documents.mapNotNull { d -> d.data?.let { d.id to it } })
        }
    /** First driver to accept wins; [onResult] is false when someone else got there first or the rider cancelled. */
    fun claimRide(id: String, driver: Map<String, Any>, onResult: (Boolean) -> Unit) {
        val me = uid ?: return onResult(false)
        val ref = db.collection("rides").document(id)
        db.runTransaction { tx ->
            if (tx.get(ref).getString("status") != RideStatus.SEARCHING.name) false
            else { tx.update(ref, driver + mapOf("status" to RideStatus.MATCHED.name, "driverUid" to me)); true }
        }.addOnSuccessListener { onResult(it) }.addOnFailureListener { onResult(false) }
    }
}

/** Small readers for Firestore maps, whose numbers arrive as Long or Double. */
fun Map<String, Any>.str(k: String) = this[k] as? String ?: ""
fun Map<String, Any>.num(k: String) = (this[k] as? Number)?.toDouble()
fun Map<String, Any>.int(k: String) = (this[k] as? Number)?.toInt() ?: 0
fun Map<String, Any>.millis(k: String) = (this[k] as? com.google.firebase.Timestamp)?.toDate()?.time
