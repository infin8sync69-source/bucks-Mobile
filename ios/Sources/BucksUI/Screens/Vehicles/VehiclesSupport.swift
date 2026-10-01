import SwiftUI
import Observation
import UniformTypeIdentifiers
import PhotosUI
import BucksCore
#if canImport(UIKit)
import UIKit
#endif

let maxDocBytes = 10 * 1024 * 1024

/// A document chosen on this phone, ready to upload.
struct PickedDoc: Equatable {
    var data: Data
    var name: String
    var mime: String
    var isImage: Bool { mime.hasPrefix("image/") }
    var fileExtension: String { mime == "application/pdf" ? "pdf" : (mime == "image/png" ? "png" : "jpg") }

    /// A photo from the library, turned upright and re-encoded as a JPEG no larger than 1600 px (small uploads on mobile data).
    static func photo(_ raw: Data, name: String) -> PickedDoc? {
        #if canImport(UIKit)
        guard let image = UIImage(data: raw) else { return nil }
        let long = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(long, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = drawn.jpegData(compressionQuality: 0.82) else { return nil }
        return PickedDoc(data: jpeg, name: (name as NSString).deletingPathExtension + ".jpg", mime: "image/jpeg")
        #else
        guard NSImage(data: raw) != nil else { return nil }
        return PickedDoc(data: raw, name: name, mime: "image/jpeg")
        #endif
    }

    /// Why a chosen file was turned away, in Android's words.
    enum Refusal: String, Error {
        case unreadable = "Couldn't read that file. Try a photo of the document."
        case unsupported = "Photos (JPG, PNG) or PDF only."
    }
    /// The largest file read into memory; bigger ones are refused before they can exhaust it (Upload.MAX_READ_BYTES).
    static let maxReadBytes = 32 * 1024 * 1024

    /// A file from the Files picker: an image or a PDF.
    static func file(at url: URL) -> Result<PickedDoc, Refusal> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxReadBytes { return .failure(.unreadable) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true { return .success(PickedDoc(data: data, name: url.lastPathComponent, mime: "application/pdf")) }
        if type?.conforms(to: .image) == true {
            guard let doc = photo(data, name: url.lastPathComponent) else { return .failure(.unreadable) }
            return .success(doc)
        }
        return .failure(.unsupported)
    }
}

/// An image from a private bucket, shown through a signed URL.
struct SignedImage: View {
    let bucket: String
    let path: String
    @State private var url: URL?
    var body: some View {
        ZStack {
            BucksColor.surfaceContainer
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").foregroundStyle(BucksColor.onSurfaceVariant)
                    default: ProgressView().controlSize(.small)
                    }
                }
            } else { ProgressView().controlSize(.small) }
        }
        .clipped()
        .task(id: path) { url = try? await Backend.shared.signedURL(bucket: bucket, path: path) }
    }
}

func vehicleKindLabel(_ kind: String) -> String {
    switch kind { case "AUTO": "Auto"; case "CAB": "Cab"; case "BIKE": "Bike"; default: kind }
}
func vehicleSymbol(_ kind: String) -> String { VehicleKind(serverValue: kind).systemImage }

/// My vehicles, their documents, drivers and stats: the owner's side of Android's MyListings, vehicle part.
@MainActor @Observable
final class VehicleStore {
    private(set) var vehicles: [VehicleRow] = []
    private(set) var docs: [String: [VehicleDoc]] = [:]
    private(set) var members: [String: Int] = [:]
    private(set) var stats: [VehicleStat] = []
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var error: String?
    private(set) var busy = false

    func vehicle(_ id: String) -> VehicleRow? { vehicles.first { $0.id == id } }

    /// Vehicles and their documents land together; the member counts follow.
    func refresh() async {
        loading = true; defer { loading = false }
        do {
            let (vs, d) = try await Backend.shared.myVehiclesWithDocs()
            docs = d; vehicles = vs.sorted { $0.model.lowercased() < $1.model.lowercased() }; loaded = true; error = nil
            for v in vs { if let rows = try? await Backend.shared.vehicleMembers(vehicleId: v.id) { members[v.id] = rows.count } }
        } catch is CancellationError {} catch { self.error = friendlyError(error) }
    }
    func refreshStats() async {
        do { stats = try await Backend.shared.vehicleStats().sorted { $0.plate < $1.plate } } catch is CancellationError {} catch let e { self.error = friendlyError(e) }
    }

    /// The vehicle row exists once addVehicle returns (the plate is unique, so Save again could not create it twice), so documents
    /// that fail to upload are reported and the ones that did upload are kept; the owner adds the rest from Edit.
    func add(me: String, kind: String, model: String, plate: String, files: [String: PickedDoc], toast: (String) -> Void) async -> Bool {
        busy = true; defer { busy = false }
        do {
            let v = try await Backend.shared.addVehicle(me: me, kind: kind, model: model, plate: plate)
            var uploaded: [VehicleDoc] = []; var failed = 0
            for (k, f) in files.sorted(by: { $0.key < $1.key }) {
                do { uploaded.append(try await Backend.shared.uploadVehicleDoc(me: me, kind: k, data: f.data, fileExtension: f.fileExtension, contentType: f.mime)) } catch { failed += 1 }
            }
            if !uploaded.isEmpty {
                do { try await Backend.shared.setVehicleDocs(id: v.id, docs: uploaded); docs[v.id] = uploaded } catch { failed += uploaded.count }
            }
            let name = "\(v.model.isEmpty ? v.kind : v.model) (\(v.plate))"
            toast(failed > 0 ? "\(name) added, but \(failed) document\(failed > 1 ? "s" : "") didn't upload. Add them from Edit." : "\(name) added. Bucks checks the documents before it can go online.")
            await refresh(); return true
        } catch { toast(friendlyError(error)); return false }
    }

    /// Keeps `keep`, uploads `add`, and drops the references of `before` (the documents the form opened with) the owner removed.
    func update(me: String, id: String, kind: String, model: String, plate: String, before: [VehicleDoc], keep: [VehicleDoc], add: [String: PickedDoc], toast: (String) -> Void) async -> Bool {
        busy = true; defer { busy = false }
        do {
            var all = keep
            for (k, f) in add.sorted(by: { $0.key < $1.key }) {
                all.append(try await Backend.shared.uploadVehicleDoc(me: me, kind: k, data: f.data, fileExtension: f.fileExtension, contentType: f.mime))
            }
            try await Backend.shared.updateVehicleDetails(id: id, kind: kind, model: model, plate: plate, docs: all)
            let gone = before.map(\.path).filter { p in !all.contains { $0.path == p } }
            if !gone.isEmpty { try? await Backend.shared.deleteObjects(bucket: "docs", paths: gone) }
            toast("Saved."); await refresh(); return true
        } catch { toast(friendlyError(error)); return false }
    }

    func delete(id: String, toast: (String) -> Void) async -> Bool {
        let paths = (docs[id] ?? []).map(\.path)
        do {
            try await Backend.shared.deleteVehicle(id: id)
            if !paths.isEmpty { try? await Backend.shared.deleteObjects(bucket: "docs", paths: paths) }
            vehicles.removeAll { $0.id == id }; toast("Vehicle removed."); return true
        } catch { toast(friendlyError(error)); return false }
    }
}
