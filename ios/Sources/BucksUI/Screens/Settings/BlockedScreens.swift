import SwiftUI
import BucksCore

/// People I blocked, each with a way back.
struct BlockedScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let social: SocialStore = session.social
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Blocked people", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if social.blocked.isEmpty { Muted("Nobody is blocked. Block someone from a chat or their profile.") }
                        ForEach(social.blocked) { p in PersonRow(p) { SmallButton("Unblock", tonal: true) { social.unblock(p.id) } } }
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { social.refreshBlocked() }
    }
}

/// Synced people ticked for the "Close friends" Moments audience.
struct CloseFriendsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        let social: SocialStore = session.social
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Close friends", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Muted("Moments shared with 'Close friends' are seen only by the people ticked here. They aren't told they're on the list.").padding(.bottom, 8)
                        if social.synced.isEmpty { Muted("Sync with people first.") }
                        ForEach(social.synced) { p in
                            let on = social.closeFriends.contains(p.id)
                            PersonRow(p) {
                                Button { social.setClose(p.id, on: !on) } label: { ChatCheckmark(on: on).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                    .buttonStyle(.plain).accessibilityLabel(p.name).accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }.padding(Gutter)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }
        .bucksBackground().bucksHideNavigationBar()
        .task { social.refreshSyncs() }
    }
}
