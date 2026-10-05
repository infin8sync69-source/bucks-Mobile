import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import BucksCore

/// Why a picked file was refused; `message` is what the person sees.
enum MediaError: Error, Equatable {
    case tooBig, unreadable
    var message: String { self == .tooBig ? Upload.tooBigMessage : Upload.unreadableMessage }
}

/// Turns what the pickers hand over into `Picked` (Upload.read): photos upright and re-encoded, everything else as is.
enum MediaReader {
    /// A photo as JPEG: rotated upright by its EXIF orientation, long side at most 1600 px, quality 0.82. nil when the bytes are not an image.
    static func jpeg(_ data: Data, name: String) -> Picked? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        guard let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue, let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
        let longest = min(Double(Upload.maxPixels), max(w, h))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: Upload.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Picked(data: out as Data, name: Upload.jpegName(name), mime: "image/jpeg")
    }

    /// Photo-library image bytes (HEIC, PNG, JPEG…).
    static func photo(_ data: Data, name: String = "photo") throws -> Picked {
        if Upload.isTooBig(data.count) { throw MediaError.tooBig }
        guard let p = jpeg(data, name: name) else { throw MediaError.unreadable }
        return p
    }

    /// A file from the Files app: images (but GIFs) go through `photo`, anything else is read as is. Size is checked before reading.
    static func file(_ url: URL) throws -> Picked {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
        if size > Upload.maxReadBytes { throw MediaError.tooBig }
        guard let data = try? Data(contentsOf: url) else { throw MediaError.unreadable }
        if Upload.isTooBig(data.count) { throw MediaError.tooBig }
        let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let mime = Upload.mime(forFileName: name)
        if mime.hasPrefix("image/"), mime != "image/gif" { return try photo(data, name: name) }
        return Picked(data: data, name: name, mime: mime)
    }

    /// A movie from the photo library as MP4. An MP4 already small enough is passed through untouched; the rest is exported at 720p.
    static func video(at url: URL) async throws -> Picked {
        defer { try? FileManager.default.removeItem(at: url) }
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if (ext == "mp4" || ext == "m4v"), size <= Upload.maxReadBytes, let data = try? Data(contentsOf: url) {
            return Picked(data: data, name: "video.mp4", mime: "video/mp4")
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPreset1280x720) else { throw MediaError.unreadable }
        session.outputURL = out; session.outputFileType = .mp4; session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
        guard session.status == .completed else { throw MediaError.unreadable }
        let exported = (try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if exported > Upload.maxReadBytes { throw MediaError.tooBig }
        guard let data = try? Data(contentsOf: out) else { throw MediaError.unreadable }
        return Picked(data: data, name: "video.mp4", mime: "video/mp4")
    }
}
