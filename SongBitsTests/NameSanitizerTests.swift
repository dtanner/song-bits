import Testing
@testable import SongBits

struct FolderNameTests {
    @Test func acceptsOrdinaryNames() {
        #expect(FolderName.isValid("Riffs"))
        #expect(FolderName.isValid("song ideas 2"))
        #expect(FolderName.isValid("a-b_c"))
    }

    @Test func rejectsReservedArchiveNameCaseInsensitively() {
        #expect(!FolderName.isValid("Archive"))
        #expect(!FolderName.isValid("archive"))
        #expect(!FolderName.isValid("ARCHIVE"))
    }

    @Test func rejectsEmptyDotsAndDisallowedCharacters() {
        #expect(!FolderName.isValid(""))
        #expect(!FolderName.isValid("."))
        #expect(!FolderName.isValid(".."))
        #expect(!FolderName.isValid(".hidden"))
        #expect(!FolderName.isValid("a/b"))
        #expect(!FolderName.isValid("a?b"))
    }

    @Test func sanitizeStripsDisallowedAndTrims() {
        #expect(FolderName.sanitize("  Riffs!  ") == "Riffs")
        #expect(FolderName.sanitize("a/b:c") == "abc")
        #expect(FolderName.sanitize("???") == "")
    }
}

struct RecordingNameTests {
    @Test func sanitizeStripsDisallowedAndTrims() {
        #expect(RecordingName.sanitize("  verse idea!  ") == "verse idea")
        #expect(RecordingName.sanitize("take.1") == "take1")
        #expect(RecordingName.sanitize("???") == "")
    }

    @Test func sanitizeKeepsAllowedSet() {
        #expect(RecordingName.sanitize("Take 2_final-v3") == "Take 2_final-v3")
    }
}
