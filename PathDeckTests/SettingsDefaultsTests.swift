import Testing
import Foundation
@testable import PathDeck

@Suite
struct SettingsDefaultsTests {
    @Test
    func terminalDefaultShellReturnsNonEmpty() {
        let shell = TerminalDefaults.defaultShell
        #expect(!shell.isEmpty)
        #expect(shell.hasPrefix("/"))
    }

    @Test
    func terminalResolvedShellFallsBackToDefault() {
        let resolved = TerminalDefaults.resolvedShell
        #expect(!resolved.isEmpty)
        #expect(FileManager.default.isExecutableFile(atPath: resolved))
    }

    @Test
    func terminalDefaultFontSize() {
        let size = TerminalDefaults.fontSize
        #expect(size == 13)
    }

    @Test
    func terminalDefaultScrollback() {
        let scrollback = TerminalDefaults.scrollback
        #expect(scrollback == 10000)
    }
}
