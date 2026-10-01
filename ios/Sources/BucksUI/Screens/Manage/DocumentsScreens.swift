import SwiftUI
import BucksCore

/// The documents a listing's service asks for: what each is for, whether customers see anything of it, and where it stands with Bucks.
/// Files go to the private docs bucket; only the uploader and Bucks staff can open them.
struct ListingDocsScreen: View {
    let id: String
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = ManageStore()
    @State private var pickingFor: DocRequirement?
    @State private var showPicker = false
    @State private var draft: DocDraft?
    @State private var removing: DocRequirement?

    struct DocDraft: Identifiable { let row: DocRequirement; let file: Picked; var id: String { row.docType } }

    private var listing: ListingRow? { store.listings[id] }
    private var rows: [DocRequirement]? { store.compliance[id] }

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Documents", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let l = listing {
                            Text(l.title).bucks(.titleLarge).foregroundStyle(BucksColor.onSurface)
                            Muted(manageServiceLabel(l.service).map { "Listed under \($0)" } ?? "").padding(.bottom, 12)
                        }
                        statusCard.padding(.bottom, 12)
                        Notice("Only you and Bucks staff can open these files. Customers see a \"checked by Bucks\" tick, plus the number for FSSAI, GST and RERA, which businesses are expected to show.")
                        Spacer().frame(height: 12)
                        if let rows {
                            if rows.isEmpty { Muted("This listing doesn't need any documents.") }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                                DocRow(row: r, uploading: store.uploading == r.docType,
                                       onPick: { pickingFor = r; showPicker = true },
                                       onRemove: r.status != "MISSING" && !(r.required && r.status == "VERIFIED") ? { removing = r } : nil)
                                    .popIn(index: i).padding(.bottom, 10)
                            }
                        } else { BucksLoader().frame(maxWidth: .infinity).padding(40) }
                    }.padding(.horizontal, Gutter).padding(.bottom, 24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await store.loadListing(id); await store.loadCompliance(id, toast: session.toast) }
        .bucksFilePicker(isPresented: $showPicker) { file in
            let row = pickingFor; pickingFor = nil
            guard let row, let file else { return }
            if file.data.count > ManageStore.maxFileBytes { session.toast("Documents up to 10 MB. Take a smaller photo.") }
            else if !(file.isImage || file.mime == "application/pdf") { session.toast("Photos (JPG, PNG) or PDF only.") }
            else { draft = DocDraft(row: row, file: file) }
        }
        .sheet(item: $draft) { d in
            DocDetailsSheet(row: d.row, file: d.file, busy: store.uploading != nil, onCancel: { draft = nil }) { number, expires in
                Task {
                    guard let me = session.me?.id else { return }
                    if await store.submit(listingId: id, row: d.row, file: d.file, number: number, expires: expires, me: me, toast: session.toast) { draft = nil; syncShared() }
                }
            }
        }
        .bucksConfirm(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                      title: "Remove \(removing?.label ?? "")?", message: "The file is deleted. You can add it again later.", confirmTitle: "Remove") {
            if let r = removing { Task { await store.remove(listingId: id, row: r, me: session.me?.id, toast: session.toast); syncShared() } }
        }
    }

    /// The dashboard checklist and the Services screen read the shared stores (Android has one `Services`), so they follow an upload or a removal.
    private func syncShared() {
        session.listings.loadCompliance(id); session.services.loadCompliance(id); session.listings.refresh()
    }

    private var statusCard: some View {
        let l = listing
        let required = (rows ?? []).filter(\.required)
        let checked = required.filter { $0.status == "VERIFIED" }.count
        let recs = store.recommendations[id] ?? 0
        let title: String = {
            guard let l else { return "Documents" }
            if l.status == "LIVE" { return "Live" }
            if l.status == "SUSPENDED" { return l.complianceHold ? "Paused for a document" : "Suspended" }
            return "Not live yet"
        }()
        let body: String = {
            guard let l else { return "" }
            if l.status == "LIVE" { return "Keep required documents in date. Seven days after one expires, the listing pauses until a new one is checked." }
            if l.status == "SUSPENDED" { return l.complianceHold ? "A required document expired. Upload a new one; you go live again as soon as Bucks checks it." : "Bucks suspended this listing. Contact support." }
            return "Two things take it live: \(store.needed) people nearby recommend it in person (\(recs) so far), and Bucks checks the required documents below (\(checked) of \(required.count) checked)."
        }()
        return BucksCard(tint: true, padding: 14) {
            Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Muted(body).padding(.top, 4)
        }
    }
}

