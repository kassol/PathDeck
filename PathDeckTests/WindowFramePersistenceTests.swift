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
    /// 尺寸约束两头卡（2026-07-03 CI 实测）：整体须落在可用区内（headless runner 虚拟屏
    /// 仅约 1024×677，超出被 AppKit constrain 改写）；高度须 ≥ 532（SwiftUI minHeight 480 +
    /// 窗口 chrome ≈52，低于此值布局 pass 会把窗口顶大——本地时序碰不到，CI 必现）。
    private func onScreenFrame(size: NSSize) throws -> NSRect {
        let visible = try #require(NSScreen.screens.first?.visibleFrame)
        let origin = NSPoint(x: visible.minX + 40, y: visible.minY + 40)
        let rect = NSRect(origin: origin, size: size)
        try #require(visible.contains(rect), "测试 frame 超出屏幕可用区，断言无意义")
        return rect
    }

    @Test
    func frameSurvivesRestartRestore() throws {
        let suite = makeSuite()
        let managerA = makeManager(suite: suite)
        let c = managerA.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        // 注意：close() 会触发 controllerWillClose 的立即持久化，把快照冲成空组，
        // 所以断言完成前不能关 A 的窗口。
        defer { c.close() }
        let frame = try onScreenFrame(size: NSSize(width: 760, height: 560))
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
        // 越界 frame 被丢弃、回退默认居中。默认 1080×720 在小屏（CI runner 可用区约
        // 1024×677）会被 AppKit constrain 缩小，不能断言绝对尺寸——断言「在屏内」
        // 且尺寸不等于越界快照的 900×640（被接受时 AppKit 只挪位置不改尺寸）。
        #expect(WorkspaceManager.validatedOnScreen(restored.frame) != nil)
        #expect(restored.frame.size != NSSize(width: 900, height: 640))
    }

    @Test
    func newWindowInheritsActiveWindowFrame() throws {
        let suite = makeSuite()
        let manager = makeManager(suite: suite)
        let a = manager.openNewWindow(cwd: URL(fileURLWithPath: "/tmp"))
        defer { a.close() }
        // 级联偏移 (x+24, y-24) 也要留在可用区内：origin 再抬高 24。
        var frame = try onScreenFrame(size: NSSize(width: 760, height: 560))
        frame.origin.y += 24
        a.window?.setFrame(frame, display: false)

        let b = manager.openNewWindow(cwd: URL(fileURLWithPath: "/Users"))
        defer { b.close() }

        let bFrame = try #require(b.window?.frame)
        #expect(bFrame.size == frame.size)
        #expect(bFrame.origin.x == frame.origin.x + 24)
        #expect(bFrame.origin.y == frame.origin.y - 24)
    }
}
