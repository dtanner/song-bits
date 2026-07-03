import Testing
import Foundation
@testable import SongBits

/// Exercises whole-folder archiving against a real temp directory, since the
/// filesystem *is* the database.
struct RecordingStoreArchiveTests {
    /// A store rooted at a fresh temp directory, cleaned up by the caller.
    private func makeStore() throws -> (RecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-tests-\(UUID().uuidString)", isDirectory: true)
        let store = RecordingStore(rootURL: root)
        try store.ensureRoot()
        return (store, root)
    }

    /// Creates a folder with one empty `.m4a` take so it isn't pruned as empty.
    @discardableResult
    private func seedFolder(_ store: RecordingStore, _ name: String) throws -> URL {
        let folder = try store.ensureFolder(named: name)
        let take = folder.appendingPathComponent("take.m4a")
        try Data().write(to: take)
        return folder
    }

    @Test func archivingRemovesFolderFromScan() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try seedFolder(store, "Ideas")
        #expect(store.scan().contains { $0.name == "Ideas" })

        try store.archiveFolder(named: "Ideas")

        // Gone from the catalog, and the top-level archive folder isn't itself
        // surfaced as a stray (empty) folder.
        #expect(!store.scan().contains { $0.name == "Ideas" })
        #expect(!store.scan().contains { $0.name == RecordingStore.archiveFolderName })
        #expect(store.archivedFolderNames() == ["Ideas"])
    }

    @Test func unarchivingRestoresFolderToScan() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try seedFolder(store, "Ideas")
        try store.archiveFolder(named: "Ideas")
        try store.unarchiveFolder(named: "Ideas")

        #expect(store.scan().contains { $0.name == "Ideas" })
        #expect(store.archivedFolderNames().isEmpty)
    }

    @Test func reArchivingDoesNotClobberTheFirst() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try seedFolder(store, "Ideas")
        try store.archiveFolder(named: "Ideas")

        // A new folder with the same name, then archive it too.
        try seedFolder(store, "Ideas")
        try store.archiveFolder(named: "Ideas")

        // Both survive under distinct names rather than one overwriting the other.
        #expect(store.archivedFolderNames().count == 2)
        #expect(store.archivedFolderNames().contains("Ideas"))
        #expect(store.archivedFolderNames().contains("Ideas_1"))
    }

    @Test func unarchivingDeDupesAgainstAnExistingRootFolder() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try seedFolder(store, "Ideas")
        try store.archiveFolder(named: "Ideas")

        // Recreate a live "Ideas" so the restore collides.
        try seedFolder(store, "Ideas")
        try store.unarchiveFolder(named: "Ideas")

        let names = store.scan().map(\.name)
        #expect(names.contains("Ideas"))
        #expect(names.contains("Ideas_1"))
    }
}
