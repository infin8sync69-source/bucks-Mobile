import Foundation
import Testing
@testable import BucksCore

@Suite struct PushRouteTests {
    @Test func safeRouteKeepsOnlyRoutesTheAppCanOpen() {
        for r in ["home", "feed", "sync", "messages", "invites", "my/orders", "my/applications", "my/listings", "jobs-near", "bucks-id"] { #expect(Push.safeRoute(r) == r) }
        for r in ["chat/abc", "cloud-order/9", "orders-for/L1", "delivery/t1", "moments/u1", "l/L1", "job/j1", "jobs-of/L1", "members/L1", "studio/L1", "listing-docs/L1", "post/p1"] { #expect(Push.safeRoute(r) == r) }
    }
    @Test func safeRouteRefusesAnythingElse() {
        #expect(Push.safeRoute(nil) == nil); #expect(Push.safeRoute("") == nil); #expect(Push.safeRoute("   ") == nil)
        #expect(Push.safeRoute("chat/") == nil)              // a prefix needs an id after it
        #expect(Push.safeRoute("settings") == nil); #expect(Push.safeRoute("https://evil.example") == nil); #expect(Push.safeRoute("../chat/x") == nil)
        #expect(Push.safeRoute("chat/a\nb") == nil)
        #expect(Push.safeRoute("chat/" + String(repeating: "x", count: 200)) == nil)
    }
    @Test func safeRouteTrimsWhitespace() { #expect(Push.safeRoute("  messages ") == "messages") }

    @Test func payloadReadsTheServersDataKeys() throws {
        let p = try #require(PushPayload(userInfo: ["type": "tasks", "title": "Ravi is here", "body": "KA05AB1234", "route": "delivery/t1", "quiet": "false", "gcm.message_id": "1"]))
        #expect(p.kind == .tasks); #expect(p.title == "Ravi is here"); #expect(p.body == "KA05AB1234"); #expect(p.route == "delivery/t1"); #expect(!p.quiet)
        #expect(p.interruptionLevel == "timeSensitive")
        #expect(p.foreground == .init(banner: true, list: true, sound: true))
    }
    @Test func payloadFallsBackToTheApsAlertAndDropsUnsafeRoutes() throws {
        let p = try #require(PushPayload(userInfo: ["aps": ["alert": ["title": "Asha", "body": "Hi"]], "route": "evil/x"]))
        #expect(p.title == "Asha"); #expect(p.body == "Hi"); #expect(p.route == nil); #expect(p.kind == .social)
        #expect(PushPayload(userInfo: ["body": "no title"]) == nil)
    }
    @Test func aRideRequestRingsInTheAppNotAsABanner() throws {
        let p = try #require(PushPayload(userInfo: ["type": "ride", "title": "New ride request", "body": "Jayanagar to MG Road", "route": "home"]))
        #expect(p.kind == .ride); #expect(p.interruptionLevel == "timeSensitive")
        #expect(p.foreground == .init(banner: false, list: false, sound: false))
    }
    @Test func quietHoursArePassiveAndSilent() throws {
        let p = try #require(PushPayload(userInfo: ["type": "messages", "title": "t", "quiet": "true"]))
        #expect(p.interruptionLevel == "passive"); #expect(p.foreground == .init(banner: false, list: true, sound: false))
    }
    @Test func kindsMapToAndroidsChannelIds() {
        #expect(PushKind(type: "messages").categoryId == "bucks_messages"); #expect(PushKind(type: "orders").categoryId == "bucks_orders")
        #expect(PushKind(type: "tasks").categoryId == "bucks_trips"); #expect(PushKind(type: "ride").categoryId == "bucks_ride_request"); #expect(PushKind(type: "anything").categoryId == "bucks_social"); #expect(PushKind(type: nil) == .social)
    }
    @MainActor @Test func inboxKeepsOnlyASafeRouteAndHandsItOutOnce() {
        let inbox = PushInbox()
        inbox.open("nope"); #expect(inbox.take() == nil)
        inbox.open("chat/c1"); #expect(inbox.pending == "chat/c1"); #expect(inbox.take() == "chat/c1"); #expect(inbox.take() == nil)
    }
}

extension DispatchTests {
    @Test func deviceTokenCallsUseTheServersParameterNames() async throws {
        boot { path, _, _ in path.hasSuffix("register_device_token") || path.hasSuffix("unregister_device_token") ? (204, [:]) : (404, [:]) }
        try await Backend.shared.registerDeviceToken("fcm-token-1")
        try await Backend.shared.unregisterDeviceToken("fcm-token-1")
        let reg = try #require(FakeServer.calls.first { $0.path == "/rest/v1/rpc/register_device_token" })
        #expect(Set(reg.body.keys) == ["p_token", "p_platform"]); #expect(reg.body["p_token"] as? String == "fcm-token-1"); #expect(reg.body["p_platform"] as? String == "ios")
        let unreg = try #require(FakeServer.calls.first { $0.path == "/rest/v1/rpc/unregister_device_token" })
        #expect(Set(unreg.body.keys) == ["p_token"])
    }

    @Test func registeringAndSigningOutTalkToTheServerOnce() async throws {
        boot { path, _, _ in path.hasSuffix("device_token") || path.hasSuffix("register_device_token") ? (204, [:]) : (404, [:]) }
        final class P: PushTokenProvider, @unchecked Sendable {
            var deleted = false
            func token() async throws -> String? { "fcm-A" }
            func deleteToken() async throws { deleted = true }
        }
        let p = P(); Push.shared.provider = p
        Push.shared.registerIfSignedIn()
        #expect(await wait { FakeServer.calls.contains { $0.path.hasSuffix("/register_device_token") } })
        await Push.shared.unregister()
        let unreg = try #require(FakeServer.calls.first { $0.path.hasSuffix("/unregister_device_token") })
        #expect(unreg.body["p_token"] as? String == "fcm-A"); #expect(p.deleted)
        // A token that arrives after sign-out is not stored against the leaving person.
        let before = FakeServer.calls.count
        await Push.shared.register("fcm-B")
        #expect(FakeServer.calls.count == before)
        Push.shared.provider = nil
    }
}
