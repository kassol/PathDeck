import AppKit

protocol TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView
    func writeText(_ text: String)
}
