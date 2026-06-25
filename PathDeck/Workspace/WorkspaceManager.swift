import AppKit
import Foundation

/// 全局 workspace 注册中心：所有 WorkspaceController 的 owner，TerminalEngine 单实例宿主，
/// 跨 window 路由查询（AppRouter）的入口。
@MainActor
final class WorkspaceManager {
    private(set) var controllers: [WorkspaceController] = []

    /// 最近一次成为 key 的 workspace controller 标识。Settings / alert 抢走 key window 时仍能定位
    /// 用户视角的「当前」workspace，避免 fallback 到 controllers.first 误导持久化与路由。
    private var lastActiveControllerID: ObjectIdentifier?

    let preferences: WorkspacePreferences
    let pinnedFolders: PinnedFolders
    let engine: GhosttyTerminalEngine
    let router: AppRouter
    let persistence: WorkspacePersistence

    /// debounce 持久化保存的工作项。
    private var persistWorkItem: DispatchWorkItem?

    init(preferences: WorkspacePreferences? = nil,
         pinnedFolders: PinnedFolders? = nil,
         engine: GhosttyTerminalEngine? = nil,
         router: AppRouter? = nil,
         persistence: WorkspacePersistence? = nil) {
        self.preferences = preferences ?? .shared
        self.pinnedFolders = pinnedFolders ?? .shared
        self.engine = engine ?? GhosttyTerminalEngine()
        self.router = router ?? .shared
        self.persistence = persistence ?? WorkspacePersistence()

        setupEngineCallbacks()
    }

    // MARK: - Public API

    var keyController: WorkspaceController? {
        if let key = NSApp.keyWindow?.windowController as? WorkspaceController { return key }
        if let lastID = lastActiveControllerID,
           let last = controllers.first(where: { ObjectIdentifier($0) == lastID }) {
            return last
        }
        return controllers.first
    }

    @discardableResult
    func openNewWindow(cwd: URL, tabbedTo existing: NSWindow? = nil) -> WorkspaceController {
        let workspace = WorkspaceModel(
            root: cwd,
            sortColumn: preferences.sortColumn,
            sortAscending: preferences.sortAscending,
            showHidden: preferences.showHidden
        )
        let controller = WorkspaceController(
            workspace: workspace,
            viewState: WorkspaceViewState(),
            manager: self,
            engine: engine
        )
        controllers.append(controller)
        if let existing, let window = controller.window {
            existing.addTabbedWindow(window, ordered: .above)
        }
        controller.window?.makeKeyAndOrderFront(nil)
        persistSession()
        return controller
    }

    func restoreSession() {
        guard let state = persistence.loadSessionState(), !state.groups.isEmpty else { return }
        var groupKeyControllers: [WorkspaceController?] = []

        for group in state.groups {
            var prevWindow: NSWindow?
            var groupControllers: [WorkspaceController] = []
            for w in group.windows {
                let controller = restoreController(from: w)
                controllers.append(controller)
                groupControllers.append(controller)
                if let window = controller.window {
                    if let prev = prevWindow {
                        prev.addTabbedWindow(window, ordered: .above)
                    }
                    prevWindow = window
                }
            }
            let keyIdx = group.keyWindowIndex ?? 0
            let keyController = groupControllers.indices.contains(keyIdx)
                ? groupControllers[keyIdx] : groupControllers.first
            groupKeyControllers.append(keyController)
            keyController?.window?.orderFront(nil)
        }

        let kgi = state.keyGroupIndex ?? 0
        let keyController = groupKeyControllers.indices.contains(kgi)
            ? groupKeyControllers[kgi] : groupKeyControllers.first ?? nil
        keyController?.window?.makeKeyAndOrderFront(nil)
    }

