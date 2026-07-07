import AVFoundation

/// Microphone permission, shared by the recording and overdub flows.
enum MicPermission {
    static var granted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
