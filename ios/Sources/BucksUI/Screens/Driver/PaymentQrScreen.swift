import SwiftUI
import PhotosUI
import BucksCore

/// My payment QR, for drivers: upload the QR image from a UPI app (or scan a printed one), Bucks reads the `upi://pay?...` link inside
/// it and keeps only that. Riders paying a fare then open it with the amount filled in.
struct PaymentQrScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router
    @State private var pending: String?
    @State private var reading = false
    @State private var confirmRemove = false
    @State private var showPicker = false
    @State private var photo: PhotosPickerItem?
    @State private var showScanner = false

    private var d: Dispatch { session.dispatch }
    private var link: String? { d.paymentLink }
    private var payee: (name: String, address: String)? { link.flatMap { upiPayee($0) } }

    var body: some View {
        VStack(spacing: 0) {
            BucksTopBar(title: "Payment QR", onBack: { router.pop() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    status
                    if pending == nil && d.paymentLinkLoaded { actions }
                    Spacer().frame(height: 24)
                }.padding(Gutter)
            }
        }
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .bucksBackground()
        .bucksHideNavigationBar()
        .task { if !d.paymentLinkLoaded { d.refreshPaymentLink() } }
        .photosPicker(isPresented: $showPicker, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in if let item { read(item) } }
        .bucksConfirm(isPresented: $confirmRemove, title: "Remove your payment QR?", message: "Customers won't be able to pay you by UPI, for trips or shop orders, until you add a QR again.", confirmTitle: "Remove", cancelTitle: "Keep it", destructive: true) { d.removePaymentLink() }
        #if os(iOS)
        .bucksFullScreenCover(isPresented: $showScanner) {
            QRScannerSheet(onResult: { accept($0) }, onUnavailable: { session.toast("The scanner isn't available on this phone yet. Type the code instead.") })
        }
        #endif
    }

    @ViewBuilder private var status: some View {
        if !d.paymentLinkLoaded {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Muted("Checking your payment QR") }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if let pending {
            PendingCard(link: pending, saving: d.busy, onSave: { d.savePaymentLink(pending) { self.pending = nil } }, onDiscard: { self.pending = nil })
        } else if let link {
            BucksCard(tint: true) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(BucksColor.onPrimaryContainer)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UPI payments are on").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Payments go to \(payee?.name ?? "you")\(payee.map { " (\($0.address))" } ?? "")")
                    }
                }
                QRBox(text: link, side: 200, label: "Your UPI QR", padding: 8, bordered: false)
                    .frame(maxWidth: .infinity).padding(.top, 16)
                Muted("When a customer taps Pay by UPI, after a trip or on an order from your shop, their app opens with this account and the amount already filled in. You can also show this QR for them to scan.", align: .center)
                    .padding(.top, 14)
            }
        } else {
            BucksCard {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode").font(.system(size: 24)).foregroundStyle(BucksColor.primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("No payment QR yet").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
                        Muted("Customers can't pay you by UPI until you add one.")
                    }
                }
                Muted("Add the QR from your UPI app and customers can pay you by UPI: riders straight after a trip or delivery, shoppers for their orders from your shop. Bucks keeps only the payment link, not the picture.").padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        SectionTitle(link != nil ? "Replace it" : "Add your QR").padding(.top, 24).padding(.bottom, 8)
        VStack(spacing: 10) {
            PrimaryButton(reading ? "Reading the picture…" : "Upload my UPI QR", enabled: !reading && !d.busy) { showPicker = true }
            #if os(iOS)
            GhostButton("Scan a printed QR", enabled: !reading && !d.busy) { showScanner = true }
            #endif
            if link != nil { BadButton("Remove payment QR") { confirmRemove = true } }
        }
        SectionTitle("How to get your QR image").padding(.top, 24).padding(.bottom, 6)
        let steps = ["Open your UPI app: Google Pay, PhonePe, Paytm or BHIM.", "Go to your profile and tap your QR code.", "Save or share the QR as an image to this phone.", "Come back here and tap Upload my UPI QR."]
        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
            HStack(alignment: .top, spacing: 10) {
                Avatar(initials: "\(i + 1)", size: 24)
                Text(step).bucks(.bodyMedium).foregroundStyle(BucksColor.onSurface).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 4)
        }
        Muted("Only UPI payment codes (upi://pay) are accepted. Money goes straight from the customer's app to your bank; Bucks never holds it.").padding(.top, 12)
    }

    private func accept(_ raw: String) {
        let l = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.lowercased().hasPrefix("upi://pay") else { session.toast("That QR isn't a UPI payment code. Use the QR from your UPI app (GPay, PhonePe, Paytm, BHIM)."); return }
        guard upiPayee(l) != nil else { session.toast("That UPI code has no payee address (pa=). Try the QR from your UPI app."); return }
        pending = l
    }

    private func read(_ item: PhotosPickerItem) {
        reading = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            var raw: String?
            if let data { raw = await driverDecodeQR(data) }
            reading = false; photo = nil
            if let raw { accept(raw) } else { session.toast("Couldn't find a QR code in that picture. Try a clearer photo, or a screenshot of the QR from your UPI app.") }
        }
    }
}

private struct PendingCard: View {
    let link: String
    let saving: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    var body: some View {
        let payee = upiPayee(link)
        BucksCard(tint: true) {
            Text("QR read").bucks(.titleMedium).foregroundStyle(BucksColor.onSurface)
            Text("Payments go to \(payee?.name ?? "?") (\(payee?.address ?? "?"))").bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface).padding(.top, 6)
            Muted("Check the name and UPI ID are yours before saving.").padding(.top, 4)
            QRBox(text: link, side: 160, label: "UPI QR", padding: 8, bordered: false).frame(maxWidth: .infinity).padding(.top, 14)
            HStack(spacing: 8) {
                SmallButton(saving ? "Saving…" : "Save", enabled: !saving, action: onSave).frame(maxWidth: .infinity)
                SmallButton("Choose another", tonal: true, enabled: !saving, action: onDiscard).frame(maxWidth: .infinity)
            }.padding(.top, 14)
        }
    }
}
