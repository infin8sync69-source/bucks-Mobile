#if os(macOS)
import SwiftUI
import AppKit
import BucksCore
import BucksUI

/// Search, three listing profiles, and the Services and Recommended tabs (hosted in a second window, since the tab shell is the app's own).
@MainActor
func scenarioDiscover(_ session: AppSession, _ router: Router) async {
    let p = Scenarios.pause
    session.discover.pendingQuery = ""
    router.push(.search); await p(1.5); Scenarios.snap("dc01-search-empty")
    session.discover.query = "sugar"; await p(2.0); Scenarios.snap("dc02-search-sugar")
    session.discover.query = ""; session.discover.selectKind(.drivers); await p(1.5); Scenarios.snap("dc03-search-drivers")
    router.pop(); router.push(.listing("L-shop")); await p(2.5); Scenarios.snap("dc04-shop")
    router.pop(); router.push(.listing("L-pro")); await p(2.5); Scenarios.snap("dc05-pro")
    router.pop(); router.push(.listing("L-drv")); await p(2.5); Scenarios.snap("dc06-driver")
    router.pop(); router.push(.listing("L-nope")); await p(2.0); Scenarios.snap("dc07-missing")
    router.popToRoot()

    // The tab roots have no route of their own: show them in the main window for a moment, then put the app back.
    guard let main = NSApplication.shared.windows.first(where: { $0.contentView != nil && $0.frame.width > 100 && $0.frame.width < 500 }), let original = main.contentViewController else { return }
    main.contentViewController = NSHostingController(rootView: DiscoverPreview.services(session: session, router: router))
    await p(2.5); Scenarios.snap("dc08-services")
    main.contentViewController = NSHostingController(rootView: DiscoverPreview.recommended(session: session, router: router))
    await p(2.5); Scenarios.snap("dc09-recommended")
    main.contentViewController = original
}
#endif
