import SwiftUI

struct FolderDetailView: View {
    @EnvironmentObject private var model: AppModel
    let folderName: String

    private var folder: Folder? { model.folder(named: folderName) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let folder, !folder.recordings.isEmpty {
                    List {
                        ForEach(model.sortedRecordings(folder.recordings)) { recording in
                            RecordingRow(recording: recording)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView(
                        "Empty Folder",
                        systemImage: "waveform",
                        description: Text("Recordings you make into “\(folderName)” appear here.")
                    )
                    .frame(maxHeight: .infinity)
                }
            }

            RecordBar(fixedFolder: folderName)
        }
        .onAppear {
            // Route recordings made here into this folder. Avoid yanking the
            // destination mid-take if a recording is already in progress.
            if !model.recorder.isRecording {
                model.selectFolder(folderName)
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let folder, !folder.recordings.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $model.recordingSort) {
                            ForEach(AppModel.RecordingSort.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(items: folder.recordings.map(\.url)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
