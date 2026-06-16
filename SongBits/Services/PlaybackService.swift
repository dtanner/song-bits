import Foundation
import AVFoundation

/// Playback for browsing. When skip-silence is on, it seeks past the quiet
/// lead-in (computed per file, cached in memory for the session). Files are
/// never modified.
@MainActor
final class PlaybackService: NSObject, ObservableObject {
    @Published private(set) var playingURL: URL?

    private var player: AVAudioPlayer?
    private var offsets: [URL: TimeInterval] = [:]

    func toggle(_ url: URL, skipSilence: Bool) {
        if playingURL == url {
            stop()
        } else {
            Task { await start(url, skipSilence: skipSilence) }
        }
    }

    private func start(_ url: URL, skipSilence: Bool) async {
        let offset = skipSilence ? await offset(for: url) : 0
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            if offset > 0, offset < player.duration {
                player.currentTime = offset
            }
            guard player.play() else { stop(); return }
            self.player = player
            playingURL = url
        } catch {
            stop()
        }
    }

    /// First-sound offset, cached for the session and recomputed on cold launch.
    /// The scan runs off the main actor so the UI stays responsive.
    private func offset(for url: URL) async -> TimeInterval {
        if let cached = offsets[url] { return cached }
        let value = await Task.detached(priority: .userInitiated) {
            SilenceDetector.firstSoundOffset(url)
        }.value
        offsets[url] = value
        return value
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }
}

extension PlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
