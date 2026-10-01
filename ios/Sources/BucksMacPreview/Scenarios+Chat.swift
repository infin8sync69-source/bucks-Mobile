#if os(macOS)
import Foundation
import BucksCore
import BucksUI

/// `--scenario chat`: messages, a direct chat, a group chat, new group, sync, contacts and the settings pages.
@MainActor
func scenarioChat(_ session: AppSession, _ router: Router) async {
    for (name, route) in [("c01-messages", Route.messages), ("c02-chat", .chat("c1")), ("c03-group", .chat("g1")), ("c04-listing-chat", .chat("l1")), ("c05-new-group", .newGroup),
                          ("c06-sync", .sync), ("c07-contacts", .contacts), ("c08-privacy", .settingsPrivacy), ("c09-notifications", .settingsNotifications),
                          ("c10-blocked", .settingsBlocked), ("c11-close-friends", .settingsCloseFriends)] {
        router.popToRoot(); router.push(route)
        await Scenarios.pause(3.0)
        Scenarios.snap(name)
    }
}
#endif
