import SwiftUI
import AVFoundation
import BucksCore
#if os(iOS)
import UIKit
#endif

// The phone's own camera, for photos and videos (Camera.kt). Android hands the capture to the camera app; iOS shows the system camera
// (UIImagePickerController), which needs NSCameraUsageDescription and NSMicrophoneUsageDescription in Info.plist.

public extension View {
    /// Takes a photo (`video: false`) or records a video of up to 30 seconds (`video: true`) with the system camera.
    /// Photos come back upright as JPEGs of at most `maxPixels` on the long side; videos as MP4 no larger than `maxVideoBytes`.
    /// `onError` hears about a phone with no camera ("No camera app found on this phone.") or a capture that couldn't be read.
    func bucksCapture(isPresented: Binding<Bool>, video: Bool, maxVideoBytes: Int = 25 * 1024 * 1024, maxPixels: Int = 1600,
                      onCaptured: @escaping (Picked) -> Void, onError: @escaping (String) -> Void) -> some View {
        modifier(CaptureModifier(isPresented: isPresented, video: video, maxVideoBytes: maxVideoBytes, maxPixels: maxPixels, onCaptured: onCaptured, onError: onError))
    }
}

/// Turns what the camera saved into something uploadable.
enum CaptureEncoder {
    /// Re-encodes a photo upright as JPEG, long side at most `maxPixels`.
    static func jpeg(_ data: Data, maxPixels: Int) -> Picked? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(image, maxPixels: maxPixels)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    static func jpeg(_ image: UIImage, maxPixels: Int) -> Picked? {
        let long = max(image.size.width, image.size.height)
        let scale = min(1, CGFloat(maxPixels) / max(long, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = drawn.jpegData(compressionQuality: 0.82) else { return nil }
        return Picked(data: data, name: "capture.jpg", mime: "image/jpeg")
    }
    #endif

    /// A recorded movie as MP4 (H.264), cut off at `maxBytes`. The camera records QuickTime, which the Moments bucket does not take.
    static func mp4(from url: URL, maxBytes: Int) async -> Picked? {
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { return nil }
        session.outputURL = out; session.outputFileType = .mp4; session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = Int64(maxBytes)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
        defer { try? FileManager.default.removeItem(at: out) }
        guard session.status == .completed, let data = try? Data(contentsOf: out) else { return nil }
        return Picked(data: data, name: "capture.mp4", mime: "video/mp4")
    }
}

#if os(iOS)
private struct CaptureModifier: ViewModifier {
    @Binding var isPresented: Bool
    let video: Bool, maxVideoBytes: Int, maxPixels: Int
    let onCaptured: (Picked) -> Void, onError: (String) -> Void

    private var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, now in
                if now && !available { isPresented = false; onError("No camera app found on this phone.") }
            }
            .fullScreenCover(isPresented: Binding(get: { isPresented && available }, set: { isPresented = $0 })) {
                CameraPicker(video: video) { result in
                    isPresented = false
                    guard let result else { return }
                    Task {
                        let picked: Picked?
                        switch result {
                        case .photo(let image): picked = CaptureEncoder.jpeg(image, maxPixels: maxPixels)
                        case .movie(let url): picked = await CaptureEncoder.mp4(from: url, maxBytes: maxVideoBytes)
                        }
                        if let picked { onCaptured(picked) } else { onError("Couldn't open what the camera saved. Try again.") }
                    }
                }.ignoresSafeArea()
            }
    }
}

private enum CameraResult { case photo(UIImage), movie(URL) }

private struct CameraPicker: UIViewControllerRepresentable {
    let video: Bool
    let onResult: (CameraResult?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = [video ? "public.movie" : "public.image"]
        if video { p.cameraCaptureMode = .video; p.videoMaximumDuration = 30; p.videoQuality = .typeMedium }
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onResult) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (CameraResult?) -> Void
        init(_ onResult: @escaping (CameraResult?) -> Void) { self.onResult = onResult }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                // The system deletes its temporary movie when this returns; keep a copy until it is exported.
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                onResult((try? FileManager.default.copyItem(at: url, to: keep)) != nil ? .movie(keep) : nil)
            } else if let image = info[.originalImage] as? UIImage { onResult(.photo(image)) }
            else { onResult(nil) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onResult(nil) }
    }
}
#else
private struct CaptureModifier: ViewModifier {
    @Binding var isPresented: Bool
    let video: Bool, maxVideoBytes: Int, maxPixels: Int
    let onCaptured: (Picked) -> Void, onError: (String) -> Void
    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, now in if now { isPresented = false; onError("No camera app found on this phone.") } }
    }
}
#endif
