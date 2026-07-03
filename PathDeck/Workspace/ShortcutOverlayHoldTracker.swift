import Foundation

/// 长按 ⌘ 快捷键浮窗（Shortcut Overlay）的纯状态机。
///
/// 语义（S36 评审拍板）：
/// - 单独按住 ⌘ 达 `holdDelay` 且期间无按键/鼠标 → 显示
/// - 阈值内按下任意键 / 出现其他修饰键 → 取消本轮，直到 ⌘ 完全松开才允许重新计时
/// - 显示期间执行组合键 → 保持显示（可连续查阅执行）
/// - 任意鼠标按下 → 立即隐藏并取消本轮（保护 ⌘+点击多选）
/// - ⌘ 松开 / 窗口失焦 → 隐藏并复位
///
/// 与 NSEvent、定时器解耦：schedule 可注入，单测同步驱动。
@MainActor
final class ShortcutOverlayHoldTracker {
    static let holdDelay: TimeInterval = 0.8

    private(set) var isVisible = false {
        didSet { if oldValue != isVisible { onVisibilityChange?(isVisible) } }
    }
    var onVisibilityChange: ((Bool) -> Void)?

    /// 本轮按住已被取消（组合键/鼠标），松开 ⌘ 前不再计时。
    private var holdCancelled = false
    private var pendingShow: DispatchWorkItem?
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void

    init(schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }) {
        self.schedule = schedule
    }

    /// 修饰键变化。commandOnly：修饰键恰为 ⌘；commandHeld：含 ⌘。
    func flagsChanged(commandOnly: Bool, commandHeld: Bool) {
        guard commandHeld else {
            reset()
            return
        }
        guard commandOnly else {
            // 其他修饰键加入（⌘⇧B 这类组合的前奏）：取消待显示；已显示保持。
            cancelPendingShow()
            return
        }
        guard !holdCancelled, !isVisible, pendingShow == nil else { return }
        // 同一时刻至多一个 pending item，且所有清除路径都先 cancel（被 cancel 的
        // DispatchWorkItem 不会执行），无需比对 item 身份。
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShow = nil
            if !self.holdCancelled {
                self.isVisible = true
            }
        }
        pendingShow = item
        schedule(Self.holdDelay, item)
    }

    /// ⌘ 按住期间按下任意键：未显示则取消本轮；已显示保持。
    func keyDown(commandHeld: Bool) {
        guard commandHeld, !isVisible else { return }
        cancelPendingShow()
        holdCancelled = true
    }

    /// ⌘ 按住期间鼠标按下（⌘+点击多选）：立即隐藏并取消本轮。
    func mouseDown(commandHeld: Bool) {
        guard commandHeld else { return }
        cancelPendingShow()
        isVisible = false
        holdCancelled = true
    }

    /// ⌘ 松开 / 窗口失焦：隐藏并复位。
    func reset() {
        cancelPendingShow()
        isVisible = false
        holdCancelled = false
    }

    private func cancelPendingShow() {
        pendingShow?.cancel()
        pendingShow = nil
    }
}
