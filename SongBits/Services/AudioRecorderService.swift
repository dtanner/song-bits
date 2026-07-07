import Foundation
import AVFoundation

/// Records M4A/AAC audio. Recording is written to a temp file and handed to
/// the caller on stop to be moved into its folder. The audio session is
/// configured to survive interruptions, screen lock, and backgrounding.
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Couldn't start recording." }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    /// Called when an interruption (call, Siri, …) ends without permission to
    /// resume. The owner should stop and save the partial take; leaving it
    /// running would show a live recording UI that captures nothing.
    var onNonResumableInterruption: (() -> Void)?

    /// Called when the system reports the capture failed, so the owner can
    /// surface it — otherwise a bad take looks like a good one until playback.
    var onRecordingError: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var displayTimer: Timer?
    private(set) var tempURL: URL?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Session

    /// `.playAndRecord` + the `audio` background mode keep capture alive through
    /// lock and backgrounding; interruptions are handled below.
    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
    }

    // MARK: - Recording

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        self.tempURL = url
        isRecording = true
        elapsed = 0
        startTimer()
    }

    /// Stops and returns the temp file for the caller to move into place. The
    /// session is released so other apps' audio can resume.
    func stop() -> URL? {
        recorder?.stop()
        stopTimer()
        isRecording = false
        let url = tempURL
        recorder = nil
        tempURL = nil
        deactivateSession()
        return url
    }

    func cancel() {
        recorder?.stop()
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        stopTimer()
        isRecording = false
        recorder = nil
        tempURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Interruptions

    /// Interruption notifications can arrive off the main thread; parse there,
    /// then hop to the main actor to touch state.
    @objc nonisolated private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let options = AVAudioSession.InterruptionOptions(
            rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        )
        Task { @MainActor in self.interruption(type, options: options) }
    }

    private func interruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            // The system pauses the recorder; nothing to do until it ends.
            break
        case .ended:
            guard isRecording else { return }
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                recorder?.record()
            } else {
                onNonResumableInterruption?()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Timer

    private func startTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            self.elapsed = recorder.currentTime
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorder(_ recorder: AVAudioRecorder, encodeErrorDidOccur error: Error?) {
        let detail = error?.localizedDescription ?? "The recording hit an encoding error."
        Task { @MainActor in self.onRecordingError?(detail) }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor in
            self.onRecordingError?("The system ended the recording early; the bit may be incomplete.")
        }
    }
}
