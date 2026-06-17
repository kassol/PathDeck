import SwiftUI

struct TerminalPanelView: NSViewRepresentable {
    let activeSessionID: UUID?
    let sessionIDs: Set<UUID>
    let engine: any TerminalEngine
    var isActive: Bool = true

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        let previousID = coordinator.lastActiveSessionID
        let sessionChanged = activeSessionID != previousID
        let becameActive = isActive && !coordinator.lastIsActive
        let becameInactive = !isActive && coordinator.lastIsActive
        coordinator.lastActiveSessionID = activeSessionID
        coordinator.lastIsActive = isActive

        // Remove subviews for closed sessions
        for (objID, sessionID) in coordinator.viewToSession where !sessionIDs.contains(sessionID) {
            if let view = container.subviews.first(where: { ObjectIdentifier($0) == objID }) {
                view.removeFromSuperview()
            }
            coordinator.viewToSession.removeValue(forKey: objID)
        }

        if becameInactive {
            if let window = container.window, let responder = window.firstResponder,
               let responderView = responder as? NSView, responderView.isDescendant(of: container) {
                window.makeFirstResponder(nil)
            }
            return
        }

        guard sessionChanged || becameActive else { return }

        if sessionChanged {
            if let prevID = previousID,
               let prevObjID = coordinator.viewToSession.first(where: { $0.value == prevID })?.key,
               let prevView = container.subviews.first(where: { ObjectIdentifier($0) == prevObjID }) {
                prevView.isHidden = true
            }
        }

        guard isActive, let id = activeSessionID else { return }
        let termView = engine.terminalView(for: id)
        if termView.superview !== container {
            container.addSubview(termView)
            termView.frame = container.bounds
            termView.autoresizingMask = [.width, .height]
            coordinator.viewToSession[ObjectIdentifier(termView)] = id
        }
        termView.isHidden = false
        container.window?.makeFirstResponder(termView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastActiveSessionID: UUID?
        var lastIsActive: Bool = true
        var viewToSession: [ObjectIdentifier: UUID] = [:]
    }
}
