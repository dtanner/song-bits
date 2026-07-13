import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var searchText = ""
    @State private var showNameRecording = false
    @State private var recordingName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                folderList
                RecordBar()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { name in
                FolderDetailView(folderName: name)
            }
            .searchable(text: $searchText, prompt: "Search recordings and folders")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !model.folders.isEmpty {
                        Menu {
                            Picker("Sort by", selection: $model.folderSort) {
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
            .sheet(isPresented: $showHelp) { HelpView() }
        }
        // Attach the app-wide flows to the NavigationStack itself, not its root
        // content, so they present above any pushed folder. An alert bound to a
        // covered view won't appear until that view is back on top.
        .onChange(of: model.pendingRecording) { _, pending in
            guard pending != nil else { return }
            // Leave the field empty so the user can just start typing; the
            // default name shows as a placeholder and is used on an empty save.
            recordingName = ""
            showNameRecording = true
        }
        .alert("Name Recording", isPresented: $showNameRecording) {
            TextField("Recording name", text: $recordingName, prompt: Text(model.pendingRecording?.defaultName ?? ""))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            // The take is already saved under the default name, so Save with an
            // empty field just keeps it — no separate Cancel needed.
            Button("Save") {
                model.savePendingRecording(named: recordingName)
            }
            Button("Delete", role: .destructive) {
                model.deletePendingRecording()
            }
        } message: {
            Text("Already saved under the default name.")
        }
        .onChange(of: recordingName) { _, new in
            let filtered = NameSanitizer.filter(new)
            if filtered != new { recordingName = filtered }
        }
        .alert("Microphone Access Needed", isPresented: $model.permissionDenied) {
            Button("Open Settings") { openSystemSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var folderList: some View {
        if isSearching {
            searchResultsList
        } else if model.folders.isEmpty && model.archivedFolderNames.isEmpty {
            ContentUnavailableView(
                "No Recordings Yet",
                systemImage: "waveform",
                description: Text("Tap record to capture your first bit.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(model.sortedFolders) { folder in
                    NavigationLink(value: folder.name) {
                        FolderRow(folder: folder)
                    }
                    .swipeActions(edge: .trailing) {
                        if folder.name != RecordingStore.defaultFolder {
                            Button {
                                model.archiveFolder(folder.name)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
                if !model.archivedFolderNames.isEmpty {
                    NavigationLink {
                        ArchivedFoldersView()
                    } label: {
                        Label("Archived Folders (\(model.archivedFolderNames.count))", systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        let results = model.searchResults(searchText)
        if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(results) { recording in
                    RecordingRow(recording: recording, showFolder: true)
                }
            }
            .listStyle(.plain)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct FolderRow: View {
    let folder: Folder

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                Text("^[\(folder.recordingCount) recording](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = folder.mostRecentDate {
                Text(date, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
