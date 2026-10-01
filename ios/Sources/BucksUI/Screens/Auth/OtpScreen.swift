import SwiftUI
import BucksCore

/// Six-digit code entry. The SMS is sent once when the screen appears; on success `session.phase` changes and RootView swaps screens.
struct OtpScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var wrong = 0
    @State private var sent = false
    @FocusState private var focused: Bool
    private let length = 6

    var body: some View {
        ContentColumn {
            VStack(spacing: 0) {
                BucksTopBar(onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Headline("Enter the code")
                        Muted("We sent a \(length)-digit code to +91 \(session.tempPhone).").padding(.top, 8).padding(.bottom, 28)
                        codeField.shake(on: wrong)
                        PrimaryButton(busy ? "Checking…" : "Verify", enabled: !busy && code.count == length) { verify() }.padding(.top, 20)
                        Button("Resend code") { Task { await session.sendOtp(resend: true) } }
                            .buttonStyle(.plain).font(.bucks(.labelLarge)).foregroundStyle(BucksColor.primary)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 8)
                        if !session.otpStatus.isEmpty {
                            Muted(session.otpStatus, align: .center).padding(.top, 12)
                        }
                        // Test builds only (Android: SELF_UPDATE builds): which Firebase project this build talks to.
                        #if DEBUG
                        if let project = session.firebaseProject {
                            Muted("Build · \(project)", align: .center).padding(.top, 6)
                        }
                        #endif
                    }.padding(20)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bucksBackground().bucksHideNavigationBar()
        .task { if !sent { sent = true; await session.sendOtp() } }
        .onChange(of: code) { _, v in
            let f = String(v.filter(\.isNumber).prefix(length)); if f != v { code = f }
        }
    }

    private var codeField: some View {
        TextField("", text: $code)
            .bucksKeyboard(.number).bucksOneTimeCode().focused($focused)
            .font(.bucks(.headlineMedium)).kerning(8).multilineTextAlignment(.center).foregroundStyle(BucksColor.onSurface)
            .padding(.horizontal, 14).frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).fill(BucksColor.surface))
            .overlay(RoundedRectangle(cornerRadius: BucksRadius.medium, style: .continuous).strokeBorder(focused ? BucksColor.primary : BucksColor.outline, lineWidth: focused ? 2 : 1))
            .accessibilityLabel("Verification code")
    }

    private func verify() {
        busy = true
        Task {
            let ok = await session.verifyOtp(code)
            busy = false
            if !ok { wrong += 1 }
        }
    }
}
