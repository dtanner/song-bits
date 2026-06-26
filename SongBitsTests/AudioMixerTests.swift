import Testing
import AVFoundation
@testable import SongBits

struct AudioMixerTests {
    @Test func mixLengthMatchesTheOverdubTake() async throws {
        // Backing longer than the take: the mix ends where recording stopped.
        let trimmed = try await mixedDuration(backingSeconds: 2.0, voiceSeconds: 1.0)
        #expect(abs(trimmed - 1.0) < 0.25)

        // Take longer than the backing: the mix keeps the full take.
        let extended = try await mixedDuration(backingSeconds: 1.0, voiceSeconds: 2.0)
        #expect(abs(extended - 2.0) < 0.25)
    }

    @Test func leavesSourceFilesUntouched() async throws {
        let backing = try makeTone(seconds: 1.0, frequency: 220)
        let voice = try makeTone(seconds: 1.0, frequency: 440)
        defer { remove(backing); remove(voice) }

        let mixed = try await AudioMixer.mix(backing: backing, voice: voice)
        defer { remove(mixed) }

        #expect(FileManager.default.fileExists(atPath: backing.path))
        #expect(FileManager.default.fileExists(atPath: voice.path))
    }

    @Test func failsWhenSourceHasNoAudio() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try Data().write(to: empty)
        let voice = try makeTone(seconds: 1.0, frequency: 440)
        defer { remove(empty); remove(voice) }

        await #expect(throws: (any Error).self) {
            _ = try await AudioMixer.mix(backing: empty, voice: voice)
        }
    }

    // MARK: - Helpers

    /// Mixes two tones and returns the resulting duration in seconds.
    private func mixedDuration(backingSeconds: Double, voiceSeconds: Double) async throws -> Double {
        let backing = try makeTone(seconds: backingSeconds, frequency: 220)
        let voice = try makeTone(seconds: voiceSeconds, frequency: 440)
        defer { remove(backing); remove(voice) }

        let mixed = try await AudioMixer.mix(backing: backing, voice: voice)
        defer { remove(mixed) }
        return try await AVURLAsset(url: mixed).load(.duration).seconds
    }

    /// Writes a mono AAC `.m4a` sine tone to a temp file.
    private func makeTone(seconds: Double, frequency: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tone-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = 0.5 * Float(sin(2.0 * .pi * frequency * Double(frame) / sampleRate))
        }
        try file.write(from: buffer)
        return url
    }

    private func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
