import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspacePersistenceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "WorkspacePersistenceTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    private func makeWindowState(cwd: String, title: String? = nil) -> WorkspaceWindowState {
        WorkspaceWindowState(
            cwd: cwd,
            isCustomTitle: title != nil,
            customTitle: title,
            mode: WorkspaceMode.finderFirst.rawValue,
            isTerminalVisible: false,
            anchorCwdPath: nil,
            terminalStates: [],
            activeTerminalIndex: nil
        )
    }

    @Test
    func loadEmptyReturnsNil() {
        let persistence = WorkspacePersistence(defaults: makeDefaults())
        #expect(persistence.loadSessionState() == nil)
    }

    @Test
    func groupFrameRoundTripsAndDefaultsToNil() {
        let suite = makeDefaults()
        let persistence = WorkspacePersistence(defaults: suite)
        let state = WorkspaceSessionState(
            groups: [
                WorkspaceGroupState(windows: [makeWindowState(cwd: "/tmp")],
                                    keyWindowIndex: 0,
                                    frame: "{{100, 200}, {1280, 800}}"),
                WorkspaceGroupState(windows: [makeWindowState(cwd: "/Users/a")],
                                    keyWindowIndex: 0)
            ],
            keyGroupIndex: 0
        )
        persistence.persist(state)

        let reloaded = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(reloaded?.groups[0].frame == "{{100, 200}, {1280, 800}}")
        #expect(reloaded?.groups[1].frame == nil)
    }

    @Test
    func roundTripWithMultipleGroups() {
        let suite = makeDefaults()
        let persistence = WorkspacePersistence(defaults: suite)
        let state = WorkspaceSessionState(
            groups: [
                WorkspaceGroupState(windows: [
                    makeWindowState(cwd: "/Users/a"),
                    makeWindowState(cwd: "/Users/b")
                ], keyWindowIndex: 1),
                WorkspaceGroupState(windows: [
                    makeWindowState(cwd: "/tmp", title: "Sandbox")
                ], keyWindowIndex: 0)
            ],
            keyGroupIndex: 0
        )
        persistence.persist(state)

        let reloaded = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(reloaded?.groups.count == 2)
        #expect(reloaded?.groups[0].windows.count == 2)
        #expect(reloaded?.groups[0].windows[1].cwd == "/Users/b")
        #expect(reloaded?.groups[0].keyWindowIndex == 1)
        #expect(reloaded?.groups[1].windows.first?.customTitle == "Sandbox")
        #expect(reloaded?.keyGroupIndex == 0)
    }

    /// S36 新增的 sidebar/preview pane 字段：roundtrip 保值，旧快照（无字段）解码为 nil。
    @Test
    func sidebarAndPreviewPaneFieldsRoundTripAndTolerateLegacySnapshots() throws {
        let suite = makeDefaults()
        let persistence = WorkspacePersistence(defaults: suite)
        var window = makeWindowState(cwd: "/tmp")
        window.isSidebarVisible = false
        window.isPreviewPaneVisible = true
        persistence.persist(WorkspaceSessionState(
            groups: [WorkspaceGroupState(windows: [window], keyWindowIndex: 0)],
            keyGroupIndex: 0
        ))
        let reloaded = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(reloaded?.groups.first?.windows.first?.isSidebarVisible == false)
        #expect(reloaded?.groups.first?.windows.first?.isPreviewPaneVisible == true)

        // S36 之前的快照没有这两个 key，必须能解码且为 nil（restore 侧回退默认值）。
        let legacySnapshot = """
        {"groups":[{"windows":[{"cwd":"/old","isCustomTitle":false,"mode":"finderFirst",
        "isTerminalVisible":false,"terminalStates":[]}],"keyWindowIndex":0}],"keyGroupIndex":0}
        """.data(using: .utf8)!
        suite.set(legacySnapshot, forKey: WorkspacePersistence.sessionStateKey)
        let legacy = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(legacy?.groups.first?.windows.first?.cwd == "/old")
        #expect(legacy?.groups.first?.windows.first?.isSidebarVisible == nil)
        #expect(legacy?.groups.first?.windows.first?.isPreviewPaneVisible == nil)
    }

    @Test
    func migratesLegacyFlatListToSingleGroup() throws {
        let suite = makeDefaults()
        let legacyJSON: [[String: Any]] = [
            [
                "id": "AAAA-1",
                "title": "First",
                "isCustomTitle": false,
                "mode": "finderFirst",
                "isTerminalVisible": true,
                "currentURLPath": "/Users/x",
                "terminalStates": [
                    ["title": "T1", "cwdPath": "/Users/x", "isManuallyRenamed": false]
                ],
                "activeTerminalIndex": 0
            ],
            [
                "id": "AAAA-2",
                "title": "Custom",
                "isCustomTitle": true,
                "mode": "terminalFirst",
                "isTerminalVisible": true,
                "currentURLPath": "/tmp",
                "anchorCwdPath": "/tmp",
                "terminalStates": [],
                "activeTerminalIndex": NSNull()
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON, options: [])
        suite.set(data, forKey: WorkspacePersistence.legacyFileTabsKey)
        suite.set("AAAA-2", forKey: WorkspacePersistence.legacyActiveTabKey)

        let state = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(state?.groups.count == 1)
        #expect(state?.keyGroupIndex == 0)
        #expect(state?.groups.first?.windows.count == 2)
        #expect(state?.groups.first?.windows[0].cwd == "/Users/x")
        #expect(state?.groups.first?.windows[0].terminalStates.count == 1)
        #expect(state?.groups.first?.windows[1].cwd == "/tmp")
        #expect(state?.groups.first?.windows[1].isCustomTitle == true)
        #expect(state?.groups.first?.windows[1].customTitle == "Custom")
        #expect(state?.groups.first?.keyWindowIndex == 1)

        #expect(suite.data(forKey: WorkspacePersistence.legacyFileTabsKey) == nil)
        #expect(suite.string(forKey: WorkspacePersistence.legacyActiveTabKey) == nil)
        #expect(suite.data(forKey: WorkspacePersistence.sessionStateKey) != nil)
    }

    @Test
    func newKeyTakesPrecedenceOverLegacy() throws {
        let suite = makeDefaults()
        let newState = WorkspaceSessionState(
            groups: [
                WorkspaceGroupState(windows: [makeWindowState(cwd: "/new")], keyWindowIndex: 0)
            ],
            keyGroupIndex: 0
        )
        let newData = try JSONEncoder().encode(newState)
        suite.set(newData, forKey: WorkspacePersistence.sessionStateKey)

        let legacyJSON: [[String: Any]] = [[
            "id": "X", "title": "Legacy", "isCustomTitle": false, "mode": "finderFirst",
            "isTerminalVisible": false, "currentURLPath": "/legacy",
            "terminalStates": [], "activeTerminalIndex": NSNull()
        ]]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON, options: [])
        suite.set(legacyData, forKey: WorkspacePersistence.legacyFileTabsKey)

        let state = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(state?.groups.first?.windows.first?.cwd == "/new")
        #expect(suite.data(forKey: WorkspacePersistence.legacyFileTabsKey) != nil)
    }

    @Test
    func corruptedLegacyReturnsNil() {
        let suite = makeDefaults()
        suite.set("not json".data(using: .utf8), forKey: WorkspacePersistence.legacyFileTabsKey)
        let state = WorkspacePersistence(defaults: suite).loadSessionState()
        #expect(state == nil)
    }
}
