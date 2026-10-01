import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import BucksCore

private let vehicleKindChoices: [(key: String, label: String)] = [("AUTO", "Auto"), ("CAB", "Cab"), ("BIKE", "Bike (delivery only)")]

/// Add or edit a vehicle; documents go to the private docs bucket under my folder. Only the owner can save.
struct VehicleEditScreen: View {
    var id: String?
    @Environment(Router.self) private var router
    @State private var store = VehicleStore()

    var body: some View {
        let existing = id.flatMap { store.vehicle($0) }
        Group {
            // The form snapshots the documents once, and Save writes that list back, so it must not open before they are known:
            // an empty snapshot would wipe the RC, insurance and permit references on the next Save.
            if let id, existing == nil || store.docs[id] == nil {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 0) {
                        BucksTopBar(title: "Edit vehicle", onBack: { router.pop() })
                        if store.loaded && existing == nil {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Vehicle not found").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                                Muted("It may have been removed, or you no longer drive it.").padding(.top, 4)
                                SmallButton("Back", tonal: true) { router.pop() }.padding(.top, 14)
                            }.padding(Gutter)
                        } else if let err = store.error, !store.loaded {
                            LoadError(err) { Task { await store.refresh() } }.padding(Gutter)
                        } else { BucksLoader().frame(maxWidth: .infinity).padding(.top, 40) }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                VehicleForm(store: store, existing: existing, before: id.flatMap { store.docs[$0] } ?? []).id(existing?.id ?? "new")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task(id: id) { if id != nil { await store.refresh() } }
    }
}

private struct VehicleForm: View {
    let store: VehicleStore
    let existing: VehicleRow?
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    /// The documents the form opened with (a later reload must not change what Save deletes).
    @State private var before: [VehicleDoc]
    @State private var kind: String
    @State private var model: String
    @State private var plate: String
    /// The documents the form opened with; Save writes back this list minus what the owner removed.
    @State private var kept: [VehicleDoc]
    @State private var added: [String: PickedDoc] = [:]
    @State private var pickingFor: String?
    @State private var chooser = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmDelete = false

    init(store: VehicleStore, existing: VehicleRow?, before: [VehicleDoc]) {
        self.store = store; self.existing = existing
        _before = State(initialValue: before)
        _kind = State(initialValue: existing?.kind ?? ""); _model = State(initialValue: existing?.model ?? ""); _plate = State(initialValue: existing?.plate ?? "")
        _kept = State(initialValue: before)
    }

    private var owner: Bool { existing == nil || existing?.ownerId == session.me?.id }

