import Foundation

/// Recording basenames become real on-disk filenames (before the `.m4a`
/// extension), so we constrain them to a safe set: letters, digits, space,
/// `-`, `_`, and `.` (used in default names like "Jul 7 2.32 PM"; safe here
/// because the `.m4a` extension is appended separately).
enum RecordingName {
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_."
    )

    /// Strips disallowed characters and surrounding whitespace. May return an
    /// empty string; callers fall back to a default name in that case.
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered.trimmingCharacters(in: .whitespaces)
    }
}
