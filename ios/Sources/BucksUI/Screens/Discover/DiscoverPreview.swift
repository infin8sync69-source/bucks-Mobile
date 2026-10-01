import SwiftUI
import BucksCore

/// Lets the macOS preview harness show the tab-root screens of this area, which have no route of their own.
public enum DiscoverPreview {
    @MainActor public static func services(session: AppSession, router: Router) -> some View { ServicesScreen().environment(session).environment(router).frame(width: 390, height: 844) }
    @MainActor public static func recommended(session: AppSession, router: Router) -> some View { RecommendedScreen().environment(session).environment(router).frame(width: 390, height: 844) }
}
