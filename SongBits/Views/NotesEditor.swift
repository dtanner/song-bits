import SwiftUI

/// Sheet editor for free-form notes (a folder's or a recording's). Loads the
/// text on appear and autosaves when dismissed (Done or swipe-down) or when
/// the app backgrounds, so an in-progress edit can't be lost to a kill. Saves
/// only when the text changed, since a recording's save rewrites its file.
struct NotesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let title: String
    let load: () async -> String
    let save: (String) -> Void

    @State private var text = ""
    /// The text as last loaded or saved; nil until the load finishes, so a
    /// quick dismiss can't save the empty placeholder over existing notes.
    @State private var saved: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($editorFocused)
                .disabled(saved == nil)
                .padding(.horizontal, 12)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task {
            let loaded = await load()
            text = loaded
            saved = loaded
            // Fresh notes go straight to typing; existing notes open for reading.
            if loaded.isEmpty { editorFocused = true }
        }
        .onDisappear { commit() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { commit() }
        }
    }

    private func commit() {
        guard let saved, text != saved else { return }
        self.saved = text
        save(text)
    }
}
