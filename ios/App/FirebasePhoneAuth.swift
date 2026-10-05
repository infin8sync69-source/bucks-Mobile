import Foundation
import FirebaseAuth
import FirebaseCore
import BucksCore

/// Phone sign-in on FirebaseAuth: the iOS side of Cloud.kt. Supabase accepts the Firebase ID token (see Backend.swift).
final class FirebasePhoneAuth: PhoneSignIn, @unchecked Sendable {
    private var verificationID: String?

    var uid: String? { Auth.auth().currentUser?.uid }
    var projectName: String? { FirebaseApp.app()?.options.projectID }

    func idToken(forceRefresh: Bool) async throws -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDTokenResult(forcingRefresh: forceRefresh).token
    }

    func sendCode(phone: String, resend: Bool) async throws -> PhoneSendResult {
        do {
            // Firebase first checks the app is genuine (APNs silent push, else a reCAPTCHA page).
            verificationID = try await FirebaseAuth.PhoneAuthProvider.provider().verifyPhoneNumber("+91\(phone)", uiDelegate: nil)
            return .codeSent
        } catch {
            #if DEBUG
            // A debug build (the simulator has no APNs token) retries once with the check off, as Android's test builds do. Firebase allows that
            // only for the console's "Phone numbers for testing", so a real number still fails with the original error.
            if (error as NSError).code != AuthErrorCode.tooManyRequests.rawValue {
                Auth.auth().settings?.isAppVerificationDisabledForTesting = true
                do { verificationID = try await FirebaseAuth.PhoneAuthProvider.provider().verifyPhoneNumber("+91\(phone)", uiDelegate: nil); return .codeSent }
                catch let retry { Auth.auth().settings?.isAppVerificationDisabledForTesting = false; throw AuthFailure(retry) }
            }
            #endif
            throw AuthFailure(error)
        }
    }

    func verify(code: String) async throws {
        guard let id = verificationID else { throw AuthFailure.message("Tap Resend code to get a new code.") }
        let credential = FirebaseAuth.PhoneAuthProvider.provider().credential(withVerificationID: id, verificationCode: code)
        do { _ = try await Auth.auth().signIn(with: credential) } catch { throw AuthFailure(error) }
    }

    func signOut() throws { try Auth.auth().signOut() }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.delete()
    }
}

/// Firebase errors in the words Cloud.kt uses; the Firebase error code goes on the end so a tester can report it.
struct AuthFailure: LocalizedError {
    let text: String
    static func message(_ t: String) -> AuthFailure { AuthFailure(text: t) }
    init(text: String) { self.text = text }
    init(_ error: Error) {
        let ns = error as NSError
        let code = AuthErrorCode(rawValue: ns.code)
        let base: String
        switch code {
        case .invalidVerificationCode, .invalidPhoneNumber, .missingPhoneNumber, .invalidVerificationID, .missingVerificationCode: base = "That code or number isn't valid. Check it and try again."
        case .tooManyRequests, .quotaExceeded: base = "Too many attempts from this phone. Try again later."
        default: base = "Couldn't verify right now."
        }
        text = "\(base) (\(code.map { "\($0)" } ?? "error \(ns.code)"))"
    }
    var errorDescription: String? { text }
}
