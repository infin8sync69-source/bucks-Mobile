import Foundation

/// What people search for on Bucks and what they do next, sent to log_discovery (supabase/migrations/discovery_log.sql) so search can
/// be measured and keep learning (docs/DISCOVERY_ALGORITHMS.md §8 and §13). Port of data/DiscoveryLog.kt: the same events, the same
/// batches, the same rule.
///
/// Only adults who haven't switched usage statistics off (Settings › Appearance and data › Help improve Bucks; `AppSession.applyUsage`).
/// Otherwise nothing is even kept in memory, and the server drops anything from under-18s whatever it receives. Switching usage
/// statistics off also deletes what the server kept (`forgetMe`).
///
/// Sent: the search (words, about where, radius, chips, how many results, how long it took; for people search no words at all), the
/// first 10 results shown, the result opened and its position, what is done on that page within 30 minutes (message, directions,
/// cart, order, sync, share; iOS pages have no Call button and no page types, so no CALL or BOOK yet), and a ↑ or ↓ given to a page,
/// tied to the search it came from when it came from one. Batched every 30 s and when the search screen closes. A send that fails is
/// dropped: logging never retries, never shows an error and never slows search down.
@MainActor
public final class DiscoveryLog {
    public static let shared = DiscoveryLog()
    init() {}

    /// One value of an event, in the form log_discovery's checks accept: whole numbers as integers and coordinates as plain decimals
    /// (a Double can leave JSONSerialization with 15 or more decimals, which discovery_num refuses).
    enum Field: Equatable, Sendable {
        case text(String), int(Int), decimal(Decimal), texts([String]), object([String: String]), null
        /// What goes into a request body (Backend writes it with JSONSerialization).
        var wire: Any {
            switch self {
            case .text(let s): s
            case .int(let n): n
            case .decimal(let d): NSDecimalNumber(decimal: d)
            case .texts(let a): a
            case .object(let o): o
            case .null: NSNull()
            }
        }
    }
    typealias Event = [String: Field]

    static let sendEveryNs: UInt64 = 30_000_000_000
    static let actionWindow: TimeInterval = 30 * 60
    static let maxPending = 1_000
    /// log_discovery takes at most 200 events in one call.
    static let perCall = 200

