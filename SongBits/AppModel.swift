import Foundation
import SwiftUI

/// Central app state. Holds the in-memory catalog (rebuilt from the filesystem
/// on demand), the session's current folder, and the two tiny persisted
/// settings (root path, trim-silence toggle).
@MainActor
final class AppModel: ObservableObject {
    static let defaultRoot = "Recordings"

    /// The iCloud container whose Documents folder shows up in iCloud Drive as
    /// "Song Bits". Must match the entitlements and `NSUbiquitousContainers`
    /// declared in project.yml.
    static let ubiquityContainerID = "iCloud.com.dantanner.songbits"

    /// Where the current root lives; drives the Settings location label.
    enum RootLocation {
        /// The app's iCloud Drive container — the zero-setup default.
        case iCloudDrive
        /// The app's local Documents — used while iCloud is unavailable.
        case onDevice
        /// A user-picked folder, held via security-scoped bookmark.
        case custom
    }

    /// How recordings are ordered within a folder's list.
    enum RecordingSort: String, CaseIterable, Identifiable {
        case date, name
        var id: String { rawValue }
        var label: String { self == .date ? "Date" : "Name" }
    }

    // Catalog, derived live from disk.
    @Published private(set) var folders: [Folder] = []

    /// Names of archived folders, refreshed alongside the catalog. Drives the
    /// "Archived Folders" row at the bottom of the root list.
    @Published private(set) var archivedFolderNames: [String] = []

    // Session-only: defaults to `unfiled` on cold launch, then to the last
    // folder recorded into.
    @Published var currentFolderName = RecordingStore.defaultFolder

    @Published var permissionDenied = false
    @Published var errorMessage: String?

    /// A just-stopped take awaiting an optional rename. The file is already
    /// saved on disk under `defaultName` when this is set — a crash or kill
    /// during the prompt can't lose it. Cleared once the user renames, keeps,
    /// or deletes it.
    @Published var pendingRecording: PendingRecording?

    struct PendingRecording: Equatable {
        /// Where the take was saved (under its default name).
        let url: URL
        let defaultName: String
    }

    /// True while a finished overdub is being mixed down.
    @Published private(set) var isMixing = false

    /// A finished (already saved) overdub take held until its UI dismisses,
    /// then promoted into the shared naming flow (`pendingRecording`) so the
    /// name prompt isn't covered by the overdub sheet.
    @Published private(set) var overdubReady: PendingRecording?

    /// The folder the in-progress recording will save into, captured when
    /// recording starts so navigating while recording can't redirect the take.
    private var activeRecordingFolder: String?

    // Persisted settings.

    /// The folder recordings are read from and written into. Defaults to the
    /// app's iCloud container (falling back to the app's own
    /// `Documents/Recordings` while iCloud is unavailable); once the user
    /// picks a folder we resolve a security-scoped bookmark to it instead.
    @Published private(set) var rootURL: URL
    @Published private(set) var rootLocation: RootLocation
    @Published var trimSilence: Bool {
        didSet { UserDefaults.standard.set(trimSilence, forKey: Keys.trim) }
    }
    @Published var recordingSort: RecordingSort {
        didSet { UserDefaults.standard.set(recordingSort.rawValue, forKey: Keys.sort) }
    }
    @Published var folderSort: RecordingSort {
        didSet { UserDefaults.standard.set(folderSort.rawValue, forKey: Keys.folderSort) }
    }

    let recorder = AudioRecorderService()
    let playback = PlaybackService()
    let overdub = OverdubService()

    private enum Keys {
        static let rootBookmark = "rootBookmark"
        static let trim = "trimSilence"
        static let sort = "recordingSort"
        static let folderSort = "folderSort"
    }

