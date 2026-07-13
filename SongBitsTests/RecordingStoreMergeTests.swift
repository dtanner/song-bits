import Testing
import Foundation
@testable import SongBits

/// Exercises the root-migration merge (local default root → iCloud container)
/// against real temp directories.
struct RecordingStoreMergeTests {
    private let fm = FileManager.default

    /// A fresh temp directory, cleaned up by the caller.
    private func makeDir() throws -> URL {
        let url = fm.temporaryDirectory
            .appendingPathComponent("merge-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func movesFoldersIntoMissingDestination() throws {
        let src = try makeDir()
        defer { try? fm.removeItem(at: src) }
        let dst = fm.temporaryDirectory
            .appendingPathComponent("merge-dst-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dst) }
        try write("take", to: src.appendingPathComponent("Riffs/take.m4a"))
        try write("words", to: src.appendingPathComponent("Riffs/notes.txt"))

        try RecordingStore.merge(contentsOf: src, into: dst)

        #expect(try String(contentsOf: dst.appendingPathComponent("Riffs/take.m4a"), encoding: .utf8) == "take")
        #expect(try String(contentsOf: dst.appendingPathComponent("Riffs/notes.txt"), encoding: .utf8) == "words")
        // A fully merged source vanishes.
        #expect(!fm.fileExists(atPath: src.path))
    }

    @Test func mergesSameNamedFoldersAndDeDupesFiles() throws {
        let src = try makeDir()
        let dst = try makeDir()
        defer {
            try? fm.removeItem(at: src)
            try? fm.removeItem(at: dst)
        }
        try write("moving", to: src.appendingPathComponent("Riffs/take.m4a"))
        try write("staying", to: dst.appendingPathComponent("Riffs/take.m4a"))

        try RecordingStore.merge(contentsOf: src, into: dst)

        #expect(try String(contentsOf: dst.appendingPathComponent("Riffs/take.m4a"), encoding: .utf8) == "staying")
        #expect(try String(contentsOf: dst.appendingPathComponent("Riffs/take_1.m4a"), encoding: .utf8) == "moving")
    }

    @Test func carriesNestedArchiveFolders() throws {
        let src = try makeDir()
        let dst = try makeDir()
        defer {
            try? fm.removeItem(at: src)
            try? fm.removeItem(at: dst)
        }
        try write("old", to: src.appendingPathComponent("Archive/Riffs/take.m4a"))

        try RecordingStore.merge(contentsOf: src, into: dst)

        #expect(try String(contentsOf: dst.appendingPathComponent("Archive/Riffs/take.m4a"), encoding: .utf8) == "old")
    }

    @Test func missingSourceIsANoOp() throws {
        let dst = try makeDir()
        defer { try? fm.removeItem(at: dst) }
        let missing = fm.temporaryDirectory
            .appendingPathComponent("merge-missing-\(UUID().uuidString)", isDirectory: true)

        try RecordingStore.merge(contentsOf: missing, into: dst)

        #expect(try fm.contentsOfDirectory(atPath: dst.path).isEmpty)
    }

    @Test func sameSourceAndDestinationIsANoOp() throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        try write("take", to: dir.appendingPathComponent("Riffs/take.m4a"))

        try RecordingStore.merge(contentsOf: dir, into: dir)

        #expect(try String(contentsOf: dir.appendingPathComponent("Riffs/take.m4a"), encoding: .utf8) == "take")
    }
}
