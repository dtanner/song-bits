import SwiftUI

/// A folder's archived bits, reached from the "Archived" row at the bottom of
/// the folder's list. Each bit can be auditioned, restored, or deleted.
struct ArchivedRecordingsView: View {
    @EnvironmentObject private var model: AppModel

    let folderName: String

    private var archived: [Recording] {
        model.sortedRecordings(model.folder(named: folderName)?.archived ?? [])
    }

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView(
                    "No Archived Bits",
                    systemImage: "archivebox",
                    description: Text("Bits you archive in “\(folderName)” appear here.")
                )
            } else {
                List {
                    ForEach(archived) { recording in
                        ArchivedRecordingRow(recording: recording)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One archived take: play/pause to audition, Unarchive to restore it to the
/// folder's live list, swipe left to permanently delete.
private struct ArchivedRecordingRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var recorder: AudioRecorderService
    let recording: Recording

    @State private var confirmingDelete = false

    private var isPlaying: Bool { playback.loadedURL == recording.url && playback.isPlaying }

    var body: some View {
        HStack(spacing: 12) {
            if recording.isDownloaded {
                Button {
                    Task { await playback.playPause(recording.url, skipSilence: model.trimSilence) }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                // Playback would reconfigure the audio session out from
                // under a live recording, killing the take.
                .disabled(recorder.isRecording)
            } else {
                // Still an iCloud placeholder; the scan already kicked off
                // its download. Tapping rescans to pick up the arrival.
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Downloading from iCloud")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name)
                    .lineLimit(1)
                Text(recording.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Unarchive") {
                model.unarchive(recording)
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
}

/// Archived folders, reached from the "Archived Folders" row at the bottom of
/// the main folder list. Unarchiving moves a folder back into that list.
struct ArchivedFoldersView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.archivedFolderNames.isEmpty {
                ContentUnavailableView(
                    "No Archived Folders",
                    systemImage: "archivebox",
                    description: Text("Folders you archive appear here.")
                )
            } else {
                List {
                    ForEach(model.archivedFolderNames, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Unarchive") {
                                model.unarchiveFolder(name)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Archived Folders")
        .navigationBarTitleDisplayMode(.inline)
    }
}
