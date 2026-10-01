import SwiftUI
import Speech
import AVFoundation
import BucksCore

/// Languages offered in the voice picker (Voice.kt's VOICE_LANGS): BCP-47 tag and the name written in that language.
public let voiceLanguages: [(tag: String, label: String)] = [("en-IN", "English"), ("hi-IN", "हिन्दी"), ("kn-IN", "ಕನ್ನಡ"), ("ta-IN", "தமிழ்"), ("te-IN", "తెలుగు")]

/// The language the microphone listens in and confirmations are spoken in.
@MainActor @Observable
public final class VoiceSettings {
    public static let shared = VoiceSettings()
    private static let key = "bucks.voiceLang"
    public var lang: String {
        didSet { UserDefaults.standard.set(lang, forKey: Self.key) }
    }
    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        lang = voiceLanguages.contains { $0.tag == saved } ? saved ?? "en-IN" : "en-IN"
    }
}

/// The language chips (English, हिन्दी, ಕನ್ನಡ, தமிழ், తెలుగు) that pick `VoiceSettings.shared.lang`.
public struct VoiceLanguageChips: View {
    private var settings = VoiceSettings.shared
    public init() {}
    public var body: some View {
        ChipRow(voiceLanguages.map(\.label), selected: voiceLanguages.first { $0.tag == settings.lang }?.label) { label in
            if let l = voiceLanguages.first(where: { $0.label == label }) { settings.lang = l.tag }
        }
    }
}

/// Push-to-talk speech recognition on `SFSpeechRecognizer` (on-device where Apple ships a pack for the language).
/// Needs `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in Info.plist.
@MainActor @Observable
public final class VoiceRecognizer {
    public private(set) var listening = false
    public private(set) var partial = ""

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var onResult: ((String) -> Void)?
    @ObservationIgnored private var onError: ((String) -> Void)?
    public init() {}

    /// Starts listening; a second call while listening ends the capture and delivers what was heard.
    public func toggle(lang: String, onResult: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        if listening { request?.endAudio(); return }
        self.onResult = onResult; self.onError = onError
        let gen = generation + 1; generation = gen
        listening = true; partial = ""
        Task { await begin(lang: lang, generation: gen) }
    }

    public func cancel() { finish(deliver: nil, error: nil) }

    private func begin(lang: String, generation gen: Int) async {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)), rec.isAvailable else {
            return finish(deliver: nil, error: "Speech recognition isn't available on this device")
        }
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speechOK == .authorized else { return finish(deliver: nil, error: "Microphone permission needed for voice") }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return finish(deliver: nil, error: "Microphone permission needed for voice") }
        guard gen == generation, listening else { return }
        do { try startCapture(rec, generation: gen) } catch { finish(deliver: nil, error: "Couldn't hear you") }
    }

    private func startCapture(_ rec: SFSpeechRecognizer, generation gen: Int) throws {
        #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audio.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
        engine.prepare()
        try engine.start()
        self.engine = engine; request = req
        armSilence(seconds: 6)
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString, final = result?.isFinal ?? false
            Task { @MainActor in self?.heard(text: text, final: final, error: error, generation: gen) }
        }
    }

    private func heard(text: String?, final: Bool, error: Error?, generation gen: Int) {
        guard gen == generation, listening else { return }
        if let text, !text.isEmpty {
            partial = text
            if final { return finish(deliver: text, error: nil) }
            armSilence(seconds: 1.6)
        }
        if let error {
            // A cancelled task or a stop after speech still carries what was heard; only silence is an error.
            if let t = text, !t.isEmpty { return finish(deliver: t, error: nil) }
            finish(deliver: nil, error: Self.message(for: error))
        } else if final {
            finish(deliver: nil, error: "Didn't catch that, try again")
        }
    }

    /// Ends the capture after a pause in speech; the recogniser then reports its final result.
    private func armSilence(seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.endCapture()
        }
    }

    private func endCapture() {
        guard listening else { return }
        let heard = partial
        if heard.isEmpty { finish(deliver: nil, error: "Didn't catch that, try again") } else { finish(deliver: heard, error: nil) }
    }

    private func finish(deliver: String?, error: String?) {
        silence?.cancel(); silence = nil
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        let wasListening = listening
        listening = false
        let (ok, bad) = (onResult, onError)
        if let deliver, wasListening { ok?(deliver) } else if let error { bad?(error) }
    }

    static func message(for error: Error) -> String {
        let e = error as NSError
        if e.domain == NSURLErrorDomain { return "No network for speech" }
        if e.domain == "kAFAssistantErrorDomain", e.code == 1110 || e.code == 203 { return "Didn't catch that, try again" }
        return "Couldn't hear you"
    }
}

/// Reads confirmations aloud so a voice-first booking can be done hands-free (Voice.kt's Speaker).
@MainActor
public final class Speaker {
    public static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    public init() {}
    public func say(_ text: String, lang: String = "en-IN") {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-IN")
        synth.speak(u)
    }
    public func stop() { synth.stopSpeaking(at: .immediate) }
}

/// The mic in a search field: tap to speak, tap again to finish. Turns into a waveform while listening.
/// Pass your own `VoiceRecognizer` to show "Listening…" / the partial text in the field (`recognizer.listening`, `.partial`).
public struct VoiceInputButton: View {
    @Environment(AppSession.self) private var session
    @State private var own = VoiceRecognizer()
    private let external: VoiceRecognizer?
    private let onResult: (String) -> Void
    private var settings = VoiceSettings.shared
    public init(recognizer: VoiceRecognizer? = nil, onResult: @escaping (String) -> Void) { external = recognizer; self.onResult = onResult }
    private var recognizer: VoiceRecognizer { external ?? own }
    public var body: some View {
        let listening = recognizer.listening
        Button {
            Haptics.tap()
            recognizer.toggle(lang: settings.lang, onResult: onResult, onError: { session.toast($0) })
        } label: {
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 20))
                .foregroundStyle(listening ? BucksColor.primary : BucksColor.onSurfaceVariant)
                .frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speak")
        .onDisappear { recognizer.cancel() }
    }
}
