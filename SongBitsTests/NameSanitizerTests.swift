import Testing
@testable import SongBits

struct NameSanitizerTests {
    @Test func filterKeepsEverydayPunctuationAndWhitespace() {
        #expect(NameSanitizer.filter("Don't Stop (take 2), final!") == "Don't Stop (take 2), final!")
        #expect(NameSanitizer.filter("  spaces stay  ") == "  spaces stay  ")
    }

    @Test func filterStripsPathHostileCharacters() {
        #expect(NameSanitizer.filter("a/b:c") == "abc")
        #expect(NameSanitizer.filter("line\nbreak\ttab") == "linebreaktab")
    }

    @Test func sanitizeTrimsAndDropsLeadingDots() {
        #expect(NameSanitizer.sanitize("  verse idea!  ") == "verse idea!")
        #expect(NameSanitizer.sanitize(".hidden") == "hidden")
        #expect(NameSanitizer.sanitize("...") == "")
        #expect(NameSanitizer.sanitize("///") == "")
        #expect(NameSanitizer.sanitize("Jul 7 2.32 PM") == "Jul 7 2.32 PM")
    }

    @Test func validFolderNamesAcceptOrdinaryAndPunctuatedNames() {
        #expect(NameSanitizer.isValidFolderName("Riffs"))
        #expect(NameSanitizer.isValidFolderName("song ideas 2"))
        #expect(NameSanitizer.isValidFolderName("Don't Stop (demos)"))
    }

    @Test func rejectsReservedArchiveNameCaseInsensitively() {
        #expect(!NameSanitizer.isValidFolderName("Archive"))
        #expect(!NameSanitizer.isValidFolderName("archive"))
        #expect(!NameSanitizer.isValidFolderName("ARCHIVE"))
    }

    @Test func rejectsEmptyDotsAndPathHostileNames() {
        #expect(!NameSanitizer.isValidFolderName(""))
        #expect(!NameSanitizer.isValidFolderName("."))
        #expect(!NameSanitizer.isValidFolderName(".."))
        #expect(!NameSanitizer.isValidFolderName(".hidden"))
        #expect(!NameSanitizer.isValidFolderName("a/b"))
        #expect(!NameSanitizer.isValidFolderName("a:b"))
    }
}
