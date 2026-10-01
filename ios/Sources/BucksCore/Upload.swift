import Foundation

/// The pure parts of Upload.kt: size limits and file-type helpers. Reading and re-encoding the pixels is in BucksUI/Media.
public enum Upload {
    /// Largest file read into memory (chat allows 25 MB, moments 30 MB); bigger files are refused before they can exhaust memory.
    public static let maxReadBytes = 32 * 1024 * 1024
    /// Photos: longest side in pixels and JPEG quality after re-encoding.
    public static let maxPixels = 1600
    public static let jpegQuality = 0.82

    public static let tooBigMessage = "That file is over 32 MB. Pick a smaller one."
    public static let unreadableMessage = "Couldn't read that file."

    public static func isTooBig(_ bytes: Int) -> Bool { bytes > maxReadBytes }

    /// The longest side scaled to fit `maxPixels`, never enlarged.
    public static func fitted(width: Double, height: Double, maxPixels: Int = Upload.maxPixels) -> (width: Double, height: Double) {
        let longest = max(width, height)
        guard longest > Double(maxPixels), longest > 0 else { return (width, height) }
        let k = Double(maxPixels) / longest
        return ((width * k).rounded(), (height * k).rounded())
    }

    /// "photo.heic" becomes "photo.jpg": re-encoded photos are JPEG whatever they were.
    public static func jpegName(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "photo" : base) + ".jpg"
    }

    private static let mimes: [String: String] = [
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp", "heic": "image/heic", "heif": "image/heif",
        "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "3gp": "video/3gpp", "webm": "video/webm",
        "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv", "json": "application/json", "zip": "application/zip",
        "doc": "application/msword", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint", "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav",
    ]
    private static let extensions: [String: String] = ["image/jpeg": "jpg", "video/mp4": "mp4", "video/quicktime": "mov"]

    /// The media type for a file name; "application/octet-stream" when unknown (what Android's content resolver falls back to).
    public static func mime(forFileName name: String) -> String { mimes[(name as NSString).pathExtension.lowercased()] ?? "application/octet-stream" }
    /// The file extension for a media type, without the dot.
    public static func fileExtension(forMime mime: String) -> String {
        if let e = extensions[mime] { return e }
        return mimes.first { $0.value == mime }?.key ?? "bin"
    }
}
