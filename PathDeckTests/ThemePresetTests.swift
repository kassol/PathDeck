import Testing
import Foundation
@testable import PathDeck

@Suite
struct ThemePresetTests {
    @Test
    func builtInThemesHaveUniqueIDs() {
        let ids = BuiltInThemes.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 6)
    }

    @Test
    func everyPresetHas16PaletteColors() {
        for theme in BuiltInThemes.all {
            #expect(theme.palette.count == 16)
        }
    }

    @Test
    func defaultIDResolvesToMocha() {
        #expect(BuiltInThemes.preset(id: BuiltInThemes.defaultID).id == "catppuccin-mocha")
    }

    @Test
    func unknownIDFallsBackToMocha() {
        #expect(BuiltInThemes.preset(id: "does-not-exist").id == "catppuccin-mocha")
    }

    @Test
    func configLinesEmitColorsAndFullPalette() {
        let lines = BuiltInThemes.dracula.configLines()
        #expect(lines.contains("background = #282a36"))
        #expect(lines.contains("foreground = #f8f8f2"))
        #expect(lines.contains("cursor-color = #f8f8f2"))
        #expect(lines.contains("palette = 0=#21222c"))
        #expect(lines.contains("palette = 15=#ffffff"))
        // 3 颜色行 + 16 palette 行
        #expect(lines.count == 19)
    }
}
