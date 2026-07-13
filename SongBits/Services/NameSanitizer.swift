import Foundation

/// User-typed recording and folder names become real on-disk file and
/// directory names. Rather than whitelisting characters, we strip only what
/// the filesystem (and iCloud Drive) can't handle: path separators, colons,
/// and control characters. Leading dots are dropped so a name never becomes a
/// hidden file.
enum NameSanitizer {
    private static let disallowed = CharacterSet(charactersIn: "/:")
        .union(.controlCharacters)
        .union(.newlines)

    private static let reservedFolderNames: Set<String> = ["", ".", ".."]

    /// Removes disallowed characters and nothing else — whitespace survives —
    /// so it can run live on a text field while the user types.
    static func filter(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { !disallowed.contains($0) })
    }

    /// The final on-disk form: filtered, trimmed, with leading dots dropped.
    /// May return an empty string; callers fall back to a default name.
    static func sanitize(_ raw: String) -> String {
        let filtered = filter(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(filtered.drop(while: { $0 == "." }))
            .trimmingCharacters(in: .whitespaces)
    }

    static func isValidFolderName(_ name: String) -> Bool {
        guard !reservedFolderNames.contains(name),
              !name.hasPrefix("."),
              // Reserved for the archive; a user folder with this name would be
              // excluded from the catalog scan and its recordings would vanish.
              // Case-insensitive because APFS is.
              name.caseInsensitiveCompare(RecordingStore.archiveFolderName) != .orderedSame
        else { return false }
        return name.unicodeScalars.allSatisfy { !disallowed.contains($0) }
    }
}
