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

    private var fm: FileManager { .default }

    // MARK: - Setup

    /// Ensures the root and the default `unfiled` folder exist.
    func ensureRoot() throws {
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ensureFolder(named: AppModel.defaultFolder)
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
            return Folder(name: entry.lastPathComponent, recordings: scanRecordings(in: entry))
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

    // MARK: - Writing

    /// Moves a freshly-finalized temp recording into a folder under the given
    /// basename (de-duplicated on collision), defaulting to a timestamp.
    @discardableResult
    func finalize(tempURL: URL, into folderURL: URL, basename: String = Self.timestamp()) throws -> URL {
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

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
