import Testing
import Foundation
import AppKit
@testable import PathDeck

/// 列宽保持回归测试：用户调整列宽后，删除文件等触发的列表刷新不得还原列宽。
/// 用真 NSWindow + NSHostingController 挂载完整 WorkspaceRootView，走真实 SwiftUI 更新周期。
@MainActor
struct FileTableColumnWidthTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "FileTableColumnWidthTests-\(UUID().uuidString)")!
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

    private func makeTempDir(files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("colwidth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in files {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        return dir
    }

    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let ov = view as? NSOutlineView { return ov }
        for sub in view.subviews {
            if let found = findOutlineView(in: sub) { return found }
        }
        return nil
    }

    private func pump(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// 等到 view tree 里出现 NSOutlineView（SwiftUI 首次布局是异步的）。
    private func waitForOutlineView(in window: NSWindow?) -> NSOutlineView? {
        for _ in 0..<40 {
            if let content = window?.contentView, let ov = findOutlineView(in: content) {
                return ov
            }
            pump()
        }
        return nil
    }

    @Test
    func savedColumnWidthAppliedOnNewWindow() throws {
        let dir = try makeTempDir(files: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        manager.preferences.columnWidths = ["name": 333, "size": 72]
        let c = manager.openNewWindow(cwd: dir)
        defer { c.close() }

        let ov = try #require(waitForOutlineView(in: c.window))
        #expect(try #require(ov.tableColumn(withIdentifier: .init("name"))).width == 333)
        #expect(try #require(ov.tableColumn(withIdentifier: .init("size"))).width == 72)
    }

    @Test
    func columnResizeWritesBackToPreferences() throws {
        let dir = try makeTempDir(files: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        let c = manager.openNewWindow(cwd: dir)
        defer { c.close() }

        let ov = try #require(waitForOutlineView(in: c.window))
        let nameColumn = try #require(ov.tableColumn(withIdentifier: .init("name")))
        nameColumn.width = 411
        pump()

        #expect(manager.preferences.columnWidths["name"] == 411)
    }

    @Test
    func sortIndicatorRestoredFromPreferences() throws {
        let dir = try makeTempDir(files: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        manager.preferences.sortColumn = .date
        manager.preferences.sortAscending = false
        let c = manager.openNewWindow(cwd: dir)
        defer { c.close() }

        let ov = try #require(waitForOutlineView(in: c.window))
        let descriptor = try #require(ov.sortDescriptors.first)
        #expect(descriptor.key == "date")
        #expect(descriptor.ascending == false)
    }

    @Test
    func columnWidthSurvivesFileDeletion() throws {
        let dir = try makeTempDir(files: ["a.txt", "b.txt", "c.txt"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        let c = manager.openNewWindow(cwd: dir)
        defer { c.close() }

        let ov = try #require(waitForOutlineView(in: c.window))
        let nameColumn = try #require(ov.tableColumn(withIdentifier: .init("name")))
        #expect(ov.numberOfRows == 3)

        nameColumn.width = 400
        pump()

        // 用户流程：选中 → 删除 → 列表刷新
        c.workspace.selectedURLs = [dir.appendingPathComponent("b.txt")]
        c.workspace.trashItems()
        for _ in 0..<10 { pump() }

        let contentAfter = try #require(c.window?.contentView)
        let ovAfter = try #require(findOutlineView(in: contentAfter))
        let nameAfter = try #require(ovAfter.tableColumn(withIdentifier: .init("name")))
        #expect(ovAfter.numberOfRows == 2, "删除应已生效")
        #expect(ovAfter === ov, "NSOutlineView 不应被 SwiftUI 销毁重建")
        #expect(nameAfter.width == 400, "调整过的列宽不得被刷新还原")
    }
}