private struct DocRow: View {
    let row: DocRequirement, uploading: Bool
    let onPick: () -> Void
    let onRemove: (() -> Void)?
    var body: some View {
        BucksCard(padding: 14) {
            HStack {
                Text(row.label).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                switch row.status {
                case "VERIFIED": PillGood("Checked")
                case "PENDING": PillWarn("Being checked")
                case "REJECTED": PillBad("Rejected")
                case "EXPIRED": PillBad("Expired")
                default: if row.required { PillPurple("Required") } else { PillGrey("Optional") }
                }
            }
            if !row.hint.trimmingCharacters(in: .whitespaces).isEmpty { Muted(row.hint).padding(.top, 4) }
            if row.status == "REJECTED", !row.note.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Bucks: \(row.note)").bucks(.bodySmall).foregroundStyle(BucksColor.bad).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            if let facts = manageDocFacts(number: row.number, expiresOn: row.expiresOn) {
                Text(facts).bucks(.bodySmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            Muted(row.publicNumber ? "Customers see: a tick and the number" : "Customers see: a tick only").padding(.top, 6)
            HStack(spacing: 8) {
                SmallButton(uploading ? "Uploading…" : row.status == "MISSING" ? "Add" : "Replace", tonal: row.status != "MISSING", enabled: !uploading, action: onPick)
                if let onRemove { SmallButton("Remove", tonal: true, action: onRemove) }
                Spacer(minLength: 0)
            }.padding(.top, 10)
        }
    }
}

/// After picking a file: the number (when the document has one Bucks keeps) and the expiry date (when it expires).
private struct DocDetailsSheet: View {
    let row: DocRequirement, file: Picked, busy: Bool
    let onCancel: () -> Void
    let onSubmit: (String, String?) -> Void
    @State private var number = ""
    @State private var expires: Date?
    @State private var choosing = false

    private var needsNumber: Bool { row.asksNumber && row.publicNumber }
    private var ready: Bool { !busy && (!needsNumber || !number.trimmingCharacters(in: .whitespaces).isEmpty) && (!row.hasExpiry || expires != nil) }
    private static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC") ?? .current; return c }
    private var expiresISO: String? {
        guard let expires else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: expires)
    }

    var body: some View {
        Sheet(scrollable: true) {
            VStack(alignment: .leading, spacing: 0) {
                Headline(row.label)
                Muted("File: \(file.name)").padding(.top, 4)
                if row.asksNumber {
                    BucksField(Binding(get: { number }, set: { number = String($0.prefix(40)) }), label: needsNumber ? "Number" : "Number (optional)",
                               keyboard: row.docType == "FSSAI" ? .number : .default).padding(.top, 12)
                }
                if row.hasExpiry {
                    GhostButton(expires.map { "Valid till \(manageHumanDate(isoDay($0)))" } ?? "Choose the expiry date") { choosing = true }.padding(.top, 12)
                }
                if !row.asksNumber { Muted("Bucks doesn't keep this document's number, only the file for checking.").padding(.top, 12) }
                HStack(spacing: 8) {
                    GhostButton("Cancel", enabled: !busy, action: onCancel)
                    PrimaryButton(busy ? "Sending…" : "Send to Bucks", enabled: ready) { onSubmit(number, expiresISO) }
                }.padding(.top, 16)
            }
        }
        .sheet(isPresented: $choosing) { expiryPicker }
    }

    private func isoDay(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private var expiryPicker: some View {
        let today = Self.utc.startOfDay(for: Date())
        return VStack(spacing: 12) {
            DatePicker("Expiry date", selection: Binding(get: { expires ?? today }, set: { expires = $0 }), in: today..., displayedComponents: .date)
                .datePickerStyle(.graphical).environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
            HStack(spacing: 8) {
                GhostButton("Cancel") { choosing = false }
                PrimaryButton("OK") { if expires == nil { expires = today }; choosing = false }
            }
        }.padding(Gutter).presentationDetents([.medium, .large])
    }
}

/// Bucks staff only: documents waiting for a decision, oldest first. Approving the last required document of a listing that
/// already has its recommendations takes it live.
struct StaffReviewScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var store = ManageStore()
    @State private var rejecting: ReviewDoc?
    @State private var reason = ""

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Review documents", onBack: { router.pop() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !store.reviewLoaded { BucksLoader().frame(maxWidth: .infinity).padding(40) }
                        else if store.reviewQueue.isEmpty { Muted("Nothing to review. New uploads show up here.") }
                        else { ForEach(store.reviewQueue) { item in card(item).padding(.bottom, 10) } }
                    }.padding(.horizontal, Gutter).padding(.bottom, 24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { await store.loadReviewQueue(toast: session.toast) }
        .alert("Reject \(rejecting?.label ?? "")?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
            TextField("Reason they will see", text: $reason)
            Button("Cancel", role: .cancel) {}
            Button("Reject") {
                let clean = String(reason.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let item = rejecting, !clean.isEmpty { Task { await store.review(item, approve: false, note: clean, toast: session.toast) } }
            }
        } message: { Text("The name on the licence doesn't match the shop") }
    }

    private func card(_ item: ReviewDoc) -> some View {
        BucksCard(padding: 14) {
            Text(item.label).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
            Muted([item.listingTitle, manageServiceLabel(item.service)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            if let facts = manageDocFacts(number: item.number, expiresOn: item.expiresOn) {
                Text(facts).bucks(.bodySmall).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            Muted("Check the name, number and dates on the file match what they entered.").padding(.top, 4)
            HStack(spacing: 8) {
                SmallButton("Open file", tonal: true) { open(item) }
                SmallButton("Approve") { Task { await store.review(item, approve: true, note: "", toast: session.toast) } }
                SmallButton("Reject", tonal: true) { reason = ""; rejecting = item }
                Spacer(minLength: 0)
            }.padding(.top, 10)
        }
    }

    private func open(_ item: ReviewDoc) {
        Task {
            do {
                let url = try await Backend.shared.signedURL(bucket: "docs", path: item.path)
                openSystemURL(url.absoluteString) { ok in if !ok { session.toast("No app on this phone can open that file.") } }
            } catch { session.toast("Couldn't open the file. Check your connection.") }
        }
    }
}
