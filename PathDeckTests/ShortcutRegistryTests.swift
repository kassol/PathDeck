import Testing
@testable import PathDeck

@Suite
struct ShortcutRegistryTests {
    /// 同一（键位, 语境）不允许绑定两个生效动作；⌘T/⌘W 靠语境区分才合法。
    /// S38 起按机器 matcher 查重（展示 token 由 matcher 派生，不再单独查）。
    @Test
    func noDuplicateActiveBindingPerContext() {
        let active = ShortcutRegistry.all.filter { !$0.isReserved }
        var seen = Set<String>()
        for spec in active {
            let key = "\(spec.match)#\(spec.context)"
            #expect(!seen.contains(key), "重复绑定: \(spec.id) → \(key)")
            seen.insert(key)
        }
    }

    /// 键帽 token 从 KeyMatch 派生的快照：覆盖修饰键顺序与全部特殊键形态。
    @Test
    func keycapTokensDerivation() {
        func keys(_ id: String) -> [String]? { ShortcutRegistry.spec(id)?.keys }
        #expect(keys("toggleSidebar") == ["⌘", "B"])
        #expect(keys("togglePreviewPane") == ["⌘", "⇧", "B"])
        #expect(keys("copyCurrentPath") == ["⌘", "⌥", "C"])
        #expect(keys("toggleTerminal") == ["⌃", "`"])
        #expect(keys("newTerminal") == ["⌃", "⇧", "`"])
        #expect(keys("nextTab") == ["⌃", "⇥"])
        #expect(keys("selectTabN") == ["⌘", "1–9"])
        #expect(keys("quickLook") == ["Space"])
        #expect(keys("renameFile") == ["↩"])
        #expect(keys("sendPathToTerminal") == ["⌘", "↩"])
        #expect(keys("moveToTrash") == ["⌘", "⌫"])
        #expect(keys("goToParent") == ["⌘", "↑"])
        #expect(keys("openSelection") == ["⌘", "↓"])
        #expect(keys("toggleHiddenFiles") == ["⌘", "⇧", "."])
    }

    /// char matcher 一律小写存储（匹配时 lowercased 比较，大写会永远匹配不上）。
    @Test
    func charMatchersStoredLowercased() {
        for spec in ShortcutRegistry.all {
            if case .char(let ch, _) = spec.match {
                #expect(String(ch) == String(ch).lowercased(),
                        "matcher 未小写: \(spec.id) → \(ch)")
            }
        }
    }

    /// 派发方式分类守卫：responder-chain / 系统级条目必须 menuOnly，
    /// 裸键与 ⌘↓（Quick Look 面板转发路径）必须 viewLocal，其余直接动作型走 monitor。
    @Test
    func dispatchViaClassification() {
        let menuOnly = Set(["copy", "paste", "moveItemHere", "selectAll", "duplicate",
                            "settings", "quit"])
        let viewLocal = Set(["renameFile", "quickLook", "openSelection"])
        for spec in ShortcutRegistry.all where !spec.isReserved {
            if menuOnly.contains(spec.id) {
                #expect(spec.dispatchVia == .menuOnly, "\(spec.id) 应为 menuOnly")
            } else if viewLocal.contains(spec.id) {
                #expect(spec.dispatchVia == .viewLocal, "\(spec.id) 应为 viewLocal")
            } else {
                #expect(spec.dispatchVia == .monitor, "\(spec.id) 应为 monitor")
            }
        }
    }

    /// 目标 policy 守卫：仅全局偏好 / 全局窗口栈三条允许非 workspace keyWindow 兜底。
    @Test
    func targetPolicyClassification() {
        let fallback = Set(["toggleHiddenFiles", "newTab", "reopenClosedWindow"])
        for spec in ShortcutRegistry.all where !spec.isReserved {
            let expected: CommandTargetPolicy =
                fallback.contains(spec.id) ? .allowsFallback : .workspaceStrict
            #expect(spec.targetPolicy == expected, "\(spec.id) 的 targetPolicy 不符")
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
