//
//  PathLinkHoverTracker.swift
//  PathDeck
//
//  Created by kassol on 2026/7/17.
//

import Foundation

/// ⌘悬停反馈的决策纯状态机（FR-BRIDGE-003 #7）：输入「⌘ 是否按住 + 所在格子」，
/// 输出视图该做什么——清理 / 保持 / 重跑命中检测。视图只执行动作，时序决策在此可单测。
nonisolated struct PathLinkHoverTracker {
    enum Action: Equatable {
        /// 清指针与浮层，格子缓存作废（松 ⌘ / 出界 / 失焦）。
        case clear
        /// 同格且已有结论，不重跑检测。
        case keep
        /// 进了新格子：重跑命中检测并按结果显示/隐藏。
        case evaluate
    }

    private(set) var cell: (col: Int, row: Int)?

    mutating func update(cmdHeld: Bool, cell newCell: (col: Int, row: Int)?) -> Action {
        guard cmdHeld, let newCell else {
            cell = nil
            return .clear
        }
        if let cell, cell == newCell {
            return .keep
        }
        cell = newCell
        return .evaluate
    }

    /// 格子下的行内容已变（滚动等）：作废缓存，下次 update 必然重估。
    mutating func invalidate() {
        cell = nil
    }
}
