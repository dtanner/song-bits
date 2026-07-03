import SwiftUI
import AVFoundation

struct RecordingRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackService
    let recording: Recording
    /// Show the parent folder (used in search results, where rows span folders).
    var showFolder = false

    @State private var duration: TimeInterval?
    @State private var showingOverdub = false

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

                RecordingActionMenu(recording: recording)
            }

            if isFocused {
                playbackControls
            }
        }
        .task(id: recording.url) {
            duration = await loadDuration(recording.url)
        }
        .sheet(isPresented: $showingOverdub, onDismiss: { model.promoteOverdubReady() }) {
            OverdubView(backingName: recording.name)
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

            HStack(spacing: 28) {
                Button { playback.seek(to: 0) } label: {
                    Image(systemName: "backward.end.circle.fill")
                }
                Button { playback.returnToPlaybackStart() } label: {
                    Image(systemName: playback.isPlaying ? "pause.rectangle.fill" : "play.rectangle.fill")
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                // Record a new part over this take and mix them into a new one.
                Button {
                    Task {
                        if await model.startOverdub(of: recording) {
                            showingOverdub = true
                        }
                    }
                } label: {
                    Image(systemName: "music.mic")
                }
                .accessibilityLabel("Record over this take")
            }
            .font(.largeTitle)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 4)
        }
        .padding(.top, 8)
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

/// The row's overflow menu, kept in a separate view that observes only `model`
/// (never `playback`). During playback the parent row re-renders 20×/sec as the
/// playhead ticks; this view's inputs don't change, so SwiftUI skips it and the
/// open menu — including the "Move to…" destination list — stays populated.
private struct RecordingActionMenu: View {
    @EnvironmentObject private var model: AppModel
    let recording: Recording

    @State private var confirmingDelete = false
    @State private var renaming = false
    @State private var renameText = ""

    var body: some View {
        let targets = model.folders.filter { $0.name != recording.folder }
        Menu {
            ShareLink(item: recording.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                renameText = recording.name
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
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
        .alert("Rename Recording", isPresented: $renaming) {
            TextField("Recording name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { model.rename(recording, to: renameText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Letters, digits, spaces, - and _ only.")
        }
    }
}
