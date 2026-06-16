import Foundation

/// Folder names are real on-disk directory names, so we constrain them to a
/// safe, cross-platform set: letters, digits, space, `-`, `_`.
enum FolderName {
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"
    )
    private static let reserved: Set<String> = ["", ".", ".."]

    /// Strips disallowed characters and surrounding whitespace.
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.trimmingCharacters(in: .whitespaces)
    }

    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty,
              !reserved.contains(name),
              !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
