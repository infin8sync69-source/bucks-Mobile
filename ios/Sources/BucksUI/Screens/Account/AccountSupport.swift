import SwiftUI
import BucksCore
import AVKit

/// "now" / "5m" / "3h" / "Yesterday" / "12 Mar" from a server timestamp (CloudSocialScreens.kt ago).
func accountAgo(_ iso: String) -> String {
    let withZone = iso.replacingOccurrences(of: " ", with: "T")
    let text = withZone.hasSuffix("Z") || withZone.contains("+") ? withZone : withZone + "Z"
    let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
    guard let t = frac.date(from: text) ?? plain.date(from: text) else { return "" }
    let s = max(0, Int(Date().timeIntervalSince(t)))
    switch s {
    case ..<60: return "now"
    case ..<3600: return "\(s / 60)m"
    case ..<86400: return "\(s / 3600)h"
    case ..<172800: return "Yesterday"
    default: let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"; return f.string(from: t)
    }
}

/// Buyer-facing order status in plain words (OrderUi.kt orderStatusLabel).
func accountOrderStatus(_ status: String, mode: String = "MARKETPLACE") -> String {
    switch status {
    case "PLACED": "Waiting for the shop"
    case "ACCEPTED": "Accepted"
    case "READY": mode == "PICKUP" ? "Ready to collect" : "Packed"
    case "PICKED_UP": "On the way"
    case "DELIVERED": mode == "PICKUP" ? "Collected" : "Delivered"
    case "REJECTED": "Not accepted"
    case "CANCELLED": "Cancelled"
    default: status.isEmpty ? status : status.lowercased().prefix(1).uppercased() + status.lowercased().dropFirst()
    }
}

/// A ride's status as the Account activity list words it ("Completed", "In ride" …).
func accountRideStatus(_ status: String) -> String {
    switch status {
    case "SEARCHING": "Searching"; case "MATCHED": "Matched"; case "ARRIVED": "Arrived"; case "IN_PROGRESS": "In ride"
    case "COMPLETED": "Completed"; case "PAID": "Paid"; case "NO_DRIVER": "No driver"; default: "Cancelled"
    }
}

// MARK: rows used by the settings pages

/// A settings line: icon, title, optional detail, chevron, then a divider.
struct AccountSettingRow: View {
    let icon: String, label: String
    var detail: String?
    var chevron = true
    let action: () -> Void
    init(icon: String, label: String, detail: String? = nil, chevron: Bool = true, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.detail = detail; self.chevron = chevron; self.action = action
    }
    var body: some View {
        VStack(spacing: 0) {
            ListRow(label, subtitle: detail, onTap: action, leading: {
                Image(systemName: icon).foregroundStyle(BucksColor.onSurfaceVariant).frame(width: 24)
            }, trailing: {
                if chevron { Image(systemName: "chevron.right").foregroundStyle(BucksColor.onSurfaceVariant) }
            }).padding(.horizontal, -Gutter)
            BucksDivider()
        }
    }
}

/// A switch row with a title and optional detail, then a divider.
struct AccountToggleRow: View {
    let label: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        VStack(spacing: 0) {
            Button { isOn.toggle() } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        if let detail { Muted(detail) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ListingSwitch($isOn)
                }.padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
            BucksDivider()
        }
    }
}

/// A titled group of radio choices, then a divider.
struct AccountChoiceGroup<T: Hashable>: View {
    let title: String
    var detail: String?
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                if let detail { Muted(detail) }
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    Button { onSelect(o.0) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: o.0 == selected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20)).foregroundStyle(o.0 == selected ? BucksColor.primary : BucksColor.onSurfaceVariant)
                            Text(o.1).bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(o.0 == selected ? .isSelected : [])
                }
            }.padding(.vertical, 8)
            BucksDivider()
        }
    }
}

// MARK: profile pieces

/// Cover band with the avatar overlapping its bottom edge. No cover photos exist yet, so a primary gradient stands in.
struct AccountProfileCover: View {
    let initials: String
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [BucksColor.primary, BucksColor.onPrimaryContainer], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 140).frame(maxHeight: .infinity, alignment: .top)
            Text(initials.isEmpty ? "?" : initials).bucks(.headlineMedium).foregroundStyle(BucksColor.onPrimaryContainer)
                .frame(width: 88, height: 88).background(Circle().fill(BucksColor.primaryContainer))
                .padding(4).background(Circle().fill(BucksColor.surface))
                .padding(.leading, Gutter)
        }.frame(height: 170)
    }
}

/// A soft rounded button with an icon (ProfileScreens.kt SoftButton).
struct AccountSoftButton: View {
    let text: String, systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: systemImage).font(.system(size: 16)); Text(text).bucks(.labelLarge) }
                .foregroundStyle(BucksColor.onSurface).padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.surfaceContainer))
        }.buttonStyle(.plain)
    }
}

/// A small icon in a round tinted badge followed by a title and subtitle: the activity lists' compact row.
struct AccountCompactRow: View {
    let systemImage: String, title: String, subtitle: String
    var onTap: (() -> Void)?
    var body: some View {
        VStack(spacing: 0) {
            Button { onTap?() } label: {
                HStack(spacing: 12) {
                    Avatar(systemImage: systemImage, size: 36, tinted: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted(subtitle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(onTap == nil)
            BucksDivider()
        }
    }
}

// MARK: viewing a stored file

/// Full-screen view of a private photo or video (the AttachmentViewer of Android, without its save/share extras beyond Share).
struct AccountAttachmentViewer: View {
    let bucket: String, path: String, mime: String
    let onClose: () -> Void
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let url {
                    if mime.hasPrefix("video/") { VideoPlayer(player: AVPlayer(url: url)) }
                    else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            case .failure: Text("Couldn't load this photo.").foregroundStyle(.white)
                            default: ProgressView().tint(.white)
                            }
                        }
                    }
                } else if failed { Text("Couldn't load this file. Check your connection.").bucks(.bodyMedium).foregroundStyle(.white).padding(Gutter) }
                else { ProgressView().tint(.white) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(.white).frame(width: 44, height: 44) }.accessibilityLabel("Share") }
                Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(.white).frame(width: 44, height: 44) }.accessibilityLabel("Close")
            }.padding(8)
        }
        .task(id: path) {
            do { url = try await Backend.shared.signedURL(bucket: bucket, path: path) } catch { failed = true }
        }
    }
}