    var body: some View {
        VStack(spacing: 0) {
            ContentColumn {
                VStack(spacing: 0) {
                    BucksTopBar(title: existing == nil ? "Add vehicle" : "Edit vehicle", onBack: { router.pop() })
                    if store.busy { ProgressView().progressViewStyle(.linear).tint(BucksColor.primary) }
                    ScrollView { fields.padding(.horizontal, Gutter).padding(.top, 8).padding(.bottom, 16) }.scrollDismissesKeyboard(.interactively)
                }
            }
            if owner {
                VStack(spacing: 4) {
                    PrimaryButton(store.busy ? "Uploading…" : existing == nil ? "Add vehicle" : "Save changes", enabled: !store.busy) { save() }
                    if existing != nil { BadButton("Remove this vehicle") { confirmDelete = true } }
                }.padding(.horizontal, Gutter).padding(.vertical, 12)
            }
        }
        .confirmationDialog("Add a document", isPresented: $chooser, titleVisibility: .visible) {
            Button("Choose a photo") { showPhotos = true }
            Button("Choose a file (photo or PDF)") { showFiles = true }
            Button("Cancel", role: .cancel) { pickingFor = nil }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .pdf]) { result in
            let k = pickingFor; pickingFor = nil
            guard let k, case .success(let url) = result else { return }
            switch PickedDoc.file(at: url) { case .success(let f): accept(f, for: k); case .failure(let why): session.toast(why.rawValue) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            let k = pickingFor; pickingFor = nil
            guard let k else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self), raw.count <= PickedDoc.maxReadBytes, let f = PickedDoc.photo(raw, name: "photo.jpg") else {
                    session.toast(PickedDoc.Refusal.unreadable.rawValue); return
                }
                accept(f, for: k)
            }
        }
        .bucksConfirm(isPresented: $confirmDelete,
                      title: "Remove \(existing.map { $0.model.isEmpty ? vehicleKindLabel($0.kind) : $0.model } ?? "") (\(existing?.plate ?? ""))?",
                      message: "Its documents are deleted and drivers you invited lose access. Past trips stay in your records.", confirmTitle: "Remove", destructive: true) {
            guard let existing else { return }
            Task { if await store.delete(id: existing.id, toast: session.toast) { router.pop() } }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !owner { Notice("You drive this vehicle but don't own it, so only the owner can change it.").padding(.bottom, 14) }
            else if existing?.status == "ACTIVE" { Notice("This vehicle is checked and active. Changing its type, number plate or documents puts it back under review; it can't go online until Bucks checks it again.").padding(.bottom, 14) }
            FieldLabel("Vehicle type")
            HStack(spacing: 8) {
                ForEach(vehicleKindChoices, id: \.key) { c in BucksChip(c.label, selected: kind == c.key, systemImage: vehicleSymbol(c.key)) { if owner { kind = c.key } } }
            }.padding(.bottom, 14)
            BucksField(Binding(get: { model }, set: { if owner { model = String($0.prefix(60)) } }), label: "Model", placeholder: "Honda Activa, Bajaj RE, Maruti Dzire", readOnly: !owner)
            BucksField(Binding(get: { plate }, set: { if owner { plate = String($0.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(12)) } }), label: "Number plate", placeholder: "KA05AB1234", readOnly: !owner).bucksAutocapCharacters()
            documents
        }
    }

    private var documents: some View {
        let kinds = vehicleDocKinds(kind.isEmpty ? "CAB" : kind)
        let requiredDone = kinds.filter { dk in dk.required && (added[dk.key] != nil || kept.contains { $0.kind == dk.key }) }.count
        let requiredAll = kinds.filter(\.required).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle("Documents")
                if requiredDone == requiredAll { PillGood("All required added") } else { PillWarn("\(requiredDone) of \(requiredAll) required") }
            }.padding(.top, 4).padding(.bottom, 2)
            ProgressView(value: Double(requiredDone), total: Double(max(requiredAll, 1))).tint(BucksColor.primary).padding(.vertical, 6)
            Muted("Clear photos or PDFs. Bucks checks them before the vehicle can go online; nobody else sees them.").padding(.bottom, 8)
            ForEach(kinds, id: \.key) { dk in
                docRow(dk)
                BucksDivider()
            }
        }
    }

    private func docRow(_ dk: VehicleDocKind) -> some View {
        let have = kept.first { $0.kind == dk.key }
        let new = added[dk.key]
        return HStack(spacing: 12) {
            thumbnail(have: have, new: new).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(dk.label + (dk.required ? "" : " (optional)")).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                Muted(new.map { "Ready to upload: \($0.name)" } ?? (have != nil ? "Uploaded" : dk.hint))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if owner {
                if new != nil || have != nil {
                    Button { added[dk.key] = nil; kept.removeAll { $0.kind == dk.key } } label: {
                        Image(systemName: "xmark").foregroundStyle(BucksColor.onSurface).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Remove")
                }
                SmallButton(new != nil || have != nil ? "Replace" : "Add", tonal: true) { pickingFor = dk.key; chooser = true }
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func thumbnail(have: VehicleDoc?, new: PickedDoc?) -> some View {
        ZStack {
            BucksColor.surfaceContainerHigh
            if let new { Image(systemName: new.isImage ? "photo" : "doc.richtext").foregroundStyle(BucksColor.primary) }
            else if let have, !have.path.lowercased().hasSuffix(".pdf") { SignedImage(bucket: "docs", path: have.path) }
            else if have != nil { Image(systemName: "doc.richtext").foregroundStyle(BucksColor.primary) }
            else { Image(systemName: "doc.text").foregroundStyle(BucksColor.onSurfaceVariant) }
        }
    }

    private func accept(_ f: PickedDoc, for k: String) {
        if f.data.count > maxDocBytes { session.toast("Documents up to 10 MB. Take a smaller photo."); return }
        added[k] = f; kept.removeAll { $0.kind == k }
    }

    private func save() {
        let p = plate.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        if kind.isEmpty { session.toast("Pick the vehicle type."); return }
        if p.count < 6 { session.toast("Enter the full number plate, like KA05AB1234."); return }
        guard let me = session.me?.id else { return }
        let name = model.trimmingCharacters(in: .whitespaces)
        Task {
            let ok: Bool
            if let existing { ok = await store.update(me: me, id: existing.id, kind: kind, model: name, plate: p, before: before, keep: kept, add: added, toast: session.toast) }
            else { ok = await store.add(me: me, kind: kind, model: name, plate: p, files: added, toast: session.toast) }
            if ok { router.pop() }
        }
    }
}
