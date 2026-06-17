import Foundation

/// The filesystem *is* the database. This type reads the configured root one
/// level deep and builds the catalog in memory; nothing about the catalog is
/// persisted. All identity is path-based.
struct RecordingStore {
    /// The folder the catalog is read from and written into. May be the app's
    /// own Documents directory or a user-picked (security-scoped) iCloud Drive
    /// folder; the store is agnostic about which.
    let rootURL: URL

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
    /// files directly under root and any non-`.m4a` files are ignored. Folders
    /// are sorted recent-first (by newest contained file); empty folders fall
    /// to the bottom, ordered by name.
    func scan() -> [Folder] {
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let folders = entries.compactMap { entry -> Folder? in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { return nil }
            return Folder(name: entry.lastPathComponent, recordings: scanRecordings(in: entry))
        }

        return folders.sorted { lhs, rhs in
            switch (lhs.mostRecentDate, rhs.mostRecentDate) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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

        return entries
            .compactMap { entry -> Recording? in
                guard let url = materializedM4AURL(for: entry) else { return nil }
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                return Recording(url: url, createdAt: date)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Maps a directory entry to the URL of its `.m4a` file, or nil if it isn't
    /// one. Downloaded files map to themselves; iCloud placeholders
    /// (`.name.m4a.icloud`) map to their real `name.m4a` sibling and trigger a
    /// download so the bytes arrive before the user taps play.
    private func materializedM4AURL(for entry: URL) -> URL? {
        let name = entry.lastPathComponent
        if entry.pathExtension.lowercased() == "m4a" {
            return name.hasPrefix(".") ? nil : entry
        }
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let realName = String(name.dropFirst().dropLast(".icloud".count))
        guard realName.lowercased().hasSuffix(".m4a") else { return nil }
        let realURL = entry.deletingLastPathComponent().appendingPathComponent(realName)
        try? fm.startDownloadingUbiquitousItem(at: realURL)
        return realURL
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
        let folderURL = recording.url.deletingLastPathComponent()
        let dest = uniqueDestination(in: folderURL, basename: basename)
        try fm.moveItem(at: recording.url, to: dest)
        return dest
    }

    /// Permanently removes a recording's file.
    func delete(recording: Recording) throws {
        try fm.removeItem(at: recording.url)
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
