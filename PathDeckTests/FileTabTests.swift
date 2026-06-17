import Testing
import Foundation
@testable import PathDeck

struct FileTabTests {
    @Test func fileTabStateRoundTrip() throws {
        let state = FileTabState(
            id: UUID().uuidString,
            title: "Projects",
            isCustomTitle: false,
            mode: "finderFirst",
            isTerminalVisible: false,
            currentURLPath: "/Users/test/Projects",
            anchorCwdPath: "/Users/test/Projects",
            terminalStates: [
                TerminalTabState(title: "Terminal", cwdPath: "/Users/test/Projects"),
                TerminalTabState(title: "Terminal 2", cwdPath: "/tmp"),
            ],
            activeTerminalIndex: nil
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(FileTabState.self, from: data)
        #expect(decoded.title == "Projects")
        #expect(decoded.currentURLPath == "/Users/test/Projects")
        #expect(decoded.anchorCwdPath == "/Users/test/Projects")
        #expect(decoded.terminalStates.count == 2)
        #expect(decoded.terminalStates[0].title == "Terminal")
        #expect(decoded.terminalStates[1].cwdPath == "/tmp")
    }

    @Test func fileTabStateArrayRoundTrip() throws {
        let states = [
            FileTabState(
                id: UUID().uuidString,
                title: "Tab1",
                isCustomTitle: false,
                mode: "finderFirst",
                isTerminalVisible: false,
                currentURLPath: "/tmp",
                anchorCwdPath: nil,
                terminalStates: [],
                activeTerminalIndex: nil
            ),
            FileTabState(
                id: UUID().uuidString,
                title: "Tab2",
                isCustomTitle: true,
                mode: "terminalFirst",
                isTerminalVisible: true,
                currentURLPath: "/Users/test",
                anchorCwdPath: "/Users/test",
                terminalStates: [TerminalTabState(title: "T", cwdPath: "/Users/test")],
                activeTerminalIndex: nil
            ),
        ]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([FileTabState].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].anchorCwdPath == nil)
        #expect(decoded[1].anchorCwdPath == "/Users/test")
    }

    @Test func fileTabDefaultInit() {
        let tab = FileTab(title: "Test")
        #expect(tab.mode == .finderFirst)
        #expect(tab.isTerminalVisible == false)
        #expect(tab.terminalAnchorCwd == nil)
        #expect(tab.terminalSessionIDs.isEmpty)
        #expect(tab.activeTerminalID == nil)
    }
}
