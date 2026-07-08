import Foundation
import AVFoundation

/// Drives an overdub session: plays a backing take while recording the mic,
/// the two started together so they share a t=0 for a clean mixdown. The mic
/// goes to a temp file; the backing file is read-only. Pair with `AudioMixer`
/// to fold the two together.
@MainActor
final class OverdubService: NSObject, ObservableObject {
    enum OverdubError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Couldn't start the overdub." }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    /// Whether the backing is monitored through headphones rather than the
    /// built-in speaker. Drives the mixdown balance: on the speaker the backing
    /// bleeds back into the mic, so the digital backing is ducked to compensate.
    /// Updated when the session starts and as the route changes mid-take.
    @Published private(set) var usingHeadphones = false

    /// The take being recorded over; retained until the mix is built.
    private(set) var backingURL: URL?
    /// The mic capture for the in-progress / just-finished take.
    private(set) var voiceURL: URL?

    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    // MARK: - Session

    /// Plays `backing` and records the mic, scheduling both to the same device
    /// clock time so the captured part lines up with the backing for mixing.
    func start(backing: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        usingHeadphones = Self.headphonesConnected()

        let player = try AVAudioPlayer(contentsOf: backing)
        player.delegate = self
        player.prepareToPlay()

        let voice = FileManager.default.temporaryDirectory
            .appendingPathComponent("overdub-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: voice, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()

        // A shared near-future start time keeps capture and playback aligned.
        let startTime = player.deviceCurrentTime + 0.15
        guard recorder.record(atTime: startTime),
              player.play(atTime: startTime) else {
            recorder.stop()
            player.stop()
            try? FileManager.default.removeItem(at: voice)
            throw OverdubError.couldNotStart
        }

        self.player = player
        self.recorder = recorder
        backingURL = backing
        voiceURL = voice
        isRecording = true
        elapsed = 0
        startTimer()
    }

    /// Stops capture and playback, keeping `backingURL`/`voiceURL` for the mix.
    /// The session is released so other apps' audio can resume.
    func stop() {
        recorder?.stop()
        player?.stop()
        stopTimer()
        isRecording = false
        recorder = nil
        player = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Aborts the session and discards the mic capture.
    func cancel() {
        stop()
        if let voice = voiceURL { try? FileManager.default.removeItem(at: voice) }
        reset()
    }

    /// Clears the retained take URLs once the caller is done with them.
    func reset() {
        backingURL = nil
        voiceURL = nil
    }

    // MARK: - Route

    /// Whether the current output route isolates the backing from the mic. While
    /// recording, AirPods and other Bluetooth headsets fall back to the HFP
    /// port (A2DP is output-only), so that case has to count too.
    static func headphonesConnected() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { isHeadphone($0.portType) }
    }

    private static func isHeadphone(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio:
            return true
        default:
            return false
        }
    }

    /// Route notifications can arrive off the main thread; hop before touching
    /// state.
    @objc nonisolated private func handleRouteChange() {
        Task { @MainActor in
            guard self.isRecording else { return }
            self.usingHeadphones = Self.headphonesConnected()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        // Scheduled from the main actor, so the timer fires on the main run loop.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension OverdubService: AVAudioRecorderDelegate, AVAudioPlayerDelegate {}
