import AppKit
import GhosttyKit

final class GhosttyTerminalEngine: TerminalEngine {
    var onSessionClose: ((UUID) -> Void)?
    var onCwdChange: ((UUID, URL) -> Void)?

    private let engineID = ObjectIdentifier(UUID.self as Any.Type)
    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]
    private var observer: NSObjectProtocol?
    private let registrationID: ObjectIdentifier

    init() {
        let sentinel = NSObject()
        registrationID = ObjectIdentifier(sentinel)

        observer = NotificationCenter.default.addObserver(
            forName: .ghosttySurfaceDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSurfaceClose()
        }

        GhosttyApp.shared.registerPwdHandler(id: registrationID) { [weak self] surface, pwd in
            self?.handlePwdChange(surface: surface, pwd: pwd)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        GhosttyApp.shared.unregisterPwdHandler(id: registrationID)
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

    private func handlePwdChange(surface: ghostty_surface_t, pwd: String) {
        for (id, view) in surfaceViews {
            guard view.surface == surface else { continue }
            let url: URL
            if pwd.hasPrefix("file://") {
                guard let parsed = URL(string: pwd) else { return }
                url = URL(fileURLWithPath: parsed.path).standardizedFileURL
            } else if let decoded = pwd.removingPercentEncoding {
                url = URL(fileURLWithPath: decoded).standardizedFileURL
            } else {
                url = URL(fileURLWithPath: pwd).standardizedFileURL
            }
            onCwdChange?(id, url)
            return
        }
    }
}
