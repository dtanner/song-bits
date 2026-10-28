import Foundation
import AVFoundation
import os

/// Playback for browsing. One file at a time is "loaded" — the focused take
/// whose transport controls a row reveals. Loading a new file replaces the
/// previous one, so focus is always single. When skip-silence is on, a loaded
/// file's playhead starts past the quiet lead-in (computed per file, cached in
/// memory for the session). Files are never modified. Failures are logged
/// and reported through `onFailure` rather than swallowed, so a play press
/// that can't play always says why.
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

    /// Called with a user-facing explanation whenever a file can't be loaded
    /// or playback can't start.
    var onFailure: ((String) -> Void)?

    private static let log = Logger(subsystem: "com.dantanner.songbits", category: "playback")

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var offsets: [URL: TimeInterval] = [:]
    /// In-flight silence scans, one per file, so a play press and a row
    /// prefetch never scan the same file twice.
    private var scans: [URL: Task<TimeInterval, Never>] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

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
        // The press commits to playback, so bring the audio session up in the
        // background while the silence offset is looked up — the two costs
        // overlap instead of running back to back.
        let activation = Task.detached { Self.activateSession() }
        let offset = skipSilence ? await offset(for: url) : 0
        guard load(url, startAt: offset) else { return }
        if let error = await activation.value {
            fail(Self.describeSessionError(error))
            return
        }
        play(sessionActivated: true)
    }

    /// Starts computing a file's first-sound offset in the background so a
    /// later play press finds it already cached. Rows call this as they come
    /// on screen; low priority keeps a fast scroll from starving the UI, and
    /// an on-demand press awaiting the same task escalates it.
    func prefetchOffset(_ url: URL) {
        guard offsets[url] == nil, scans[url] == nil else { return }
        scans[url] = Task.detached(priority: .utility) {
            SilenceDetector.firstSoundOffset(url)
        }
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
        deactivateSession()
    }

    /// Forgets a file whose path is about to change (rename, move, archive,
    /// delete): drops its cached silence offset and, if it's the loaded take,
    /// stops playback — otherwise the player keeps playing the old file with
    /// no visible transport to stop it.
    func discard(_ url: URL) {
        offsets[url] = nil
        scans[url] = nil
        if loadedURL == url { stop() }
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
            if RecordingStore.isAwaitingDownload(url) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                Self.log.error("Load failed, still downloading from iCloud: \(url.path, privacy: .public)")
                fail("“\(url.deletingPathExtension().lastPathComponent)” is still downloading from iCloud. Try again in a moment.")
            } else {
                Self.log.error("Load failed for \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                fail("Couldn't open “\(url.deletingPathExtension().lastPathComponent)”: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// Resets to the unloaded state and reports why playback didn't happen.
    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }

    private func play(sessionActivated: Bool = false) {
        guard let player else { return }
        if !sessionActivated, let error = Self.activateSession() {
            fail(Self.describeSessionError(error))
            return
        }
        playbackStart = player.currentTime
        guard player.play() else {
            Self.log.error("AVAudioPlayer.play() returned false for \(self.loadedURL?.path ?? "nil", privacy: .public)")
            fail("Couldn't start playback. Another app may be using audio.")
            return
        }
        isPlaying = true
        startTicker()
    }

    /// Configures and activates the shared session for playback. Safe off the
    /// main thread — activation is a media-server round trip, so callers that
    /// can overlap it with other work should. The category is only set when it
    /// differs (recording flows switch it away between takes). Returns the
    /// error when activation fails, nil on success.
    private nonisolated static func activateSession() -> Error? {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback {
                try session.setCategory(.playback)
            }
            try session.setActive(true)
            return nil
        } catch {
            let ns = error as NSError
            log.error("Audio session activation failed: \(ns.domain, privacy: .public) \(ns.code) \(ns.localizedDescription, privacy: .public)")
            return error
        }
    }

    /// User-facing text for a failed session activation. The priority errors
    /// mean another app (or a call) holds audio that playback can't interrupt.
    nonisolated static func describeSessionError(_ error: Error) -> String {
        let code = AVAudioSession.ErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .insufficientPriority, .cannotInterruptOthers:
            return "Couldn't start audio: another app or a call is using it right now."
        default:
            return "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        if let player { currentTime = player.currentTime }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Interruption notifications can arrive off the main thread; parse there,
    /// then hop to the main actor. On an interruption the system pauses the
    /// player — mirror that so the transport shows the true state. The user
    /// resumes manually.
    @objc nonisolated private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Self.log.notice("Audio session interrupted")
        Task { @MainActor in
            if self.isPlaying { self.pause() }
        }
    }

    /// First-sound offset, cached for the session and recomputed on cold launch.
    /// The scan runs off the main actor so the UI stays responsive; a scan the
    /// row already prefetched is awaited rather than restarted.
    private func offset(for url: URL) async -> TimeInterval {
        if let cached = offsets[url] { return cached }
        let scan = scans[url] ?? Task.detached(priority: .userInitiated) {
            SilenceDetector.firstSoundOffset(url)
        }
        scans[url] = scan
        let value = await scan.value
        offsets[url] = value
        scans[url] = nil
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
    /// controls are ready to replay. The session is released so other apps'
    /// audio can resume.
    private func finish() {
        isPlaying = false
        stopTicker()
        let offset = loadedURL.flatMap { offsets[$0] } ?? 0
        if let player {
            player.currentTime = offset < player.duration ? offset : 0
            currentTime = player.currentTime
        }
        deactivateSession()
    }
}
