import SwiftUI
import BucksCore

/// Who can drive a vehicle (owner and invited drivers). The owner invites by Bucks ID and removes people; anyone else can only leave.
struct VehicleDriversScreen: View {
    let vehicleId: String
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var store = VehicleStore()
    @State private var members: [VehicleMemberRow]?
    @State private var pending: [SentInviteRow] = []
    @State private var names: [String: String] = [:]
    @State private var code = ""
    @State private var removeFor: VehicleMemberRow?
    @State private var sending = false
    @State private var scanning = false

    private var meId: String? { session.me?.id }
    private var vehicle: VehicleRow? { store.vehicle(vehicleId) }
    private var owner: Bool { vehicle?.ownerId == meId && meId != nil }
    private var title: String { vehicle.map { "\($0.model.isEmpty ? vehicleKindLabel($0.kind) : $0.model) · \($0.plate)" } ?? "…" }
    private func name(_ id: String) -> String { names[id] ?? session.names[id] ?? "" }
    private func valid(_ s: String) -> Bool { BucksQr.looksLikeBucksId(s) }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Drivers", onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("The owner and the drivers who can go online with this vehicle.")
                        SectionTitle("People").padding(.top, 20).padding(.bottom, 4)
                        peopleList
                        if owner { inviteSection } else { Notice("Only the owner can invite or remove people.").padding(.top, 20) }
                    }.padding(Gutter).padding(.bottom, 16)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await load() }
        .manageQrScanner(isPresented: $scanning, onResult: { raw in
            if case .bucksId(let c) = BucksQr.parse(raw) { code = String(c.filter { $0.isLetter || $0.isNumber }.prefix(8)) } else { session.toast("That isn't a Bucks ID code.") }
        }, onError: { session.toast($0) })
        .bucksConfirm(isPresented: Binding(get: { removeFor != nil }, set: { if !$0 { removeFor = nil } }),
                      title: removeTitle, message: removeMessage, confirmTitle: removeFor?.profileId == meId ? "Leave" : "Remove", destructive: true) {
            if let m = removeFor { Task { await remove(m) } }
        }
    }

    @ViewBuilder private var peopleList: some View {
        if let members {
            if members.isEmpty { Muted("Only you so far.") }
            ForEach(members.sorted { ($0.role == "OWNER" ? 0 : 1, name($0.profileId).lowercased()) < ($1.role == "OWNER" ? 0 : 1, name($1.profileId).lowercased()) }, id: \.profileId) { m in
                HStack(spacing: 12) {
                    Avatar(initials: initials(name(m.profileId).isEmpty ? "?" : name(m.profileId)), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name(m.profileId) + (m.profileId == meId ? " (you)" : "")).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(roleLabel(m.role) + " · " + roleExplain(m.role), maxLines: 2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if owner && m.role != "OWNER" {
                        Button { removeFor = m } label: { Image(systemName: "person.fill.xmark").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Remove")
                    } else if m.profileId == meId && m.role != "OWNER" { SmallButton("Leave", tonal: true) { removeFor = m } }
                }.padding(.vertical, 8)
                BucksDivider()
            }
        } else { BucksLoader().frame(maxWidth: .infinity).padding(.vertical, 20) }
    }

    @ViewBuilder private var inviteSection: some View {
        SectionTitle("Invite a driver").padding(.top, 24).padding(.bottom, 4)
        Muted("Ask for their Bucks ID (Account > Your Bucks ID) or scan it. They get an invite to accept under My listings > Invites.").padding(.bottom, 10)
        HStack(spacing: 8) {
            BucksField(Binding(get: { code }, set: { code = String($0.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8)) }), placeholder: "H6VF YWYF").bucksAutocapCharacters()
            IconAction("qrcode.viewfinder", "Scan a Bucks ID") { scanning = true }
        }
        FieldLabel("Role")
        BucksChip("Driver", selected: true, systemImage: "car.fill") {}
        Muted(roleExplain("ADMIN")).padding(.top, 6)
        PrimaryButton("Send invite", enabled: valid(code) && !sending) { Task { await send() } }.padding(.top, 14)
        if !pending.isEmpty {
            SectionTitle("Invites sent").padding(.top, 24).padding(.bottom, 4)
            ForEach(pending) { i in
                HStack(spacing: 12) {
                    Avatar(initials: initials(name(i.inviteeId).isEmpty ? "?" : name(i.inviteeId)), size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name(i.inviteeId)).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Invited as \(roleLabel(i.role).lowercased()) · waiting for their answer")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Cancel") { Task { await revoke(i) } }.buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                }.padding(.vertical, 8)
                BucksDivider()
            }
        }
    }

    private func roleLabel(_ r: String) -> String { switch r { case "OWNER": "Owner"; case "ADMIN": "Driver"; default: r } }
    private func roleExplain(_ r: String) -> String {
        switch r { case "OWNER": "Can do everything, including deleting it."; case "ADMIN": "Can go online with this vehicle and take rides or deliveries."; default: "" }
    }
    private var removeTitle: String {
        guard let m = removeFor else { return "" }
        return m.profileId == meId ? "Leave \(title)?" : "Remove \(name(m.profileId))?"
    }
    private var removeMessage: String {
        guard let m = removeFor else { return "" }
        return m.profileId == meId ? "You'll no longer be able to go online with this vehicle. The owner can invite you again."
            : "\(name(m.profileId)) will no longer be \(roleLabel(m.role).lowercased()) here. You can invite them again later."
    }

    private func load() async {
        if !store.loaded { await store.refresh() }
        do {
            let rows = try await Backend.shared.vehicleMembers(vehicleId: vehicleId)
            let sent = (try? await Backend.shared.pendingVehicleInvites(vehicleId: vehicleId)) ?? []
            let ids = Array(Set(rows.map(\.profileId) + sent.map(\.inviteeId)))
            if let ps = try? await Backend.shared.profiles(ids) { for p in ps { names[p.id] = p.name } }
            members = rows; pending = owner ? sent : []
        } catch is CancellationError {} catch let e { members = members ?? []; session.toast(friendlyError(e)) }
    }
    private func send() async {
        sending = true; defer { sending = false }
        let c = code
        do {
            try await Backend.shared.inviteDriver(vehicleId: vehicleId, bucksId: c)
            session.toast("Invite sent to \(c). They'll see it under Invites."); code = ""; await load()
        } catch let e { session.toast(friendlyError(e)) }
    }
    private func revoke(_ i: SentInviteRow) async {
        do { try await Backend.shared.revokeInvite(id: i.id); pending.removeAll { $0.id == i.id } } catch let e { session.toast(friendlyError(e)) }
    }
    private func remove(_ m: VehicleMemberRow) async {
        do {
            try await Backend.shared.removeVehicleMember(vehicleId: vehicleId, profileId: m.profileId)
            members?.removeAll { $0.profileId == m.profileId }
            if m.profileId == meId { dismiss() }
        } catch let e { session.toast(friendlyError(e)) }
    }
}
