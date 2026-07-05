import Testing
import Foundation
import AppKit
@testable import PathDeck

/// ⌘T 双开回归（2026-07-05，ADR-0002 补充）：local monitor 返回 nil 拦不住同一次
/// sendEvent 内的菜单 key-equivalent 处理，monitor 与菜单曾各执行一次。
/// 管线级回归：test host 即真 PathDeck app（全局 monitor 已装、SwiftUI 菜单已建），
/// 投递真 ⌘T keyDown 并用 nextEvent → sendEvent 泵复刻 NSApplication.run 派发层级
/// （实验证实 monitor 恰在 sendEvent 内触发），用派发遥测断言合计恰好执行一次。
/// keyWindow 在 xcodebuild 会话不可得，故观测执行路径数而非 tab 数。
@Suite(.serialized)
@MainActor
struct CommandTSingleFireTests {
    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05),
                                       inMode: .default, dequeue: true) {
                NSApp.sendEvent(e)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @Test
    func postedCommandTFiresExactlyOneDispatchPath() throws {
        CommandDispatchTelemetry.reset()

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17
        ))
        NSApp.postEvent(event, atStart: false)
        pump(0.8)

        let monitorFires = CommandDispatchTelemetry.monitorDispatchCount
        let menuFires = CommandDispatchTelemetry.menuRunIDs
        #expect(monitorFires + menuFires.count == 1,
                "一次 ⌘T 应只执行一条派发路径，实际 monitor=\(monitorFires) menu=\(menuFires)")
    }

    // MARK: - menuShouldRun 守卫规则矩阵

    private func keyDownEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "t",
            charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17
        )!
    }

    private func mouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        )!
    }

    /// monitor 型命令：键盘触发的菜单执行是重复派发，跳过；点击/无事件照常。
    @Test
    func monitorCommandsSkipKeyboardTriggeredMenuRuns() throws {
        let newTab = try #require(ShortcutRegistry.spec("newTab"))
        #expect(!CommandDispatch.menuShouldRun(newTab, triggeredBy: keyDownEvent()))
        #expect(CommandDispatch.menuShouldRun(newTab, triggeredBy: mouseEvent()))
        #expect(CommandDispatch.menuShouldRun(newTab, triggeredBy: nil))
        let selectTabN = try #require(ShortcutRegistry.spec("selectTabN"))
        #expect(!CommandDispatch.menuShouldRun(selectTabN, triggeredBy: keyDownEvent()))
    }

    /// menuOnly（responder-chain）命令：菜单是唯一派发路径，键盘触发必须放行。
    @Test
    func menuOnlyCommandsAlwaysRunFromMenu() throws {
        let copy = try #require(ShortcutRegistry.spec("copy"))
        #expect(CommandDispatch.menuShouldRun(copy, triggeredBy: keyDownEvent()))
        #expect(CommandDispatch.menuShouldRun(copy, triggeredBy: mouseEvent()))
    }
}
