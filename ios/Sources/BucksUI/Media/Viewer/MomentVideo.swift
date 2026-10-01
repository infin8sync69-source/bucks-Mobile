import SwiftUI
import AVFoundation
import BucksCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Drives one AVPlayer for a clip: progress 0...1, buffering, end of clip or loop, pause and mute (the ExoPlayer wrapper of MomentVideo in CloudSocialScreens.kt).
@MainActor
final class ClipPlayer {
    let player: AVPlayer
    var onProgress: (Float) -> Void = { _ in }
    var onEnded: () -> Void = {}
    var onBuffering: (Bool) -> Void = { _ in }
    private let loop: Bool
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var wantsPlay = false

    init(url: URL, loop: Bool, muted: Bool) {
        #if os(iOS)
        // A clip should be heard even with the silent switch on, like a video in any other app.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        self.loop = loop
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player.isMuted = muted
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
                self.onProgress(Float(min(max(t.seconds / d, 0), 1)))
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loop { self.player.seek(to: .zero); if self.wantsPlay { self.player.play() } } else { self.onEnded() }
            }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let waiting = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in self?.onBuffering(waiting || (self?.wantsPlay == true && p.currentItem?.status != .readyToPlay)) }
        }
    }

    func setPaused(_ paused: Bool) {
        wantsPlay = !paused
        if paused { player.pause() } else { player.play() }
    }

    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver?.invalidate(); statusObserver = nil
        player.replaceCurrentItem(with: nil)
    }
}

#if canImport(UIKit)
private final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView(); v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect; v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: PlayerLayerUIView, context: Context) { if v.playerLayer.player !== player { v.playerLayer.player = player } }
}
#elseif canImport(AppKit)
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView(); v.wantsLayer = true
        let l = AVPlayerLayer(player: player); l.videoGravity = .resizeAspect; l.backgroundColor = NSColor.black.cgColor
        v.layer = l
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v.layer as? AVPlayerLayer)?.player = player }
}
#endif

/// Plays one video (a signed URL or a file picked on the phone), fitted into its box on black. `onProgress` gets 0...1 from the player's own position;
/// `onEnded` fires once at the end (unless `loop`). The clip stops while the app is in the background.
struct MomentVideo: View {
    let url: URL
    var paused: Bool
    var loop = false
    var muted = false
    var onProgress: (Float) -> Void = { _ in }
    var onEnded: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var clip: ClipPlayer?
    @State private var buffering = true

    private var shouldPlay: Bool { !paused && scenePhase == .active }

    var body: some View {
        ZStack {
            Color.black
            if let clip { PlayerLayerView(player: clip.player) }
            if buffering { BucksLoader(color: .white).accessibilityLabel("Buffering") }
        }
        .task(id: url) {
            let c = ClipPlayer(url: url, loop: loop, muted: muted)
            c.onProgress = { onProgress($0) }
            c.onEnded = { onEnded() }
            c.onBuffering = { buffering = $0 }
            clip = c
            c.setPaused(!shouldPlay)
            // Held until this view goes away (the task is cancelled), then the player is released.
            await withTaskCancellationHandler { try? await Task.sleep(nanoseconds: .max / 2) } onCancel: { Task { @MainActor in c.stop() } }
        }
        .onChange(of: shouldPlay) { _, play in clip?.setPaused(!play) }
    }
}
