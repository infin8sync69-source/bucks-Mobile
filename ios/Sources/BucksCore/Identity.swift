import Foundation
import CryptoKit
import Security

// Port of data/Identity.kt. The user's ID is the SHA-256 of a P-256 public key that never leaves the device: a Secure Enclave key
// where the hardware has one, otherwise a software key kept in the Keychain (this-device-only). Every ride, order and vote is
// signed with it. (VerificationLevel lives in BucksIdCardInfo.swift.)

/// Where the identity key material is kept; the Keychain in the app, memory in tests.
public protocol IdentityKeyStore: AnyObject {
    func load() -> Data?
    func save(_ data: Data) -> Bool
    func delete()
}

/// A Keychain generic-password item, readable only while the device is unlocked and never synced or restored to another device.
public final class KeychainKeyStore: IdentityKeyStore {
    private let service: String, account: String
    public init(service: String = "com.bucks.app.identity", account: String = "bucks-identity") { self.service = service; self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    public func load() -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    public func save(_ data: Data) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    public func delete() { SecItemDelete(query as CFDictionary) }
}

/// Test double: keeps the key in memory.
public final class MemoryKeyStore: IdentityKeyStore {
    private var data: Data?
    public init() {}
    public func load() -> Data? { data }
    public func save(_ data: Data) -> Bool { self.data = data; return true }
    public func delete() { data = nil }
}

public final class IdentityService: @unchecked Sendable {
    private enum Tag: UInt8 { case secureEnclave = 1, software = 2 }
    private let store: IdentityKeyStore
    private let useSecureEnclave: Bool
    private let lock = NSLock()
    private var cached: (any Signer)?

    private protocol Signer {
        var publicKey: P256.Signing.PublicKey { get }
        func signature(_ payload: Data) throws -> P256.Signing.ECDSASignature
    }
    private struct SoftwareSigner: Signer {
        let key: P256.Signing.PrivateKey
        var publicKey: P256.Signing.PublicKey { key.publicKey }
        func signature(_ p: Data) throws -> P256.Signing.ECDSASignature { try key.signature(for: p) }
    }
    private struct EnclaveSigner: Signer {
        let key: SecureEnclave.P256.Signing.PrivateKey
        var publicKey: P256.Signing.PublicKey { key.publicKey }
        func signature(_ p: Data) throws -> P256.Signing.ECDSASignature { try key.signature(for: p) }
    }

    public init(store: IdentityKeyStore = KeychainKeyStore(), useSecureEnclave: Bool = true) {
        self.store = store; self.useSecureEnclave = useSecureEnclave
    }

    private func signer() -> (any Signer)? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        if let blob = store.load(), let s = decode(blob) { cached = s; return s }
        // A stored key that can't be read (restored without its Enclave key) is replaced rather than left unusable.
        let made = make()
        cached = made
        return made
    }

    private func decode(_ blob: Data) -> (any Signer)? {
        guard let first = blob.first, let tag = Tag(rawValue: first) else { return nil }
        let body = blob.dropFirst()
        switch tag {
        case .software: return (try? P256.Signing.PrivateKey(rawRepresentation: body)).map(SoftwareSigner.init)
        case .secureEnclave: return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: body)).map(EnclaveSigner.init)
        }
    }

    private func make() -> (any Signer)? {
        if useSecureEnclave, SecureEnclave.isAvailable, let k = try? SecureEnclave.P256.Signing.PrivateKey() {
            if store.save(Data([Tag.secureEnclave.rawValue]) + k.dataRepresentation) { return EnclaveSigner(key: k) }
        }
        let k = P256.Signing.PrivateKey()
        return store.save(Data([Tag.software.rawValue]) + k.rawRepresentation) ? SoftwareSigner(key: k) : nil
    }

    /// Creates the key if there is none yet.
    public func ensureKey() { _ = signer() }
    public func deleteKey() { lock.lock(); cached = nil; lock.unlock(); store.delete() }
    /// True when the private key lives in the Secure Enclave.
    public var isHardwareBacked: Bool { signer() is EnclaveSigner }

    /// The X.509 SubjectPublicKeyInfo of the public key, base64 (what Android's `publicKey.encoded` gives).
    public func publicKeyBase64() -> String { signer()?.publicKey.derRepresentation.base64EncodedString() ?? "" }
    /// Stable user identifier derived from the public key: the first 32 hex characters of its SHA-256 ("UUID-verified user").
    public func userId() -> String { signer().map { String(Self.sha256($0.publicKey.derRepresentation).prefix(32)) } ?? "" }
    /// ECDSA P-256 over SHA-256 of the UTF-8 payload, DER-encoded and base64 (Android's SHA256withECDSA); "" when no key is available.
    public func sign(_ payload: String) -> String {
        guard let s = signer(), let sig = try? s.signature(Data(payload.utf8)) else { return "" }
        return sig.derRepresentation.base64EncodedString()
    }
    public func verify(_ payload: String, signature: String) -> Bool {
        guard let s = signer() else { return false }
        return Self.verify(payload, signature: signature, publicKey: s.publicKey)
    }
    /// Verifies a signature against any base64 SPKI public key, the check a counterparty or the server makes.
    public static func verify(_ payload: String, signature: String, publicKeyBase64: String) -> Bool {
        guard let der = Data(base64Encoded: publicKeyBase64), let pk = try? P256.Signing.PublicKey(derRepresentation: der) else { return false }
        return verify(payload, signature: signature, publicKey: pk)
    }
    private static func verify(_ payload: String, signature: String, publicKey: P256.Signing.PublicKey) -> Bool {
        guard let der = Data(base64Encoded: signature), let sig = try? P256.Signing.ECDSASignature(derRepresentation: der) else { return false }
        return publicKey.isValidSignature(sig, for: Data(payload.utf8))
    }

    public static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
}

/// The app's identity (Android's `Identity` object): one shared key in the Keychain.
public enum Identity {
    public static let shared = IdentityService()
    public static func ensureKey() { shared.ensureKey() }
    public static func deleteKey() { shared.deleteKey() }
    public static func publicKeyBase64() -> String { shared.publicKeyBase64() }
    public static func userId() -> String { shared.userId() }
    public static func sign(_ payload: String) -> String { shared.sign(payload) }
    public static func verify(_ payload: String, signature: String) -> Bool { shared.verify(payload, signature: signature) }
    public static func sha256(_ b: Data) -> String { IdentityService.sha256(b) }
    /// Canonical string that both parties sign for a transaction.
    public static func txnPayload(type: String, txnId: String, actor: String, counterparty: String, amount: Int, at: Int64) -> String {
        "\(type)|\(txnId)|\(actor)|\(counterparty)|\(amount)|\(at)"
    }
}
