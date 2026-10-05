import SwiftUI
import BucksCore
#if os(iOS)
import UIKit
import Photos
#elseif canImport(AppKit)
import AppKit
#endif

/// Downloads an attachment into the cache and hands it to the phone: the share sheet (save to Files, send on WhatsApp...) or the Photos library.
/// Port of FileOpener and MediaSaver in AttachmentViewer.kt.
public enum FileOpener {
    /// Fetches a private file through a short-lived signed URL into the cache (files older than a day are cleared). The name keeps its extension so the system knows the type.
    public static func download(bucket: String, path: String, name: String? = nil) async throws -> URL {
        let url = try await Backend.shared.signedURL(bucket: bucket, path: path)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("opened", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < cutoff { try? FileManager.default.removeItem(at: f) }
        }
        let raw = name ?? (path as NSString).lastPathComponent
        let safe = String(String(raw.unicodeScalars.map { c in CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-").contains(c) ? Character(c) : "_" }).suffix(80))
        let file = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw BackendError.http(status: http.statusCode, body: "") }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        return file
    }

    /// The system share sheet for an attachment. False when the download failed.
    @MainActor public static func share(bucket: String, path: String, name: String? = nil) async -> Bool {
        guard let file = try? await download(bucket: bucket, path: path, name: name) else { return false }
        present(file)
        return true
    }

    /// Opens `file` in the phone's own share/open sheet.
    @MainActor public static func present(_ file: URL) {
        #if os(iOS)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(sheet, animated: true)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(file)
        #endif
    }
}

/// Saves a photo or video into the phone's gallery. iOS asks for add-only access to Photos the first time.
public enum MediaSaver {
    public enum Outcome: Equatable { case saved, denied, failed }

    @MainActor public static func save(bucket: String, path: String, mime: String) async -> Outcome {
        let video = mime.hasPrefix("video/")
        let ext = mime == "image/png" ? "png" : mime == "image/webp" ? "webp" : mime == "image/gif" ? "gif" : video ? "mp4" : "jpg"
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd_HHmmss"
        let name = "Bucks_" + stamp.string(from: Date()) + "." + ext
        guard let file = try? await FileOpener.download(bucket: bucket, path: path, name: name) else { return .failed }
        #if os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file) } else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file) }
            }
            return .saved
        } catch { return .failed }
        #else
        // No Photos library to add to here: put it in ~/Pictures/Bucks (or Movies).
        let base = FileManager.default.urls(for: video ? .moviesDirectory : .picturesDirectory, in: .userDomainMask).first
        guard let dir = base?.appendingPathComponent("Bucks", isDirectory: true) else { return .failed }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: file, to: dest)
            return .saved
        } catch { return .failed }
        #endif
    }
}
