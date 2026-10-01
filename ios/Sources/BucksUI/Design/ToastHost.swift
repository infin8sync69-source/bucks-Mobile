import SwiftUI

/// App-wide snackbar: `center.show("Saved")`; the message clears itself after 3 s.
@MainActor public final class ToastCenter: ObservableObject {
    @Published public var message: String?
    private var task: Task<Void, Never>?
    public init() {}
    public func show(_ text: String) {
        message = text
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }
    public func dismiss() { task?.cancel(); message = nil }
}

public extension View {
    /// Overlays the toast centre's message as a snackbar at the bottom.
    func bucksToasts(_ center: ToastCenter) -> some View { modifier(ToastHost(center: center)) }
}

private struct ToastHost: ViewModifier {
    @ObservedObject var center: ToastCenter
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = center.message {
                Text(m).font(.bucks(.bodyMedium)).foregroundStyle(BucksColor.onSecondary)
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 520, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: BucksRadius.small, style: .continuous).fill(BucksColor.secondary))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 2).padding(.horizontal, 16).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity)).onTapGesture { center.dismiss() }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.message)
    }
}
