import Testing
import Foundation
import AppKit
@testable import PathDeck

/// S37：命令表（ShortcutSpec.action / isEnabled）完整性与谓词行为。
/// paste/moveItemHere 的剪贴板谓词依赖系统剪贴板状态，不进单测（手动走查覆盖）。
@MainActor
struct ShortcutCommandTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "ShortcutCommandTests-\(UUID().uuidString)")!
        let prefs = WorkspacePreferences(defaults: suite)
        let pinned = PinnedFolders(userDefaults: suite)
        let persistence = WorkspacePersistence(defaults: suite)
        return WorkspaceManager(
            preferences: prefs,
            pinnedFolders: pinned,
            engine: GhosttyTerminalEngine(),
            router: AppRouter(),
            persistence: persistence
        )
    }

    /// 除 system 组外，所有生效条目必须挂 action 或 indexedAction（⌘1–9 参数化，S38）
    /// ——Palette 内容完全派生自本表，键驱动行为不得住在表外。
    @Test
    func allActiveSpecsHaveActions() {
        for spec in ShortcutRegistry.all
        where !spec.isReserved && spec.group != .system {
            #expect(spec.action != nil || spec.indexedAction != nil, "缺 action: \(spec.id)")
        }
    }

    /// indexedAction 与 action 互斥；当前仅 selectTabN 参数化。
    @Test
    func indexedActionExclusivity() {
        for spec in ShortcutRegistry.all {
            #expect(spec.action == nil || spec.indexedAction == nil,
                    "\(spec.id) 不得同时挂 action 与 indexedAction")
            if spec.indexedAction != nil {
                #expect(spec.id == "selectTabN")
            }
        }
    }

    /// id 查找返回对应条目。
    @Test
    func specLookupById() {
        #expect(ShortcutRegistry.spec("toggleSidebar")?.id == "toggleSidebar")
        #expect(ShortcutRegistry.spec("nonexistent") == nil)
    }

    /// 依赖选中项的命令：无选中 false，有选中 true；renameFile 要求单选。
    @Test
    func selectionPredicates() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let selectionDependent = ["moveToTrash", "duplicate", "copy",
                                  "sendPathToTerminal", "openSelection", "quickLook"]
        c.workspace.selectedURLs = []
        for id in selectionDependent {
            #expect(ShortcutRegistry.spec(id)?.isEnabled(c) == false, "\(id) 应在无选中时禁用")
        }
        #expect(ShortcutRegistry.spec("renameFile")?.isEnabled(c) == false)

        c.workspace.selectedURLs = [URL(fileURLWithPath: "/tmp/a")]
        for id in selectionDependent {
            #expect(ShortcutRegistry.spec(id)?.isEnabled(c) == true, "\(id) 应在有选中时可用")
        }
        #expect(ShortcutRegistry.spec("renameFile")?.isEnabled(c) == true)

        c.workspace.selectedURLs = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        #expect(ShortcutRegistry.spec("renameFile")?.isEnabled(c) == false, "renameFile 多选应禁用")
        #expect(ShortcutRegistry.spec("openSelection")?.isEnabled(c) == true, "openSelection 多选可用")
    }

    /// closeTerminal 依赖活动终端。
    @Test
    func closeTerminalPredicate() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        c.viewState.activeTerminalID = nil
        #expect(ShortcutRegistry.spec("closeTerminal")?.isEnabled(c) == false)
        c.viewState.activeTerminalID = UUID()
        #expect(ShortcutRegistry.spec("closeTerminal")?.isEnabled(c) == true)
    }

    /// nil controller：workspace 型谓词 false，恒真型不受影响。
    @Test
    func nilControllerPredicates() {
        #expect(ShortcutRegistry.spec("moveToTrash")?.isEnabled(nil) == false)
        #expect(ShortcutRegistry.spec("renameFile")?.isEnabled(nil) == false)
        #expect(ShortcutRegistry.spec("toggleSidebar")?.isEnabled(nil) == true)
    }

    /// action 行为抽查：viewState / workspace 状态型命令生效。
    @Test
    func actionSmoke() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let sidebarBefore = c.viewState.isSidebarVisible
        ShortcutRegistry.spec("toggleSidebar")?.action?(c)
        #expect(c.viewState.isSidebarVisible == !sidebarBefore)

        let previewBefore = c.viewState.isPreviewPaneVisible
        ShortcutRegistry.spec("togglePreviewPane")?.action?(c)
        #expect(c.viewState.isPreviewPaneVisible == !previewBefore)

        #expect(!c.workspace.isSearching)
        ShortcutRegistry.spec("find")?.action?(c)
        #expect(c.workspace.isSearching)

        let terminalBefore = c.viewState.isTerminalVisible
        ShortcutRegistry.spec("toggleTerminal")?.action?(c)
        #expect(c.viewState.isTerminalVisible == !terminalBefore)
    }

    /// renameFile action 触发 inline rename 信号（pendingRenameURL）。
    @Test
    func renameActionSetsPendingRename() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let target = URL(fileURLWithPath: "/tmp/a")
        c.workspace.selectedURLs = [target]
        ShortcutRegistry.spec("renameFile")?.action?(c)
        #expect(c.workspace.pendingRenameURL == target)
    }

    /// workspace 型 action 收到 nil controller 时静默 no-op（Settings 为 key 的菜单场景）。
    @Test
    func nilControllerActionIsNoop() {
        ShortcutRegistry.spec("toggleSidebar")?.action?(nil)
        ShortcutRegistry.spec("find")?.action?(nil)
    }

    /// 兜底命令回归（2026-07-05）：nil controller 时须经 WorkspaceManager.appShared 生效。
    /// 原实现走 `NSApp.delegate as? AppDelegate`——运行时 delegate 是 SwiftUI adaptor 的
    /// 转发对象，cast 恒 nil，Settings 焦点下 allowsFallback 命令自 S37 起静默 no-op。
    @Test
    func fallbackCommandsReachAppSharedManagerWithoutController() {
        let previous = WorkspaceManager.appShared
        defer { WorkspaceManager.appShared = previous }
        let manager = makeManager()
        WorkspaceManager.appShared = manager

        // 全局偏好型：toggleHiddenFiles(nil) 直达 appShared 偏好。
        let before = manager.preferences.showHidden
        ShortcutRegistry.spec("toggleHiddenFiles")?.action?(nil)
        #expect(manager.preferences.showHidden == !before)

        // 全局窗口栈型：isEnabled(nil) 反映 appShared 的 Close History。
        #expect(ShortcutRegistry.spec("reopenClosedWindow")?.isEnabled(nil) == false)
        manager.closedWindows.push(ClosedWindowRecord(
            state: WorkspaceWindowState(
                cwd: "/tmp", isCustomTitle: false, customTitle: nil,
                mode: WorkspaceMode.finderFirst.rawValue, isTerminalVisible: false,
                anchorCwdPath: nil, terminalStates: [], activeTerminalIndex: nil
            ),
            frame: nil, hostGroup: nil
        ))
        #expect(ShortcutRegistry.spec("reopenClosedWindow")?.isEnabled(nil) == true)

        // newTab(nil)：keyController 为空时按 home 开新独立窗口（Settings 焦点 ⌘T 语义）。
        ShortcutRegistry.spec("newTab")?.action?(nil)
        #expect(manager.controllers.count == 1)
        manager.controllers.first?.close()
    }
}
