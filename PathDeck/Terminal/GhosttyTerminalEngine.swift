import AppKit
import GhosttyKit

final class GhosttyTerminalEngine: TerminalEngine {
    var onSessionClose: ((UUID) -> Void)?

    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .ghosttySurfaceDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSurfaceClose()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

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

    private func handleSurfaceClose() {
        for (id, view) in surfaceViews {
            guard let surface = view.surface else { continue }
            if ghostty_surface_process_exited(surface) {
                onSessionClose?(id)
                return
            }
        }
    }
}
