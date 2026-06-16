import Foundation

/// Recording basenames become real on-disk filenames (before the `.m4a`
/// extension), so we constrain them to the same safe set as folders:
/// letters, digits, space, `-`, `_`.
enum RecordingName {
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"
    )

    /// Strips disallowed characters and surrounding whitespace. May return an
    /// empty string; callers fall back to a default name in that case.
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.trimmingCharacters(in: .whitespaces)
    }
}
