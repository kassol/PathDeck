import AppKit

protocol TerminalEngine: AnyObject {
    var onCwdChange: ((UUID, URL) -> Void)? { get set }
    var onTitleChange: ((UUID, String) -> Void)? { get set }
    /// 终端输出中的 Path Link 被 ⌘Click（FR-BRIDGE-003）：业务层据此执行 Locate。
    var onPathLinkClick: ((UUID, PathLink) -> Void)? { get set }
    func createSession(cwd: URL) -> UUID
    func closeSession(_ id: UUID)
    func terminalView(for id: UUID) -> NSView
    func writeText(_ text: String, to id: UUID)
}
