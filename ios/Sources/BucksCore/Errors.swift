import Foundation

/// What went wrong talking to Supabase.
public enum BackendError: Error, Sendable {
    /// The server answered with an error status; `body` is the PostgREST error JSON.
    case http(status: Int, body: String)
    /// No usable answer: offline, timeout, dropped connection.
    case transport(String)
    /// The server answered but the reply wasn't what we expected.
    case decoding(String)
    case notSignedIn
}

/// Statuses that say nothing about the request itself: an expired or withheld token (401), a timeout (408), rate limiting (429). Retry them like a lost connection.
private let transientStatus: Set<Int> = [401, 408, 429]

/// True when the server answered and said no (its message is ours to show); false for a lost connection, a timeout, a gateway or server error (5xx), an expired token or a bad reply.
public func isServerRefusal(_ e: Error) -> Bool {
    if case BackendError.http(let status, _) = e { return (400...499).contains(status) && !transientStatus.contains(status) }
    return false
}

/// True when no usable answer came back: no signal, a timeout, a 5xx/401/429 or a dropped connection. The action may or may not have reached the server.
public func isTransportError(_ e: Error) -> Bool {
    if e is CancellationError { return false }
    if case BackendError.decoding = e { return false }
    if case BackendError.notSignedIn = e { return false }
    return !isServerRefusal(e)
}

private struct PostgrestMessage: Decodable { var message: String? }

/// Our own database errors come back wrapped; show just the sentence we wrote. Connection problems get one plain sentence instead of an exception name.
public func friendlyError(_ e: Error) -> String {
    if case BackendError.notSignedIn = e { return "You're signed out. Sign in again." }
    if isTransportError(e) { return "Couldn't reach Bucks. Check your connection and try again." }
    if case BackendError.http(_, let body) = e {
        if let m = try? JSONDecoder().decode(PostgrestMessage.self, from: Data(body.utf8)).message, !m.isEmpty { return capitalised(m) }
        let t = body.split(separator: "\n").first.map(String.init)?.prefix(140) ?? ""
        return t.isEmpty ? "Something went wrong. Try again." : capitalised(String(t))
    }
    return "Something went wrong. Try again."
}

private func capitalised(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let f = t.first else { return "Something went wrong. Try again." }
    return f.uppercased() + t.dropFirst()
}

/// Whole seconds since an ISO timestamp from PostgREST (with offset); nil when it can't be read.
public func secondsSince(_ iso: String) -> Int? {
    let s = iso.replacingOccurrences(of: " ", with: "T")
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
    guard let d = f.date(from: s) ?? g.date(from: s) ?? g.date(from: s + "Z") else { return nil }
    return Int(Date().timeIntervalSince(d))
}
