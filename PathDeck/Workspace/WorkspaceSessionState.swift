import Foundation

/// 单个 NSWindow workspace 的持久化快照。
struct WorkspaceWindowState: Codable {
    let cwd: String
    let isCustomTitle: Bool
    let customTitle: String?
    let mode: String
    let isTerminalVisible: Bool
    let anchorCwdPath: String?
    let terminalStates: [TerminalTabState]
    let activeTerminalIndex: Int?
}

/// 一个 NSWindow tab group（含若干合入同一 title bar 的 window）。
/// 单个独立 window 也对应一个 group（windows.count == 1）。
struct WorkspaceGroupState: Codable {
    let windows: [WorkspaceWindowState]
    /// group 内 key tab 的 index；nil = 取首项。
    let keyWindowIndex: Int?
}

/// 一次会话的全部 workspace window 状态。
/// 保留真实的 NSWindow tab grouping：每个 group 一个条目，跨 group 是独立 window。
struct WorkspaceSessionState: Codable {
    let groups: [WorkspaceGroupState]
    /// app key window 所在的 group 索引；nil = 取首项。
    let keyGroupIndex: Int?
}
