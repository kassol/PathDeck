import AppKit

final class GhosttyTerminalEngine: TerminalEngine {
    private weak var currentSurfaceView: GhosttySurfaceView?

    func makeTerminalView(cwd: URL) -> NSView {
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = cwd
        currentSurfaceView = view
        return view
    }

    func writeText(_ text: String) {
        currentSurfaceView?.insertText(text)
    }
}
