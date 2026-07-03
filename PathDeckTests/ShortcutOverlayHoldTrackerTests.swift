import Testing
import Foundation
@testable import PathDeck

/// 同步驱动的调度器：捕获 work item，由测试手动触发「阈值到点」。
@MainActor
private final class ManualScheduler {
    private(set) var pending: [DispatchWorkItem] = []

    func schedule(_ delay: TimeInterval, _ item: DispatchWorkItem) {
        pending.append(item)
    }

    /// 模拟计时到点：执行未取消的 item。
    func fire() {
        let items = pending
        pending = []
        for item in items where !item.isCancelled {
            item.perform()
        }
    }
}

@MainActor
struct ShortcutOverlayHoldTrackerTests {
    private func makeTracker() -> (ShortcutOverlayHoldTracker, ManualScheduler) {
        let scheduler = ManualScheduler()
        let tracker = ShortcutOverlayHoldTracker { delay, item in
            scheduler.schedule(delay, item)
        }
        return (tracker, scheduler)
    }

    @Test
    func pureCommandHoldShowsAfterDelay() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        #expect(!tracker.isVisible)
        scheduler.fire()
        #expect(tracker.isVisible)
    }

    @Test
    func releaseHidesImmediately() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        tracker.flagsChanged(commandOnly: false, commandHeld: false)
        #expect(!tracker.isVisible)
    }

    /// 阈值内敲键（⌘C 这类快速组合）：不显示，且松开前不再重新计时。
    @Test
    func keyDownBeforeDelayCancelsUntilRelease() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        tracker.keyDown(commandHeld: true)
        scheduler.fire()
        #expect(!tracker.isVisible)
        // 仍按着 ⌘ 再次触发 flagsChanged（如 shift 短暂加入又离开）→ 不得重新计时
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        #expect(scheduler.pending.isEmpty)
        // 松开 ⌘ 后重按 → 恢复正常计时
        tracker.flagsChanged(commandOnly: false, commandHeld: false)
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        #expect(tracker.isVisible)
    }

    /// 显示期间执行组合键：保持显示（shift 加入 + 字符键都不隐藏）。
    @Test
    func executingShortcutWhileVisibleKeepsOverlay() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        tracker.flagsChanged(commandOnly: false, commandHeld: true)  // ⇧ 加入
        tracker.keyDown(commandHeld: true)                           // 按下 B
        #expect(tracker.isVisible)
        tracker.flagsChanged(commandOnly: false, commandHeld: false)
        #expect(!tracker.isVisible)
    }

    /// ⌘+点击多选：立即隐藏并取消本轮。
    @Test
    func mouseDownHidesAndCancelsHold() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        #expect(tracker.isVisible)
        tracker.mouseDown(commandHeld: true)
        #expect(!tracker.isVisible)
        // 继续按住 ⌘ → 本轮不再显示
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        #expect(scheduler.pending.isEmpty)
    }

    /// 阈值内鼠标按下：待显示取消。
    @Test
    func mouseDownBeforeDelayCancelsPendingShow() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        tracker.mouseDown(commandHeld: true)
        scheduler.fire()
        #expect(!tracker.isVisible)
    }

    /// 其他修饰键先于计时到点加入：取消待显示，已显示才保持。
    @Test
    func extraModifierBeforeShowCancelsPending() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        tracker.flagsChanged(commandOnly: false, commandHeld: true)  // ⇧ 加入
        scheduler.fire()
        #expect(!tracker.isVisible)
    }

    /// 窗口失焦复位：隐藏 + 允许下一轮。
    @Test
    func resetHidesAndReArms() {
        let (tracker, scheduler) = makeTracker()
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        tracker.reset()
        #expect(!tracker.isVisible)
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        #expect(tracker.isVisible)
    }

    @Test
    func visibilityCallbackFiresOnChangesOnly() {
        let (tracker, scheduler) = makeTracker()
        var events: [Bool] = []
        tracker.onVisibilityChange = { events.append($0) }
        tracker.flagsChanged(commandOnly: true, commandHeld: true)
        scheduler.fire()
        tracker.reset()
        tracker.reset()
        #expect(events == [true, false])
    }
}
