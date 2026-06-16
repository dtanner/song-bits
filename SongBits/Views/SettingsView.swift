import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var rootDraft = ""

    private var sanitizedDraft: String { FolderName.sanitize(rootDraft) }
    private var canApply: Bool {
        FolderName.isValid(sanitizedDraft) && sanitizedDraft != model.rootRelativePath
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $rootDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Apply") {
                        model.rootRelativePath = sanitizedDraft
                        rootDraft = sanitizedDraft
                    }
                    .disabled(!canApply)
                } header: {
                    Text("Recordings Folder")
                } footer: {
                    Text("Stored under the app's Documents folder, visible in the Files app and in Finder over USB.")
                }

                Section {
                    Toggle("Skip leading silence", isOn: $model.trimSilence)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Skips the quiet lead-in when playing. Files are never modified.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { rootDraft = model.rootRelativePath }
        }
    }
}
