import Testing
import Foundation
@testable import SongBits

/// Per-folder notes: a plain `notes.txt` inside the folder, invisible to the
/// recording catalog.
struct RecordingStoreNotesTests {
    /// A store rooted at a fresh temp directory, cleaned up by the caller.
    private func makeStore() throws -> (RecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-tests-\(UUID().uuidString)", isDirectory: true)
        let store = RecordingStore(rootURL: root)
        try store.ensureRoot()
        return (store, root)
    }

    @Test func notesRoundTrip() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")

        try store.writeNotes("capo 3, drop D", inFolderNamed: "Riffs")
        #expect(store.readNotes(inFolderNamed: "Riffs") == "capo 3, drop D")
    }

    @Test func readReturnsEmptyWhenThereIsNoNotesFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")

        #expect(store.readNotes(inFolderNamed: "Riffs") == "")
    }

    @Test func writingBlankTextDeletesTheNotesFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")

        try store.writeNotes("capo 3", inFolderNamed: "Riffs")
        try store.writeNotes("  \n ", inFolderNamed: "Riffs")

        #expect(!FileManager.default.fileExists(atPath: store.notesURL(inFolderNamed: "Riffs").path))
    }

    @Test func writingBlankTextWithNoFileIsANoOp() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")

        try store.writeNotes("", inFolderNamed: "Riffs")
        #expect(store.readNotes(inFolderNamed: "Riffs") == "")
    }

    @Test func scanFlagsFoldersWithNotes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")
        try store.ensureFolder(named: "Songs")
        try store.writeNotes("chorus is the keeper", inFolderNamed: "Riffs")

        let folders = store.scan()
        #expect(folders.first { $0.name == "Riffs" }?.hasNotes == true)
        #expect(folders.first { $0.name == "Songs" }?.hasNotes == false)
    }

    @Test func scanCountsAnICloudPlaceholderAsNotes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.ensureFolder(named: "Riffs")
        try Data().write(to: folder.appendingPathComponent(".notes.txt.icloud"))

        #expect(store.scan().first { $0.name == "Riffs" }?.hasNotes == true)
    }

    @Test func notesFileNeverAppearsAsARecording() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.ensureFolder(named: "Riffs")
        try store.writeNotes("capo 3", inFolderNamed: "Riffs")

        #expect(store.scan().first { $0.name == "Riffs" }?.recordings.isEmpty == true)
    }
}
