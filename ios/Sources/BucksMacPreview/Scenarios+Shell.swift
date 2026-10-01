#if os(macOS)
import SwiftUI
import BucksCore
import BucksUI

/// The app shell: every tab with its bottom bar, the side menu, and a pushed screen with and without the bar.
@MainActor
func scenarioShell(_ session: AppSession, _ router: Router) async {
    for (n, t) in [("sh01-home", BottomTab.home), ("sh02-feed", .feed), ("sh03-services", .services), ("sh04-foryou", .recommended), ("sh05-profile", .account)] {
        router.select(t); await Scenarios.pause(2.5); Scenarios.snap(n)
    }
    router.select(.home); router.menuOpen = true; await Scenarios.pause(1.2); Scenarios.snap("sh06-menu")
    router.menuOpen = false; router.select(.account, accountTab: "settings"); await Scenarios.pause(2); Scenarios.snap("sh07-settings")
    router.select(.home); router.push(.search); await Scenarios.pause(2); Scenarios.snap("sh08-search")
    router.popToRoot(); router.push(.messages); await Scenarios.pause(2); Scenarios.snap("sh09-messages")
}
#endif
