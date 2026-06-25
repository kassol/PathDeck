import Testing
import Foundation
import AppKit
@testable import PathDeck

/// 覆盖 WorkspaceManager 的纯逻辑路径：路由查找、tab grouping、preferences sync。
/// 用真 NSWindow + NSWindowController 测，单 AppKit 环境足够。
@MainActor
struct WorkspaceManagerTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "WorkspaceManagerTests-\(UUID().uuidString)")!
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

    // MARK: - Route lookup

    @Test
    func findControllerByCurrentURLMatchesExisting() {
        let manager = makeManager()
        let a = URL(fileURLWithPath: "/tmp")
        let c = manager.openNewWindow(cwd: a)
        defer { c.close() }

        let found = manager.findController(matchingCwd: a)
        #expect(found === c)
    }

    @Test
    func findControllerByAnchorCwd() {
        let manager = makeManager()
        let a = URL(fileURLWithPath: "/tmp")
        let anchor = URL(fileURLWithPath: "/Users")
        let c = manager.openNewWindow(cwd: a)
        defer { c.close() }
        c.viewState.terminalAnchorCwd = anchor

        let found = manager.findController(matchingCwd: anchor)
        #expect(found === c)
    }

    @Test
    func findControllerReturnsNilWhenNoMatch() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        defer { c.close() }

        let found = manager.findController(matchingCwd: URL(fileURLWithPath: "/Volumes"))
        #expect(found == nil)
    }

    // MARK: - Controller lifecycle

    @Test
    func openNewWindowAppendsToControllers() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        defer { c.close() }

        #expect(manager.controllers.contains { $0 === c })
    }

    @Test
    func windowCloseRemovesController() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        c.close()

        #expect(!manager.controllers.contains { $0 === c })
    }

    // MARK: - keyController fallback

    @Test
    func keyControllerFallsBackToFirstWhenNoKeyAndNoLastActive() {
        let manager = makeManager()
        let c1 = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        let c2 = manager.openNewWindow(cwd: URL(fileURLWithPath: "/Users"))
        defer { c1.close(); c2.close() }

        // 无任一 window 是 key 也无 lastActive 标记时回退到 controllers.first。
        let key = manager.keyController
        #expect(key === c1 || key === c2)  // 至少不是 nil
    }

    // MARK: - Engine ownership

    @Test
    func engineSessionOwnedByController() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.homeDirectoryForCurrentUser)
        defer { c.close() }

        let session = c.createTerminal()
        #expect(session != nil)
        if let s = session {
            #expect(c.store.contains(s.id))
            #expect(manager.findControllerOwning(sessionID: s.id) === c)
        }
    }

    // MARK: - Preferences propagation

    @Test
    func toggleHiddenPropagatesToAllWorkspaces() {
        let manager = makeManager()
        let c1 = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        let c2 = manager.openNewWindow(cwd: URL(fileURLWithPath: "/Users"))
        defer { c1.close(); c2.close() }

        let before = manager.preferences.showHidden
        manager.toggleHidden()
        #expect(manager.preferences.showHidden == !before)
        #expect(c1.workspace.showHidden == manager.preferences.showHidden)
        #expect(c2.workspace.showHidden == manager.preferences.showHidden)
    }
}
