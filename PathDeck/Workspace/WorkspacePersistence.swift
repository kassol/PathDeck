import Foundation

/// `workspaceSessionState` 的持久化封装；启动时一次性迁移旧 `fileTabsState` + `activeFileTabID`。
final class WorkspacePersistence {
    private let defaults: UserDefaults

    static let sessionStateKey = "workspaceSessionState"
    static let legacyFileTabsKey = "fileTabsState"
    static let legacyActiveTabKey = "activeFileTabID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 优先读新 key；否则尝试旧 key 迁移；都没有返回 nil。
    func loadSessionState() -> WorkspaceSessionState? {
        if let data = defaults.data(forKey: Self.sessionStateKey),
           let s = try? JSONDecoder().decode(WorkspaceSessionState.self, from: data) {
            return s
        }
        if let migrated = migrateLegacy() {
            persist(migrated)
            defaults.removeObject(forKey: Self.legacyFileTabsKey)
            defaults.removeObject(forKey: Self.legacyActiveTabKey)
            return migrated
        }
        return nil
    }

    func persist(_ state: WorkspaceSessionState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.sessionStateKey)
        }
    }

    /// 读旧 `fileTabsState` + `activeFileTabID`，转换为新 `WorkspaceSessionState`。
    /// 旧 schema 是单一 flat list，所有 tab 视为同一 NSWindow tab group。
    private func migrateLegacy() -> WorkspaceSessionState? {
        guard let data = defaults.data(forKey: Self.legacyFileTabsKey),
              let legacy = try? JSONDecoder().decode([LegacyFileTabState].self, from: data),
              !legacy.isEmpty else { return nil }

        let activeID = defaults.string(forKey: Self.legacyActiveTabKey)
        let windows = legacy.map { tab in
            WorkspaceWindowState(
                cwd: tab.currentURLPath,
                isCustomTitle: tab.isCustomTitle,
                customTitle: tab.isCustomTitle ? tab.title : nil,
                mode: tab.mode,
                isTerminalVisible: tab.isTerminalVisible,
                anchorCwdPath: tab.anchorCwdPath,
                terminalStates: tab.terminalStates,
                activeTerminalIndex: tab.activeTerminalIndex
            )
        }
        let keyIdx = legacy.firstIndex { $0.id == activeID }
        let group = WorkspaceGroupState(windows: windows, keyWindowIndex: keyIdx)
        return WorkspaceSessionState(groups: [group], keyGroupIndex: 0)
    }
}

/// S31 之前的旧持久化 schema；仅在迁移路径中使用。
private struct LegacyFileTabState: Codable {
    let id: String
    let title: String
    let isCustomTitle: Bool
    let mode: String
    let isTerminalVisible: Bool
    let currentURLPath: String
    let anchorCwdPath: String?
    let terminalStates: [TerminalTabState]
    let activeTerminalIndex: Int?
}
