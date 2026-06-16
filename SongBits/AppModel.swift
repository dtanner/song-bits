import Foundation
import SwiftUI

/// Central app state. Holds the in-memory catalog (rebuilt from the filesystem
/// on demand), the session's current folder, and the two tiny persisted
/// settings (root path, trim-silence toggle).
@MainActor
final class AppModel: ObservableObject {
    static let defaultRoot = "Recordings"
    static let defaultFolder = "unfiled"

    // Catalog, derived live from disk.
    @Published private(set) var folders: [Folder] = []

    // Session-only: defaults to `unfiled` on cold launch, then to the last
    // folder recorded into.
    @Published var currentFolderName = AppModel.defaultFolder

    @Published var permissionDenied = false
    @Published var errorMessage: String?

    // Persisted settings.
    @Published var rootRelativePath: String {
        didSet {
            UserDefaults.standard.set(rootRelativePath, forKey: Keys.root)
            bootstrap()
        }
    }
    @Published var trimSilence: Bool {
        didSet { UserDefaults.standard.set(trimSilence, forKey: Keys.trim) }
    }

    let recorder = AudioRecorderService()
    let playback = PlaybackService()

    private enum Keys {
        static let root = "rootRelativePath"
        static let trim = "trimSilence"
    }

    private var store: RecordingStore { RecordingStore(rootRelativePath: rootRelativePath) }

    init() {
        let defaults = UserDefaults.standard
        rootRelativePath = defaults.string(forKey: Keys.root) ?? Self.defaultRoot
        trimSilence = defaults.bool(forKey: Keys.trim)
        bootstrap()
    }

    // MARK: - Catalog

    func bootstrap() {
        do {
            try store.ensureRoot()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        folders = store.scan()
    }

    func folder(named name: String) -> Folder? {
        folders.first { $0.name == name }
    }

    /// Substring match over the in-memory listing: filename or folder name.
    func searchResults(_ query: String) -> [Recording] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return folders
            .flatMap(\.recordings)
            .filter { $0.filename.lowercased().contains(q) || $0.folder.lowercased().contains(q) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Recording

    func toggleRecording() async {
        if recorder.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        if !recorder.permissionGranted {
            let granted = await recorder.requestPermission()
            guard granted else { permissionDenied = true; return }
        }
        do {
            try store.ensureFolder(named: currentFolderName)
            try recorder.configureSession()
            try recorder.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let temp = recorder.stop() else { return }
        do {
            let dest = try store.ensureFolder(named: currentFolderName)
            try store.finalize(tempURL: temp, into: dest)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Folders

    func selectFolder(_ name: String) {
        currentFolderName = name
    }

    func createFolder(_ rawName: String) {
        let name = FolderName.sanitize(rawName)
        guard FolderName.isValid(name) else {
            errorMessage = "“\(rawName)” isn't a valid folder name."
            return
        }
        do {
            try store.ensureFolder(named: name)
            refresh()
            currentFolderName = name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ recording: Recording, to folderName: String) {
        do {
            let dest = try store.ensureFolder(named: folderName)
            try store.move(recording: recording, into: dest)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
