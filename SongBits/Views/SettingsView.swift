import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var choosingFolder = false
    @State private var archivedFolders: [String] = []

    private func reloadArchived() {
        archivedFolders = model.archivedFolderNames()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: model.rootURL.lastPathComponent)
                    Button("Choose Folder…") { choosingFolder = true }
                } header: {
                    Text("Recordings Folder")
                } footer: {
                    Text("Pick a folder anywhere in iCloud Drive to keep recordings in sync across your devices and visible in Finder on your Mac.")
                }
                .fileImporter(
                    isPresented: $choosingFolder,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case let .success(urls) = result, let url = urls.first {
                        model.chooseRootFolder(url)
                    }
                }

                Section {
                    Toggle("Skip leading silence", isOn: $model.trimSilence)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Skips the quiet lead-in when playing. Files are never modified.")
                }

                if !archivedFolders.isEmpty {
                    Section {
                        ForEach(archivedFolders, id: \.self) { name in
                            HStack {
                                Text(name)
                                Spacer()
                                Button("Unarchive") {
                                    model.unarchiveFolder(name)
                                    reloadArchived()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("Archived Folders")
                    } footer: {
                        Text("Unarchiving moves a folder back into your list.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: reloadArchived)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
