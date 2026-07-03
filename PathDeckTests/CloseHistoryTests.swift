import Testing
import Foundation
import AppKit
@testable import PathDeck

/// S37：Close History（关闭历史）——栈行为、终端/窗口重开语义。
/// .serialized：用真 NSWindow + tabbing，并行执行时窗口 ordering 互相干扰导致 flaky。
@Suite(.serialized)
@MainActor
struct CloseHistoryTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "CloseHistoryTests-\(UUID().uuidString)")!
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

    // MARK: - CloseHistoryStack

    @Test
    func stackIsLIFO() {
        let stack = CloseHistoryStack<Int>()
        stack.push(1)
        stack.push(2)
        stack.push(3)
        #expect(stack.pop() == 3)
        #expect(stack.pop() == 2)
        #expect(stack.pop() == 1)
        #expect(stack.pop() == nil)
        #expect(stack.isEmpty)
    }

    @Test
    func stackEvictsOldestBeyondCapacity() {
        let stack = CloseHistoryStack<Int>(capacity: 3)
        for n in 1...5 { stack.push(n) }
        #expect(stack.records == [3, 4, 5])
    }

    // MARK: - 终端 Close History

    @Test
    func uiCloseRecordsTerminalHistory() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let session = c.createTerminal()!
        c.closeTerminal(session.id)
        #expect(c.closedTerminals.records.count == 1)
        #expect(c.closedTerminals.records.first?.cwd == session.cwd)
    }

    @Test
    func engineExitDoesNotRecordHistory() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let session = c.createTerminal()!
        c.closeTerminal(session.id, recordHistory: false)
        #expect(c.closedTerminals.isEmpty)
    }

    @Test
    func reopenRestoresTitleCwdAndIndex() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let first = c.createTerminal()!
        let second = c.createTerminal()!
        let third = c.createTerminal()!
        _ = third
        c.renameTerminal(second.id, to: "custom", manual: true)

        c.closeTerminal(second.id)
        #expect(c.store.sessions.count == 2)

        c.reopenClosedTerminal()
        #expect(c.store.sessions.count == 3)
        let reopened = c.store.sessions[1]
        #expect(reopened.title == "custom")
        #expect(reopened.isManuallyRenamed)
        #expect(reopened.cwd == second.cwd)
        #expect(reopened.id != second.id, "重建为新 session，不是复活旧 PTY")
        #expect(c.store.sessions[0].id == first.id)
    }

    @Test
    func reopenClampsIndexWhenTabsShrunk() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        let a = c.createTerminal()!
        let b = c.createTerminal()!
        c.closeTerminal(b.id)          // index 1 入栈
        c.closeTerminal(a.id)          // index 0 入栈
        #expect(c.store.sessions.isEmpty)

        c.reopenClosedTerminal()       // 重开 a（index 0，clamp 到 0）
        c.reopenClosedTerminal()       // 重开 b（index 1）
        #expect(c.store.sessions.count == 2)
    }

    @Test
    func reopenEmptyStackIsNoop() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        c.reopenClosedTerminal()
        #expect(c.store.sessions.isEmpty)
    }

    // MARK: - 窗口 Close History

    @Test
    func windowCloseRecordsHistory() {
        let manager = makeManager()
        let cwd = FileManager.default.temporaryDirectory
        let c = manager.openNewWindow(cwd: cwd)
        c.close()

        #expect(manager.closedWindows.records.count == 1)
        let record = manager.closedWindows.records.first
        #expect(record?.state.cwd == cwd.standardizedFileURL.path(percentEncoded: false)
            || record?.state.cwd == cwd.path(percentEncoded: false))
        #expect(record?.frame != nil)
    }

    @Test
    func reopenClosedWindowRestoresStandaloneWindow() {
        let manager = makeManager()
        let cwd = FileManager.default.temporaryDirectory
        let c = manager.openNewWindow(cwd: cwd)
        c.viewState.isCustomTitle = true
        c.viewState.customTitle = "reopen-me"
        c.close()
        #expect(manager.controllers.isEmpty)

        manager.reopenClosedWindow()
        #expect(manager.controllers.count == 1)
        let reopened = manager.controllers[0]
        defer { reopened.close() }
        #expect(reopened.viewState.customTitle == "reopen-me")
        #expect(manager.closedWindows.isEmpty)
    }

    @Test
    func reopenRestoresTerminalComposition() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        c.createTerminal()
        c.createTerminal()
        c.close()

        manager.reopenClosedWindow()
        let reopened = manager.controllers[0]
        defer { reopened.close() }
        #expect(reopened.store.sessions.count == 2)
    }

    @Test
    func reopenJoinsSurvivingTabGroup() {
        let manager = makeManager()
        let cwd = FileManager.default.temporaryDirectory
        let host = manager.openNewWindow(cwd: cwd)
        defer { host.close() }
        let second = manager.openNewWindow(cwd: cwd, tabbedTo: host.window)
        second.close()

        manager.reopenClosedWindow()
        let reopened = manager.controllers.first { $0 !== host }!
        defer { reopened.close() }
        #expect(host.window?.tabbedWindows?.contains(reopened.window!) == true,
                "原组存活时应 tab 回原组")
    }

    /// 组内窗口全关后重开：hostGroup 失效降级为独立窗口，frame 按快照恢复。
    @Test
    func reopenFallsBackToStandaloneWhenGroupIsGone() {
        let manager = makeManager()
        let cwd = FileManager.default.temporaryDirectory
        let host = manager.openNewWindow(cwd: cwd)
        let hostFrame = host.window!.frame
        let second = manager.openNewWindow(cwd: cwd, tabbedTo: host.window)
        second.close()
        host.close()
        #expect(manager.controllers.isEmpty)
        #expect(manager.closedWindows.records.count == 2)

        manager.reopenClosedWindow()   // 重开 host（后关先出）；其缓存组已无存活窗口
        #expect(manager.controllers.count == 1)
        let reopened = manager.controllers[0]
        defer { reopened.close() }
        #expect(reopened.window?.tabbedWindows == nil
            || reopened.window?.tabbedWindows?.count == 1, "组已消亡应恢复为独立窗口")
        #expect(reopened.window?.frame == hostFrame, "独立恢复应还原关闭时 frame")
    }

    @Test
    func reopenEmptyWindowStackIsNoop() {
        let manager = makeManager()
        manager.reopenClosedWindow()
        #expect(manager.controllers.isEmpty)
    }
}
