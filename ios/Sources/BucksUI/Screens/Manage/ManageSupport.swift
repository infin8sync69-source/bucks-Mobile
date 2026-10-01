import SwiftUI
import BucksCore

/// A short explanation with a title and an icon, for empty states and rules (Android's InfoRow).
struct ManageInfoRow: View {
    let systemImage: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(systemImage: systemImage, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleSmall).foregroundStyle(BucksColor.onSurface)
                Muted(detail)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8)
    }
}

/// The rules for who may recommend a listing, in plain words. Shown on both recommendation screens.
struct RecommendRules: View {
    var body: some View {
        VStack(spacing: 0) {
            ManageInfoRow(systemImage: "house.fill", title: "Lives within 3 km", detail: "Their home on Bucks must be near where the listing is.")
            ManageInfoRow(systemImage: "calendar", title: "Account older than 14 days", detail: "New accounts can't recommend yet.")
            ManageInfoRow(systemImage: "qrcode.viewfinder", title: "Scanned in person", detail: "They must be standing near the shop or worker while scanning. Photos of the code don't work.")
            ManageInfoRow(systemImage: "person.3.fill", title: "Not part of the team", detail: "Owners, admins and store riders can't recommend their own listing.")
        }
    }
}

/// "4 Oct 2026" from an ISO date or timestamp; the input unchanged when it isn't one.
func manageHumanDate(_ iso: String) -> String {
    let p = DateFormatter(); p.locale = Locale(identifier: "en_US_POSIX"); p.timeZone = TimeZone(identifier: "UTC"); p.dateFormat = "yyyy-MM-dd"
    guard let d = p.date(from: String(iso.prefix(10))) else { return iso }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}

/// The service's label ("Listed under Food"); nil for an unknown key.
func manageServiceLabel(_ key: String?) -> String? {
    switch key {
    case "TAXI": "Taxi"; case "AUTO": "Auto"; case "PARCEL": "Parcel"; case "FOOD": "Food"; case "GROCERY": "Grocery"; case "VEGETABLES": "Vegetables"
    case "MEAT": "Meat"; case "SHOPPING": "Shopping"; case "GIGS": "Gigs"; case "JOBS": "Jobs"; case "PROPERTIES": "Properties"
    default: nil
    }
}

/// "No. 123 · valid till 4 Oct 2026", or nil when there is nothing to show.
func manageDocFacts(number: String, expiresOn: String?) -> String? {
    let facts = [number.isEmpty ? nil : "No. \(number)", expiresOn.map { "valid till \(manageHumanDate($0))" }].compactMap { $0 }
    return facts.isEmpty ? nil : facts.joined(separator: " · ")
}

extension View {
    /// Opens the camera QR scanner in a sheet (iPhone); elsewhere it explains that scanning needs a phone camera.
    func manageQrScanner(isPresented: Binding<Bool>, onResult: @escaping (String) -> Void, onError: @escaping (String) -> Void) -> some View {
        #if os(iOS)
        sheet(isPresented: isPresented) {
            QRScannerSheet(onResult: onResult, onUnavailable: { onError("The scanner isn't available on this phone yet. Type the code instead.") })
        }
        #else
        onChange(of: isPresented.wrappedValue) { _, on in
            if on { isPresented.wrappedValue = false; onError("The scanner needs the camera of an iPhone. Type the code instead.") }
        }
        #endif
    }
}
