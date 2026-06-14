import SwiftUI

struct TerminalPanelView: NSViewRepresentable {
    let activeSessionID: UUID?
    let sessionIDs: Set<UUID>
    let engine: any TerminalEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        let previousID = coordinator.lastActiveSessionID
        let changed = activeSessionID != previousID
        coordinator.lastActiveSessionID = activeSessionID

        // Remove subviews for closed sessions
        for (objID, sessionID) in coordinator.viewToSession where !sessionIDs.contains(sessionID) {
            if let view = container.subviews.first(where: { ObjectIdentifier($0) == objID }) {
                view.removeFromSuperview()
            }
            coordinator.viewToSession.removeValue(forKey: objID)
        }

        guard changed else { return }

        // Hide only the previous active view
        if let prevID = previousID,
           let prevObjID = coordinator.viewToSession.first(where: { $0.value == prevID })?.key,
           let prevView = container.subviews.first(where: { ObjectIdentifier($0) == prevObjID }) {
            prevView.isHidden = true
        }

        guard let id = activeSessionID else { return }
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
        var viewToSession: [ObjectIdentifier: UUID] = [:]
    }
}
