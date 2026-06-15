import AppKit

protocol TerminalEngine: AnyObject {
    var onCwdChange: ((UUID, URL) -> Void)? { get set }
    func createSession(cwd: URL) -> UUID
    func closeSession(_ id: UUID)
    func terminalView(for id: UUID) -> NSView
    func writeText(_ text: String, to id: UUID)
}
