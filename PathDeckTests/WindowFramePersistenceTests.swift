import Testing
import Foundation
import AppKit
@testable import PathDeck

/// 窗口 frame 持久化：重启还原 + 新窗口继承最近活跃窗口。
@MainActor
struct WindowFramePersistenceTests {
    private func makeSuite() -> UserDefaults {
        UserDefaults(suiteName: "WindowFramePersistenceTests-\(UUID().uuidString)")!
    }

    private func makeManager(suite: UserDefaults) -> WorkspaceManager {
        WorkspaceManager(
            preferences: WorkspacePreferences(defaults: suite),
            pinnedFolders: PinnedFolders(userDefaults: suite),
            engine: GhosttyTerminalEngine(),
            router: AppRouter(),
            persistence: WorkspacePersistence(defaults: suite)
        )
    }

    /// 任一可见屏幕内的测试 frame（避免越界防护把它过滤掉）。
    private func onScreenFrame(size: NSSize) throws -> NSRect {
        let visible = try #require(NSScreen.screens.first?.visibleFrame)
        return NSRect(origin: NSPoint(x: visible.minX + 60, y: visible.minY + 120), size: size)
    }

    @Test
    func frameSurvivesRestartRestore() throws {
        let suite = makeSuite()
        let managerA = makeManager(suite: suite)
        let c = managerA.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        // 注意：close() 会触发 controllerWillClose 的立即持久化，把快照冲成空组，
        // 所以断言完成前不能关 A 的窗口。
        defer { c.close() }
        let frame = try onScreenFrame(size: NSSize(width: 900, height: 640))
        c.window?.setFrame(frame, display: false)
        managerA.persistSessionImmediately()

        let managerB = makeManager(suite: suite)
        managerB.restoreSession()
        defer { managerB.controllers.forEach { $0.close() } }

        let restored = try #require(managerB.controllers.first?.window)
        #expect(restored.frame == frame)
    }

    @Test
    func offscreenFrameFallsBackToDefault() throws {
        let suite = makeSuite()
        let managerA = makeManager(suite: suite)
        let c = managerA.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        defer { c.close() }
        managerA.persistSessionImmediately()

        // 直接篡改持久化快照为越界 frame，模拟显示器配置变化。
        var state = try #require(WorkspacePersistence(defaults: suite).loadSessionState())
        var group = state.groups[0]
        group.frame = "{{-99999, -99999}, {900, 640}}"
        WorkspacePersistence(defaults: suite)
            .persist(WorkspaceSessionState(groups: [group], keyGroupIndex: state.keyGroupIndex))

        let managerB = makeManager(suite: suite)
        managerB.restoreSession()
        defer { managerB.controllers.forEach { $0.close() } }

        let restored = try #require(managerB.controllers.first?.window)
        // 越界 frame 被丢弃，回到默认尺寸（居中位置随屏幕而变，只断言尺寸）。
        #expect(restored.frame.size == NSSize(width: 1080, height: 720))
    }

    @Test
    func newWindowInheritsActiveWindowFrame() throws {
        let suite = makeSuite()
        let manager = makeManager(suite: suite)
        let a = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        defer { a.close() }
        let frame = try onScreenFrame(size: NSSize(width: 880, height: 600))
        a.window?.setFrame(frame, display: false)

        let b = manager.openNewWindow(cwd: URL(fileURLWithPath: "/Users"))
        defer { b.close() }

        let bFrame = try #require(b.window?.frame)
        #expect(bFrame.size == frame.size)
        #expect(bFrame.origin.x == frame.origin.x + 24)
        #expect(bFrame.origin.y == frame.origin.y - 24)
    }
}
