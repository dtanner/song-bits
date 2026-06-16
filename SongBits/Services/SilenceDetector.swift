import AVFoundation

/// Finds where audible sound first begins in a file, so playback can seek past
/// a quiet lead-in. The file is never modified — this only yields an offset.
enum SilenceDetector {
    /// Returns the time offset where audible sound first begins, or 0 if the
    /// file is effectively silent or unreadable.
    ///
    /// Loudness is measured as RMS over short windows (~20 ms) rather than
    /// per-sample amplitude: real audio oscillates through zero on every cycle,
    /// so an instantaneous threshold never stays satisfied. RMS integrates
    /// across those zero-crossings, so a hum/voice reads as loud while a quiet
    /// lead-in stays below threshold (~−40 dBFS). A small pre-roll keeps the
    /// attack from being clipped.
    static func firstSoundOffset(_ url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return 0 }

        let threshold: Float = 0.01          // ~−40 dBFS RMS in linear amplitude
        let windowFrames = max(1, Int(0.02 * sampleRate))
        let prerollFrames = Int(0.05 * sampleRate)
        let chunkFrames: AVAudioFrameCount = 16_384
        let channelCount = max(1, Int(format.channelCount))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
        else { return 0 }

        var globalFrame = 0
        var windowStart = 0
        var windowCount = 0
        var sumSquares: Float = 0

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
                if windowCount == 0 { windowStart = globalFrame + i }
                var frameSq: Float = 0
                for c in 0..<channelCount {
                    let s = channels[c][i]
                    frameSq += s * s
                }
                sumSquares += frameSq / Float(channelCount)
                windowCount += 1

                if windowCount >= windowFrames {
                    let rms = (sumSquares / Float(windowCount)).squareRoot()
                    if rms > threshold {
                        let onset = max(0, windowStart - prerollFrames)
                        return Double(onset) / sampleRate
                    }
                    sumSquares = 0
                    windowCount = 0
                }
            }

            globalFrame += count
            if buffer.frameLength < chunkFrames { break }
        }

        return 0 // never rose above the threshold → treat as all-silent, start at 0
    }
}
