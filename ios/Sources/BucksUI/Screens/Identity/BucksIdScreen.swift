import SwiftUI
import BucksCore

/// My Bucks ID as a card: name, the 8-character ID, the account's UUID, a year of validity, a QR code and a barcode.
/// Anyone who scans either (or types the ID) can send a sync request; the phone number stays private.
struct BucksIdScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    private let gradient = LinearGradient(colors: [Color(red: 0x8B / 255, green: 0x2C / 255, blue: 0xF5 / 255), Color(red: 0x5B / 255, green: 0x12 / 255, blue: 0xC8 / 255), Color(red: 0x3A / 255, green: 0x0A / 255, blue: 0x8C / 255)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(title: "Bucks Pro", onBack: { router.pop() })
                if let me = session.me { content(me) }
                else { Muted("Your Bucks ID appears once you're signed in and your profile is saved. Check your connection and open this again.").padding(Gutter) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
    }

    private func content(_ me: ProfileRow) -> some View {
        let info = BucksIdCardInfo.of(me.idIssuedAt)
        let name = me.name.isEmpty ? (session.user?.name ?? "") : me.name
        let area = me.area.isEmpty ? (session.user?.area ?? "") : me.area
        return ScrollView {
            VStack(spacing: 0) {
                card(me, info: info, name: name, area: area)
                barcodeStrip(me.shortCode)
                statusRow(info)
                if info?.expired == true {
                    Notice("An expired ID can't be used by others to sync with you. Renew it: it takes a second and keeps the same ID.").padding(.top, 10)
                }
                SectionTitle("Scan to sync").padding(.top, 20).padding(.bottom, 8)
                QRBox(text: BucksQr.forBucksId(me.shortCode), side: 220, label: "Bucks ID QR code", padding: 10, bordered: false)
                Muted("Anyone who scans this, or types your ID, can send you a sync request. Your phone number stays private.", align: .center).padding(.top, 10)
                HStack(spacing: 8) {
                    SmallButton("Copy ID", tonal: true) { copyToClipboard(me.shortCode); session.toast("Bucks ID copied.") }.frame(maxWidth: .infinity)
                    ShareLink(item: session.shareTextForBucksId(me.shortCode)) {
                        Text("Share").font(.bucks(.labelMedium)).foregroundStyle(BucksColor.onSecondaryContainer).padding(.horizontal, 14).frame(minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.secondaryContainer))
                    }.buttonStyle(.plain).frame(maxWidth: .infinity)
                }.padding(.top, 16)
                PrimaryButton("Scan or enter someone's ID") { router.push(.sync) }.padding(.top, 10)
            }.padding(.horizontal, Gutter).padding(.bottom, 24)
        }
    }

    // MARK: the card

    private func card(_ me: ProfileRow, info: BucksIdCardInfo?, name: String, area: String) -> some View {
        let expired = info?.expired == true
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                BucksWordmark(color: .white, height: 24)
                Text(" pro").bucks(.titleLarge).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 14))
                    Text(expired ? "Expired" : "Verified").bucks(.labelMedium)
                }.foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.18)))
            }
            HStack(spacing: 14) {
                Text(initials(name).isEmpty ? "?" : initials(name)).bucks(.titleMedium).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Circle().fill(.white.opacity(0.2))).overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(name).bucks(.titleLarge).foregroundStyle(.white).lineLimit(1)
                        if !expired { Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(Color(red: 0x7C / 255, green: 0xF0 / 255, blue: 0xC0 / 255)).accessibilityLabel("Verified") }
                    }
                    let town = area.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    Text(town.isEmpty ? "Bengaluru" : town).bucks(.bodyMedium).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.top, 20)
            Text("BUCKS ID").bucks(.labelSmall).tracking(1.5).foregroundStyle(.white.opacity(0.7)).padding(.top, 20)
            Text(BucksIdCode.pretty(me.shortCode)).font(.system(size: 28, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(.white)
            Text(me.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).truncationMode(.tail)
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1).padding(.vertical, 14)
            HStack(alignment: .top) {
                dateColumn("VALID FROM", info?.validFrom)
                dateColumn("VALID TILL", info?.validTill)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func dateColumn(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).bucks(.labelSmall).tracking(1).foregroundStyle(.white.opacity(0.7))
            Text(value ?? "–").bucks(.titleSmall).foregroundStyle(.white)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: barcode and status

    private func barcodeStrip(_ code: String) -> some View {
        Group {
            if let bar = bucksBarcodeImage(BucksQr.forBucksId(code)) {
                bar.resizable().frame(height: 64).accessibilityLabel("Bucks ID barcode")
            } else { Color.clear.frame(height: 64) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(Color.white))
        .padding(.top, 12)
    }

    private func statusRow(_ info: BucksIdCardInfo?) -> some View {
        let bg: Color, fg: Color, text: String
        if let info {
            if info.expired { bg = BucksColor.badTint; fg = BucksColor.bad; text = "Expired on \(info.validTill)" }
            else if info.renewable { bg = BucksColor.warnTint; fg = BucksColor.warn; text = "Expires in \(info.daysLeft) day\(info.daysLeft == 1 ? "" : "s")" }
            else { bg = BucksColor.goodTint; fg = BucksColor.good; text = "Active · \(info.daysLeft) days left" }
        } else { bg = BucksColor.surfaceContainer; fg = BucksColor.onSurfaceVariant; text = "Checking validity…" }
        return HStack(spacing: 10) {
            Image(systemName: info?.expired == true ? "xmark.circle.fill" : "checkmark.seal.fill").foregroundStyle(fg)
            Text(text).bucks(.titleSmall).foregroundStyle(fg).frame(maxWidth: .infinity, alignment: .leading)
            if let info, info.renewable { SmallButton("Renew") { Task { await session.renewBucksId() } } }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(bg))
        .padding(.top, 12)
    }
}
