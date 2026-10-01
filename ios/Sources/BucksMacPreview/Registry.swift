#if os(macOS)
import Foundation

/// Each area adds ONE line below (re-read the file before editing; other agents add theirs at the same time):
/// `FakeSupabase.areaHandlers.append(fakeDiscover)` and/or `Scenarios.extra["discover"] = scenarioDiscover`.
@MainActor
enum HarnessRegistry {
    static func registerAll() {
        // --- area registrations (one line each) ---
        Scenarios.extra["shell"] = scenarioShell
        FakeSupabase.areaHandlers.append(fakeFeed); Scenarios.extra["feed"] = scenarioFeed
        FakeSupabase.areaHandlers.append(fakeChat); Scenarios.extra["chat"] = scenarioChat
        FakeSupabase.areaHandlers.append(fakeDiscover); Scenarios.extra["discover"] = scenarioDiscover
        FakeSupabase.areaHandlers.insert(fakeStudio, at: 0); Scenarios.extra["studio"] = scenarioStudio
    }
}
#endif
