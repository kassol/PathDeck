import Testing
@testable import PathDeck

@Suite
struct ShortcutRegistryTests {
    /// 同一（键位, 语境）不允许绑定两个生效动作；⌘T/⌘W 靠语境区分才合法。
    @Test
    func noDuplicateActiveBindingPerContext() {
        let active = ShortcutRegistry.all.filter { !$0.isReserved }
        var seen = Set<String>()
        for spec in active {
            let key = "\(spec.keys.joined())#\(spec.context)"
            #expect(!seen.contains(key), "重复绑定: \(spec.id) → \(key)")
            seen.insert(key)
        }
    }

    /// 预留键位不得与任何生效绑定同键位（预留的意义就是空置）。
    @Test
    func reservedKeysDoNotCollideWithActiveBindings() {
        let activeKeys = Set(ShortcutRegistry.all.filter { !$0.isReserved }.map { $0.keys.joined() })
        for spec in ShortcutRegistry.all where spec.isReserved {
            #expect(!activeKeys.contains(spec.keys.joined()),
                    "预留位被占用: \(spec.id)")
        }
    }

    /// 预留键位不进浮窗。
    @Test
    func reservedKeysHiddenFromOverlay() {
        #expect(ShortcutRegistry.overlaySpecs.allSatisfy { !$0.isReserved })
        #expect(!ShortcutRegistry.overlaySpecs.contains { $0.group == .system })
    }

    /// 终端拦截集合的派生结果：新键位在集合内，已退役/预留键位不在。
    @Test
    func terminalReservedKeysDerivation() {
        let keys = ShortcutRegistry.terminalReservedKeys
        // S36 新增
        #expect(keys.contains(.init(char: "b")))                       // ⌘B Sidebar
        #expect(keys.contains(.init(char: "b", shift: true)))          // ⌘⇧B Preview
        #expect(keys.contains(.init(char: "\r")))                      // ⌘↩ Send Path
        // 既有保留项
        for c: Character in ["t", "w", "o", "f", "q", ",", "d"] {
            #expect(keys.contains(.init(char: c)))
        }
        for n in 1...9 {
            #expect(keys.contains(.init(char: Character("\(n)"))))
        }
        #expect(keys.contains(.init(char: "n", shift: true)))          // ⌘⇧N New Folder
        #expect(keys.contains(.init(char: "r", shift: true)))          // ⌘⇧R Rename Workspace
        #expect(keys.contains(.init(char: ".", shift: true)))          // ⌘⇧. Hidden Files
        #expect(keys.contains(.init(char: "c", option: true)))         // ⌘⌥C Copy Path
        #expect(keys.contains(.init(char: "\u{7F}")))                  // ⌘⌫ Trash
        #expect(keys.contains(.init(char: "\u{F700}")))                // ⌘↑ Parent
        // S37 转正：⌘⇧T Reopen Closed Tab、⌘⇧P Command Palette 需从终端拦截回 app
        #expect(keys.contains(.init(char: "t", shift: true)))
        #expect(keys.contains(.init(char: "p", shift: true)))
    }

    /// 浮窗布局覆盖全部应展示分组，且每个展示条目都能落进某一列。
    @Test
    func overlayColumnsCoverAllVisibleGroups() {
        let columnGroups = Set(ShortcutRegistry.overlayColumns.flatMap { $0 })
        let visibleGroups = Set(ShortcutRegistry.overlaySpecs.map(\.group))
        #expect(visibleGroups.isSubset(of: columnGroups))
    }
}
