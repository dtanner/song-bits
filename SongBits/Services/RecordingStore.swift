import Foundation

/// The filesystem *is* the database. This type reads the configured root one
/// level deep and builds the catalog in memory; nothing about the catalog is
/// persisted. All identity is path-based.
struct RecordingStore {
    let rootRelativePath: String

    private var fm: FileManager { .default }

    var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var rootURL: URL {
        documentsURL.appendingPathComponent(rootRelativePath, isDirectory: true)
    }

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

    private func scanRecordings(in folderURL: URL) -> [Recording] {
        guard let files = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                return Recording(url: url, createdAt: date)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Writing

    /// Moves a freshly-finalized temp recording into a folder under a unique
    /// timestamp name.
    @discardableResult
    func finalize(tempURL: URL, into folderURL: URL) throws -> URL {
        let dest = uniqueDestination(in: folderURL, basename: Self.timestamp())
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
