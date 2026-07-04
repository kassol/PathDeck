import Testing
import Foundation
import AppKit
@testable import PathDeck

/// S38：全局 monitor adapter（WorkspaceManager.dispatchCommand）——合成 NSEvent 直调，
/// 验证 KeyStroke 转换、执行接线与吞/放行语义。语境经测试缝显式注入
/// （非活跃 app 下 keyWindow 不可靠）。真窗口测试，串行避免 tabbing 干扰。
@Suite(.serialized)
@MainActor
struct CommandMonitorAdapterTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "CommandMonitorAdapterTests-\(UUID().uuidString)")!
        return WorkspaceManager(
            preferences: WorkspacePreferences(defaults: suite),
            pinnedFolders: PinnedFolders(userDefaults: suite),
            engine: GhosttyTerminalEngine(),
            router: AppRouter(),
            persistence: WorkspacePersistence(defaults: suite)
        )
    }

    private func keyEvent(_ chars: String, keyCode: UInt16 = 0,
                          _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode
        )!
    }

    /// S32 回归：文件焦点 ⌘T 必须开新 workspace tab（原 bug：SwiftUI command 不派发致静默失效）。
    @Test
    func commandTWithFileFocusOpensWorkspaceTab() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer {
            let opened = manager.controllers
            opened.forEach { $0.close() }
        }

        let consumed = manager.dispatchCommand(
            for: keyEvent("t", [.command]), context: (target: c, focus: .file)
        )
        #expect(consumed == nil, "命中命令必须吞事件")
        #expect(manager.controllers.count == 2)
    }

    @Test
    func commandTWithTerminalFocusCreatesTerminalSession() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let before = c.store.sessions.count
        let consumed = manager.dispatchCommand(
            for: keyEvent("t", [.command]), context: (target: c, focus: .terminal)
        )
        #expect(consumed == nil)
        #expect(c.store.sessions.count == before + 1)
        #expect(manager.controllers.count == 1, "终端语义不得误开 workspace tab")
    }

    @Test
    func directActionExecutesAgainstTarget() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let before = c.viewState.isSidebarVisible
        let consumed = manager.dispatchCommand(
            for: keyEvent("b", [.command]), context: (target: c, focus: .file)
        )
        #expect(consumed == nil)
        #expect(c.viewState.isSidebarVisible == !before)
    }

    /// 未命中 / 裸键 / textEditing / 非 workspace keyWindow 的 strict 命令：原样放行。
    @Test
    func passthroughSemantics() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let unknown = keyEvent("k", [.command])
        #expect(manager.dispatchCommand(for: unknown, context: (c, .file)) === unknown)

        let bare = keyEvent("t", [])
        #expect(manager.dispatchCommand(for: bare, context: (c, .file)) === bare)

        let editing = keyEvent("t", [.command])
        #expect(manager.dispatchCommand(for: editing, context: (c, .textEditing)) === editing)

        let strictNoWorkspace = keyEvent("b", [.command])
        #expect(manager.dispatchCommand(for: strictNoWorkspace, context: (nil, nil)) === strictNoWorkspace)
    }

    /// ⌘3 经 indexedAction 执行（单窗无 tab 组时 no-op 但吞事件）。
    @Test
    func digitCommandConsumesViaIndexedAction() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let consumed = manager.dispatchCommand(
            for: keyEvent("3", [.command]), context: (target: c, focus: .file)
        )
        #expect(consumed == nil)
    }

    /// monitor 安装/拆除幂等（token 管理，不重复安装）。
    @Test
    func monitorInstallRemoveIsIdempotent() {
        let manager = makeManager()
        manager.installCommandMonitor()
        manager.installCommandMonitor()
        manager.removeCommandMonitor()
        manager.removeCommandMonitor()
    }
}
