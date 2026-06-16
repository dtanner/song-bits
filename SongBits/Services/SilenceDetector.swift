import AVFoundation

/// Finds where audible sound first begins in a file, so playback can seek past
/// a quiet lead-in. The file is never modified — this only yields an offset.
enum SilenceDetector {
    /// Returns the time offset of the first sustained sound, or 0 if the file
    /// is effectively silent or unreadable.
    ///
    /// Threshold ~−40 dBFS, required to stay above it for ~20 ms (so a single
    /// click/pop doesn't trigger), with a small pre-roll so the attack isn't
    /// clipped.
    static func firstSoundOffset(_ url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return 0 }

        let threshold: Float = 0.01          // ~−40 dBFS in linear amplitude
        let sustainFrames = Int(0.02 * sampleRate)
        let prerollFrames = Int(0.05 * sampleRate)
        let chunkFrames: AVAudioFrameCount = 16_384
        let channelCount = Int(format.channelCount)

        guard sustainFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
        else { return 0 }

        var globalFrame = 0
        var run = 0
        var runStart = 0

        while true {
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                return 0
            }
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            guard let channels = buffer.floatChannelData else { break }

            for i in 0..<count {
                var peak: Float = 0
                for c in 0..<channelCount {
                    peak = max(peak, abs(channels[c][i]))
                }
                if peak > threshold {
                    if run == 0 { runStart = globalFrame + i }
                    run += 1
                    if run >= sustainFrames {
                        let onset = max(0, runStart - prerollFrames)
                        return Double(onset) / sampleRate
                    }
                } else {
                    run = 0
                }
            }

            globalFrame += count
            if buffer.frameLength < chunkFrames { break }
        }

        return 0 // never crossed the threshold → treat as all-silent, start at 0
    }
}
