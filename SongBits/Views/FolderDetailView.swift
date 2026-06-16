import SwiftUI

struct FolderDetailView: View {
    @EnvironmentObject private var model: AppModel
    let folderName: String

    private var folder: Folder? { model.folder(named: folderName) }

    var body: some View {
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
