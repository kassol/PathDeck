import Testing
import Foundation
@testable import PathDeck

@Suite
struct TerminalPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.terminalprefs.\(UUID().uuidString)")!
    }

    @Test
    func defaultShellReturnsNonEmptyAbsolute() {
        let shell = TerminalPreferences.defaultShell
        #expect(!shell.isEmpty)
        #expect(shell.hasPrefix("/"))
    }

    @Test
    func resolvedShellFallsBackToExecutable() {
        let prefs = TerminalPreferences(defaults: makeDefaults())
        #expect(FileManager.default.isExecutableFile(atPath: prefs.resolvedShell))
    }

    @Test
    func resolvedShellUsesCustomPath() {
        let prefs = TerminalPreferences(defaults: makeDefaults())
        prefs.shell = "custom"
        prefs.customShellPath = "/bin/bash"
        #expect(prefs.resolvedShell == "/bin/bash")
    }

    @Test
    func resolvedShellCustomEmptyFallsBack() {
        let prefs = TerminalPreferences(defaults: makeDefaults())
        prefs.shell = "custom"
        prefs.customShellPath = ""
        #expect(prefs.resolvedShell == TerminalPreferences.defaultShell)
    }

    @Test
    func defaultFontSizeAndScrollback() {
        let prefs = TerminalPreferences(defaults: makeDefaults())
        #expect(prefs.fontSize == 13)
        #expect(prefs.scrollback == 10000)
    }

    @Test
    func appearanceDefaults() {
        let prefs = TerminalPreferences(defaults: makeDefaults())
        #expect(prefs.fontFamily == "")
        #expect(prefs.fontStyle == "")
        #expect(prefs.useLigatures == true)
        #expect(prefs.fontThicken == true)
        #expect(prefs.useNonASCIIFont == false)
        #expect(prefs.nonASCIIFontFamily == "")
        #expect(prefs.cursorStyle == "bar")
        #expect(prefs.padding == 8)
        #expect(prefs.opacity == 1.0)
        #expect(prefs.blur == false)
        #expect(prefs.copyOnSelect == false)
    }

    @Test
    func persistenceRoundTrip() {
        let defaults = makeDefaults()
        let a = TerminalPreferences(defaults: defaults)
        a.fontSize = 16
        a.scrollback = 25000
        a.shell = "custom"
        a.customShellPath = "/bin/bash"
        a.fontFamily = "Menlo"
        a.fontStyle = "Bold"
        a.useLigatures = false
        a.fontThicken = false
        a.useNonASCIIFont = true
        a.nonASCIIFontFamily = "PingFang SC"
        a.cursorStyle = "block"
        a.padding = 12
        a.opacity = 0.85
        a.blur = true
        a.copyOnSelect = true
        let b = TerminalPreferences(defaults: defaults)
        #expect(b.fontSize == 16)
        #expect(b.scrollback == 25000)
        #expect(b.shell == "custom")
        #expect(b.customShellPath == "/bin/bash")
        #expect(b.fontFamily == "Menlo")
        #expect(b.fontStyle == "Bold")
        #expect(b.useLigatures == false)
        #expect(b.fontThicken == false)
        #expect(b.useNonASCIIFont == true)
        #expect(b.nonASCIIFontFamily == "PingFang SC")
        #expect(b.cursorStyle == "block")
        #expect(b.padding == 12)
        #expect(b.opacity == 0.85)
        #expect(b.blur == true)
        #expect(b.copyOnSelect == true)
    }
}
