import Testing
import Foundation
@testable import PathDeck

struct TerminalSessionTests {
    @Test func createSessionIncrementsCount() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id1 = engine.createSession(cwd: cwd)
        let id2 = engine.createSession(cwd: cwd)
        #expect(id1 != id2)
    }

    @Test func closeNonActivePreservesOthers() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id1 = engine.createSession(cwd: cwd)
        let id2 = engine.createSession(cwd: cwd)

        var sessions = [
            TerminalSession(id: id1, title: "T1", cwd: cwd),
            TerminalSession(id: id2, title: "T2", cwd: cwd),
        ]
        let activeID: UUID? = id2

        engine.closeSession(id1)
        sessions.removeAll { $0.id == id1 }

        #expect(sessions.count == 1)
        #expect(activeID == id2)
    }

    @Test func closeActiveSelectsAdjacent() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id1 = engine.createSession(cwd: cwd)
        let id2 = engine.createSession(cwd: cwd)

        var sessions = [
            TerminalSession(id: id1, title: "T1", cwd: cwd),
            TerminalSession(id: id2, title: "T2", cwd: cwd),
        ]
        var activeID: UUID? = id2

        engine.closeSession(id2)
        sessions.removeAll { $0.id == id2 }
        if activeID == id2 {
            activeID = sessions.last?.id
        }

        #expect(sessions.count == 1)
        #expect(activeID == id1)
    }

    @Test func closeLastResultsInEmpty() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id1 = engine.createSession(cwd: cwd)

        var sessions = [TerminalSession(id: id1, title: "T1", cwd: cwd)]
        var activeID: UUID? = id1

        engine.closeSession(id1)
        sessions.removeAll { $0.id == id1 }
        if activeID == id1 {
            activeID = sessions.last?.id
        }

        #expect(sessions.isEmpty)
        #expect(activeID == nil)
    }

    @Test func writeTextBeforeViewDoesNotCrash() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id = engine.createSession(cwd: cwd)
        engine.writeText("hello", to: id)
    }

    @Test func writeTextToUnknownSessionDoesNotCrash() {
        let engine = GhosttyTerminalEngine()
        engine.writeText("hello", to: UUID())
    }

    @Test func closeSessionClearsPendingText() {
        let engine = GhosttyTerminalEngine()
        let cwd = URL(fileURLWithPath: "/tmp")
        let id = engine.createSession(cwd: cwd)
        engine.writeText("queued text", to: id)
        engine.closeSession(id)
        engine.writeText("after close", to: id)
    }

    @Test func exitedSessionIDsReturnsAllExited() {
        let a = UUID(), b = UUID(), c = UUID()
        let result = GhosttyTerminalEngine.exitedSessionIDs(
            from: [(id: a, exited: true), (id: b, exited: false), (id: c, exited: true)]
        )
        #expect(result == [a, c])
    }

    @Test func onPendingDroppedFiresOnOverflow() {
        let engine = GhosttyTerminalEngine()
        let id = engine.createSession(cwd: URL(fileURLWithPath: "/tmp"))
        var reason: PendingDropReason?
        var droppedCount = 0
        engine.onPendingDropped = { _, count, r in
            reason = r
            droppedCount = count
        }
        for i in 0..<70 {
            engine.writeText("text\(i)", to: id)
        }
        #expect(reason == .overflow)
        #expect(droppedCount > 0)
    }

    @Test func closeSessionDropsPendingAndCancelsTimeout() {
        let engine = GhosttyTerminalEngine()
        let id = engine.createSession(cwd: URL(fileURLWithPath: "/tmp"))
        engine.writeText("queued", to: id)
        #expect(engine.pendingBuffers[id] != nil)
        #expect(engine.pendingTimeoutTokens[id] != nil)
        engine.closeSession(id)
        #expect(engine.pendingBuffers[id] == nil)
        #expect(engine.pendingTimeoutTokens[id] == nil)
    }

    @Test func terminalTabStateCodable() throws {
        let state = TerminalTabState(title: "Terminal 2", cwdPath: "/Users/test/project")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TerminalTabState.self, from: data)
        #expect(decoded.title == "Terminal 2")
        #expect(decoded.cwdPath == "/Users/test/project")
    }

    @Test func terminalTabStateArrayRoundTrip() throws {
        let states = [
            TerminalTabState(title: "Terminal", cwdPath: "/tmp"),
            TerminalTabState(title: "Terminal 2", cwdPath: "/Users/test"),
        ]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([TerminalTabState].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].title == "Terminal")
        #expect(decoded[1].cwdPath == "/Users/test")
    }
}