    /// The app's own `Documents/Recordings`, used until the user picks a folder.
    private static var localDefaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(defaultRoot, isDirectory: true)
    }

    private var store: RecordingStore { RecordingStore(rootURL: rootURL) }

    init() {
        let defaults = UserDefaults.standard
        let bookmark = defaults.data(forKey: Keys.rootBookmark)
        let resolved = Self.resolveRoot(from: bookmark)
        rootURL = resolved ?? Self.localDefaultRoot
        rootLocation = resolved != nil ? .custom : .onDevice
        trimSilence = defaults.bool(forKey: Keys.trim)
        recordingSort = defaults.string(forKey: Keys.sort)
            .flatMap(RecordingSort.init) ?? .date
        folderSort = defaults.string(forKey: Keys.folderSort)
            .flatMap(RecordingSort.init) ?? .date

        // A chosen folder that won't resolve must be surfaced — silently
        // falling back makes the whole library appear to have vanished.
        if bookmark != nil, resolved == nil {
            errorMessage = "Couldn't open your recordings folder, so recordings are going to the app's local folder for now. Re-pick your folder in Settings."
        }

        recorder.onNonResumableInterruption = { [weak self] in
            self?.stopRecording()
        }
        recorder.onRecordingError = { [weak self] detail in
            self?.errorMessage = detail
        }
        bootstrap()
        if resolved == nil { adoptICloudRoot() }
    }

    /// Swaps the default root to the app's iCloud container once it resolves,
    /// merging anything already recorded under the local default into it. Runs
    /// on every launch that has no user-picked folder, so recordings made
    /// while iCloud was off flow into the container when it comes back. When
    /// iCloud is unavailable the app simply stays on the local root.
    private func adoptICloudRoot() {
        Task {
            // First resolution of the container can block on iCloud setup, so
            // it stays off the main actor; the app runs on the local root
            // until it lands.
            let containerDocs = await Task.detached {
                FileManager.default.url(forUbiquityContainerIdentifier: Self.ubiquityContainerID)?
                    .appendingPathComponent("Documents", isDirectory: true)
            }.value
            guard let containerDocs else { return }
            // The user may have picked a folder while the container resolved.
            guard UserDefaults.standard.data(forKey: Keys.rootBookmark) == nil else { return }
            do {
                try RecordingStore.merge(contentsOf: Self.localDefaultRoot, into: containerDocs)
            } catch {
                errorMessage = "Couldn't move recordings into iCloud Drive: \(error.localizedDescription)"
                return
            }
            rootURL = containerDocs
            rootLocation = .iCloudDrive
            bootstrap()
        }
    }

    /// Resolves the persisted bookmark to its folder, refreshing access and
    /// re-saving a stale bookmark. Nil when there's no bookmark or it can't be
    /// resolved or accessed.
    private static func resolveRoot(from bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
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
            rootLocation = .custom
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
        archivedFolderNames = store.archivedFolderNames()
    }

    func folder(named name: String) -> Folder? {
        folders.first { $0.name == name }
    }

    /// Folders ordered per the current folder-sort preference: by newest
    /// contained recording (recent-first), or alphabetically by name. Empty
    /// folders fall to the bottom of the date sort, ordered by name.
    var sortedFolders: [Folder] {
        switch folderSort {
        case .date:
            return folders.sorted { lhs, rhs in
                switch (lhs.mostRecentDate, rhs.mostRecentDate) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        case .name:
            return folders.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
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

    func toggleRecording(into folderName: String) async {
        if recorder.isRecording {
            stopRecording()
        } else {
            await startRecording(into: folderName)
        }
    }

    func startRecording(into folderName: String) async {
        if !MicPermission.granted {
            let granted = await MicPermission.request()
            guard granted else { permissionDenied = true; return }
        }
        // One audio flow at a time: recording claims the session, so browsing
        // playback must stop (and not bleed into the take).
        playback.stop()
        do {
            try store.ensureFolder(named: folderName)
            try recorder.configureSession()
            try recorder.start()
            activeRecordingFolder = folderName
            currentFolderName = folderName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops the capture and saves it immediately into the folder captured at
    /// start, under a timestamp name — the naming prompt then only renames the
    /// already-safe file.
    func stopRecording() {
        guard let temp = recorder.stop() else { return }
        let folderName = activeRecordingFolder ?? currentFolderName
        activeRecordingFolder = nil
        do {
            let dest = try store.ensureFolder(named: folderName)
            let saved = try store.finalize(tempURL: temp, into: dest)
            refresh()
            pendingRecording = PendingRecording(
                url: saved,
                defaultName: saved.deletingPathExtension().lastPathComponent
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renames the pending take to the user-supplied name; an empty or
    /// unchanged sanitized name keeps the default it was saved under.
    func savePendingRecording(named rawName: String) {
        guard let pending = pendingRecording else { return }
        pendingRecording = nil
        let sanitized = NameSanitizer.sanitize(rawName)
        guard !sanitized.isEmpty, sanitized != pending.defaultName else { return }
        do {
            try store.rename(fileAt: pending.url, to: sanitized)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the pending take under the default name it was saved with.
    func keepPendingRecording() {
        pendingRecording = nil
    }

    /// Deletes the pending take's (already saved) file.
    func deletePendingRecording() {
        guard let pending = pendingRecording else { return }
        pendingRecording = nil
        do {
            try FileManager.default.removeItem(at: pending.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Overdub

    /// Starts recording over an existing take: plays it back while capturing the
    /// mic. Returns whether the session actually started, so the caller can
    /// present the overdub UI only on success.
    func startOverdub(of recording: Recording) async -> Bool {
        // One audio flow at a time: never stack an overdub on a live recording.
        guard !recorder.isRecording else { return false }
        if !MicPermission.granted {
            let granted = await MicPermission.request()
            guard granted else { permissionDenied = true; return false }
        }
        // Free the audio session from any browsing playback first.
        playback.stop()
        selectFolder(recording.folder)
        do {
            try overdub.start(backing: recording.url)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Stops the overdub, mixes the captured part into the backing take, and
    /// saves the result into the backing take's folder right away; the naming
    /// prompt then only renames it.
    func finishOverdub() async {
        overdub.stop()
        guard let backing = overdub.backingURL, let voice = overdub.voiceURL else { return }
        defer { overdub.reset() }
        let folderURL = backing.deletingLastPathComponent()
        let defaultName = "\(backing.deletingPathExtension().lastPathComponent) overdub"

        // Through headphones the take is clean, so the digital backing is folded
        // in. On the speaker the backing already bled into the mic acoustically,
        // so the raw capture *is* the take — remixing would double and echo it.
        guard overdub.usingHeadphones else {
            stageOverdubTake(voice, into: folderURL, basename: defaultName)
            return
        }

        isMixing = true
        defer { isMixing = false }
        do {
            let mixed = try await AudioMixer.mix(backing: backing, voice: voice)
            try? FileManager.default.removeItem(at: voice)
            stageOverdubTake(mixed, into: folderURL, basename: defaultName)
        } catch {
            // Keep the raw part rather than losing the performance with the mix.
            errorMessage = "\(error.localizedDescription) The unmixed part was kept."
            stageOverdubTake(voice, into: folderURL, basename: defaultName)
        }
    }

    /// Saves a finished overdub take, then stages it for the naming prompt
    /// (shown once the overdub sheet has dismissed).
    private func stageOverdubTake(_ tempURL: URL, into folderURL: URL, basename: String) {
        do {
            let saved = try store.finalize(tempURL: tempURL, into: folderURL, basename: basename)
            refresh()
            overdubReady = PendingRecording(
                url: saved,
                defaultName: saved.deletingPathExtension().lastPathComponent
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Discards an in-progress overdub.
    func cancelOverdub() {
        overdub.cancel()
    }

    /// Promotes a finished mix into the shared naming flow. Called once the
    /// overdub UI has fully dismissed so the name prompt isn't covered.
    func promoteOverdubReady() {
        guard let ready = overdubReady else { return }
        overdubReady = nil
        pendingRecording = ready
    }

    // MARK: - Notes

    /// The folder's notes text, empty when it has none.
    func notes(forFolder name: String) -> String {
        store.readNotes(inFolderNamed: name)
    }

    /// Persists the folder's notes; blank text deletes the notes file. The
    /// rescan keeps the catalog's `hasNotes` flags current.
    func saveNotes(_ text: String, forFolder name: String) {
        do {
            try store.writeNotes(text, inFolderNamed: name)
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
        let name = NameSanitizer.sanitize(rawName)
        guard NameSanitizer.isValidFolderName(name) else {
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

    /// Renames a recording within its folder, falling back silently when the
    /// sanitized name is empty or unchanged.
    func rename(_ recording: Recording, to rawName: String) {
        let sanitized = NameSanitizer.sanitize(rawName)
        guard !sanitized.isEmpty, sanitized != recording.name else { return }
        do {
            try store.rename(recording: recording, to: sanitized)
            playback.discard(recording.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ recording: Recording, to folderName: String) {
        do {
            let dest = try store.ensureFolder(named: folderName)
            try store.move(recording: recording, into: dest)
            playback.discard(recording.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves a recording into an `Archive` subfolder of its current folder,
    /// dropping it out of the live list. Restorable from the "Archived" row at
    /// the bottom of the folder's list.
    func archive(_ recording: Recording) {
        do {
            try store.archive(recording: recording)
            playback.discard(recording.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves an archived recording back into its folder's live list.
    func unarchive(_ recording: Recording) {
        do {
            try store.unarchive(recording: recording)
            playback.discard(recording.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves an entire folder into the top-level archive so it drops out of the
    /// catalog. The default `unfiled` folder can't be archived — `ensureRoot`
    /// recreates it on every launch, so it would just reappear empty. Restore
    /// via the "Archived Folders" row at the bottom of the root list.
    func archiveFolder(_ name: String) {
        guard name != RecordingStore.defaultFolder else { return }
        // If the loaded take lives in this folder, its path is about to change.
        if playback.loadedURL?.deletingLastPathComponent().lastPathComponent == name {
            playback.stop()
        }
        do {
            try store.archiveFolder(named: name)
            if currentFolderName == name { currentFolderName = RecordingStore.defaultFolder }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves an archived folder back to the root so it rejoins the catalog.
    func unarchiveFolder(_ name: String) {
        do {
            try store.unarchiveFolder(named: name)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Permanently deletes a recording's file.
    func delete(_ recording: Recording) {
        do {
            try store.delete(recording: recording)
            playback.discard(recording.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
