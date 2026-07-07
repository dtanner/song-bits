import SwiftUI

/// Sheet editor for a folder's notes. Loads the text on appear and autosaves
/// when dismissed (Done or swipe-down) or when the app backgrounds, so an
/// in-progress edit can't be lost to a kill.
struct FolderNotesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let folderName: String

    @State private var text = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($editorFocused)
                .padding(.horizontal, 12)
                .navigationTitle(folderName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear {
            text = model.notes(forFolder: folderName)
            // Fresh notes go straight to typing; existing notes open for reading.
            if text.isEmpty { editorFocused = true }
        }
        .onDisappear {
            model.saveNotes(text, forFolder: folderName)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.saveNotes(text, forFolder: folderName)
            }
        }
    }
}