    private func restoreController(from w: WorkspaceWindowState) -> WorkspaceController {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cwdURL = URL(fileURLWithPath: w.cwd)
        var isDir: ObjCBool = false
        let root = FileManager.default.fileExists(
            atPath: w.cwd, isDirectory: &isDir
        ) && isDir.boolValue ? cwdURL : home

        let workspace = WorkspaceModel(
            root: root,
            sortColumn: preferences.sortColumn,
            sortAscending: preferences.sortAscending,
            showHidden: preferences.showHidden
        )
        let viewState = WorkspaceViewState(
            mode: WorkspaceMode(rawValue: w.mode) ?? .finderFirst,
            isTerminalVisible: w.isTerminalVisible,
            terminalAnchorCwd: w.anchorCwdPath.map { URL(fileURLWithPath: $0) },
            isCustomTitle: w.isCustomTitle,
            customTitle: w.customTitle
        )
        let controller = WorkspaceController(
            workspace: workspace,
            viewState: viewState,
            manager: self,
            engine: engine
        )
        for termState in w.terminalStates {
            let cwdURL = URL(fileURLWithPath: termState.cwdPath)
            var termIsDir: ObjCBool = false
            let termCwd = FileManager.default.fileExists(
                atPath: termState.cwdPath, isDirectory: &termIsDir
            ) && termIsDir.boolValue ? cwdURL : home
            let sid = engine.createSession(cwd: termCwd)
            let session = TerminalSession(
                id: sid, title: termState.title, cwd: termCwd,
                isManuallyRenamed: termState.isManuallyRenamed
            )
            controller.store.append(session)
            if viewState.activeTerminalID == nil {
                viewState.activeTerminalID = sid
            }
        }
        if let idx = w.activeTerminalIndex,
           controller.store.sessions.indices.contains(idx) {
            viewState.activeTerminalID = controller.store.sessions[idx].id
        }
        if viewState.isCustomTitle, let title = viewState.customTitle, !title.isEmpty {
            controller.window?.title = title
        }
        return controller
    }

    func findController(matchingCwd url: URL) -> WorkspaceController? {
        let std = url.standardizedFileURL
        return controllers.first { c in
            c.workspace.currentURL.standardizedFileURL == std
                || c.viewState.terminalAnchorCwd?.standardizedFileURL == std
        }
    }

    func findControllerOwning(sessionID id: UUID) -> WorkspaceController? {
        controllers.first { $0.store.contains(id) }
    }

    func applySort(column: String, ascending: Bool) {
        guard let col = SortColumn(rawValue: column) else { return }
        preferences.sortColumn = col
        preferences.sortAscending = ascending
        for c in controllers {
            c.workspace.applySort(column: column, ascending: ascending)
        }
    }

    func toggleHidden() {
        preferences.showHidden.toggle()
        for c in controllers {
            c.workspace.showHidden = preferences.showHidden
            c.workspace.reload()
        }
    }

    // MARK: - Persistence

