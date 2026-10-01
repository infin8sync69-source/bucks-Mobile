import SwiftUI
import BucksCore

/// Who runs a listing (owner, admins, store riders) or drives a vehicle (id "v:<vehicleId>", owner and drivers).
/// The owner invites by Bucks ID and removes people; anyone else can only leave.
struct MembersScreen: View {
    let id: String
    var body: some View {
        if id.hasPrefix("v:") { VehicleDriversScreen(vehicleId: String(id.dropFirst(2))) }
        else { ListingMembersScreen(listingId: id) }
    }
}

private struct ListingMembersScreen: View {
    let listingId: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = ManageStore()
    @State private var code = ""
    @State private var role = "ADMIN"
    @State private var removeFor: MemberRow?
    @State private var scanning = false
    @State private var sending = false

    private var meId: String? { session.me?.id }
    private var listing: ListingRow? { store.listings[listingId] }
    private var owner: Bool { listing?.ownerId == meId && meId != nil }
    private var title: String { listing?.title ?? "…" }
    private func name(_ pid: String) -> String { store.names[pid] ?? session.names[pid] ?? "" }
    private static let order = ["OWNER": 0, "ADMIN": 1, "STORE_RIDER": 2]

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Members", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("The owner, admins who help run it, and the store's own delivery riders.")
                        SectionTitle("People").padding(.top, 20).padding(.bottom, 4)
                        people
                        if owner { invite } else { Notice("Only the owner can invite or remove people.").padding(.top, 20) }
                    }.padding(Gutter).padding(.bottom, 16)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task {
            await store.loadListing(listingId)
            await store.loadMembers(listingId, me: meId, toast: session.toast)
        }
        .manageQrScanner(isPresented: $scanning, onResult: { raw in
            if case .bucksId(let c) = BucksQr.parse(raw) { code = String(c.filter { $0.isLetter || $0.isNumber }.prefix(8)) } else { session.toast("That isn't a Bucks ID code.") }
        }, onError: { session.toast($0) })
        .bucksConfirm(isPresented: Binding(get: { removeFor != nil }, set: { if !$0 { removeFor = nil } }),
                      title: removeTitle, message: removeMessage, confirmTitle: removeFor?.profileId == meId ? "Leave" : "Remove", destructive: true) {
            if let m = removeFor { Task { if await store.removeMember(listingId: listingId, profileId: m.profileId, me: meId, toast: session.toast) { session.listings.refresh(); router.pop() } } }
        }
    }

    @ViewBuilder private var people: some View {
        if let rows = store.members[listingId] {
            if rows.isEmpty { Muted("Only you so far.") }
            ForEach(rows.sorted { (Self.order[$0.role] ?? 9, name($0.profileId).lowercased()) < (Self.order[$1.role] ?? 9, name($1.profileId).lowercased()) }, id: \.profileId) { m in
                HStack(spacing: 12) {
                    Avatar(initials: initials(name(m.profileId).isEmpty ? "?" : name(m.profileId)), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name(m.profileId) + (m.profileId == meId ? " (you)" : "")).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(roleLabel(m.role, vehicle: false) + " · " + roleExplain(m.role, vehicle: false), maxLines: 2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if owner && m.role != "OWNER" {
                        Button { removeFor = m } label: { Image(systemName: "person.fill.xmark").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("Remove")
                    } else if m.profileId == meId && m.role != "OWNER" { SmallButton("Leave", tonal: true) { removeFor = m } }
                }.padding(.vertical, 8)
                BucksDivider()
            }
        } else { BucksLoader().frame(maxWidth: .infinity).padding(40) }
    }

    @ViewBuilder private var invite: some View {
        SectionTitle("Invite someone").padding(.top, 24).padding(.bottom, 4)
        Muted("Ask for their Bucks ID (Account > Your Bucks ID) or scan it. They get an invite to accept under My listings > Invites.").padding(.bottom, 10)
        HStack(spacing: 8) {
            BucksField(Binding(get: { code }, set: { code = String($0.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8)) }), placeholder: "H6VF YWYF").bucksAutocapCharacters()
            IconAction("qrcode.viewfinder", "Scan a Bucks ID") { scanning = true }
        }
        FieldLabel("Role")
        HStack(spacing: 8) {
            BucksChip("Admin", selected: role == "ADMIN") { role = "ADMIN" }
            BucksChip("Store rider", selected: role == "STORE_RIDER") { role = "STORE_RIDER" }
            Spacer(minLength: 0)
        }
        Muted(roleExplain(role, vehicle: false)).padding(.top, 6)
        PrimaryButton("Send invite", enabled: BucksQr.looksLikeBucksId(code) && !sending) { Task { await send() } }.padding(.top, 14)
        let pending = store.sentInvites[listingId] ?? []
        if !pending.isEmpty {
            SectionTitle("Invites sent").padding(.top, 24).padding(.bottom, 4)
            ForEach(pending) { i in
                HStack(spacing: 12) {
                    Avatar(initials: initials(name(i.inviteeId).isEmpty ? "?" : name(i.inviteeId)), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name(i.inviteeId)).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Invited as \(roleLabel(i.role, vehicle: false).lowercased()) · waiting for their answer")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Cancel") { Task { await store.revoke(listingId: listingId, invite: i, toast: session.toast) } }
                        .buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                }.padding(.vertical, 8)
                BucksDivider()
            }
        }
    }

    private var removeTitle: String {
        guard let m = removeFor else { return "" }
        return m.profileId == meId ? "Leave \(title)?" : "Remove \(name(m.profileId))?"
    }
    private var removeMessage: String {
        guard let m = removeFor else { return "" }
        return m.profileId == meId ? "You'll no longer be able to manage this listing or take its orders. The owner can invite you again."
            : "\(name(m.profileId)) will no longer be \(roleLabel(m.role, vehicle: false).lowercased()) here. You can invite them again later."
    }

    private func send() async {
        sending = true; defer { sending = false }
        if await store.invite(listingId: listingId, bucksId: code, role: role, toast: session.toast) { code = "" }
    }
}
