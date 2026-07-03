import Foundation
import Observation

/// 单个 NSWindow workspace 的视图状态（@Observable）。
/// 每个 WorkspaceController 持有独立一份；切换 NSWindow tab 即切换 view state。
@Observable
final class WorkspaceViewState {
    var mode: WorkspaceMode
    var isTerminalVisible: Bool
    var activeTerminalID: UUID?
    var terminalAnchorCwd: URL?
    var isCustomTitle: Bool
    var customTitle: String?
    /// 左 Sidebar / 右 Preview Pane 显隐，per-window Session State（S36 从全局 Preference 迁入）。
    var isSidebarVisible: Bool
    var isPreviewPaneVisible: Bool
    /// 长按 ⌘ 快捷键浮窗；瞬态，不持久化。
    var isShortcutOverlayVisible: Bool = false

    init(mode: WorkspaceMode = .finderFirst,
         isTerminalVisible: Bool = false,
         activeTerminalID: UUID? = nil,
         terminalAnchorCwd: URL? = nil,
         isCustomTitle: Bool = false,
         customTitle: String? = nil,
         isSidebarVisible: Bool = true,
         isPreviewPaneVisible: Bool = true) {
        self.mode = mode
        self.isTerminalVisible = isTerminalVisible
        self.activeTerminalID = activeTerminalID
        self.terminalAnchorCwd = terminalAnchorCwd
        self.isCustomTitle = isCustomTitle
        self.customTitle = customTitle
        self.isSidebarVisible = isSidebarVisible
        self.isPreviewPaneVisible = isPreviewPaneVisible
    }
}
