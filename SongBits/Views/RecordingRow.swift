import SwiftUI
import AVFoundation

struct RecordingRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackService
    let recording: Recording
    /// Show the parent folder (used in search results, where rows span folders).
    var showFolder = false

    @State private var duration: TimeInterval?
    @State private var confirmingDelete = false

    /// This row holds focus when its file is the one loaded into the player.
    private var isFocused: Bool { playback.loadedURL == recording.url }
    private var isPlaying: Bool { isFocused && playback.isPlaying }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    Task { await playback.playPause(recording.url, skipSilence: model.trimSilence) }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)

                // Tapping the body (not the play button or action menu) focuses
                // the row, revealing its transport controls without playing.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.name)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(recording.createdAt, format: .dateTime.month().day().hour().minute())
                            if showFolder {
                                Label(recording.folder, systemImage: "folder")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let duration {
                        Text(durationString(duration))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await playback.focus(recording.url, skipSilence: model.trimSilence) }
                }

                actionMenu
            }

            if isFocused {
                playbackControls
            }
        }
        .task(id: recording.url) {
            duration = await loadDuration(recording.url)
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.duration, 0.1),
                onEditingChanged: { editing in
                    if editing { playback.beginScrub() } else { playback.endScrub() }
                }
            )

            HStack {
                Text(durationString(playback.currentTime))
                Spacer()
                Text(durationString(playback.duration))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 32) {
                Button { playback.seek(to: 0) } label: {
                    Image(systemName: "backward.end.fill").font(.title3)
                }
                Button { playback.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.title2)
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }
                Button { playback.skip(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.title2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private var actionMenu: some View {
        let targets = model.folders.filter { $0.name != recording.folder }
        return Menu {
            ShareLink(item: recording.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !targets.isEmpty {
                Menu {
                    ForEach(targets) { folder in
                        Button(folder.name) { model.move(recording, to: folder.name) }
                    }
                } label: {
                    Label("Move to…", systemImage: "folder")
                }
            }
            Button {
                model.archive(recording)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Delete “\(recording.name)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.delete(recording) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the recording.")
        }
    }

    private func loadDuration(_ url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : nil
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
