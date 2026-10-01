import SwiftUI
import AVFoundation
#if os(iOS)
import AudioToolbox
#endif

/// The driver's ring (RideRing.kt): while a ride or delivery request is ringing on this phone and Bucks is on screen, the ride-request
/// tune loops with a repeating buzz. The ring/silent switch is respected (a silenced phone still buzzes), like Android's ringer volume.
/// It stops the moment the request is accepted, passed, taken by someone else or times out. With Bucks in the background the
/// notification rings instead (same tune, RingAlert), so the two never overlap.
@MainActor final class RideRinger {
    static let shared = RideRinger()
    private var on = false
    private var player: AVAudioPlayer?
    private var buzz: Task<Void, Never>?

    func set(_ ringing: Bool) {
        guard ringing != on else { return }
        on = ringing
        if ringing { start() } else { stop() }
    }

    private func start() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        // The app bundle's copy of Android's res/raw/ride_request.wav (absent in the macOS preview harness, which then only shows the card).
        if let url = Bundle.main.url(forResource: "ride_request", withExtension: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1; p.play(); player = p
        }
        #if os(iOS)
        // Android's pattern repeats about every 2.8 s.
        buzz = Task { @MainActor in
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 2_800_000_000)
            }
        }
        #endif
    }

    private func stop() {
        player?.stop(); player = nil
        buzz?.cancel(); buzz = nil
    }
}

extension View {
    /// Rings while `ringing` is true and the app is active.
    func rideRing(_ ringing: Bool) -> some View { modifier(RideRingModifier(ringing: ringing)) }
}

private struct RideRingModifier: ViewModifier {
    let ringing: Bool
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content
            .onChange(of: ringing && phase == .active, initial: true) { _, on in RideRinger.shared.set(on) }
            .onDisappear { RideRinger.shared.set(false) }
    }
}
