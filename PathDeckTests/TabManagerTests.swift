import Testing
import Foundation
@testable import PathDeck

@MainActor
struct TabManagerTests {

    private func makeManager() -> TabManager {
        let suite = UserDefaults(suiteName: "TabManagerTests.\(UUID().uuidString)")!
        let tm = TabManager(defaults: suite)
        tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        return tm
    }

    private func makeBareManager() -> TabManager {
        let suite = UserDefaults(suiteName: "TabManagerTests.\(UUID().uuidString)")!
        return TabManager(defaults: suite)
    }

    // MARK: - Tab CRUD

    @Test func createTabAddsTabAndModel() {
        let tm = makeBareManager()
        let id = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        #expect(tm.fileTabs.count == 1)
        #expect(tm.activeFileTabID == id)
        #expect(tm.workspaceModels[id] != nil)
        #expect(tm.activeModel?.currentURL.standardizedFileURL == URL(fileURLWithPath: "/tmp").standardizedFileURL)
    }

    @Test func createMultipleTabs() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        #expect(tm.fileTabs.count == 2)
        #expect(tm.activeFileTabID == id2)
        #expect(tm.workspaceModels[id1] != nil)
        #expect(tm.workspaceModels[id2] != nil)
    }

    @Test func closeTabRemovesTabAndModel() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        tm.closeTab(id2)
        #expect(tm.fileTabs.count == 1)
        #expect(tm.workspaceModels[id2] == nil)
        #expect(tm.activeFileTabID == id1)
    }

    @Test func closeActiveTabSelectsNext() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        tm.switchTab(to: id1)
        tm.closeTab(id1)
        #expect(tm.activeFileTabID == id2)
    }

    @Test func switchTab() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        _ = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        tm.switchTab(to: id1)
        #expect(tm.activeFileTabID == id1)
    }

    @Test func switchToTabByIndex() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        _ = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        tm.switchToTabByIndex(0)
        #expect(tm.activeFileTabID == id1)
    }

    @Test func switchToNextTabWraps() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        _ = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        // Active is id2 (last created). Next wraps to id1.
        tm.switchToNextTab()
        #expect(tm.activeFileTabID == id1)
    }

    @Test func switchToPreviousTabWraps() {
        let tm = makeBareManager()
        _ = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        // Active is id2. Switch to first, then previous wraps to id2.
        tm.switchToTabByIndex(0)
        tm.switchToPreviousTab()
        #expect(tm.activeFileTabID == id2)
    }

    @Test func renameTab() {
        let tm = makeManager()
        let id = tm.activeFileTabID!
        tm.renameTab(id, to: "Custom Name")
        #expect(tm.fileTabs.first?.title == "Custom Name")
    }

    // MARK: - Terminal Session Management

    @Test func addTerminalSessionSetsAnchor() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)

        #expect(tm.activeTab?.terminalSessionIDs.count == 1)
        #expect(tm.activeTab?.activeTerminalID == session.id)
        #expect(tm.activeTab?.terminalAnchorCwd != nil)
        #expect(tm.terminalSessions[session.id] != nil)
    }

    @Test func addMultipleTerminalSessionsPreservesAnchor() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: tabID)
        let anchor = tm.activeTab?.terminalAnchorCwd
        tm.addTerminalSession(s2, to: tabID)

        #expect(tm.activeTab?.terminalSessionIDs.count == 2)
        #expect(tm.activeTab?.terminalAnchorCwd == anchor)
        #expect(tm.activeTab?.activeTerminalID == s2.id)
    }

    @Test func removeLastTerminalSessionClearsAnchor() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: tabID)
        #expect(tm.activeTab?.terminalAnchorCwd != nil)

        tm.removeTerminalSession(s1.id)
        #expect(tm.activeTab?.terminalSessionIDs.isEmpty == true)
        #expect(tm.activeTab?.terminalAnchorCwd == nil)
        #expect(tm.terminalSessions[s1.id] == nil)
    }

    @Test func removeNonLastTerminalSessionKeepsAnchor() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: tabID)
        tm.addTerminalSession(s2, to: tabID)

        tm.removeTerminalSession(s1.id)
        #expect(tm.activeTab?.terminalSessionIDs.count == 1)
        #expect(tm.activeTab?.terminalAnchorCwd != nil)
    }

    @Test func removeActiveTerminalSelectsLast() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: tabID)
        tm.addTerminalSession(s2, to: tabID)
        #expect(tm.activeTab?.activeTerminalID == s2.id)

        tm.removeTerminalSession(s2.id)
        #expect(tm.activeTab?.activeTerminalID == s1.id)
    }

    @Test func setActiveTerminal() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: tabID)
        tm.addTerminalSession(s2, to: tabID)
        tm.setActiveTerminal(s1.id)
        #expect(tm.activeTab?.activeTerminalID == s1.id)
    }

    @Test func closeTabRemovesTerminalSessions() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: id1)

        _ = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        tm.closeTab(id1)

        #expect(tm.terminalSessions[s1.id] == nil)
    }

    @Test func terminalSessionsIsolatedBetweenTabs() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: id1)

        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/Users"))
        tm.addTerminalSession(s2, to: id2)

        #expect(tm.activeTabSessions.count == 1)
        #expect(tm.activeTabSessions.first?.id == s2.id)

        tm.switchTab(to: id1)
        #expect(tm.activeTabSessions.count == 1)
        #expect(tm.activeTabSessions.first?.id == s1.id)
    }

    // MARK: - Global Preferences

    @Test func applySortUpdatesAllModels() {
        let tm = makeBareManager()
        _ = tm.createTab(at: FileManager.default.temporaryDirectory)
        _ = tm.createTab(at: FileManager.default.temporaryDirectory)
        tm.applySort(column: "date", ascending: false)

        for model in tm.workspaceModels.values {
            #expect(model.sortColumn == .date)
            #expect(model.sortAscending == false)
        }
    }

    @Test func toggleHiddenUpdatesAllModels() {
        let tm = makeBareManager()
        _ = tm.createTab(at: FileManager.default.temporaryDirectory)
        _ = tm.createTab(at: FileManager.default.temporaryDirectory)
        #expect(tm.showHidden == false)
        tm.toggleHidden()
        #expect(tm.showHidden == true)
        for model in tm.workspaceModels.values {
            #expect(model.showHidden == true)
        }
    }

    // MARK: - Terminal Visibility & Mode (per-tab)

    @Test func toggleTerminalVisibilityPerTab() {
        let tm = makeManager()
        #expect(tm.activeTabTerminalVisible == false)
        tm.toggleTerminalVisibility()
        #expect(tm.activeTabTerminalVisible == true)
        tm.toggleTerminalVisibility()
        #expect(tm.activeTabTerminalVisible == false)
    }

    @Test func toggleModePerTab() {
        let tm = makeManager()
        #expect(tm.activeTabMode == .finderFirst)
        tm.toggleActiveTabMode()
        #expect(tm.activeTabMode == .terminalFirst)
        #expect(tm.activeTabTerminalVisible == true)
        tm.toggleActiveTabMode()
        #expect(tm.activeTabMode == .finderFirst)
    }

    @Test func modeIsPerTabNotGlobal() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        _ = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        // Tab2 is active, switch to terminal-first
        tm.toggleActiveTabMode()
        #expect(tm.activeTabMode == .terminalFirst)
        // Switch to Tab1 — still finder-first
        tm.switchTab(to: id1)
        #expect(tm.activeTabMode == .finderFirst)
    }

    // MARK: - Tab Matching

    @Test func findTabByAnchorCwd() {
        let tm = makeBareManager()
        let id = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let session = TerminalSession(id: UUID(), title: "T", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: id)

        let found = tm.findTabByAnchorOrCwd(URL(fileURLWithPath: "/tmp"))
        #expect(found == id)
    }

    @Test func findTabByCurrentCwd() {
        let tm = makeBareManager()
        let id = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let found = tm.findTabByAnchorOrCwd(URL(fileURLWithPath: "/tmp"))
        #expect(found == id)
    }

    @Test func findTabNoMatch() {
        let tm = makeBareManager()
        _ = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let found = tm.findTabByAnchorOrCwd(URL(fileURLWithPath: "/nonexistent"))
        #expect(found == nil)
    }

    @Test func findTabByCurrentCwdWhenAnchorDiffers() {
        let tm = makeBareManager()
        let id = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let session = TerminalSession(id: UUID(), title: "T", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: id)
        // anchor is /tmp, navigate to /Users
        tm.workspaceModels[id]?.navigate(to: URL(fileURLWithPath: "/Users"))
        // search by /Users (currentURL) still finds the tab
        let found = tm.findTabByAnchorOrCwd(URL(fileURLWithPath: "/Users"))
        #expect(found == id)
        // anchor stays at /tmp
        #expect(tm.fileTabs.first?.terminalAnchorCwd?.standardizedFileURL == URL(fileURLWithPath: "/tmp").standardizedFileURL)
    }

    @Test func ownerTabIDFindsCorrectTab() {
        let tm = makeBareManager()
        let id1 = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
        let s1 = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(s1, to: id1)
        let id2 = tm.createTab(at: URL(fileURLWithPath: "/Users"))
        let s2 = TerminalSession(id: UUID(), title: "T2", cwd: URL(fileURLWithPath: "/Users"))
        tm.addTerminalSession(s2, to: id2)
        #expect(tm.ownerTabID(for: s1.id) == id1)
        #expect(tm.ownerTabID(for: s2.id) == id2)
        #expect(tm.ownerTabID(for: UUID()) == nil)
    }

    @Test func renameTerminalSession() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)
        tm.renameTerminalSession(session.id, to: "Custom")
        #expect(tm.terminalSessions[session.id]?.title == "Custom")
    }

    @Test func manualRenameSetsFlag() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)

        tm.renameTerminalSession(session.id, to: "MyTitle", manual: true)
        #expect(tm.terminalSessions[session.id]?.title == "MyTitle")
        #expect(tm.terminalSessions[session.id]?.isManuallyRenamed == true)
    }

    @Test func autoRenameSkippedWhenManual() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)

        tm.renameTerminalSession(session.id, to: "Pinned", manual: true)
        tm.renameTerminalSession(session.id, to: "OSC Override")
        #expect(tm.terminalSessions[session.id]?.title == "OSC Override")

        // Simulating what ContentView.onTitleChange does: skip if isManuallyRenamed
        #expect(tm.terminalSessions[session.id]?.isManuallyRenamed == true)
    }

    @Test func clearTitleResetsManualFlag() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)

        tm.renameTerminalSession(session.id, to: "Pinned", manual: true)
        #expect(tm.terminalSessions[session.id]?.isManuallyRenamed == true)

        tm.renameTerminalSession(session.id, to: "", manual: true)
        #expect(tm.terminalSessions[session.id]?.isManuallyRenamed == false)
        #expect(tm.terminalSessions[session.id]?.title == "Pinned")
    }

    @Test func updateTerminalCwd() {
        let tm = makeManager()
        let tabID = tm.activeFileTabID!
        let session = TerminalSession(id: UUID(), title: "T1", cwd: URL(fileURLWithPath: "/tmp"))
        tm.addTerminalSession(session, to: tabID)
        tm.updateTerminalCwd(session.id, to: URL(fileURLWithPath: "/Users"))
        #expect(tm.terminalSessions[session.id]?.currentCwd.standardizedFileURL == URL(fileURLWithPath: "/Users").standardizedFileURL)
    }
}
