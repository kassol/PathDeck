import AppKit

final class GhosttyTerminalEngine: TerminalEngine {
    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]

    func createSession(cwd: URL) -> UUID {
        let id = UUID()
        sessionCwds[id] = cwd
        return id
    }

    func closeSession(_ id: UUID) {
        surfaceViews.removeValue(forKey: id)
        sessionCwds.removeValue(forKey: id)
    }

    func terminalView(for id: UUID) -> NSView {
        if let existing = surfaceViews[id] { return existing }
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = sessionCwds[id]
        surfaceViews[id] = view
        return view
    }

    func writeText(_ text: String, to id: UUID) {
        surfaceViews[id]?.insertText(text)
    }
}
