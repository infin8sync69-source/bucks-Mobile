import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import BucksCore

public extension View {
    /// Photo library; photos come back upright and re-encoded (≤1600 px JPEG quality 0.82, like Upload.read), videos as MP4.
    /// A file over 32 MB (or one that can't be read) is skipped with a toast; the rest still arrive.
    func bucksPhotoPicker(isPresented: Binding<Bool>, maxCount: Int = 1, allowVideo: Bool = false, onPicked: @escaping ([Picked]) -> Void) -> some View {
        modifier(PhotoPickerModifier(isPresented: isPresented, maxCount: max(1, maxCount), allowVideo: allowVideo, onPicked: onPicked))
    }
    /// Files app: any file up to 32 MB. `onPicked` gets nil (after a toast) when the file is too big or can't be read; cancelling does not call it.
    func bucksFilePicker(isPresented: Binding<Bool>, onPicked: @escaping (Picked?) -> Void) -> some View {
        modifier(FilePickerModifier(isPresented: isPresented, onPicked: onPicked))
    }
    /// The camera, photo or video (the capture itself lives in Camera.swift).
    func bucksCamera(isPresented: Binding<Bool>, video: Bool = false, onCaptured: @escaping (Picked) -> Void) -> some View {
        modifier(CameraForwarder(isPresented: isPresented, video: video, onCaptured: onCaptured))
    }
}

private struct CameraForwarder: ViewModifier {
    @Environment(AppSession.self) private var session: AppSession?
    @Binding var isPresented: Bool
    let video: Bool
    let onCaptured: (Picked) -> Void
    func body(content: Content) -> some View {
        content.bucksCapture(isPresented: $isPresented, video: video, onCaptured: onCaptured, onError: { session?.toast($0) })
    }
}

/// A movie handed over by the photo picker, copied to a temporary file we own.
private struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

private struct PhotoPickerModifier: ViewModifier {
    @Environment(AppSession.self) private var session: AppSession?
    @Binding var isPresented: Bool
    let maxCount: Int
    let allowVideo: Bool
    let onPicked: ([Picked]) -> Void
    @State private var items: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $items, maxSelectionCount: maxCount, matching: allowVideo ? .any(of: [.images, .videos]) : .images)
            .onChange(of: items) { _, chosen in
                guard !chosen.isEmpty else { return }
                items = []
                Task { await load(chosen) }
            }
    }

    private func load(_ chosen: [PhotosPickerItem]) async {
        var picked: [Picked] = []
        var refused: MediaError?
        for item in chosen {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw MediaError.unreadable }
                    picked.append(try await MediaReader.video(at: movie.url))
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaError.unreadable }
                    picked.append(try MediaReader.photo(data))
                }
            } catch let e as MediaError { refused = refused ?? e } catch { refused = refused ?? .unreadable }
        }
        if let refused { session?.toast(refused.message) }
        if !picked.isEmpty { onPicked(picked) }
    }
}

private struct FilePickerModifier: ViewModifier {
    @Environment(AppSession.self) private var session: AppSession?
    @Binding var isPresented: Bool
    let onPicked: (Picked?) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task.detached {
                do { let p = try MediaReader.file(url); await MainActor.run { onPicked(p) } }
                catch { let m = (error as? MediaError)?.message ?? Upload.unreadableMessage; await MainActor.run { session?.toast(m); onPicked(nil) } }
            }
        }
    }
}
