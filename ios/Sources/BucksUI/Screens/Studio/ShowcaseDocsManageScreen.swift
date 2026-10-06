import SwiftUI
import BucksCore

// The documents a business, NGO or institution shows on its profile (migration showcase_docs.sql; port of ShowcaseDocsManageScreen.kt).
// Owner and admins add them, choose who may open each one, answer requests to see locked ones and see who looked. Separate from the
// compliance documents Bucks staff check (ListingDocsScreen): those never appear here and these never affect going live.

private func showcaseUTC() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC") ?? .current; return c }
private func showcaseDayFormatter() -> DateFormatter {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
}
/// "2027-03-12" for the date picked (always in UTC, the way the server reads a date).
private func showcaseISODay(_ d: Date) -> String { showcaseDayFormatter().string(from: d) }
private func showcaseParseDay(_ s: String) -> Date? { showcaseDayFormatter().date(from: String(s.prefix(10))) }

struct ShowcaseDocsManageScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var docs: [ShowcaseDoc]?
    @State private var requests: [DocRequest] = []
    @State private var views: [DocView] = []
    @State private var loadError: String?
    @State private var tick = 0
    @State private var adding = false
    @State private var editing: ShowcaseDoc?
    @State private var removing: ShowcaseDoc?
    @State private var viewing: ShowcaseDoc?
    @State private var busyKey: String?

    private var m: ListingsStore { session.listings }
    private var allowed: Bool { m.loaded && m.canManage(id) }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Documents to show", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let l = m.listing(id) { Text(l.title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface).padding(.bottom, 8) }
                        if !m.loaded {
                            if let err = m.error { ListingsLoadError(message: err) { m.refresh() } } else { CenteredLoading() }
                        } else if !allowed {
                            Muted("Only the owner or an admin can manage the documents shown on this profile.")
                        } else {
                            manage
                        }
                    }.padding(.horizontal, Gutter).padding(.bottom, 24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .onAppear { if !m.loaded { m.refresh() } }
        .task(id: "\(id)#\(tick)#\(allowed)") { await load() }
        .bucksFullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let d = viewing { ShowcaseDocViewer(doc: d, team: true, onClose: { viewing = nil }, onChanged: {}) }
        }
        .sheet(isPresented: $adding) {
            ShowcaseEditorSheet(listingId: id, existing: nil) { adding = false; tick += 1 }
        }
        .sheet(item: $editing) { d in
            ShowcaseEditorSheet(listingId: id, existing: d) { editing = nil; tick += 1 }
        }
        .bucksConfirm(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                      title: "Remove \(removing?.title ?? "")?", message: "The file is deleted and anyone who had access loses it. You can add it again later.", confirmTitle: "Remove", destructive: true) {
            if let d = removing {
                act("x" + d.id, "Document removed.") {
                    let path = try await Backend.shared.removeShowcaseDoc(d.id)
                    await Backend.shared.removeShowcaseFile(path)
                }
            }
        }
    }

    @MainActor private func load() async {
        guard allowed else { return }
        do { docs = try await Backend.shared.showcaseDocs(id); loadError = nil }
        catch is CancellationError { return }
        catch { loadError = friendlyError(error) }
        if let r = try? await Backend.shared.docRequestsFor(id) { requests = r }
        if let v = try? await Backend.shared.docViewLog(id) { views = v }
    }

    /// Runs one team action with its buttons disabled, shows the server's message when it fails, and reloads on success.
    private func act(_ key: String, _ okText: String, _ block: @escaping () async throws -> Void) {
        Task { @MainActor in
            busyKey = key
            defer { busyKey = nil }
            do { try await block(); session.toast(okText); tick += 1 }
            catch is CancellationError {}
            catch { session.toast(friendlyError(error)) }
        }
    }

    @ViewBuilder private var manage: some View {
        Notice("These appear on your public profile, as you choose below. They are separate from the checks Bucks does for going live: nothing here is \"checked by Bucks\" unless Bucks staff say so.")
        HStack {
            Text("Your documents").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            if let list = docs { Text("\(list.count) of 20").bucks(.bodySmall).foregroundStyle(BucksColor.onSurfaceVariant) }
        }.padding(.top, 16)
        if let list = docs {
            if list.isEmpty { Muted("No documents yet. Registrations, licences, certificates and awards help people trust a page.").padding(.top, 8) }
            ForEach(list) { d in
                ShowcaseManageCard(doc: d, onOpen: { viewing = d }, onEdit: { editing = d }, onRemove: { removing = d }).padding(.top, 10)
            }
            if list.count < 20 { ShowcaseButton("Add a document", systemImage: "plus", action: { adding = true }).padding(.top, 12) }
            else { Muted("You have reached 20 documents. Remove one to add another.").padding(.top, 12) }
        } else if let err = loadError {
            LoadError(err) { loadError = nil; tick += 1 }.padding(.top, 8)
        } else { CenteredLoading() }

        SectionTitle("Requests").padding(.top, 24)
        Muted("People ask to see documents marked On request. You choose; approving lasts 30 days and you can revoke it any time.").padding(.top, 2).padding(.bottom, 4)
        if requests.isEmpty { Muted("No requests right now.").padding(.top, 4) }
        ForEach(requests) { r in requestCard(r).padding(.top, 10) }

        SectionTitle("Who looked").padding(.top, 24)
        Muted("The last 50 people who opened one of your documents. Team members are not listed.").padding(.top, 2).padding(.bottom, 4)
        if views.isEmpty { Muted("Nobody has opened a document yet.").padding(.top, 4) }
        ForEach(views) { v in
            VStack(alignment: .leading, spacing: 0) {
                Text(v.viewerName.isEmpty ? "A Bucks member" : v.viewerName).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface)
                Muted("\(v.docTitle) · \(humanDate(v.lastAt))" + (v.times > 1 ? " · \(v.times) times" : ""))
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func requestCard(_ r: DocRequest) -> some View {
        BucksCard(padding: 14) {
            HStack {
                Text(r.requesterName.isEmpty ? "A Bucks member" : r.requesterName).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                if r.status == "PENDING" { PillWarn("Waiting") } else { PillGood("Approved") }
            }
            Muted("For \(r.docTitle)" + (r.relation.isEmpty ? "" : " · \(r.relation)")).padding(.top, 2)
            if !r.message.isEmpty { Text("\"\(r.message)\"").bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
            if r.status == "PENDING" {
                FlowLayout(spacing: 8) {
                    ShowcaseButton("Approve 30 days", enabled: busyKey == nil) {
                        act("a" + r.id, "Approved for 30 days. They've been told.") { _ = try await Backend.shared.decideDocRequest(r.id, approve: true, days: 30) }
                    }
                    ShowcaseButton("Decline", tonal: true, enabled: busyKey == nil) {
                        act("d" + r.id, "Declined. They've been told.") { _ = try await Backend.shared.decideDocRequest(r.id, approve: false) }
                    }
                }.padding(.top, 8)
            } else {
                Muted("Can open until \(humanDate(r.expiresAt))").padding(.top, 6)
                ShowcaseButton("Revoke", tonal: true, enabled: busyKey == nil) {
                    act("r" + r.id, "Access ended.") { try await Backend.shared.revokeDocAccess(r.id) }
                }.padding(.top, 4)
            }
        }
    }
}

/// One document in the team's list: what it is, who can open it, its number and expiry, what viewers said, and requests waiting.
private struct ShowcaseManageCard: View {
    let doc: ShowcaseDoc
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let d = doc
        BucksCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(systemImage: showcaseKindIcon(d.kind), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                    Muted(showcaseSubtitle(d))
                }.frame(maxWidth: .infinity, alignment: .leading)
                if d.pendingRequests > 0 { PillWarn("\(d.pendingRequests) waiting") }
            }
            ShowcasePills(doc: d, selfLabelled: d.kind == "OTHER").padding(.top, 10)
            if !d.number.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No. \(d.number)" + (Registries.all.first { $0.key == d.registry }.map { " · \($0.label) link shown" } ?? ""))
                    .bucks(.bodySmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            Muted(d.checks == 0 ? "No viewer opinions yet." : "Viewer opinions (not a Bucks check): \(d.checksUp) say it looks genuine, \(d.checksDown) say it doesn't look right.").padding(.top, 4)
            FlowLayout(spacing: 8) {
                ShowcaseButton("Open", tonal: true, action: onOpen)
                ShowcaseButton("Edit", tonal: true, action: onEdit)
                ShowcaseButton("Remove", tonal: true, action: onRemove)
            }.padding(.top, 8)
        }
    }
}

