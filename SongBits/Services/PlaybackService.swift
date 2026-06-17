import Foundation
import AVFoundation

/// Playback for browsing. One file at a time is "loaded" — the focused take
/// whose transport controls a row reveals. Loading a new file replaces the
/// previous one, so focus is always single. When skip-silence is on, a loaded
/// file's playhead starts past the quiet lead-in (computed per file, cached in
/// memory for the session). Files are never modified.
@MainActor
final class PlaybackService: NSObject, ObservableObject {
    /// The file currently loaded into the player; nil when nothing is focused.
    @Published private(set) var loadedURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// The playhead position the current take last started playing from. Updated
    /// each time playback begins, so the user can jump back to where they pressed
    /// play after scrubbing elsewhere.
    @Published private(set) var playbackStart: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var offsets: [URL: TimeInterval] = [:]

    /// Loads a file as the focused take, paused at its first-sound offset. The
    /// audio session is left untouched until playback actually starts, so
    /// focusing a row doesn't interrupt the user's other audio.
    func focus(_ url: URL, skipSilence: Bool) async {
        guard loadedURL != url else { return }
        let offset = skipSilence ? await offset(for: url) : 0
        load(url, startAt: offset)
    }

    /// The row's play button: focus + play in one gesture, or toggle play/pause
    /// when the file is already loaded.
    func playPause(_ url: URL, skipSilence: Bool) async {
        if loadedURL == url {
            togglePlayPause()
            return
        }
        let offset = skipSilence ? await offset(for: url) : 0
        guard load(url, startAt: offset) else { return }
        play()
    }

    func togglePlayPause() {
        guard player != nil else { return }
        isPlaying ? pause() : play()
    }

    /// DAW-style transport: while stopped, start playing; while playing, stop and
    /// rewind the playhead to where play last began.
    func returnToPlaybackStart() {
        if isPlaying {
            pause()
            seek(to: playbackStart)
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// Slider editing brackets: suspend the time ticker while the user scrubs so
    /// it doesn't fight the drag, then resume if still playing.
    func beginScrub() { stopTicker() }
    func endScrub() { if isPlaying { startTicker() } }

    func stop() {
        player?.stop()
        player = nil
        stopTicker()
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playbackStart = 0
    }

    // MARK: - Private

    @discardableResult
    private func load(_ url: URL, startAt offset: TimeInterval) -> Bool {
        player?.stop()
        stopTicker()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            if offset > 0, offset < player.duration {
                player.currentTime = offset
            }
            self.player = player
            loadedURL = url
            duration = player.duration
            currentTime = player.currentTime
            playbackStart = player.currentTime
            isPlaying = false
            return true
        } catch {
            stop()
            return false
        }
    }

    private func play() {
        guard let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            stop()
            return
        }
        playbackStart = player.currentTime
        guard player.play() else { stop(); return }
        isPlaying = true
        startTicker()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        if let player { currentTime = player.currentTime }
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

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player, isPlaying else { return }
        currentTime = player.currentTime
    }
}

extension PlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    /// Keep the take focused after it ends, rewound to its start offset so the
    /// controls are ready to replay.
    private func finish() {
        isPlaying = false
        stopTicker()
        let offset = loadedURL.flatMap { offsets[$0] } ?? 0
        if let player {
            player.currentTime = offset < player.duration ? offset : 0
            currentTime = player.currentTime
        }
    }
}
