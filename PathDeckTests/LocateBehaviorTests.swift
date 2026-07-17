//
//  LocateBehaviorTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/17.
//

import AppKit
import Foundation
import Testing
@testable import PathDeck

/// FR-BRIDGE-003 Locate 行为回归（真 NSWindow + 完整 WorkspaceRootView）：
/// 文件 → 导航父目录并选中、不夺焦（ADR-0003）；目录 → 导航进入；
/// reveal 默认路径（外部入口 / Open Selection）仍夺焦——语义不得被 Locate 改动波及。
/// 「焦点留在终端」的终端侧另一半（GhosttySurfaceView 保持 first responder）依赖真 surface，走人工走查。
@MainActor
@Suite(.serialized)
struct LocateBehaviorTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "LocateBehaviorTests-\(UUID().uuidString)")!
        return WorkspaceManager(
            preferences: WorkspacePreferences(defaults: suite),
            pinnedFolders: PinnedFolders(userDefaults: suite),
            engine: GhosttyTerminalEngine(),
            router: AppRouter(),
            persistence: WorkspacePersistence(defaults: suite)
        )
    }

    /// root 下建 sub/a.txt，返回 (root, sub, file)。
    private func makeFixture() throws -> (root: URL, sub: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("locate-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let file = sub.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        return (root, sub, file)
    }

    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let ov = view as? NSOutlineView { return ov }
        for sub in view.subviews {
            if let found = findOutlineView(in: sub) { return found }
        }
        return nil
    }

    /// 等待必须用 `await` 让出 MainActor：updateNSView 的选中块经 `DispatchQueue.main.async`
    /// 排在 main queue 尾部，测试体（MainActor job）不返回它就永远不执行——
    /// `RunLoop.run(until:)` 只泵 runloop source（SwiftUI 渲染），drain 不了 main queue。
    private func yieldMainQueue(_ seconds: TimeInterval = 0.05) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitForOutlineView(in window: NSWindow?) async throws -> NSOutlineView? {
        for _ in 0..<40 {
            if let content = window?.contentView, let ov = findOutlineView(in: content) {
                return ov
            }
            try await yieldMainQueue()
        }
        return nil
    }

    private func waitForSelection(in outlineView: NSOutlineView) async throws -> Bool {
        for _ in 0..<40 {
            if !outlineView.selectedRowIndexes.isEmpty { return true }
            try await yieldMainQueue()
        }
        return false
    }

    @Test func locateFileNavigatesToParentSelectsAndKeepsFocus() async throws {
        let (root, sub, file) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = makeManager()
        let c = manager.openNewWindow(cwd: root)
        defer { c.close() }
        let ov = try #require(try await waitForOutlineView(in: c.window))

        // 焦点放在非列表位置（window 自身），Locate 后必须原地不动。
        c.window?.makeFirstResponder(nil)

        c.locate(PathLink(url: file, isDirectory: false))
        #expect(try await waitForSelection(in: ov))

        #expect(c.workspace.currentURL == sub.standardizedFileURL)
        #expect(c.workspace.selectedURLs.map(\.lastPathComponent) == ["a.txt"])
        #expect(!(c.window?.firstResponder is NSOutlineView))
    }

    @Test func locateDirectoryNavigatesIntoIt() async throws {
        let (root, sub, _) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = makeManager()
        let c = manager.openNewWindow(cwd: root)
        defer { c.close() }
        _ = try #require(try await waitForOutlineView(in: c.window))
        c.window?.makeFirstResponder(nil)

        c.locate(PathLink(url: sub, isDirectory: true))
        try await yieldMainQueue()

        #expect(c.workspace.currentURL == sub.standardizedFileURL)
        #expect(!(c.window?.firstResponder is NSOutlineView))
    }

    @Test func revealByDefaultStillTakesFocus() async throws {
        let (root, _, file) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = makeManager()
        let c = manager.openNewWindow(cwd: root)
        defer { c.close() }
        let ov = try #require(try await waitForOutlineView(in: c.window))
        c.window?.makeFirstResponder(nil)

        c.workspace.reveal([file])
        #expect(try await waitForSelection(in: ov))

        #expect(c.window?.firstResponder is NSOutlineView)
    }
}
