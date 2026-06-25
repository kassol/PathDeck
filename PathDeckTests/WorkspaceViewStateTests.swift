import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspaceViewStateTests {
    @Test
    func defaultsAreFinderFirstHiddenTerminal() {
        let s = WorkspaceViewState()
        #expect(s.mode == .finderFirst)
        #expect(s.isTerminalVisible == false)
        #expect(s.activeTerminalID == nil)
        #expect(s.terminalAnchorCwd == nil)
        #expect(s.isCustomTitle == false)
        #expect(s.customTitle == nil)
    }

    @Test
    func acceptsInitOverrides() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp")
        let s = WorkspaceViewState(
            mode: .terminalFirst,
            isTerminalVisible: true,
            activeTerminalID: id,
            terminalAnchorCwd: url,
            isCustomTitle: true,
            customTitle: "Custom"
        )
        #expect(s.mode == .terminalFirst)
        #expect(s.isTerminalVisible == true)
        #expect(s.activeTerminalID == id)
        #expect(s.terminalAnchorCwd == url)
        #expect(s.isCustomTitle == true)
        #expect(s.customTitle == "Custom")
    }
}
