import Testing
import Foundation
import AppKit
@testable import PathDeck

/// S37：Command Palette 匹配排序（纯函数）与 paletteSpecs 派生。
@MainActor
struct CommandPaletteFilterTests {
    private func spec(_ id: String, _ title: String, group: ShortcutGroup = .files) -> ShortcutSpec {
        ShortcutSpec(id: id, match: .char("x", [.command]), title: title, group: group,
                     context: .global, action: { _ in })
    }

    // MARK: - score

    @Test
    func nonMatchingQueryReturnsNil() {
        #expect(CommandPaletteFilter.score(query: "zzz", title: "Toggle Sidebar") == nil)
        #expect(CommandPaletteFilter.score(query: "sidebarx", title: "Toggle Sidebar") == nil)
    }

    @Test
    func emptyQueryScoresZero() {
        #expect(CommandPaletteFilter.score(query: "", title: "Anything") == 0)
    }

    @Test
    func matchIsCaseInsensitive() {
        #expect(CommandPaletteFilter.score(query: "TS", title: "toggle sidebar") != nil)
    }

    @Test
    func wordStartBeatsScattered() {
        // "ts" 命中 "Toggle Sidebar" 两个词首（3+3）> 命中 "Trash" 词首+散点（3+1）
        let wordStarts = CommandPaletteFilter.score(query: "ts", title: "Toggle Sidebar")!
        let scattered = CommandPaletteFilter.score(query: "ts", title: "Trash")!
        #expect(wordStarts > scattered)
    }

    @Test
    func consecutiveBeatsScattered() {
        // "op" 在 "Open" 连续（3+2）> 在 "Old Trap" 散点（3+1）
        let consecutive = CommandPaletteFilter.score(query: "op", title: "Open")!
        let scattered = CommandPaletteFilter.score(query: "op", title: "Old trap")!
        #expect(consecutive > scattered)
    }

    // MARK: - rank

    @Test
    func rankFiltersAndSortsByScore() {
        let specs = [spec("a", "Trash"), spec("b", "Toggle Sidebar"), spec("c", "Open Folder…")]
        let ranked = CommandPaletteFilter.rank(query: "ts", specs: specs)
        #expect(ranked.map(\.id) == ["b", "a"], "词首双命中排前，Open Folder 不命中被过滤")
    }

    @Test
    func rankKeepsOriginalOrderOnTie() {
        let specs = [spec("first", "Open"), spec("second", "Open")]
        let ranked = CommandPaletteFilter.rank(query: "open", specs: specs)
        #expect(ranked.map(\.id) == ["first", "second"])
    }

    @Test
    func emptyQueryReturnsOriginalOrder() {
        let specs = [spec("a", "B Title"), spec("b", "A Title")]
        #expect(CommandPaletteFilter.rank(query: "  ", specs: specs).map(\.id) == ["a", "b"])
    }

    // MARK: - paletteSpecs 派生

    @Test
    func paletteSpecsExcludeSystemReservedAndParameterized() {
        let ids = Set(ShortcutRegistry.paletteSpecs.map(\.id))
        #expect(!ids.contains("settings"))
        #expect(!ids.contains("quit"))
        #expect(!ids.contains("selectTabN"), "参数化条目无 action，不进 Palette")
        #expect(ids.contains("commandPalette"))
        #expect(ids.contains("reopenClosedWindow"))
        #expect(ids.contains("reopenClosedTerminal"))
    }

    @Test
    func paletteSpecsFollowOverlayGroupOrder() {
        let groups = ShortcutRegistry.paletteSpecs.map(\.group)
        let order = ShortcutRegistry.overlayColumns.flatMap { $0 }
        let indices = groups.compactMap { order.firstIndex(of: $0) }
        #expect(indices == indices.sorted(), "Palette 无输入时按浮窗分组序")
    }
}
