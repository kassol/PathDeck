import AppKit

final class GhosttyTerminalEngine: TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView {
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = cwd
        return view
    }
}