    func persistSession() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistSessionImmediately() }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func persistSessionImmediately() {
        // 按 NSWindow.tabGroup 聚合 controllers，保留真实 tab 分组与组内顺序。
        var groupOrder: [(group: NSWindowTabGroup, controllers: [WorkspaceController])] = []
        var ungrouped: [WorkspaceController] = []
        for c in controllers {
            guard c.window != nil else { continue }
            if let g = c.window?.tabGroup {
                if let idx = groupOrder.firstIndex(where: { $0.group === g }) {
                    groupOrder[idx].controllers.append(c)
                } else {
                    groupOrder.append((g, [c]))
                }
            } else {
                ungrouped.append(c)
            }
        }

        // 用 lastActive 兜底：Settings / alert 抢走 key window 时，所有 workspace window 的
        // isKeyWindow 都为 false；此时仍把用户视角的「上次活跃」controller 标为 key。
        func isActive(_ c: WorkspaceController) -> Bool {
            if c.window?.isKeyWindow == true { return true }
            return lastActiveControllerID == ObjectIdentifier(c)
        }

        var groups: [WorkspaceGroupState] = []
        var groupHasActive: [Bool] = []

        for (g, ctrls) in groupOrder {
            // 按 tabGroup.windows 顺序排序组内 controllers
            let ordered = g.windows.compactMap { w in
                ctrls.first { $0.window === w }
            }
            let windows = ordered.map(windowStateFor)
            // 先找 isKeyWindow；没有再找 lastActive。
            let keyIdx = ordered.firstIndex { $0.window?.isKeyWindow == true }
                ?? ordered.firstIndex { isActive($0) }
            groups.append(WorkspaceGroupState(windows: windows, keyWindowIndex: keyIdx))
            groupHasActive.append(ordered.contains(where: isActive))
        }
        for c in ungrouped {
            let windows = [windowStateFor(c)]
            groups.append(WorkspaceGroupState(windows: windows, keyWindowIndex: 0))
            groupHasActive.append(isActive(c))
        }
        let keyGroupIndex = groupHasActive.firstIndex(of: true)
        persistence.persist(WorkspaceSessionState(groups: groups, keyGroupIndex: keyGroupIndex))
    }

    private func windowStateFor(_ c: WorkspaceController) -> WorkspaceWindowState {
        let termStates = c.store.sessions.map { s in
            TerminalTabState(
                title: s.title,
                cwdPath: s.currentCwd.path(percentEncoded: false),
                isManuallyRenamed: s.isManuallyRenamed
            )
        }
        let activeIdx = c.viewState.activeTerminalID.flatMap { id in
            c.store.sessions.firstIndex { $0.id == id }
        }
        return WorkspaceWindowState(
            cwd: c.workspace.currentURL.path(percentEncoded: false),
            isCustomTitle: c.viewState.isCustomTitle,
            customTitle: c.viewState.customTitle,
            mode: c.viewState.mode.rawValue,
            isTerminalVisible: c.viewState.isTerminalVisible,
            anchorCwdPath: c.viewState.terminalAnchorCwd?.path(percentEncoded: false),
            terminalStates: termStates,
            activeTerminalIndex: activeIdx
        )
    }

    // MARK: - WorkspaceController callbacks

    func controllerDidBecomeKey(_ controller: WorkspaceController) {
        lastActiveControllerID = ObjectIdentifier(controller)
        persistSession()
    }

    func controllerWillClose(_ controller: WorkspaceController) {
        if lastActiveControllerID == ObjectIdentifier(controller) {
            lastActiveControllerID = nil
        }
        controllers.removeAll { $0 === controller }
        // 立即 flush 而非 debounce：关 window 后用户可能立刻 Cmd+Q，debounce 100ms 可能丢，
        // 导致重启时已关闭 window 仍出现。
        persistSessionImmediately()
    }

    // MARK: - Engine wiring

    private func setupEngineCallbacks() {
        engine.onSessionClose = { [weak self] id in
            Task { @MainActor in self?.handleEngineSessionClose(id) }
        }
        engine.onCwdChange = { [weak self] id, url in
            Task { @MainActor in self?.handleEngineCwdChange(id, url: url) }
        }
        engine.onTitleChange = { [weak self] id, title in
            Task { @MainActor in self?.handleEngineTitleChange(id, title: title) }
        }
        engine.onPendingDropped = { id, count, reason in
            NSLog("[PathDeck] dropped %d pending text(s) for session %@: %@",
                  count, id.uuidString, String(describing: reason))
        }
    }

    private func handleEngineSessionClose(_ id: UUID) {
        guard let controller = findControllerOwning(sessionID: id) else { return }
        controller.closeTerminal(id)
    }

    private func handleEngineCwdChange(_ id: UUID, url: URL) {
        guard let controller = findControllerOwning(sessionID: id) else { return }
        controller.updateTerminalCwd(id, to: url)
    }

    private func handleEngineTitleChange(_ id: UUID, title: String) {
        guard let controller = findControllerOwning(sessionID: id),
              controller.store.session(id)?.isManuallyRenamed != true else { return }
        controller.renameTerminal(id, to: title, manual: false)
    }
}
