import SwiftUI
import BucksCore
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A Code 128 barcode of `text` (the Bucks ID card's strip), black bars on white, with no quiet zone so it can fill its strip.
func bucksBarcodeImage(_ text: String) -> Image? {
    let f = CIFilter.code128BarcodeGenerator()
    f.message = Data(text.utf8); f.quietSpace = 0
    guard let out = f.outputImage, out.extent.width > 0 else { return nil }
    let sx = max(1, (900 / out.extent.width).rounded(.down))
    let big = out.transformed(by: CGAffineTransform(scaleX: sx, y: 1))
    guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
    return Image(decorative: cg, scale: 1).interpolation(.none)
}

/// Puts text on the clipboard.
@MainActor func copyToClipboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    #endif
}

extension AppSession {
    /// Renews my Bucks ID card for another year (rpc renew_bucks_id) and tells the person.
    func renewBucksId() async {
        do {
            let issued = try await Backend.shared.renewBucksIdCard()
            me?.idIssuedAt = issued
            toast("Your Bucks ID is renewed for a year.")
        } catch { toast(friendlyError(error)) }
    }

    func shareTextForBucksId(_ code: String) -> String { "Sync with me on Bucks. My Bucks ID is \(BucksIdCode.pretty(code))." }
}
