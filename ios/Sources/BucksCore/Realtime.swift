import Foundation

/// A row change from Supabase Realtime. `event` is INSERT, UPDATE or DELETE; `record` is the new row as JSON (decode with `Backend.decoder`).
public struct RealtimeChange: Sendable {
    public var event: String
    public var record: Data?
    /// The previous row (UPDATE and DELETE; only the primary key unless the table has replica identity full).
    public var oldRecord: Data?
    public init(event: String, record: Data?, oldRecord: Data? = nil) { self.event = event; self.record = record; self.oldRecord = oldRecord }
}

// MARK: - Phoenix wire format (vsn 1.0.0: one JSON object per frame)

/// One Phoenix channel frame: `{topic, event, payload, ref}`.
public struct PhoenixMessage: Sendable, Equatable {
    public var topic: String
    public var event: String
    public var ref: String?
    public var payload: JSONValue
}

/// Builds and reads the frames Supabase Realtime speaks (what supabase-kt's RealtimeChannel sends for `postgresChangeFlow`).
public enum Phoenix {
    public static func encode(topic: String, event: String, ref: String?, payload: JSONValue) -> String {
        var o: [String: JSONValue] = ["topic": .string(topic), "event": .string(event), "payload": payload]
        o["ref"] = ref.map { .string($0) } ?? .null
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: e.encode(JSONValue.object(o)), as: UTF8.self)) ?? "{}"
    }

    public static func decode(_ text: String) -> PhoenixMessage? {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), let topic = v["topic"]?.string, let event = v["event"]?.string else { return nil }
        let ref: String? = v["ref"]?.string ?? v["ref"]?.int.map(String.init)
        return PhoenixMessage(topic: topic, event: event, ref: ref, payload: v["payload"] ?? .emptyObject)
    }

    /// `phx_join` for one table: one `postgres_changes` entry per event, the person's token in the payload.
    public static func join(topic: String, ref: String, table: String, filter: String?, events: [String], token: String) -> String {
        let entries: [JSONValue] = (events.isEmpty ? ["*"] : events).map { ev in
            var o: [String: JSONValue] = ["event": .string(ev), "schema": .string("public"), "table": .string(table)]
            if let filter, !filter.isEmpty { o["filter"] = .string(filter) }
            return .object(o)
        }
        let config: JSONValue = .object([
            "broadcast": .object(["ack": .bool(false), "self": .bool(false)]),
            "presence": .object(["key": .string("")]),
            "postgres_changes": .array(entries),
            "private": .bool(false),
        ])
        return encode(topic: topic, event: "phx_join", ref: ref, payload: .object(["config": config, "access_token": .string(token)]))
    }
    public static func leave(topic: String, ref: String) -> String { encode(topic: topic, event: "phx_leave", ref: ref, payload: .emptyObject) }
    public static func heartbeat(ref: String) -> String { encode(topic: "phoenix", event: "heartbeat", ref: ref, payload: .emptyObject) }
    public static func accessToken(topic: String, ref: String, token: String) -> String {
        encode(topic: topic, event: "access_token", ref: ref, payload: .object(["access_token": .string(token)]))
    }

    /// The change inside a `postgres_changes` frame, or nil for any other frame.
    public static func change(in m: PhoenixMessage) -> RealtimeChange? {
        guard m.event == "postgres_changes", let data = m.payload["data"], let type = data["type"]?.string else { return nil }
        func bytes(_ v: JSONValue?) -> Data? { guard let v, v != .null else { return nil }; return try? JSONEncoder().encode(v) }
        return RealtimeChange(event: type, record: bytes(data["record"]), oldRecord: bytes(data["old_record"]))
    }

    /// `https://<project>.supabase.co` becomes `wss://<project>.supabase.co/realtime/v1/websocket?apikey=…&vsn=1.0.0`.
    public static func socketURL(base: String, anonKey: String) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        c.scheme = (c.scheme == "http") ? "ws" : "wss"
        c.path = "/realtime/v1/websocket"
        c.queryItems = [URLQueryItem(name: "apikey", value: anonKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return c.url
    }
}

// MARK: - Transport

/// The socket under the client; the real one is URLSession's, tests use a stub.
public protocol WebSocketTransport: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// The next text frame; throws when the socket closes or fails.
    func receive() async throws -> String
    func close()
}

