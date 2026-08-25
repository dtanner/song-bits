import Testing
import AVFoundation
@testable import SongBits

@MainActor
struct PlaybackServiceTests {
    @Test func playPauseSkipsTheQuietLeadIn() async throws {
        let url = try makeRecording(silenceSeconds: 2, toneSeconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackService()

        await playback.playPause(url, skipSilence: true)
        #expect(playback.isPlaying)
        #expect(abs(playback.currentTime - 1.95) < 0.3)
        playback.stop()
    }

    @Test func prefetchedOffsetIsUsedByALaterPress() async throws {
        let url = try makeRecording(silenceSeconds: 2, toneSeconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackService()

        // The press must land the same offset whether the row's prefetch scan
        // has finished or is still in flight.
        playback.prefetchOffset(url)
        await playback.playPause(url, skipSilence: true)
        #expect(playback.isPlaying)
        #expect(abs(playback.currentTime - 1.95) < 0.3)
        playback.stop()
    }

    @Test func skipSilenceOffStartsAtZero() async throws {
        let url = try makeRecording(silenceSeconds: 2, toneSeconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackService()

        await playback.playPause(url, skipSilence: false)
        #expect(playback.isPlaying)
        #expect(playback.currentTime < 0.3)
        playback.stop()
    }

    // MARK: - Helpers

    /// Writes a mono AAC `.m4a` of near-silence followed by a tone. The lead-in
    /// uses a tiny dither (well below the −40 dBFS threshold) rather than pure
    /// zeros so the encoder produces realistic frames.
    private func makeRecording(silenceSeconds: Double, toneSeconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer(seconds: silenceSeconds, sampleRate: sampleRate, format: file.processingFormat) { frame in
            0.0005 * Float(sin(2.0 * .pi * 50 * Double(frame) / sampleRate))
        })
        try file.write(from: buffer(seconds: toneSeconds, sampleRate: sampleRate, format: file.processingFormat) { frame in
            0.5 * Float(sin(2.0 * .pi * 440 * Double(frame) / sampleRate))
        })
        return url
    }

    private func buffer(
        seconds: Double,
        sampleRate: Double,
        format: AVAudioFormat,
        sample: (Int) -> Float
    ) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = sample(frame)
        }
        return buffer
    }
}
