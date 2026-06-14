import SwiftUI

struct TerminalPanelView: NSViewRepresentable {
    let cwd: URL
    let engine: any TerminalEngine

    func makeNSView(context: Context) -> NSView {
        engine.makeTerminalView(cwd: cwd)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
