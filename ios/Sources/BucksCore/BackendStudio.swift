import Foundation

// Calls for the Studio (port of data/BackendStudio.kt, listing parts): galleries, listing media and the recommendation threshold.

public extension Backend {
    /// A photo list as the jsonb the server stores: `caption` only when there is one.
    static func mediaJSON(_ photos: [MediaPhoto]) -> [[String: String]] {
        photos.map { p in p.caption.trimmingCharacters(in: .whitespaces).isEmpty ? ["url": p.url] : ["url": p.url, "caption": p.caption] }
    }
    /// Replaces a listing's gallery (the server keeps only photos from the listing's own listing-media folder, at most 20).
    func setGallery(listingId: String, photos: [MediaPhoto]) async throws {
        try await update("listings", ["gallery": Self.mediaJSON(photos)], filters: [.eq("id", listingId)])
    }
    /// Uploads a photo to listing-media/<listing id>/ and returns its public URL.
    func uploadListingMedia(listingId: String, photo: Picked) async throws -> String {
        let path = "\(listingId)/\(photo.objectName())"
        try await upload(bucket: "listing-media", path: path, data: photo.data, contentType: photo.mime)
        guard let url = publicURL(bucket: "listing-media", path: path) else { throw BackendError.notSignedIn }
        return url.absoluteString
    }
    /// Removes files of listing-media by their public URLs (photos taken out of a gallery or a product). Callers ignore failures.
    func deleteListingMedia(urls: [String]) async throws {
        let marker = "/object/public/listing-media/"
        let paths = urls.compactMap { u -> String? in
            guard let r = u.range(of: marker) else { return nil }
            let p = String(u[r.upperBound...]); return p.isEmpty ? nil : p
        }
        try await deleteFiles(bucket: "listing-media", paths: paths)
    }
    /// How many in-person recommendations take a listing live (settings.min_recommendations); nil when it can't be read.
    func minRecommendations() async throws -> Int? { try await settingValue("min_recommendations").map { Int($0) } }
}
