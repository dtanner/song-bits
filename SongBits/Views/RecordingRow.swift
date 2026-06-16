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

    private var isPlaying: Bool { playback.playingURL == recording.url }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.toggle(recording.url, skipSilence: model.trimSilence)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

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

            actionMenu
        }
        .task(id: recording.url) {
            duration = await loadDuration(recording.url)
        }
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
