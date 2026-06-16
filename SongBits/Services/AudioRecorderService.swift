import Foundation
import AVFoundation

/// Records M4A/AAC audio. Recording is written to a temp file and only moved
/// into its folder once finalized (crash-safety). The audio session is
/// configured to survive interruptions, screen lock, and backgrounding.
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Couldn't start recording." }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

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

    // MARK: - Permission

    var permissionGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
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

    /// Stops and returns the temp file for the caller to move into place.
    func stop() -> URL? {
        recorder?.stop()
        stopTimer()
        isRecording = false
        let url = tempURL
        recorder = nil
        return url
    }

    func cancel() {
        recorder?.stop()
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        stopTimer()
        isRecording = false
        recorder = nil
        tempURL = nil
    }

    // MARK: - Interruptions

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            // The system pauses the recorder; nothing to do until it ends.
            break
        case .ended:
            guard let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                recorder?.record()
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

extension AudioRecorderService: AVAudioRecorderDelegate {}
