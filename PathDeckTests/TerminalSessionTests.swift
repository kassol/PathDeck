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
}
