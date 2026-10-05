import SwiftUI
import BucksCore

/// Welcome screen for people who are not signed in. The wordmark's letters spring up one after another in the middle of the
/// purple field, glide up into place, then the promise and the button rise in. With reduced motion everything is simply there.
struct SplashScreen: View {
    var onStart: () -> Void
    @State private var letters = [Bool](repeating: false, count: 5)
    @State private var settle: CGFloat = 0
    @State private var copy: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BucksColor.purple.ignoresSafeArea()
                wordmark
                    .offset(y: -geo.size.height * 0.16 * settle)
                    .scaleEffect(1 - 0.12 * settle)
                VStack(spacing: 0) {
                    Text("Rides, food, skilled people and local shops, ranked only by the people who used them.")
                        .bucks(.bodyLarge).foregroundStyle(Color.white.opacity(0.88)).multilineTextAlignment(.center)
                        .padding(.bottom, 32)
                    SplashButton(title: "Get started", enabled: copy > 0.3, action: onStart)
                }
                .padding(.horizontal, 32).padding(.vertical, 32)
                .opacity(copy).offset(y: (1 - copy) * 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .bucksHideNavigationBar()
        .task { await play() }
    }

    /// Five letters stacked exactly as BucksWordmark draws them, each rising on its own beat.
    private var wordmark: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                WordmarkLetter(index: i).fill(Color.white, style: FillStyle(eoFill: true))
                    .opacity(letters[i] ? 1 : 0).offset(y: letters[i] ? 0 : 28).scaleEffect(letters[i] ? 1 : 0.8)
            }
        }
        .frame(width: 72 * WordmarkData.width / WordmarkData.height, height: 72)
        .accessibilityElement().accessibilityLabel("Bucks").accessibilityAddTraits(.isImage)
    }

    private func play() async {
        if bucksReduceMotion { letters = letters.map { _ in true }; settle = 1; copy = 1; return }
        for i in 0..<5 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { letters[i] = true }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(Motion.emphasized(0.62)) { settle = 1 }
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(Motion.emphasized(0.46)) { copy = 1 }
    }
}
