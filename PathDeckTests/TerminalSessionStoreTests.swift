import Testing
import Foundation
@testable import PathDeck

@MainActor
struct TerminalSessionStoreTests {
    private func makeStore(count: Int = 3) -> (TerminalSessionStore, [UUID]) {
        let store = TerminalSessionStore()
        let home = FileManager.default.homeDirectoryForCurrentUser
        var ids: [UUID] = []
        for i in 0..<count {
            let id = UUID()
            store.append(TerminalSession(id: id, title: "Terminal \(i + 1)", cwd: home))
            ids.append(id)
        }
        return (store, ids)
    }

    @Test
    func appendAndContains() {
        let (store, ids) = makeStore()
        #expect(store.sessions.count == 3)
        #expect(store.contains(ids[0]))
        #expect(store.allIDs == Set(ids))
    }

    @Test
    func removeReturnsIndex() {
        let (store, ids) = makeStore()
        #expect(store.remove(ids[1]) == 1)
        #expect(store.sessions.count == 2)
        #expect(store.contains(ids[1]) == false)
    }

    @Test
    func removeUnknownReturnsNil() {
        let (store, _) = makeStore()
        #expect(store.remove(UUID()) == nil)
    }

    @Test
    func renameWithoutManualFlag() {
        let (store, ids) = makeStore()
        store.rename(ids[0], to: "Custom", manual: false)
        #expect(store.session(ids[0])?.title == "Custom")
        #expect(store.session(ids[0])?.isManuallyRenamed == false)
    }

    @Test
    func renameWithManualFlag() {
        let (store, ids) = makeStore()
        store.rename(ids[0], to: "Custom", manual: true)
        #expect(store.session(ids[0])?.isManuallyRenamed == true)
    }

    @Test
    func emptyManualRenameClearsFlagAndRestoresCwdName() {
        let (store, ids) = makeStore()
        store.rename(ids[0], to: "Custom", manual: true)
        store.rename(ids[0], to: "", manual: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(store.session(ids[0])?.isManuallyRenamed == false)
        #expect(store.session(ids[0])?.title == home.lastPathComponent)
    }

    @Test
    func updateCwd() {
        let (store, ids) = makeStore()
        let url = URL(fileURLWithPath: "/tmp")
        store.updateCwd(ids[0], to: url)
        #expect(store.session(ids[0])?.currentCwd == url)
    }

    @Test
    func moveForward() {
        let (store, ids) = makeStore()
        let changed = store.move(source: ids[0], to: 2)
        #expect(changed == true)
        #expect(store.sessions.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    @Test
    func moveBackward() {
        let (store, ids) = makeStore()
        let changed = store.move(source: ids[2], to: 0)
        #expect(changed == true)
        #expect(store.sessions.map(\.id) == [ids[2], ids[0], ids[1]])
    }

    @Test
    func moveSameSlotNoChange() {
        let (store, ids) = makeStore()
        let changed = store.move(source: ids[1], to: 1)
        #expect(changed == false)
    }

    @Test
    func moveUnknownSourceFails() {
        let (store, _) = makeStore()
        let changed = store.move(source: UUID(), to: 0)
        #expect(changed == false)
    }
}
