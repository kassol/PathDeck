import AppKit
import Foundation
import Observation

/// Close History（关闭历史）：⌘⇧T 可逆序重开的关闭记录栈（S37）。
/// 仅进程内、栈式、上限 capacity（超限淘汰最旧）；仅用户关闭手势入栈，shell exit 不入。
/// 终端栈挂 WorkspaceController（per-window），窗口栈挂 WorkspaceManager（全局）。
/// @Observable：菜单 disabled 与 Palette isEnabled 依赖 isEmpty。
@Observable
final class CloseHistoryStack<Element> {
    private(set) var records: [Element] = []
    let capacity: Int

    init(capacity: Int = 10) {
        self.capacity = capacity
    }

    func push(_ element: Element) {
        records.append(element)
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
    }

    func pop() -> Element? {
        records.isEmpty ? nil : records.removeLast()
    }

    var isEmpty: Bool { records.isEmpty }
}

/// 关闭的终端 session 快照：重开时恢复 cwd、标题与原 tab 位置（PTY 状态不可恢复）。
struct ClosedTerminalRecord {
    let title: String
    let cwd: URL
    let isManuallyRenamed: Bool
    let index: Int
}

/// 关闭的 workspace 窗口快照：复用 Session State 的窗口快照结构整窗重建。
/// hostGroup 弱持有关闭时所属的 tab 组（windowWillClose 时窗口已脱组，组关系取自
/// controller 存活期缓存）；重开时组内仍有存活窗口即 tab 回原组，否则按 frame
/// 恢复为独立窗口。
struct ClosedWindowRecord {
    let state: WorkspaceWindowState
    let frame: NSRect?
    weak var hostGroup: NSWindowTabGroup?
}
