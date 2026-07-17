//
//  GhosttyGridCellTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/17.
//

import Foundation
import Testing
@testable import PathDeck

/// FR-BRIDGE-003：像素→格子换算纯函数（⌘Click / ⌘悬停共用）。
/// 基准场景：bounds 高 400pt、scale 2（surface 800px 高）、格子 14×28px、100 列 × 28 行。
/// ghostty 真实 padding 语义（乘 content scale）无法脱离 GPU surface 验证，走人工走查。
struct GhosttyGridCellTests {
    private func cell(_ point: NSPoint, padding: Int = 0,
                      scale: Double = 2, boundsHeight: CGFloat = 400,
                      columns: Int = 100, rows: Int = 28) -> (col: Int, row: Int)? {
        GhosttySurfaceView.gridCell(atLocal: point, boundsHeight: boundsHeight, scale: scale,
                                    paddingPoints: padding, columns: columns, rows: rows,
                                    cellWidthPx: 14, cellHeightPx: 28)
    }

    @Test func topLeftPointIsFirstCell() {
        let c = cell(NSPoint(x: 1, y: 399))
        #expect(c?.col == 0)
        #expect(c?.row == 0)
    }

    @Test func yAxisIsFlipped() {
        // AppKit 左下原点：y 越小 → 行号越大。
        let c = cell(NSPoint(x: 1, y: 10))  // yPx = (400-10)*2 = 780 → row 27
        #expect(c?.row == 27)
    }

    @Test func scaleConvertsPointsToPixels() {
        // scale 2 下每格宽 7pt：x=100pt → 200px → col 14；y=200pt → 400px → row 14。
        let c = cell(NSPoint(x: 100, y: 200))
        #expect(c?.col == 14)
        #expect(c?.row == 14)
    }

    @Test func paddingShiftsGridOrigin() {
        // padding 8pt × scale 2 = 16px：同一点比无 padding 时左上偏移一格量级。
        let c = cell(NSPoint(x: 100, y: 200), padding: 8)  // xPx 184 → col 13；yPx 384 → row 13
        #expect(c?.col == 13)
        #expect(c?.row == 13)
    }

    @Test func pointInsidePaddingIsNil() {
        // padding 区（xPx < 0）不是格子。
        #expect(cell(NSPoint(x: 7, y: 392), padding: 8) == nil)
        #expect(cell(NSPoint(x: 100, y: 397), padding: 8) == nil)
    }

    @Test func cellBoundaryBelongsToNextCell() {
        // floor 语义：恰在格边界像素（xPx = 14）归下一格。
        let c = cell(NSPoint(x: 7, y: 399))  // xPx = 14 → col 1
        #expect(c?.col == 1)
    }

    @Test func beyondLastColumnOrRowIsNil() {
        #expect(cell(NSPoint(x: 399, y: 399), columns: 10) == nil)   // xPx 798 → col 57 ≥ 10
        #expect(cell(NSPoint(x: 1, y: 1), rows: 10) == nil)          // yPx 798 → row 28 ≥ 10
    }

    @Test func degenerateGeometryIsNil() {
        #expect(GhosttySurfaceView.gridCell(atLocal: NSPoint(x: 1, y: 1), boundsHeight: 400,
                                            scale: 2, paddingPoints: 0, columns: 0, rows: 28,
                                            cellWidthPx: 14, cellHeightPx: 28) == nil)
        #expect(GhosttySurfaceView.gridCell(atLocal: NSPoint(x: 1, y: 1), boundsHeight: 400,
                                            scale: 2, paddingPoints: 0, columns: 100, rows: 28,
                                            cellWidthPx: 0, cellHeightPx: 28) == nil)
    }
}
