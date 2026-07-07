import Testing
import Foundation
@testable import SongBits

/// Exercises the store's file operations against a real temp directory, since
/// the filesystem *is* the database.
struct RecordingStoreTests {
    /// A store rooted at a fresh temp directory, cleaned up by the caller.
    private func makeStore() throws -> (RecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-tests-\(UUID().uuidString)", isDirectory: true)
        let store = RecordingStore(rootURL: root)
        try store.ensureRoot()
        return (store, root)
    }

    /// Writes an empty file at a fresh temp URL, standing in for a finished take.
    private func makeTempTake() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-\(UUID().uuidString).m4a")
        try Data().write(to: url)
        return url
    }

    @Test func finalizeDeDupesOnNameCollision() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.ensureFolder(named: "Riffs")

        let first = try store.finalize(tempURL: makeTempTake(), into: folder, basename: "take")
        let second = try store.finalize(tempURL: makeTempTake(), into: folder, basename: "take")

        #expect(first.lastPathComponent == "take.m4a")
        #expect(second.lastPathComponent == "take_1.m4a")
    }

    @Test func renameKeepsExtensionAndDeDupes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.ensureFolder(named: "Riffs")

        let original = try store.finalize(tempURL: makeTempTake(), into: folder, basename: "take")
        try store.finalize(tempURL: makeTempTake(), into: folder, basename: "chorus")

        let renamed = try store.rename(fileAt: original, to: "chorus")
        #expect(renamed.lastPathComponent == "chorus_1.m4a")
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @Test func moveKeepsNameAndDeDupes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = try store.ensureFolder(named: "Riffs")
        let dst = try store.ensureFolder(named: "Songs")

        let take = try store.finalize(tempURL: makeTempTake(), into: src, basename: "idea")
        try store.finalize(tempURL: makeTempTake(), into: dst, basename: "idea")

        let recording = Recording(url: take, createdAt: .now)
        let moved = try store.move(recording: recording, into: dst)

        #expect(moved.lastPathComponent == "idea_1.m4a")
        #expect(moved.deletingLastPathComponent().lastPathComponent == "Songs")
    }

    @Test func scanIgnoresLooseFilesAndForeignExtensions() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.ensureFolder(named: "Riffs")

        try Data().write(to: root.appendingPathComponent("loose.m4a"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))
        try Data().write(to: folder.appendingPathComponent("take.m4a"))

        let riffs = try #require(store.scan().first { $0.name == "Riffs" })
        #expect(riffs.recordings.map(\.name) == ["take"])
    }

    @Test func scanSurfacesICloudPlaceholdersAsNotDownloaded() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try store.ensureFolder(named: "Riffs")

        try Data().write(to: folder.appendingPathComponent(".take.m4a.icloud"))

        let riffs = try #require(store.scan().first { $0.name == "Riffs" })
        let take = try #require(riffs.recordings.first)
        #expect(take.name == "take")
        #expect(take.url.lastPathComponent == "take.m4a")
        #expect(!take.isDownloaded)
    }
}
