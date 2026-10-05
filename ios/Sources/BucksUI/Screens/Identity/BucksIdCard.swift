import SwiftUI
import BucksCore

/// The person's Bucks ID as text and QR, with copy, share and "sync with someone" (Settings > Identity).
struct BucksIdCard: View {
    @Environment(AppSession.self) private var session
    let onSync: () -> Void

    var body: some View {
        if let me = session.me {
            BucksCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "qrcode").font(.system(size: 22)).foregroundStyle(BucksColor.primary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Your Bucks ID").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                            Muted("Share it so people can sync with you. Your number stays private.")
                        }
                    }
                    VStack(spacing: 14) {
                        QRBox(text: BucksQr.forBucksId(me.shortCode), side: 200, label: "Bucks ID QR code", padding: 8, bordered: false)
                        Text(BucksIdCode.pretty(me.shortCode)).font(.system(size: 28, weight: .heavy)).tracking(2).foregroundStyle(BucksColor.onSurface)
                    }.frame(maxWidth: .infinity).padding(.top, 16)
                    HStack(spacing: 8) {
                        SmallButton("Copy", tonal: true) { copyToClipboard(me.shortCode); session.toast("Bucks ID copied.") }.frame(maxWidth: .infinity)
                        ShareLink(item: session.shareTextForBucksId(me.shortCode)) {
                            Text("Share").font(.bucks(.labelMedium)).foregroundStyle(BucksColor.onSecondaryContainer).padding(.horizontal, 14).frame(minHeight: 38)
                                .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.secondaryContainer))
                        }.buttonStyle(.plain).frame(maxWidth: .infinity)
                        SmallButton("Sync with someone", action: onSync)
                    }.padding(.top, 14)
                }
            }
        }
    }
}
