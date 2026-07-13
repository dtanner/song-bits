import Foundation

/// The filesystem *is* the database. This type reads the configured root one
/// level deep and builds the catalog in memory; nothing about the catalog is
/// persisted. All identity is path-based.
struct RecordingStore {
    /// The folder the catalog is read from and written into. May be the app's
    /// own Documents directory or a user-picked (security-scoped) iCloud Drive
    /// folder; the store is agnostic about which.
    let rootURL: URL

    /// Top-level folder that holds archived folders. Excluded from the catalog
    /// scan, so anything moved inside it drops out of the app's listing. A
    /// visible (non-dotted) name keeps archived folders reachable in the Files
    /// app; the tradeoff is that "Archive" is reserved as a root folder name.
    static let archiveFolderName = "Archive"

    /// Folder that recordings land in when the user hasn't picked one.
    static let defaultFolder = "unfiled"

    private var fm: FileManager { .default }

    // MARK: - Setup

    /// Ensures the root and the default `unfiled` folder exist.
    func ensureRoot() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureFolder(named: Self.defaultFolder)
    }

    func folderURL(named name: String) -> URL {
        rootURL.appendingPathComponent(name, isDirectory: true)
    }

    @discardableResult
    func ensureFolder(named name: String) throws -> URL {
        let url = folderURL(named: name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Reading

    /// One-level scan: root's subfolders and the `.m4a` files in each. Loose
    /// files directly under root and any non-`.m4a` files are ignored. Ordering
    /// is left to the caller (`AppModel` sorts per the user's preference).
    func scan() -> [Folder] {
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { entry -> Folder? in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir, entry.lastPathComponent != Self.archiveFolderName else { return nil }
            return Folder(
                name: entry.lastPathComponent,
                recordings: scanRecordings(in: entry),
                archived: scanRecordings(in: entry.appendingPathComponent(Self.archiveFolderName, isDirectory: true)),
                hasNotes: notesExist(in: entry)
            )
        }
    }

    /// Lists the `.m4a` takes in a folder. Recordings created on another device
    /// or the Mac may not be downloaded yet; iCloud represents those as hidden
    /// `.<name>.m4a.icloud` placeholders. We surface them (resolving the real
    /// name and URL) and kick off a download so playback works shortly after.
    private func scanRecordings(in folderURL: URL) -> [Recording] {
        guard let entries = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        return entries.compactMap { entry -> Recording? in
            guard let (url, isDownloaded) = materializedM4A(for: entry) else { return nil }
            // A placeholder's real URL has no attributes yet, so fall back to
            // the placeholder file's own dates rather than sorting it nowhere.
            let dateKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
            let values = (try? url.resourceValues(forKeys: dateKeys))
                ?? (try? entry.resourceValues(forKeys: dateKeys))
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return Recording(url: url, createdAt: date, isDownloaded: isDownloaded)
        }
    }

    /// Maps a directory entry to the URL of its `.m4a` file, or nil if it isn't
    /// one. Downloaded files map to themselves; iCloud placeholders
    /// (`.name.m4a.icloud`) map to their real `name.m4a` sibling (flagged as
    /// not downloaded) and trigger a download so the bytes arrive before the
    /// user taps play.
    private func materializedM4A(for entry: URL) -> (url: URL, isDownloaded: Bool)? {
        let name = entry.lastPathComponent
        if entry.pathExtension.lowercased() == "m4a" {
            return name.hasPrefix(".") ? nil : (entry, true)
        }
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let realName = String(name.dropFirst().dropLast(".icloud".count))
        guard realName.lowercased().hasSuffix(".m4a") else { return nil }
        let realURL = entry.deletingLastPathComponent().appendingPathComponent(realName)
        try? fm.startDownloadingUbiquitousItem(at: realURL)
        return (realURL, false)
    }

    // MARK: - Migration

    /// Moves everything inside one root into another, merging same-named
    /// folders and de-duplicating colliding file names (never overwriting or
    /// skipping). Emptied source directories are removed, so a fully merged
    /// source vanishes. A missing source is a no-op. Used to migrate the
    /// app-local default root into the iCloud container once it's available.
    static func merge(contentsOf src: URL, into dst: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue else { return }
        guard src.standardizedFileURL.path != dst.standardizedFileURL.path else { return }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for entry in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let target = dst.appendingPathComponent(entry.lastPathComponent, isDirectory: isDirectory)
            if isDirectory {
                try merge(contentsOf: entry, into: target)
            } else if fm.fileExists(atPath: target.path) {
                try fm.moveItem(at: entry, to: uniqueSibling(of: target))
            } else {
                try fm.moveItem(at: entry, to: target)
            }
        }
        if let remaining = try? fm.contentsOfDirectory(atPath: src.path), remaining.isEmpty {
            try fm.removeItem(at: src)
        }
    }

    /// A not-yet-existing URL alongside `url`, formed by suffixing `_1`, `_2`, …
    /// to the basename (keeping the extension).
    private static func uniqueSibling(of url: URL) -> URL {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            var candidate = folder.appendingPathComponent("\(base)_\(counter)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    // MARK: - Notes

    /// Free-form per-folder notes, stored as a plain `notes.txt` inside the
    /// folder so they sync and travel with the recordings. The scan ignores
    /// the file (only `.m4a` is cataloged).
    static let notesFileName = "notes.txt"

    func notesURL(inFolderNamed name: String) -> URL {
        folderURL(named: name).appendingPathComponent(Self.notesFileName)
    }

    /// The folder's notes text, empty when there is no notes file. A not-yet-
    /// downloaded iCloud copy reads as empty; its download is kicked off so
    /// the text is there on a later open.
    func readNotes(inFolderNamed name: String) -> String {
        let url = notesURL(inFolderNamed: name)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        try? fm.startDownloadingUbiquitousItem(at: url)
        return ""
    }

    /// Persists the folder's notes, deleting the file when the text is blank
    /// so unused folders stay clean.
    func writeNotes(_ text: String, inFolderNamed name: String) throws {
        let url = notesURL(inFolderNamed: name)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Whether a folder has notes: either the file itself or an iCloud
    /// placeholder (`.notes.txt.icloud`) for one created on another device.
    private func notesExist(in folderURL: URL) -> Bool {
        if fm.fileExists(atPath: folderURL.appendingPathComponent(Self.notesFileName).path) {
            return true
        }
        return fm.fileExists(atPath: folderURL.appendingPathComponent(".\(Self.notesFileName).icloud").path)
    }

    // MARK: - Writing

    /// Moves a freshly-finalized temp recording into a folder under the given
    /// basename (de-duplicated on collision), defaulting to a readable
    /// date-time name.
    @discardableResult
    func finalize(tempURL: URL, into folderURL: URL, basename: String = Self.defaultBasename()) throws -> URL {
        let dest = uniqueDestination(in: folderURL, basename: basename)
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// Recategorizes a recording by moving its file to another folder, keeping
    /// its original name (de-duplicated on collision).
    @discardableResult
    func move(recording: Recording, into folderURL: URL) throws -> URL {
        let basename = recording.url.deletingPathExtension().lastPathComponent
        let dest = uniqueDestination(in: folderURL, basename: basename)
        try fm.moveItem(at: recording.url, to: dest)
        return dest
    }

    /// Renames a recording in place within its folder, keeping its `.m4a`
    /// extension (de-duplicated on collision).
    @discardableResult
    func rename(recording: Recording, to basename: String) throws -> URL {
        try rename(fileAt: recording.url, to: basename)
    }

    /// Renames an `.m4a` file in place by URL (de-duplicated on collision).
    @discardableResult
    func rename(fileAt url: URL, to basename: String) throws -> URL {
        let folderURL = url.deletingLastPathComponent()
        let dest = uniqueDestination(in: folderURL, basename: basename)
        try fm.moveItem(at: url, to: dest)
        return dest
    }

    /// Permanently removes a recording's file.
    func delete(recording: Recording) throws {
        try fm.removeItem(at: recording.url)
    }

    // MARK: - Recording archiving

    /// Moves a recording into an `Archive` subfolder alongside it, where the
    /// scan lists it as archived rather than live (de-duplicated on collision
    /// with an already-archived take of the same name).
    @discardableResult
    func archive(recording: Recording) throws -> URL {
        let archiveURL = recording.url.deletingLastPathComponent()
            .appendingPathComponent(Self.archiveFolderName, isDirectory: true)
        try fm.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        return try move(recording: recording, into: archiveURL)
    }

    /// Moves an archived recording back up into its folder's live list
    /// (de-duplicated on collision with a live take of the same name).
    @discardableResult
    func unarchive(recording: Recording) throws -> URL {
        let folderURL = recording.url
            .deletingLastPathComponent()  // .../<folder>/Archive
            .deletingLastPathComponent()  // .../<folder>
        return try move(recording: recording, into: folderURL)
    }

    // MARK: - Folder archiving

    /// Moves an entire folder into the top-level archive, where the catalog
    /// scan won't see it. The folder (and its own nested `Archive` of archived
    /// takes) rides along intact. De-duplicated on name collision so a folder
    /// archived, recreated, and archived again doesn't clobber the first.
    @discardableResult
    func archiveFolder(named name: String) throws -> URL {
        let archiveRoot = try ensureFolder(named: Self.archiveFolderName)
        let dest = uniqueDirectory(in: archiveRoot, basename: name)
        try fm.moveItem(at: folderURL(named: name), to: dest)
        return dest
    }

    /// Names of archived folders (immediate subdirectories of the top-level
    /// archive), sorted alphabetically. Empty when nothing is archived.
    func archivedFolderNames() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(
            at: folderURL(named: Self.archiveFolderName),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Moves an archived folder back out to the root (de-duplicated on collision
    /// with an existing root folder of the same name).
    @discardableResult
    func unarchiveFolder(named name: String) throws -> URL {
        let src = folderURL(named: Self.archiveFolderName).appendingPathComponent(name, isDirectory: true)
        let dest = uniqueDirectory(in: rootURL, basename: name)
        try fm.moveItem(at: src, to: dest)
        return dest
    }

    private func uniqueDirectory(in parent: URL, basename: String) -> URL {
        var candidate = parent.appendingPathComponent(basename, isDirectory: true)
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(basename)_\(counter)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    private func uniqueDestination(in folderURL: URL, basename: String) -> URL {
        var candidate = folderURL.appendingPathComponent(basename).appendingPathExtension("m4a")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = folderURL
                .appendingPathComponent("\(basename)_\(counter)")
                .appendingPathExtension("m4a")
            counter += 1
        }
        return candidate
    }

    /// Default basename for a new recording, e.g. "Jul 7 2.32 PM". Dots stand
    /// in for the time's colon, which isn't filename-safe; same-minute
    /// collisions are handled by `uniqueDestination`.
    static func defaultBasename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d h.mm a"
        return formatter.string(from: date)
    }
}
