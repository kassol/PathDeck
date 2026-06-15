import AppKit
import GhosttyKit

final class GhosttyTerminalEngine: TerminalEngine {
    var onSessionClose: ((UUID) -> Void)?
    var onCwdChange: ((UUID, URL) -> Void)?

    private let engineID = ObjectIdentifier(UUID.self as Any.Type)
    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]
    private var pendingTexts: [UUID: [String]] = [:]
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
        pendingTexts.removeValue(forKey: id)
    }

    func terminalView(for id: UUID) -> NSView {
        if let existing = surfaceViews[id] { return existing }
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = sessionCwds[id]
        view.onSurfaceReady = { [weak self] in
            self?.flushPendingTexts(for: id)
        }
        surfaceViews[id] = view
        return view
    }

    func writeText(_ text: String, to id: UUID) {
        if let view = surfaceViews[id], view.surface != nil {
            view.insertText(text)
        } else {
            pendingTexts[id, default: []].append(text)
            schedulePendingTimeout(for: id)
        }
    }

    private func flushPendingTexts(for id: UUID) {
        guard let texts = pendingTexts.removeValue(forKey: id),
              let view = surfaceViews[id] else { return }
        for text in texts {
            view.insertText(text)
        }
    }

    private func schedulePendingTimeout(for id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let texts = self.pendingTexts.removeValue(forKey: id) else { return }
            NSLog("[PathDeck] writeText timeout: dropped %d pending text(s) for session %@", texts.count, id.uuidString)
        }
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