// MARK: - Add / edit

/// Add (existing == nil: choose a file first) or edit one document's details and who may open it. The file itself cannot be swapped:
/// remove and add again.
private struct ShowcaseEditorSheet: View {
    let listingId: String
    let existing: ShowcaseDoc?
    var onDone: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var title: String
    @State private var titleTouched: Bool
    @State private var issuer: String
    @State private var number: String
    @State private var registry: String?
    @State private var visibility: String
    @State private var hasExpiry: Bool
    @State private var expires: Date
    @State private var file: Picked?
    @State private var pickingFile = false
    @State private var pickingPhoto = false
    @State private var busy = false

    private static let allowedMimes: Set<String> = ["application/pdf", "image/jpeg", "image/png", "image/webp"]
    private static let visibilityOptions: [(key: String, label: String, hint: String)] = [
        ("PUBLIC", "Public", "Anyone signed in can open it."),
        ("ON_REQUEST", "On request", "People see it is there and ask you. You approve for 30 days or decline, and can revoke."),
        ("PRIVATE", "Team only", "Only your team sees it. Choosing this ends any access already given."),
    ]

    init(listingId: String, existing: ShowcaseDoc?, onDone: @escaping () -> Void) {
        self.listingId = listingId; self.existing = existing; self.onDone = onDone
        let k = existing?.kind ?? "REGISTRATION"
        _kind = State(initialValue: k)
        _title = State(initialValue: existing?.title ?? ShowcaseKinds.label("REGISTRATION"))
        _titleTouched = State(initialValue: existing != nil)
        _issuer = State(initialValue: existing?.issuer ?? "")
        _number = State(initialValue: existing?.number ?? "")
        let reg = existing?.registry
        _registry = State(initialValue: (reg?.isEmpty ?? true) ? nil : reg)
        _visibility = State(initialValue: existing?.visibility ?? ShowcaseKinds.defaultVisibility(k))
        let parsed: Date? = existing?.expiresOn.flatMap { showcaseParseDay($0) }
        _hasExpiry = State(initialValue: parsed != nil)
        _expires = State(initialValue: parsed ?? Date())
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanNumber: String { number.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showNumber: Bool { ShowcaseKinds.hasNumber(kind) || !cleanNumber.isEmpty || registry != nil }
    private var registryChoices: [String] { ["None"] + Registries.all.map { $0.label } }
    private var registryChoice: String { Registries.all.first(where: { $0.key == registry })?.label ?? "None" }
    private var valid: Bool { (2...60).contains(cleanTitle.count) && (existing != nil || file != nil) && (registry == nil || !cleanNumber.isEmpty) }

    var body: some View {
        Sheet(scrollable: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(existing == nil ? "Add a document" : "Edit document").bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                if existing == nil { newDocumentFields } else {
                    Muted("\(ShowcaseKinds.label(kind)). To use a different file, remove this document and add it again.").padding(.top, 4)
                }

                BucksField(Binding(get: { title }, set: { title = String($0.prefix(60)); titleTouched = true }), label: kind == "OTHER" ? "Name of the document" : "Title").padding(.top, 12)
                Muted(kind == "OTHER" ? "You choose the name, 2 to 60 characters. It is shown as self-labelled. Names with \"verified\" or \"Bucks\" are not allowed."
                                      : "2 to 60 characters. Names with \"verified\" or \"Bucks\" are not allowed.").padding(.top, -8).padding(.bottom, 8)
                BucksField(Binding(get: { issuer }, set: { issuer = String($0.prefix(80)) }), label: "Issued by (optional)", placeholder: "Registrar of Companies, FSSAI, a university...")
                if showNumber { numberFields }

                Text("Who can open it?").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 4)
                ForEach(Self.visibilityOptions, id: \.key) { o in visibilityRow(o.key, o.label, o.hint) }

                HStack {
                    Text("Expiry date (optional)").bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                    ListingSwitch($hasExpiry)
                }.frame(minHeight: 48).padding(.top, 8)
                if hasExpiry {
                    let today = showcaseUTC().startOfDay(for: Date())
                    DatePicker("Valid till", selection: $expires, in: min(today, expires)..., displayedComponents: .date)
                        .datePickerStyle(.compact).environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current).frame(minHeight: 48)
                }

                HStack(spacing: 8) {
                    ShowcaseButton(busy ? "Saving…" : "Save", enabled: valid && !busy) { save() }
                    ShowcaseTextButton("Cancel", enabled: !busy) { dismiss() }
                    Spacer(minLength: 0)
                }.padding(.top, 16)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
    }

    @ViewBuilder private var newDocumentFields: some View {
        Text("What is it?").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.top, 12).padding(.bottom, 6)
        FlowChips(ShowcaseKinds.all.map { $0.label }, selected: [ShowcaseKinds.label(kind)]) { label in
            guard let k = ShowcaseKinds.all.first(where: { $0.label == label })?.key else { return }
            if !titleTouched || cleanTitle.isEmpty { title = k == "OTHER" ? "" : label }
            kind = k; visibility = ShowcaseKinds.defaultVisibility(k)
        }
        Muted(ShowcaseKinds.hint(kind)).padding(.top, 6)
        HStack(spacing: 8) {
            SmallButton(file == nil ? "Choose a file" : "Change file", tonal: true, enabled: !busy) { pickingFile = true }
                .bucksFilePicker(isPresented: $pickingFile) { accept($0) }
            SmallButton("Choose a photo", tonal: true, enabled: !busy) { pickingPhoto = true }
                .bucksPhotoPicker(isPresented: $pickingPhoto) { accept($0.first) }
            Spacer(minLength: 0)
        }.padding(.top, 12)
        Muted(file.map { "File: \($0.name)" } ?? "PDF, JPG or PNG, up to 10 MB.").padding(.top, 4)
    }

