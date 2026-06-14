import Testing
@testable import PathDeck

struct ShellEscapeTests {
    @Test func plainASCIIPath() {
        #expect(ShellEscape.escape("/usr/local/bin/foo") == "/usr/local/bin/foo")
    }

    @Test func pathWithSpaces() {
        #expect(ShellEscape.escape("/Users/me/My Documents/file.txt") == "'/Users/me/My Documents/file.txt'")
    }

    @Test func pathWithSingleQuote() {
        #expect(ShellEscape.escape("/tmp/it's here") == "'/tmp/it'\\''s here'")
    }

    @Test func pathWithDoubleQuote() {
        #expect(ShellEscape.escape("/tmp/say \"hello\"") == "'/tmp/say \"hello\"'")
    }

    @Test func pathWithBackslash() {
        #expect(ShellEscape.escape("/tmp/back\\slash") == "'/tmp/back\\slash'")
    }

    @Test func pathWithChinese() {
        #expect(ShellEscape.escape("/Users/me/文档/报告.pdf") == "'/Users/me/文档/报告.pdf'")
    }

    @Test func emptyString() {
        #expect(ShellEscape.escape("") == "''")
    }

    @Test func multiplePathsJoined() {
        let paths = ["/usr/bin/foo", "/tmp/my file.txt", "/tmp/it's"]
        let result = ShellEscape.escapeMultiple(paths)
        #expect(result == "/usr/bin/foo '/tmp/my file.txt' '/tmp/it'\\''s'")
    }

    @Test func pathWithNewline() {
        #expect(ShellEscape.escape("/tmp/line\nbreak") == "'/tmp/line\nbreak'")
    }

    @Test func pathWithParentheses() {
        #expect(ShellEscape.escape("/tmp/foo (1).txt") == "'/tmp/foo (1).txt'")
    }
}
