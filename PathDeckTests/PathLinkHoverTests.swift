//
//  PathLinkHoverTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/16.
//

import AppKit
import Testing
@testable import PathDeck

/// FR-BRIDGE-003 #7：⌘悬停浮层的定位 clamp 纯函数。
/// 指针/浮层的视觉呈现与消失时机依赖真实 surface 与鼠标事件，走 GUI 人工走查。
struct PathLinkHoverTests {
    private let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)

    @Test func overlaySitsAtCursorOffsetWhenRoomAvailable() {
        let origin = GhosttySurfaceView.hoverOverlayOrigin(
            cursor: NSPoint(x: 100, y: 100), overlaySize: NSSize(width: 200, height: 20),
            in: bounds, offset: 12
        )
        #expect(origin == NSPoint(x: 112, y: 112))
    }

    @Test func overlayClampsAtRightEdge() {
        let origin = GhosttySurfaceView.hoverOverlayOrigin(
            cursor: NSPoint(x: 780, y: 100), overlaySize: NSSize(width: 200, height: 20),
            in: bounds, offset: 12
        )
        #expect(origin.x == 600)
        #expect(origin.y == 112)
    }

    @Test func overlayClampsAtTopEdge() {
        let origin = GhosttySurfaceView.hoverOverlayOrigin(
            cursor: NSPoint(x: 100, y: 595), overlaySize: NSSize(width: 200, height: 20),
            in: bounds, offset: 12
        )
        #expect(origin.y == 580)
    }

    @Test func overlayNeverGoesNegative() {
        // 浮层比 bounds 还宽的极端情况：clamp 到 minX/minY，不为负。
        let origin = GhosttySurfaceView.hoverOverlayOrigin(
            cursor: NSPoint(x: 0, y: 0), overlaySize: NSSize(width: 1000, height: 700),
            in: bounds, offset: 12
        )
        #expect(origin == NSPoint(x: 0, y: 0))
    }
}

/// 悬停决策状态机：何时重跑命中检测 / 清理 / 保持（#7 时序语义的程序化回归）。
struct PathLinkHoverTrackerTests {
    @Test func firstCmdHoverEvaluates() {
        var tracker = PathLinkHoverTracker()
        #expect(tracker.update(cmdHeld: true, cell: (3, 5)) == .evaluate)
    }

    @Test func sameCellKeepsWithoutReevaluating() {
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        #expect(tracker.update(cmdHeld: true, cell: (3, 5)) == .keep)
    }

    @Test func newCellReevaluates() {
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        #expect(tracker.update(cmdHeld: true, cell: (4, 5)) == .evaluate)
    }

    @Test func releasingCmdClearsImmediately() {
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        #expect(tracker.update(cmdHeld: false, cell: (3, 5)) == .clear)
    }

    @Test func cmdAgainOnSameCellAfterClearReevaluates() {
        // clear 必须作废缓存：松 ⌘ 再按，同格也要重跑检测（行内容可能已变）。
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        _ = tracker.update(cmdHeld: false, cell: (3, 5))
        #expect(tracker.update(cmdHeld: true, cell: (3, 5)) == .evaluate)
    }

    @Test func leavingGridClears() {
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        #expect(tracker.update(cmdHeld: true, cell: nil) == .clear)
    }

    @Test func invalidateForcesReevaluationOnSameCell() {
        // 滚动语义：内容换了，同格也要重估。
        var tracker = PathLinkHoverTracker()
        _ = tracker.update(cmdHeld: true, cell: (3, 5))
        tracker.invalidate()
        #expect(tracker.update(cmdHeld: true, cell: (3, 5)) == .evaluate)
    }

    @Test func hoverWithoutCmdAlwaysClears() {
        var tracker = PathLinkHoverTracker()
        #expect(tracker.update(cmdHeld: false, cell: (3, 5)) == .clear)
        #expect(tracker.update(cmdHeld: false, cell: (4, 6)) == .clear)
    }
}
