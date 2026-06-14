import AppKit

protocol TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView
}
