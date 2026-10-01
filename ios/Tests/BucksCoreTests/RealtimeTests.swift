import Foundation
import Testing
@testable import BucksCore

/// A scripted socket: frames the test pushes come out of `receive()`, everything the client sends is recorded.
final class StubSocket: WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sentFrames: [String] = []
    private var closed = false
    private let incoming: AsyncThrowingStream<String, Error>
    private let feed: AsyncThrowingStream<String, Error>.Continuation
    private var iterator: AsyncThrowingStream<String, Error>.AsyncIterator

    init() {
        var c: AsyncThrowingStream<String, Error>.Continuation!
        incoming = AsyncThrowingStream { c = $0 }
        feed = c; iterator = incoming.makeAsyncIterator()
    }
    var sent: [String] { lock.lock(); defer { lock.unlock() }; return sentFrames }
    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }
    func push(_ frame: String) { feed.yield(frame) }
    func drop() { feed.finish(throwing: URLError(.networkConnectionLost)) }
    private func record(_ text: String) { lock.lock(); sentFrames.append(text); lock.unlock() }
    func send(_ text: String) async throws { record(text) }
    func receive() async throws -> String {
        guard let s = try await iterator.next() else { throw URLError(.cancelled) }
        return s
    }
    func close() { lock.lock(); closed = true; lock.unlock(); feed.finish() }
}

final class StubSockets: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var made: [StubSocket] = []
    func make() -> StubSocket { let s = StubSocket(); lock.lock(); made.append(s); lock.unlock(); return s }
    var count: Int { lock.lock(); defer { lock.unlock() }; return made.count }
    subscript(i: Int) -> StubSocket { lock.lock(); defer { lock.unlock() }; return made[i] }
}

func json(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:] }
func waitUntil(_ timeout: Double = 3, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 10_000_000) }
    return cond()
}

@Suite(.serialized) struct RealtimeTests {
    @Test func joinFrameCarriesTheTableFilterAndToken() {
        let m = json(Phoenix.join(topic: "realtime:bucks-tasks-1", ref: "7", table: "tasks", filter: "id=eq.abc", events: ["*"], token: "TOK"))
        #expect(m["topic"] as? String == "realtime:bucks-tasks-1"); #expect(m["event"] as? String == "phx_join"); #expect(m["ref"] as? String == "7")
        let p = m["payload"] as? [String: Any] ?? [:]
        #expect(p["access_token"] as? String == "TOK")
        let cfg = p["config"] as? [String: Any] ?? [:]
        let pc = (cfg["postgres_changes"] as? [[String: Any]]) ?? []
        #expect(pc.count == 1)
        #expect(pc.first?["event"] as? String == "*"); #expect(pc.first?["schema"] as? String == "public")
        #expect(pc.first?["table"] as? String == "tasks"); #expect(pc.first?["filter"] as? String == "id=eq.abc")
        #expect((cfg["broadcast"] as? [String: Any])?["self"] as? Bool == false)
    }

    @Test func joinWithoutFilterAndSeveralEvents() {
        let p = json(Phoenix.join(topic: "t", ref: "1", table: "messages", filter: nil, events: ["INSERT", "UPDATE"], token: "x"))["payload"] as? [String: Any] ?? [:]
        let pc = ((p["config"] as? [String: Any])?["postgres_changes"] as? [[String: Any]]) ?? []
        #expect(pc.map { $0["event"] as? String } == ["INSERT", "UPDATE"])
        #expect(pc.allSatisfy { $0["filter"] == nil })
    }

    @Test func heartbeatLeaveAndTokenFrames() {
        let h = json(Phoenix.heartbeat(ref: "3"))
        #expect(h["topic"] as? String == "phoenix"); #expect(h["event"] as? String == "heartbeat"); #expect(h["ref"] as? String == "3")
        #expect(json(Phoenix.leave(topic: "realtime:a", ref: "4"))["event"] as? String == "phx_leave")
        let t = json(Phoenix.accessToken(topic: "realtime:a", ref: "5", token: "NEW"))
        #expect(t["event"] as? String == "access_token"); #expect((t["payload"] as? [String: Any])?["access_token"] as? String == "NEW")
    }

    @Test func socketURLUsesWssAndTheAnonKey() {
        let u = Phoenix.socketURL(base: "https://abc.supabase.co", anonKey: "anon-key")
        #expect(u?.absoluteString == "wss://abc.supabase.co/realtime/v1/websocket?apikey=anon-key&vsn=1.0.0")
    }

    @Test func decodesAPostgresChangeWithItsRecord() throws {
        let frame = #"{"topic":"realtime:bucks-tasks-1","event":"postgres_changes","ref":null,"payload":{"ids":[1],"data":{"schema":"public","table":"tasks","type":"UPDATE","commit_timestamp":"2026-10-01T10:00:00Z","record":{"id":"t1","status":"MATCHED","driver_id":"d1"},"old_record":{"id":"t1"},"errors":null}}}"#
        let m = try #require(Phoenix.decode(frame))
        let c = try #require(Phoenix.change(in: m))
        #expect(c.event == "UPDATE")
        #expect(json(String(decoding: try #require(c.record), as: UTF8.self))["status"] as? String == "MATCHED")
        #expect(json(String(decoding: try #require(c.oldRecord), as: UTF8.self))["id"] as? String == "t1")
        #expect(Phoenix.change(in: try #require(Phoenix.decode(#"{"topic":"phoenix","event":"phx_reply","ref":"1","payload":{"status":"ok","response":{}}}"#))) == nil)
        #expect(Phoenix.decode("not json") == nil)
    }