    private var allowed = false
    /// Events waiting for the next send.
    private(set) var pending: [Event] = []
    private var sender: Task<Void, Never>?
    /// The send (or deletion) on its way. The next one starts after it, so "forget me" can't be overtaken by a batch already going out.
    private var inFlight: Task<Void, Never>?
    /// The search a result was opened from, so what is done on that page can point back to it.
    private var lastOpen: (queryId: String, listingId: String, at: Date)?
    private lazy var app: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        return "ios \(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
    }()

    /// On for adults who haven't switched usage statistics off, in builds that talk to the cloud.
    public var on: Bool { Backend.shared.enabled && allowed }

    /// Called whenever the age band or the person's choice changes (Analytics.configure on Android). `band`: ADULT, TEEN, CHILD or
    /// UNKNOWN (not known yet, or signed out: stay off). Off drops whatever was waiting.
    public func configure(band: String, optedIn: Bool) {
        allowed = band == "ADULT" && optedIn
        if !allowed { pending.removeAll(); lastOpen = nil }
    }

    /// A new search id; the events that follow point at it.
    public func newId() -> String { UUID().uuidString.lowercased() }

    /// A search that ran and gave `n` results in `ms` milliseconds. People search passes `q` nil: the name typed is never sent.
    /// Filters whose value is nil are left out.
    public func search(_ id: String, surface: String, q: String?, at: LatLng, radiusM: Int, filters: [String: String?], n: Int, ms: Int) {
        guard on else { return }
        let words: Field = q.map { Field.text(String($0.prefix(100))) } ?? .null
        var e: Event = ["t": .text("QUERY"), "id": .text(id), "surface": .text(surface), "q": words, "radius_m": .int(radiusM), "n": .int(n), "ms": .int(ms)]
        e["lat"] = Self.coordinate(at.lat); e["lng"] = Self.coordinate(at.lng)
        e["app"] = .text(app); e["ranker"] = .text("v1"); e["at"] = .text(Self.now())
        e["filters"] = .object(filters.compactMapValues { $0 })
        add(e)
    }

    /// The first results shown for search `queryId`, in the order shown.
    public func shown(_ queryId: String, listingIds: [String]) {
        guard on, !listingIds.isEmpty else { return }
        add(["t": .text("IMPRESSION"), "query_id": .text(queryId), "subject_type": .text("LISTING"), "at": .text(Self.now()), "ids": .texts(Array(listingIds.prefix(10)))])
    }

    /// A result of search `queryId` opened at `position` (0 = the first).
    public func opened(_ queryId: String, listingId: String, position: Int) {
        guard on else { return }
        lastOpen = (queryId, listingId, Date())
        add(event("OPEN", queryId, listingId, position: position))
    }

    /// Something done on a page opened from search in the last 30 minutes: CALL, MESSAGE, DIRECTIONS, ADD_TO_CART, ORDER, BOOK, SYNC
    /// or SHARE. Anything done on a page that wasn't opened from search is not sent.
    public func acted(_ kind: String, listingId: String?) {
        guard on, let listingId, let qid = queryFor(listingId) else { return }
        add(event(kind, qid, listingId, position: nil))
    }

    /// The search `listingId` was opened from, when it was opened from search in the last 30 minutes.
    public func queryFor(_ listingId: String) -> String? {
        guard let o = lastOpen, o.listingId == listingId, Date().timeIntervalSince(o.at) <= Self.actionWindow else { return nil }
        return o.queryId
    }

    /// The person rated a page ↑ (`vote` 1) or ↓ (-1): the outcome of the search it came from (`queryId`, when known). A vote with
    /// no search is still sent; 0 (a review removed) is not.
    public func voted(_ listingId: String, vote: Int, queryId: String?) {
        guard on, vote != 0 else { return }
        var e: Event = ["t": .text("VOTE"), "subject_type": .text("LISTING"), "subject_id": .text(listingId), "detail": .text(vote > 0 ? "UP" : "DOWN"), "at": .text(Self.now())]
        if let queryId { e["query_id"] = .text(queryId) }
        add(e)
    }

    /// Sends what is waiting now; it is also sent every 30 s on its own.
    public func flush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        guard on else { return }
        let before = inFlight
        inFlight = Task {
            await before?.value
            for start in stride(from: 0, to: batch.count, by: Self.perCall) {
                _ = try? await Backend.shared.logDiscovery(batch[start..<min(start + Self.perCall, batch.count)].map(Self.wire))
            }
        }
    }

    /// Usage statistics switched off: nothing more is sent, and what the server kept is deleted.
    public func forgetMe() {
        pending.removeAll(); lastOpen = nil
        guard Backend.shared.enabled else { return }
        let before = inFlight
        inFlight = Task { await before?.value; try? await Backend.shared.discoveryForgetMe() }
    }

    private func event(_ kind: String, _ queryId: String, _ listingId: String, position: Int?) -> Event {
        var e: Event = ["t": .text(kind), "query_id": .text(queryId), "subject_type": .text("LISTING"), "subject_id": .text(listingId), "at": .text(Self.now())]
        if let position { e["position"] = .int(position) }
        return e
    }

    /// Keeps the event and, unless a send is already due, sends in 30 s.
    private func add(_ e: Event) {
        if pending.count < Self.maxPending { pending.append(e) }
        guard sender == nil else { return }
        sender = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.sendEveryNs)
            guard let self else { return }
            self.sender = nil
            self.flush()
        }
    }

    /// An event as a request body holds it.
    nonisolated static func wire(_ e: Event) -> [String: Any] { e.mapValues(\.wire) }
    /// A coordinate to 6 decimals (about 10 cm; the server keeps only a cell of about 2 km), as a decimal so it is written exactly.
    nonisolated static func coordinate(_ v: Double) -> Field {
        guard v.isFinite, abs(v) <= 180 else { return .null }
        return .decimal(Decimal(Int((v * 1_000_000).rounded())) / 1_000_000)
    }
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static func now() -> String { iso.string(from: Date()) }
}
