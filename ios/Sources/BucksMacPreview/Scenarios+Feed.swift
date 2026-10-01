#if os(macOS)
import Foundation
import BucksCore
import BucksUI

/// Walks the Feed area's pushed screens: composer, post detail, Moment viewer, new Moment.
@MainActor
func scenarioFeed(_ session: AppSession, _ router: Router) async {
    router.push(.createPost); await Scenarios.pause(1.0); Scenarios.snap("f01-create-post")
    router.pop(); router.push(.post("p1")); await Scenarios.pause(1.5); Scenarios.snap("f02-post-detail")
    router.pop(); router.push(.moments("u9")); await Scenarios.pause(1.5); Scenarios.snap("f03-moment-viewer")
    router.pop(); router.push(.momentNew); await Scenarios.pause(1.0); Scenarios.snap("f04-new-moment")
}
#endif
