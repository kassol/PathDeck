import Foundation
import Observation

enum WorkspaceMode: String {
    case finderFirst
    case terminalFirst
}

@Observable
final class TabManager {
    var fileTabs: [FileTab] = []
    var activeFileTabID: UUID?

    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false

    private(set) var workspaceModels: [UUID: WorkspaceModel] = [:]
    private(set) var terminalSessions: [UUID: TerminalSession] = [:]

    private let defaults: UserDefaults

    private static let fileTabsKey = "fileTabsState"
    private static let activeTabKey = "activeFileTabID"
    private static let sortColumnKey = "sortColumn"
    private static let sortAscendingKey = "sortAscending"
    private static let showHiddenKey = "showHidden"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreGlobalPreferences()
    }

    // MARK: - Computed

    var activeTab: FileTab? {
        fileTabs.first { $0.id == activeFileTabID }
    }

    var activeModel: WorkspaceModel? {
        guard let id = activeFileTabID else { return nil }
        return workspaceModels[id]
    }

    var activeTabSessions: [TerminalSession] {
        guard let tab = activeTab else { return [] }
        return tab.terminalSessionIDs.compactMap { terminalSessions[$0] }
    }

    var activeTabSessionIDs: Set<UUID> {
        guard let tab = activeTab else { return [] }
        return Set(tab.terminalSessionIDs)
    }

    var allTerminalSessionIDs: Set<UUID> {
        Set(terminalSessions.keys)
    }

    var activeTerminalID: UUID? {
        activeTab?.activeTerminalID
    }

    var activeTabMode: WorkspaceMode {
        get { activeTab?.mode ?? .finderFirst }
        set {
            guard let idx = fileTabs.firstIndex(where: { $0.id == activeFileTabID }) else { return }
            fileTabs[idx].mode = newValue
        }
    }

    var activeTabTerminalVisible: Bool {
        get { activeTab?.isTerminalVisible ?? false }
        set {
            guard let idx = fileTabs.firstIndex(where: { $0.id == activeFileTabID }) else { return }
            fileTabs[idx].isTerminalVisible = newValue
        }
    }

    // MARK: - File Tab CRUD

    @discardableResult
    func createTab(at url: URL) -> UUID {
        let tab = FileTab(title: url.lastPathComponent)
        let model = WorkspaceModel(
            root: url,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            showHidden: showHidden
        )
        fileTabs.append(tab)
        workspaceModels[tab.id] = model
        activeFileTabID = tab.id
        return tab.id
    }

    func closeTab(_ id: UUID) {
        guard let idx = fileTabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = fileTabs[idx]
        for sessionID in tab.terminalSessionIDs {
            terminalSessions.removeValue(forKey: sessionID)
        }
        workspaceModels.removeValue(forKey: id)
        fileTabs.remove(at: idx)

        if activeFileTabID == id {
            if let next = fileTabs[safe: idx] ?? fileTabs.last {
                activeFileTabID = next.id
            } else {
                activeFileTabID = nil
            }
        }
    }

    func switchTab(to id: UUID) {
        guard fileTabs.contains(where: { $0.id == id }) else { return }
        activeFileTabID = id
    }

    func switchToTabByIndex(_ index: Int) {
        guard fileTabs.indices.contains(index) else { return }
        activeFileTabID = fileTabs[index].id
    }

    func switchToNextTab() {
        guard let current = activeFileTabID,
              let idx = fileTabs.firstIndex(where: { $0.id == current }) else { return }
        let next = (idx + 1) % fileTabs.count
        activeFileTabID = fileTabs[next].id
    }

    func switchToPreviousTab() {
        guard let current = activeFileTabID,
              let idx = fileTabs.firstIndex(where: { $0.id == current }) else { return }
        let prev = (idx - 1 + fileTabs.count) % fileTabs.count
        activeFileTabID = fileTabs[prev].id
    }

    func renameTab(_ id: UUID, to title: String) {
        guard let idx = fileTabs.firstIndex(where: { $0.id == id }) else { return }
        fileTabs[idx].title = title
        fileTabs[idx].isCustomTitle = true
    }

    // MARK: - Terminal Session Management

    func addTerminalSession(_ session: TerminalSession, to tabID: UUID) {
        guard let idx = fileTabs.firstIndex(where: { $0.id == tabID }) else { return }
        terminalSessions[session.id] = session
        fileTabs[idx].terminalSessionIDs.append(session.id)
        fileTabs[idx].activeTerminalID = session.id
        if fileTabs[idx].terminalAnchorCwd == nil {
            fileTabs[idx].terminalAnchorCwd = workspaceModels[tabID]?.currentURL
        }
    }

    func removeTerminalSession(_ sessionID: UUID) {
        guard let idx = fileTabs.firstIndex(where: { $0.terminalSessionIDs.contains(sessionID) }) else {
            terminalSessions.removeValue(forKey: sessionID)
            return
        }
        fileTabs[idx].terminalSessionIDs.removeAll { $0 == sessionID }
        terminalSessions.removeValue(forKey: sessionID)
        if fileTabs[idx].activeTerminalID == sessionID {
            fileTabs[idx].activeTerminalID = fileTabs[idx].terminalSessionIDs.last
        }
        if fileTabs[idx].terminalSessionIDs.isEmpty {
            fileTabs[idx].terminalAnchorCwd = nil
        }
    }

    func ownerTabID(for sessionID: UUID) -> UUID? {
        fileTabs.first { $0.terminalSessionIDs.contains(sessionID) }?.id
    }

    func setActiveTerminal(_ sessionID: UUID) {
        guard let tabID = activeFileTabID,
              let idx = fileTabs.firstIndex(where: { $0.id == tabID }),
              fileTabs[idx].terminalSessionIDs.contains(sessionID) else { return }
        fileTabs[idx].activeTerminalID = sessionID
    }

    func renameTerminalSession(_ sessionID: UUID, to title: String, manual: Bool = false) {
        if manual && title.isEmpty {
            terminalSessions[sessionID]?.isManuallyRenamed = false
            return
        }
        terminalSessions[sessionID]?.title = title
        if manual {
            terminalSessions[sessionID]?.isManuallyRenamed = true
        }
    }

    func updateTerminalCwd(_ sessionID: UUID, to url: URL) {
        terminalSessions[sessionID]?.currentCwd = url
    }

    // MARK: - Global Preferences

    func applySort(column: String, ascending: Bool) {
        guard let col = SortColumn(rawValue: column) else { return }
        sortColumn = col
        sortAscending = ascending
        for model in workspaceModels.values {
            model.applySort(column: column, ascending: ascending)
        }
        persistGlobalPreferences()
    }

    func toggleHidden() {
        showHidden.toggle()
        for model in workspaceModels.values {
            model.showHidden = showHidden
            model.reload()
        }
        persistGlobalPreferences()
    }

    // MARK: - Terminal Visibility & Mode (per-tab)

    func toggleTerminalVisibility() {
        guard let idx = fileTabs.firstIndex(where: { $0.id == activeFileTabID }) else { return }
        fileTabs[idx].isTerminalVisible.toggle()
    }

    func toggleActiveTabMode() {
        guard let idx = fileTabs.firstIndex(where: { $0.id == activeFileTabID }) else { return }
        if fileTabs[idx].mode == .finderFirst {
            fileTabs[idx].mode = .terminalFirst
            fileTabs[idx].isTerminalVisible = true
        } else {
            fileTabs[idx].mode = .finderFirst
        }
    }

    // MARK: - Persistence

    private func restoreGlobalPreferences() {
        if let raw = defaults.string(forKey: Self.sortColumnKey),
           let col = SortColumn(rawValue: raw) {
            sortColumn = col
        }
        if defaults.object(forKey: Self.sortAscendingKey) != nil {
            sortAscending = defaults.bool(forKey: Self.sortAscendingKey)
        }
        if defaults.object(forKey: Self.showHiddenKey) != nil {
            showHidden = defaults.bool(forKey: Self.showHiddenKey)
        }
    }

    func persistGlobalPreferences() {
        defaults.set(sortColumn.rawValue, forKey: Self.sortColumnKey)
        defaults.set(sortAscending, forKey: Self.sortAscendingKey)
        defaults.set(showHidden, forKey: Self.showHiddenKey)
    }

    func saveTabState() {
        var tabStates: [FileTabState] = []
        for tab in fileTabs {
            let model = workspaceModels[tab.id]
            let termStates = tab.terminalSessionIDs.compactMap { id -> TerminalTabState? in
                guard let session = terminalSessions[id] else { return nil }
                return TerminalTabState(
                    title: session.title,
                    cwdPath: session.currentCwd.path(percentEncoded: false),
                    isManuallyRenamed: session.isManuallyRenamed
                )
            }
            let activeIndex: Int? = tab.activeTerminalID.flatMap {
                id in tab.terminalSessionIDs.firstIndex(of: id)
            }
            tabStates.append(FileTabState(
                id: tab.id.uuidString,
                title: tab.title,
                isCustomTitle: tab.isCustomTitle,
                mode: tab.mode.rawValue,
                isTerminalVisible: tab.isTerminalVisible,
                currentURLPath: model?.currentURL.path(percentEncoded: false)
                    ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
                anchorCwdPath: tab.terminalAnchorCwd?.path(percentEncoded: false),
                terminalStates: termStates,
                activeTerminalIndex: activeIndex
            ))
        }
        if let data = try? JSONEncoder().encode(tabStates) {
            defaults.set(data, forKey: Self.fileTabsKey)
        }
        defaults.set(activeFileTabID?.uuidString, forKey: Self.activeTabKey)
        persistGlobalPreferences()
    }

    func restoreTabState(terminalEngine: any TerminalEngine) {
        guard let data = defaults.data(forKey: Self.fileTabsKey),
              let states = try? JSONDecoder().decode([FileTabState].self, from: data),
              !states.isEmpty else {
            createTab(at: FileManager.default.homeDirectoryForCurrentUser)
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var restoredActiveID: UUID?

        if let savedActive = defaults.string(forKey: Self.activeTabKey) {
            restoredActiveID = UUID(uuidString: savedActive)
        }

        for state in states {
            guard let tabUUID = UUID(uuidString: state.id) else { continue }
            let cwdURL = URL(fileURLWithPath: state.currentURLPath)
            var isDir: ObjCBool = false
            let root = FileManager.default.fileExists(
                atPath: state.currentURLPath, isDirectory: &isDir
            ) && isDir.boolValue ? cwdURL : home

            let model = WorkspaceModel(
                root: root,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                showHidden: showHidden
            )

            var tab = FileTab(
                id: tabUUID,
                title: state.title,
                isCustomTitle: state.isCustomTitle,
                mode: WorkspaceMode(rawValue: state.mode) ?? .finderFirst,
                isTerminalVisible: state.isTerminalVisible
            )

            if let anchorPath = state.anchorCwdPath {
                tab.terminalAnchorCwd = URL(fileURLWithPath: anchorPath)
            }

            for termState in state.terminalStates {
                let termCwd = URL(fileURLWithPath: termState.cwdPath)
                var termIsDir: ObjCBool = false
                let cwd = FileManager.default.fileExists(
                    atPath: termState.cwdPath, isDirectory: &termIsDir
                ) && termIsDir.boolValue ? termCwd : home

                let sessionID = terminalEngine.createSession(cwd: cwd)
                let session = TerminalSession(id: sessionID, title: termState.title, cwd: cwd, isManuallyRenamed: termState.isManuallyRenamed)
                terminalSessions[sessionID] = session
                tab.terminalSessionIDs.append(sessionID)
                if tab.activeTerminalID == nil {
                    tab.activeTerminalID = sessionID
                }
            }

            if let idx = state.activeTerminalIndex,
               tab.terminalSessionIDs.indices.contains(idx) {
                tab.activeTerminalID = tab.terminalSessionIDs[idx]
            }

            fileTabs.append(tab)
            workspaceModels[tabUUID] = model
        }

        if let rid = restoredActiveID, fileTabs.contains(where: { $0.id == rid }) {
            activeFileTabID = rid
        } else {
            activeFileTabID = fileTabs.first?.id
        }
    }

    // MARK: - Tab Matching (for AppRouter)

    func findTabByAnchorOrCwd(_ url: URL) -> UUID? {
        let standardized = url.standardizedFileURL
        if let tab = fileTabs.first(where: { $0.terminalAnchorCwd?.standardizedFileURL == standardized }) {
            return tab.id
        }
        if let tab = fileTabs.first(where: { workspaceModels[$0.id]?.currentURL.standardizedFileURL == standardized }) {
            return tab.id
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