    private func client(_ sockets: StubSockets, token: @escaping @Sendable () async -> String? = { "TOK" }, heartbeat: Double = 25, refresh: Double = 3000) -> RealtimeClient {
        var timing = RealtimeClient.Timing()
        timing.heartbeat = heartbeat; timing.tokenRefresh = refresh; timing.backoff = { _ in 0.02 }
        return RealtimeClient(timing: timing, endpoint: { URL(string: "wss://x.supabase.co/realtime/v1/websocket?apikey=a&vsn=1.0.0") }, token: token, factory: { _ in sockets.make() })
    }
    private func topic(of frame: String) -> String { json(frame)["topic"] as? String ?? "" }

    @Test func joinsOnSubscribeYieldsChangesAndLeavesWhenTheConsumerStops() async throws {
        let sockets = StubSockets(); let c = client(sockets)
        let consumer = Task<[String], Never> {
            var got: [String] = []
            for await ch in c.subscribe(table: "tasks", filter: "id=eq.t1", events: ["*"]) { got.append(ch.event); if got.count == 2 { break } }
            return got
        }
        #expect(await waitUntil { sockets.count == 1 && sockets[0].sent.count == 1 })
        let join = json(sockets[0].sent[0])
        #expect(join["event"] as? String == "phx_join")
        let topic = join["topic"] as? String ?? ""
        let change = { (type: String) in #"{"topic":"\#(topic)","event":"postgres_changes","ref":null,"payload":{"ids":[1],"data":{"type":"\#(type)","record":{"id":"t1"}}}}"# }
        sockets[0].push(#"{"topic":"\#(topic)","event":"phx_reply","ref":"1","payload":{"status":"ok","response":{}}}"#)
        sockets[0].push(change("UPDATE")); sockets[0].push(change("INSERT"))
        #expect(await consumer.value == ["UPDATE", "INSERT"])
        // The consumer broke out of its loop: the channel is left and the socket closed.
        #expect(await waitUntil { sockets[0].sent.contains { json($0)["event"] as? String == "phx_leave" } })
        #expect(await waitUntil { sockets[0].isClosed })
    }

    @Test func oneSocketCarriesEveryChannel() async throws {
        let sockets = StubSockets(); let c = client(sockets)
        let a = Task { for await _ in c.subscribe(table: "tasks", filter: nil, events: ["*"]) {} }
        let b = Task { for await _ in c.subscribe(table: "messages", filter: "conversation_id=eq.9", events: ["INSERT"]) {} }
        #expect(await waitUntil { sockets.count >= 1 && sockets[0].sent.filter { json($0)["event"] as? String == "phx_join" }.count == 2 })
        #expect(sockets.count == 1)
        let topics = Set(sockets[0].sent.map(topic(of:)))
        #expect(topics.count == 2)
        a.cancel(); b.cancel()
    }

    @Test func reconnectsAndRejoinsAfterTheSocketDrops() async throws {
        let sockets = StubSockets(); let c = client(sockets)
        let t = Task { for await _ in c.subscribe(table: "tasks", filter: "status=eq.SEARCHING", events: ["*"]) {} }
        #expect(await waitUntil { sockets.count == 1 && !sockets[0].sent.isEmpty })
        sockets[0].drop()
        #expect(await waitUntil { sockets.count == 2 && !sockets[1].sent.isEmpty })
        let join = json(sockets[1].sent[0])
        #expect(join["event"] as? String == "phx_join")
        let cfg = ((join["payload"] as? [String: Any])?["config"] as? [String: Any]) ?? [:]
        #expect(((cfg["postgres_changes"] as? [[String: Any]])?.first?["filter"] as? String) == "status=eq.SEARCHING")
        t.cancel()
    }

    @Test func heartbeatsAreSentAndAMissedReplyForcesAReconnect() async throws {
        let sockets = StubSockets(); let c = client(sockets, heartbeat: 0.05)
        let t = Task { for await _ in c.subscribe(table: "tasks", filter: nil, events: ["*"]) {} }
        #expect(await waitUntil { sockets.count >= 1 && sockets[0].sent.contains { json($0)["event"] as? String == "heartbeat" } })
        // Nobody answers the heartbeat: the next tick closes the socket and a new one is opened.
        #expect(await waitUntil { sockets.count >= 2 })
        #expect(sockets[0].isClosed)
        t.cancel()
    }

    @Test func refreshesTheTokenOnOpenChannels() async throws {
        let sockets = StubSockets()
        let counter = Counter()
        let c = client(sockets, token: { "TOK\(counter.next())" }, refresh: 0.05)
        let t = Task { for await _ in c.subscribe(table: "tasks", filter: nil, events: ["*"]) {} }
        #expect(await waitUntil { sockets.count >= 1 && sockets[0].sent.contains { json($0)["event"] as? String == "access_token" } })
        let frame = sockets[0].sent.first { json($0)["event"] as? String == "access_token" }.map(json)
        #expect(((frame?["payload"] as? [String: Any])?["access_token"] as? String)?.hasPrefix("TOK") == true)
        t.cancel()
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}
