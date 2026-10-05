import SwiftUI
import BucksCore

/// Sign-in by mobile number: a one-time code is texted to it.
struct LoginScreen: View {
    var onSent: () -> Void
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Headline("Sign in")
                        Muted("We'll text a one-time code to your mobile number.").padding(.top, 8).padding(.bottom, 20)
                        FieldLabel("Mobile number")
                        HStack(spacing: 10) {
                            Text("+91").bucks(.bodyLarge).foregroundStyle(BucksColor.onSurface)
                                .frame(width: 80, height: 56)
                                .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(BucksColor.outline, lineWidth: 1))
                            BucksField($phone, placeholder: "98765 43210", keyboard: .phone).padding(.bottom, -14)
                        }
                        PrimaryButton("Send code") { send() }.padding(.top, 20)
                        Muted("By continuing you agree to the community rules: review honestly, one account per person.", align: .center)
                            .padding(.top, 8)
                    }.padding(20)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .onChange(of: phone) { _, v in
            let f = String(v.filter(\.isNumber).prefix(10)); if f != v { phone = f }
        }
    }

    private func send() {
        if phone.count < 10 { session.toast("Enter a 10-digit number") } else { session.tempPhone = phone; onSent() }
    }
}