    @ViewBuilder private var numberFields: some View {
        BucksField(Binding(get: { number }, set: { number = String($0.prefix(40)) }), label: "Registration number (optional)").bucksAutocapCharacters()
        Muted("People who may open the document see it. It is shown only as you typed it; Bucks does not check it.").padding(.top, -8).padding(.bottom, 8)
        Text("Where can people check it?").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).padding(.bottom, 6)
        FlowChips(registryChoices, selected: [registryChoice]) { label in
            registry = Registries.all.first(where: { $0.label == label })?.key
        }
        Muted(registry == nil ? "Pick a registry to add a \"Check on official site\" link. It opens the registry's own website; viewers search there."
                              : "Needs the number above. GST: 15 characters. FSSAI: 14 digits.").padding(.top, 6).padding(.bottom, 8)
    }

    private func visibilityRow(_ key: String, _ label: String, _ hint: String) -> some View {
        Button { visibility = key } label: {
            HStack(spacing: 12) {
                Image(systemName: visibility == key ? "largecircle.fill.circle" : "circle").font(.system(size: 20)).foregroundStyle(visibility == key ? BucksColor.primary : BucksColor.onSurfaceVariant)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                    Muted(hint)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(visibility == key ? .isSelected : [])
    }

    private func accept(_ f: Picked?) {
        guard let f else { return }
        if f.data.count > ManageStore.maxFileBytes { session.toast("Documents up to 10 MB. Take a smaller photo.") }
        else if !Self.allowedMimes.contains(f.mime) { session.toast("PDF, JPG or PNG only.") }
        else { file = f }
    }

    private func save() {
        let registryValue: String? = (registry?.isEmpty ?? true) ? nil : registry
        let expiresValue: String? = hasExpiry ? showcaseISODay(expires) : nil
        busy = true
        Task { @MainActor in
            defer { busy = false }
            var uploaded: String?
            do {
                if let existing {
                    try await Backend.shared.updateShowcaseDoc(existing.id, title: cleanTitle, issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines), number: cleanNumber,
                                                               registry: registryValue, visibility: visibility, expires: expiresValue)
                    session.toast("Saved.")
                } else {
                    guard let me = session.me?.id, let f = file else { session.toast("Choose a file first."); return }
                    let path = try await Backend.shared.uploadShowcaseFile(me: me, data: f.data, mime: f.mime)
                    uploaded = path
                    try await Backend.shared.addShowcaseDoc(listingId: listingId, kind: kind, title: cleanTitle, issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines), number: cleanNumber,
                                                            registry: registryValue, path: path, mime: f.mime, size: f.data.count, visibility: visibility, expires: expiresValue)
                    session.toast("Document added.")
                }
                onDone()
            } catch is CancellationError {
            } catch {
                session.toast(friendlyError(error))
                // The file went up but the server refused the document (for instance a name it rejects): don't leave the file behind.
                if let uploaded { await Backend.shared.removeShowcaseFile(uploaded) }
            }
        }
    }
}

// MARK: - Dashboard entry

/// Entry to the documents shown on the public profile, with the number of people waiting for an answer. Separate from the documents Bucks checks.
struct ShowcaseDocsCard: View {
    let listingId: String
    var onTap: () -> Void
    @State private var waiting = 0

    var body: some View {
        BucksCard(onTap: onTap, padding: 14) {
            HStack {
                Text("Documents to show").bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                if waiting > 0 { PillWarn("\(waiting) waiting") }
            }
            Muted("Registrations, licences and certificates you show on your profile, and who may open each. Separate from the documents Bucks checks to take you live.").padding(.top, 4)
        }
        .frame(minHeight: 48)
        .onAppear { reload() }
    }

    /// On every appearance, so coming back from the manage screen shows the new count.
    private func reload() {
        Task { @MainActor in
            if let rows = try? await Backend.shared.showcaseDocs(listingId) { waiting = rows.reduce(0) { $0 + $1.pendingRequests } }
        }
    }
}
