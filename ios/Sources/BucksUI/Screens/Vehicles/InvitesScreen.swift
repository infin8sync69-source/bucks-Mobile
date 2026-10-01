import SwiftUI
import BucksCore

/// Invites waiting for my answer: help run a listing, or drive a vehicle (Android's InvitesScreen).
struct InvitesScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var invites: [InviteForMe] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var answering: String?

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Invites", onBack: { router.pop() })
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let error, !loaded { LoadError(error) { Task { await load() } } }
                        if loaded && invites.isEmpty {
                            BucksCard {
                                Text("No invites").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted("When a shop owner asks you to help run their listing or deliver their orders, or a vehicle owner asks you to drive for them, the invite shows up here. They need your Bucks ID to send one.").padding(.top, 4)
                            }
                        }
                        ForEach(invites) { i in card(i) }
                    }.padding(Gutter)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await load() }
    }

    private func card(_ i: InviteForMe) -> some View {
        let vehicle = i.kind == "VEHICLE"
        let who = "\(i.inviterName.isEmpty ? "Someone" : i.inviterName) invited you as \(roleLabel(i.role, vehicle: vehicle).lowercased())"
        let when = i.createdAt.isEmpty ? nil : inviteAgo(i.createdAt)
        return BucksCard {
            HStack(alignment: .top, spacing: 12) {
                Avatar(systemImage: vehicle ? "car.fill" : Studio.listingIcon(i.kind, ""), size: 48)
                VStack(alignment: .leading, spacing: 0) {
                    Text(i.title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                    Muted([who, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Muted(roleExplain(i.role, vehicle: vehicle)).padding(.top, 10)
            HStack(spacing: 8) {
                SmallButton("Accept", enabled: answering == nil) { Task { await respond(i, accept: true) } }.frame(maxWidth: .infinity)
                SmallButton("Decline", tonal: true, enabled: answering == nil) { Task { await respond(i, accept: false) } }.frame(maxWidth: .infinity)
            }.padding(.top, 12)
        }
    }

    private func load() async {
        do { invites = try await Backend.shared.invitesForMe(); loaded = true; error = nil }
        catch is CancellationError {} catch let e { error = friendlyError(e); if loaded { session.toast(friendlyError(e)) } }
    }
    private func respond(_ i: InviteForMe, accept: Bool) async {
        answering = i.id; defer { answering = nil }
        do {
            try await Backend.shared.respondInvite(id: i.id, accept: accept)
            invites.removeAll { $0.id == i.id }
            // The shared hub state (invite badges, My listings) follows the answer, as Android's single MyListings does.
            session.listings.refreshInvites(); if accept { session.listings.refresh() }
            // A vehicle lands under Vehicles on this app (Android files it under My listings).
            session.toast(accept ? "Done. \(i.title) is now under \(i.kind == "VEHICLE" ? "Vehicles" : "My listings")." : "Declined.")
        } catch is CancellationError {} catch let e { session.toast(friendlyError(e)) }
    }
}

func roleLabel(_ role: String, vehicle: Bool) -> String {
    switch role { case "OWNER": "Owner"; case "ADMIN": vehicle ? "Driver" : "Admin"; case "STORE_RIDER": "Store rider"; default: role }
}
func roleExplain(_ role: String, vehicle: Bool) -> String {
    switch role {
    case "OWNER": "Can do everything, including deleting it."
    case "ADMIN": vehicle ? "Can go online with this vehicle and take rides or deliveries." : "Runs it with you: edits details, products, accepts orders and posts jobs. Cannot delete it or invite people."
    case "STORE_RIDER": "Delivers your orders. Cash-on-delivery orders go only to store riders."
    default: ""
    }
}

/// "now", "5m", "3h", "Yesterday", else "4 Oct" (Android's `ago`).
func inviteAgo(_ iso: String) -> String {
    guard let s = secondsSince(iso) else { return "" }
    let secs = max(s, 0)
    switch secs {
    case ..<60: return "now"
    case ..<3600: return "\(secs / 60)m"
    case ..<86400: return "\(secs / 3600)h"
    case ..<172800: return "Yesterday"
    default:
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: Date().addingTimeInterval(-Double(secs)))
    }
}
