import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var choosingFolder = false
    @State private var archivedFolders: [String] = []

    private func reloadArchived() {
        archivedFolders = model.archivedFolderNames()
    }

    private var locationLabel: String {
        switch model.rootLocation {
        case .iCloudDrive: "iCloud Drive → Song Bits"
        case .onDevice: "On My iPhone → Song Bits"
        case .custom: model.rootURL.lastPathComponent
        }
    }

    private var locationFooter: String {
        switch model.rootLocation {
        case .iCloudDrive:
            "Recordings sync across your devices. On a Mac, find them in Finder under iCloud Drive → Song Bits."
        case .onDevice:
            "iCloud Drive isn't available, so recordings are only on this iPhone (Files → On My iPhone → Song Bits → Recordings). They'll move to iCloud Drive automatically once it's available, or choose a folder yourself."
        case .custom:
            "Recordings live in the folder you picked. Choose a folder in iCloud Drive to keep them in sync across your devices and visible in Finder on your Mac."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Location", value: locationLabel)
                    Button("Choose Folder…") { choosingFolder = true }
                } header: {
                    Text("Recordings Folder")
                } footer: {
                    Text(locationFooter)
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