final class URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    init(url: URL) { session = URLSession(configuration: .default); task = session.webSocketTask(with: url); task.resume() }
    func send(_ text: String) async throws { try await task.send(.string(text)) }
    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let s): return s
        case .data(let d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }
    /// Also invalidates the session: a URLSession keeps itself alive until told otherwise, so every reconnect would leak one.
    func close() { task.cancel(with: .goingAway, reason: nil); session.finishTasksAndInvalidate() }
}

// MARK: - Client

/// One shared websocket to Supabase Realtime carrying a channel per consumer. It joins with the person's token, answers the
/// heartbeat, refreshes the token on the open channels, and reconnects with a growing pause and rejoins everything after a drop.
public actor RealtimeClient {
    public struct Timing: Sendable {
        public var heartbeat: TimeInterval = 25
        public var tokenRefresh: TimeInterval = 50 * 60
        public var backoff: @Sendable (Int) -> TimeInterval = { n in min(30, pow(2, Double(min(n, 5)))) * Double.random(in: 0.8...1.2) }
        public init() {}
    }

    private struct Sub {
        var topic: String; var table: String; var filter: String?; var events: [String]
        var cont: AsyncStream<RealtimeChange>.Continuation
        var joinedOn: ObjectIdentifier?; var joinRef: String?; var failures = 0
    }

    private let endpoint: @Sendable () async -> URL?
    private let token: @Sendable () async -> String?
    private let factory: @Sendable (URL) -> WebSocketTransport
    private let timing: Timing

    private var subs: [Int: Sub] = [:]
    private var nextId = 0, refCounter = 0, generation = 0
    private var transport: WebSocketTransport?
    private var runner: Task<Void, Never>?
    private var pendingHeartbeat: String?

    public init(timing: Timing = Timing(), endpoint: @escaping @Sendable () async -> URL?, token: @escaping @Sendable () async -> String?, factory: @escaping @Sendable (URL) -> WebSocketTransport) {
        self.timing = timing; self.endpoint = endpoint; self.token = token; self.factory = factory
    }

    private let ids = IdSource()
    private final class IdSource: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }
    private var gone = Set<Int>()

    /// Joins `realtime:…` for the table and yields every change until the consumer stops; stopping leaves the channel.
    public nonisolated func subscribe(table: String, filter: String?, events: [String]) -> AsyncStream<RealtimeChange> {
        let id = ids.next()
        return AsyncStream { cont in
            Task { await self.add(id, table: table, filter: filter, events: events, cont: cont) }
            cont.onTermination = { _ in Task { await self.leave(id) } }
        }
    }

    // MARK: subscriptions

    private func add(_ id: Int, table: String, filter: String?, events: [String], cont: AsyncStream<RealtimeChange>.Continuation) async {
        // The consumer may have stopped before this ran.
        if gone.remove(id) != nil { return }
        subs[id] = Sub(topic: "realtime:bucks-\(table)-\(id)", table: table, filter: filter, events: events, cont: cont)
        if let t = transport { await join(id, on: t) }
        if runner == nil { start() }
    }

    private func leave(_ id: Int) async {
        guard let s = subs.removeValue(forKey: id) else { gone.insert(id); return }
        if let t = transport, s.joinedOn == ObjectIdentifier(t) { try? await t.send(Phoenix.leave(topic: s.topic, ref: nextRef())) }
        if subs.isEmpty { stop() }
    }

    private func nextRef() -> String { refCounter += 1; return String(refCounter) }

    private func join(_ id: Int, on t: WebSocketTransport) async {
        guard var s = subs[id], s.joinedOn != ObjectIdentifier(t) else { return }
        let ref = nextRef()
        s.joinedOn = ObjectIdentifier(t); s.joinRef = ref; subs[id] = s
        let access = (await token()) ?? ""
        try? await t.send(Phoenix.join(topic: s.topic, ref: ref, table: s.table, filter: s.filter, events: s.events, token: access))
    }

    // MARK: connection

    private func start() {
        generation += 1
        let gen = generation
        runner = Task { await self.run(gen) }
    }
    private func stop() {
        generation += 1
        runner?.cancel(); runner = nil
        transport?.close(); transport = nil; pendingHeartbeat = nil
    }

    private func run(_ gen: Int) async {
        var failures = 0
        while !Task.isCancelled, gen == generation, !subs.isEmpty {
            guard let url = await endpoint() else { failures += 1; await pause(timing.backoff(failures)); continue }
            let t = factory(url)
            transport = t; pendingHeartbeat = nil
            for id in subs.keys { subs[id]?.joinedOn = nil; subs[id]?.joinRef = nil }
            let beat = Task { await self.heartbeatLoop(t) }
            let refresh = Task { await self.tokenLoop(t) }
            for id in subs.keys.sorted() { await join(id, on: t) }
            do {
                while !Task.isCancelled {
                    let text = try await t.receive()
                    failures = 0
                    await handle(text, on: t)
                }
            } catch {}
            beat.cancel(); refresh.cancel(); t.close()
            if gen == generation { transport = nil }
            guard !Task.isCancelled, gen == generation, !subs.isEmpty else { return }
            failures += 1
            await pause(timing.backoff(failures))
        }
    }

    private func pause(_ seconds: TimeInterval) async { try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }

    private func heartbeatLoop(_ t: WebSocketTransport) async {
        while !Task.isCancelled {
            await pause(timing.heartbeat)
            if Task.isCancelled { return }
            // The last heartbeat never came back: the socket is dead without telling anyone. Close it so the loop reconnects.
            if pendingHeartbeat != nil { t.close(); return }
            let ref = nextRef(); pendingHeartbeat = ref
            do { try await t.send(Phoenix.heartbeat(ref: ref)) } catch { t.close(); return }
        }
    }

    /// Firebase tokens last an hour: hand the channels a fresh one before the old one runs out.
    private func tokenLoop(_ t: WebSocketTransport) async {
        while !Task.isCancelled {
            await pause(timing.tokenRefresh)
            if Task.isCancelled { return }
            guard let access = await token() else { continue }
            for s in subs.values where s.joinedOn == ObjectIdentifier(t) { try? await t.send(Phoenix.accessToken(topic: s.topic, ref: nextRef(), token: access)) }
        }
    }

    private func handle(_ text: String, on t: WebSocketTransport) async {
        guard let m = Phoenix.decode(text) else { return }
        switch m.event {
        case "postgres_changes":
            if let c = Phoenix.change(in: m), let s = subs.values.first(where: { $0.topic == m.topic }) { s.cont.yield(c) }
        case "phx_reply":
            if m.ref != nil, m.ref == pendingHeartbeat { pendingHeartbeat = nil; return }
            guard let id = subs.first(where: { $0.value.topic == m.topic })?.key, subs[id]?.joinRef == m.ref else { return }
            if m.payload["status"]?.string == "ok" { subs[id]?.failures = 0 } else { await rejoin(id, on: t) }
        case "phx_error", "phx_close":
            if let id = subs.first(where: { $0.value.topic == m.topic })?.key { await rejoin(id, on: t) }
        default: break
        }
    }

    /// One channel failed to join or was closed by the server: join it again after a pause, leaving the others alone.
    private func rejoin(_ id: Int, on t: WebSocketTransport) async {
        guard var s = subs[id] else { return }
        s.failures += 1; s.joinedOn = nil; subs[id] = s
        let wait = timing.backoff(s.failures)
        Task {
            await self.pause(wait)
            if await self.transport === t { await self.join(id, on: t) }
        }
    }
}

// MARK: - The app's shared client

enum RealtimeHub {
    /// False under test (requests are stubbed): `changes` then never yields instead of dialling the network.
    nonisolated(unsafe) static var live = true
    static let client = RealtimeClient(
        endpoint: {
            guard let c = Backend.shared.config, c.isComplete else { return nil }
            return Phoenix.socketURL(base: c.url, anonKey: c.anonKey)
        },
        token: { await Backend.shared.accessToken() ?? Backend.shared.config?.anonKey },
        factory: { URLSessionWebSocketTransport(url: $0) })
}

public extension Backend {
    /// A stream of changes on `table` (row-level security still applies), optionally narrowed by a PostgREST-style filter such as `id=eq.<uuid>`.
    /// Cancel the consuming task to close it. Callers keep their polling: this only makes them quicker.
    func changes(table: String, filter: String? = nil, events: [String] = ["*"]) -> AsyncStream<RealtimeChange> {
        guard enabled, RealtimeHub.live else { return AsyncStream { _ in } }
        return RealtimeHub.client.subscribe(table: table, filter: filter, events: events)
    }
}
