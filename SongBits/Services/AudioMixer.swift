import Foundation
import AVFoundation

/// Combines two audio files into one, both starting at t=0. Overdub uses it to
/// fold a freshly recorded part into the backing take it was played over. The
/// source files are never modified; the result is a new temp `.m4a`.
enum AudioMixer {
    enum MixError: LocalizedError {
        case noAudioTrack
        case exportUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:      return "One of the recordings had no audio to mix."
            case .exportUnavailable: return "Couldn't prepare the mixdown."
            case .exportFailed(let detail): return "Couldn't mix the recording. \(detail)"
            }
        }
    }

    /// Each source is attenuated so two near-peak signals sum without clipping.
    private static let trackGain: Float = 0.8

    /// Mixes `backing` and `voice` into a new temp `.m4a`, both starting at t=0.
    /// The overdub take sets the length: it's inserted whole and the backing is
    /// clamped to it, so the mix ends where recording stopped — whether that's
    /// before or after the backing's own end.
    static func mix(backing: URL, voice: URL) async throws -> URL {
        let composition = AVMutableComposition()
        let voiceTrack = try await append(voice, to: composition)
        let backingTrack = try await append(backing, to: composition, limit: composition.duration)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [backingTrack, voiceTrack].map { track in
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(trackGain, at: .zero)
            return params
        }

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw MixError.exportUnavailable }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("overdub-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        export.outputURL = output
        export.outputFileType = .m4a
        export.audioMix = audioMix

        try await runExport(export)
        return output
    }

    /// Adds a file's first audio track to the composition at t=0, returning the
    /// new composition track so its level can be set in the mix. `limit` caps
    /// how much is inserted, trimming a source that runs longer than it.
    private static func append(
        _ url: URL,
        to composition: AVMutableComposition,
        limit: CMTime? = nil
    ) async throws -> AVMutableCompositionTrack {
        let asset = AVURLAsset(url: url)
        let sources = try await asset.loadTracks(withMediaType: .audio)
        guard let source = sources.first else { throw MixError.noAudioTrack }
        let assetDuration = try await asset.load(.duration)
        let duration = limit.map { min($0, assetDuration) } ?? assetDuration
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw MixError.exportUnavailable }
        try track.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: source,
            at: .zero
        )
        return track
    }

    private static func runExport(_ export: AVAssetExportSession) async throws {
        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }
        switch export.status {
        case .completed:
            return
        case .cancelled:
            throw MixError.exportFailed("The mixdown was cancelled.")
        default:
            throw MixError.exportFailed(export.error?.localizedDescription ?? "Unknown error.")
        }
    }
}
