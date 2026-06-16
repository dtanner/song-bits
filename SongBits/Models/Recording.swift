import Foundation

/// A single recording, derived live from the filesystem. There is no stored
/// identity — the file's current path *is* its identity.
struct Recording: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: URL { url }
    var filename: String { url.lastPathComponent }

    /// The user-facing name: filename without the `.m4a` extension.
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// The category for this recording: the name of its parent directory.
    var folder: String { url.deletingLastPathComponent().lastPathComponent }
}
