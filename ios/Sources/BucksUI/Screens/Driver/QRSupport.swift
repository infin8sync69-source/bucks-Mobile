import SwiftUI
import BucksCore
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A crisp QR code for `text` (nil when it cannot be encoded). Black on white, scaled up without smoothing.
func driverQRImage(_ text: String, size: CGFloat = 512) -> Image? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8); f.correctionLevel = "M"
    guard let out = f.outputImage, out.extent.width > 0 else { return nil }
    let scale = max(1, (size / out.extent.width).rounded(.down))
    let big = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
    return Image(decorative: cg, scale: 1).interpolation(.none)
}

/// The white framed QR used on the trip and payment screens.
struct QRBox: View {
    let text: String
    var side: CGFloat = 200
    var label: String
    var padding: CGFloat = 10
    var bordered = true
    var body: some View {
        Group {
            if let img = driverQRImage(text) { img.resizable().scaledToFit().accessibilityLabel(label) }
            else { Color.clear }
        }
        .padding(padding).frame(width: side, height: side).background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: bordered ? BucksRadius.small : BucksRadius.medium, style: .continuous))
        .overlay { if bordered { RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1) } }
    }
}

/// Reads the QR code in a picked image with Vision; tries the inverted image too (dark-mode screenshots). Nil when there is none.
func driverDecodeQR(_ data: Data) async -> String? {
    await Task.detached(priority: .userInitiated) { () -> String? in
        if let t = detectQR(handler: VNImageRequestHandler(data: data, options: [:])) { return t }
        guard let ci = CIImage(data: data) else { return nil }
        let inv = CIFilter.colorInvert(); inv.inputImage = ci
        guard let out = inv.outputImage else { return nil }
        return detectQR(handler: VNImageRequestHandler(ciImage: out, options: [:]))
    }.value
}

private func detectQR(handler: VNImageRequestHandler) -> String? {
    let req = VNDetectBarcodesRequest()
    req.symbologies = [.qr]
    guard (try? handler.perform([req])) != nil else { return nil }
    return req.results?.compactMap { $0.payloadStringValue }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Opens a URL with the system. Reports whether it was taken.
@MainActor func driverOpenURL(_ s: String, completion: ((Bool) -> Void)? = nil) {
    guard let url = URL(string: s) else { completion?(false); return }
    #if canImport(UIKit)
    UIApplication.shared.open(url, options: [:]) { completion?($0) }
    #elseif canImport(AppKit)
    completion?(NSWorkspace.shared.open(url))
    #else
    completion?(false)
    #endif
}

/// Short distance text used on the request card and trip screen.
func driverMetres(_ km: Double) -> String { km < 1 ? "\(Int(km * 1000))m" : "\(Geo.round1(km))km" }

/// Text before the first " · " (the shop name in delivery copy).
func driverBeforeDot(_ s: String) -> String { s.components(separatedBy: " · ").first ?? s }
/// Text after the first " · ", or "" when there is none.
func driverAfterDot(_ s: String) -> String {
    guard let r = s.range(of: " · ") else { return "" }
    return String(s[r.upperBound...])
}

#if os(iOS)
import VisionKit

/// Live camera scan for a printed QR (iOS 16+ DataScanner). Calls `onResult` once with the first code read, `onUnavailable` when the camera can't scan.
struct QRScannerSheet: View {
    var onResult: (String) -> Void
    var onUnavailable: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable { dismiss(); onResult($0) }
                } else {
                    Color.clear.onAppear { dismiss(); onUnavailable() }
                }
            }
            .ignoresSafeArea()
            .navigationTitle("Scan a QR").bucksInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let b) in addedItems { if let s = b.payloadStringValue { done = true; dataScanner.stopScanning(); onCode(s); return } }
        }
    }
}
#endif

/// Profiles store 10-digit Indian numbers; anything else passes through.
func driverFullNumber(_ p: String) -> String {
    let d = p.filter { $0.isNumber || $0 == "+" }
    return d.count == 10 ? "+91\(d)" : d
}
@MainActor func driverDial(_ phone: String) { driverOpenURL("tel:\(driverFullNumber(phone))") }
@MainActor func driverSMS(_ phone: String) { driverOpenURL("sms:\(driverFullNumber(phone))") }

/// The blue "you" dot of the maps (MeColor on Android).
let driverMeColor = Color(hex: 0x1D4ED8)

/// The road between the driver and where they are heading: keeps the last route while a new one loads, nil offline.
@MainActor @Observable
final class DriverRoadRoute {
    private(set) var route: MapServices.RoadRoute?
    @ObservationIgnored private var key: [Int]?
    /// Re-queries only when an end moved by about 200 m.
    func load(from: LatLng?, to: LatLng?) async {
        guard let from, let to else { route = nil; key = nil; return }
        let k = [from.lat, from.lng, to.lat, to.lng].map { Int(($0 * 500).rounded()) }
        guard k != key else { return }
        key = k
        if let r = await MapServices.route(from: from, to: to) { route = r }
    }
}
