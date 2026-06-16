import Foundation
import SwiftUI

/// Central app state. Holds the in-memory catalog (rebuilt from the filesystem
/// on demand), the session's current folder, and the two tiny persisted
/// settings (root path, trim-silence toggle).
@MainActor
final class AppModel: ObservableObject {
    static let defaultRoot = "Recordings"
    static let defaultFolder = "unfiled"

    /// How recordings are ordered within a folder's list.
    enum RecordingSort: String, CaseIterable, Identifiable {
        case date, name
        var id: String { rawValue }
        var label: String { self == .date ? "Date" : "Name" }
    }

    // Catalog, derived live from disk.
    @Published private(set) var folders: [Folder] = []

    // Session-only: defaults to `unfiled` on cold launch, then to the last
    // folder recorded into.
    @Published var currentFolderName = AppModel.defaultFolder

    @Published var permissionDenied = false
    @Published var errorMessage: String?

    /// A finished recording awaiting a name. Set when recording stops; cleared
    /// once the user saves or deletes it.
    @Published var pendingRecording: PendingRecording?

    struct PendingRecording: Equatable {
        let tempURL: URL
        let defaultName: String
    }

    // Persisted settings.

    /// The folder recordings are read from and written into. Defaults to the
    /// app's own `Documents/Recordings`; once the user picks a folder (e.g. in
    /// iCloud Drive) we resolve a security-scoped bookmark to it instead.
    @Published private(set) var rootURL: URL
    @Published var trimSilence: Bool {
        didSet { UserDefaults.standard.set(trimSilence, forKey: Keys.trim) }
    }
    @Published var recordingSort: RecordingSort {
        didSet { UserDefaults.standard.set(recordingSort.rawValue, forKey: Keys.sort) }
    }

    let recorder = AudioRecorderService()
    let playback = PlaybackService()

    private enum Keys {
        static let rootBookmark = "rootBookmark"
        static let trim = "trimSilence"
        static let sort = "recordingSort"
    }

    /// The app's own `Documents/Recordings`, used until the user picks a folder.
    private static var localDefaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(defaultRoot, isDirectory: true)
    }

    private var store: RecordingStore { RecordingStore(rootURL: rootURL) }

    init() {
        let defaults = UserDefaults.standard
        rootURL = Self.resolveRoot(from: defaults.data(forKey: Keys.rootBookmark))
        trimSilence = defaults.bool(forKey: Keys.trim)
        recordingSort = defaults.string(forKey: Keys.sort)
            .flatMap(RecordingSort.init) ?? .date
        bootstrap()
    }

    /// Resolves the persisted bookmark to its folder, refreshing access and
    /// re-saving a stale bookmark. Falls back to the local default when there's
    /// no bookmark or it can't be resolved.
    private static func resolveRoot(from bookmark: Data?) -> URL {
        guard let bookmark else { return localDefaultRoot }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return localDefaultRoot }
        _ = url.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Keys.rootBookmark)
        }
        return url
    }

    /// Switches the app to a user-picked folder, persisting a security-scoped
    /// bookmark so access survives relaunches. Access is held for the app's
    /// lifetime (AppModel lives the whole session), so it's never stopped.
    func chooseRootFolder(_ picked: URL) {
        guard picked.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access “\(picked.lastPathComponent)”."
            return
        }
        do {
            let bookmark = try picked.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: Keys.rootBookmark)
            rootURL = picked
            bootstrap()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Orders a folder's recordings per the current sort preference.
    func sortedRecordings(_ recordings: [Recording]) -> [Recording] {
        switch recordingSort {
        case .date:
            return recordings.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return recordings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Substring match over the in-memory listing: filename or folder name.
    func searchResults(_ query: String) -> [Recording] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return folders
            .flatMap(\.recordings)
            .filter { $0.name.lowercased().contains(q) || $0.folder.lowercased().contains(q) }
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
        pendingRecording = PendingRecording(tempURL: temp, defaultName: RecordingStore.timestamp())
    }

    /// Finalizes the pending recording under the user-supplied name, falling
    /// back to the timestamp default if the sanitized name is empty.
    func savePendingRecording(named rawName: String) {
        guard let pending = pendingRecording else { return }
        let sanitized = RecordingName.sanitize(rawName)
        let basename = sanitized.isEmpty ? pending.defaultName : sanitized
        do {
            let dest = try store.ensureFolder(named: currentFolderName)
            try store.finalize(tempURL: pending.tempURL, into: dest, basename: basename)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingRecording = nil
    }

    /// Discards the pending recording, deleting its temp file.
    func deletePendingRecording() {
        if let pending = pendingRecording {
            try? FileManager.default.removeItem(at: pending.tempURL)
        }
        pendingRecording = nil
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

    /// Moves a recording into an `Archive` subfolder of its current folder. The
    /// one-level catalog scan ignores nested folders, so archived recordings
    /// drop out of the app's listing (reachable only via the Files app).
    func archive(_ recording: Recording) {
        do {
            let dest = try store.ensureFolder(named: "\(recording.folder)/Archive")
            try store.move(recording: recording, into: dest)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently deletes a recording's file.
    func delete(_ recording: Recording) {
        do {
            try store.delete(recording: recording)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
