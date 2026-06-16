import Foundation

/// A category, derived live from the filesystem: an immediate subdirectory of
/// the configured root, plus the `.m4a` files it directly contains.
struct Folder: Identifiable, Hashable {
    let name: String
    let recordings: [Recording]

    var id: String { name }
    var recordingCount: Int { recordings.count }

    /// Newest contained recording's date, used for recent-first ordering.
    var mostRecentDate: Date? { recordings.map(\.createdAt).max() }
}
