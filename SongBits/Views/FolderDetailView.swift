import SwiftUI

struct FolderDetailView: View {
    @EnvironmentObject private var model: AppModel
    let folderName: String

    @State private var searchText = ""
    @State private var showSettings = false

    private var folder: Folder? { model.folder(named: folderName) }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Recordings in this folder, filtered by the search query and ordered by
    /// the current sort preference.
    private var visibleRecordings: [Recording] {
        let recordings = folder?.recordings ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty
            ? recordings
            : recordings.filter { $0.name.lowercased().contains(q) }
        return model.sortedRecordings(filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if visibleRecordings.isEmpty {
                    if isSearching {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "waveform",
                            description: Text("Recordings you make into “\(folderName)” appear here.")
                        )
                        .frame(maxHeight: .infinity)
                    }
                } else {
                    List {
                        ForEach(visibleRecordings) { recording in
                            RecordingRow(recording: recording)
                        }
                    }
                    .listStyle(.plain)
                }
            }

            RecordBar(fixedFolder: folderName)
        }
        .searchable(text: $searchText, prompt: "Search “\(folderName)”")
        .keepsToolbarDuringSearch()
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let folder, !folder.recordings.isEmpty {
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
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

private extension View {
    /// Keeps the navigation bar (and its back button) visible when the search
    /// field takes focus, instead of the default behavior of hiding it.
    @ViewBuilder
    func keepsToolbarDuringSearch() -> some View {
        if #available(iOS 17.1, *) {
            searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }
}
