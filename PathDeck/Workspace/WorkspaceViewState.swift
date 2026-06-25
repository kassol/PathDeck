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

    init(mode: WorkspaceMode = .finderFirst,
         isTerminalVisible: Bool = false,
         activeTerminalID: UUID? = nil,
         terminalAnchorCwd: URL? = nil,
         isCustomTitle: Bool = false,
         customTitle: String? = nil) {
        self.mode = mode
        self.isTerminalVisible = isTerminalVisible
        self.activeTerminalID = activeTerminalID
        self.terminalAnchorCwd = terminalAnchorCwd
        self.isCustomTitle = isCustomTitle
        self.customTitle = customTitle
    }
}
