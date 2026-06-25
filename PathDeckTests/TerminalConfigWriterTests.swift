import Testing
import Foundation
@testable import PathDeck

@Suite
struct TerminalConfigWriterTests {
    private func makePrefs(fontSize: Double = 13, scrollback: Int = 10000) -> TerminalPreferences {
        let prefs = TerminalPreferences(defaults: UserDefaults(suiteName: "test.cfgwriter.\(UUID().uuidString)")!)
        prefs.fontSize = fontSize
        prefs.scrollback = scrollback
        return prefs
    }

    @Test
    func serializeEmitsFontSizeLine() {
        let text = TerminalConfigWriter.serialize(makePrefs(fontSize: 15))
        #expect(text.contains("font-size = 15"))
    }

    @Test
    func serializeFontSizeNonInteger() {
        let text = TerminalConfigWriter.serialize(makePrefs(fontSize: 13.5))
        #expect(text.contains("font-size = 13.5"))
    }

    @Test
    func scrollbackConvertedToBytes() {
        #expect(TerminalConfigWriter.scrollbackBytes(lines: 10000) == 10_240_000)
        let text = TerminalConfigWriter.serialize(makePrefs(scrollback: 10000))
        #expect(text.contains("scrollback-limit = 10240000"))
    }

    @Test
    func scrollbackBytesPositiveAndMonotonic() {
        #expect(TerminalConfigWriter.scrollbackBytes(lines: 0) == 1024)
        #expect(TerminalConfigWriter.scrollbackBytes(lines: 1000)
            < TerminalConfigWriter.scrollbackBytes(lines: 2000))
    }

    @Test
    func formatNumberIntegerVsDecimal() {
        #expect(TerminalConfigWriter.formatNumber(13) == "13")
        #expect(TerminalConfigWriter.formatNumber(13.5) == "13.5")
    }

    @Test
    func serializeIncludesActiveThemeColors() {
        let prefs = makePrefs()
        prefs.activeThemeID = "dracula"
        let text = TerminalConfigWriter.serialize(prefs)
        #expect(text.contains("background = #282a36"))
        #expect(text.contains("palette = 0=#21222c"))
    }

    @Test
    func serializeAlwaysEmitsCursorPaddingOpacity() {
        let text = TerminalConfigWriter.serialize(makePrefs())
        #expect(text.contains("cursor-style = bar"))
        #expect(text.contains("window-padding-x = 8"))
        #expect(text.contains("window-padding-y = 8"))
        #expect(text.contains("background-opacity = 1"))
    }

    @Test
    func fontFamilyOmittedWhenEmptyQuotedWhenSet() {
        #expect(!TerminalConfigWriter.serialize(makePrefs()).contains("font-family"))
        let prefs = makePrefs()
        prefs.fontFamily = "Menlo"
        #expect(TerminalConfigWriter.serialize(prefs).contains("font-family = Menlo"))
    }

    @Test
    func blurAndCopyOnSelectOnlyWhenEnabled() {
        let off = TerminalConfigWriter.serialize(makePrefs())
        #expect(!off.contains("background-blur"))
        #expect(!off.contains("copy-on-select"))
        let prefs = makePrefs()
        prefs.blur = true
        prefs.copyOnSelect = true
        let on = TerminalConfigWriter.serialize(prefs)
        #expect(on.contains("background-blur = 20"))
        #expect(on.contains("copy-on-select = true"))
    }

    @Test
    func writeCurrentProducesReadableFile() throws {
        let prefs = makePrefs(fontSize: 14, scrollback: 5000)
        let url = TerminalConfigWriter.writeCurrent(prefs)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("font-size = 14"))
        #expect(contents.contains("scrollback-limit ="))
    }
}
