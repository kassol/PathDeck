import AppKit
import Foundation

/// 全局 workspace 注册中心：所有 WorkspaceController 的 owner，TerminalEngine 单实例宿主，
/// 跨 window 路由查询（AppRouter）的入口。
@MainActor
final class WorkspaceManager {
    /// app 级 manager 引用，AppDelegate 启动时赋值。运行时 NSApp.delegate 是 SwiftUI
    /// @NSApplicationDelegateAdaptor 的转发 delegate（cast 回 AppDelegate 恒 nil，
    /// 2026-07-05 实测），全局兜底命令（targetPolicy.allowsFallback）经此取 manager；
    /// 测试各自构造独立 manager，不写本引用（用后须还原）。
    static weak var appShared: WorkspaceManager?

    private(set) var controllers: [WorkspaceController] = []

    /// 最近一次成为 key 的 workspace controller 标识。Settings / alert 抢走 key window 时仍能定位
    /// 用户视角的「当前」workspace，避免 fallback 到 controllers.first 误导持久化与路由。
    private var lastActiveControllerID: ObjectIdentifier?

    /// 关闭窗口的 Close History（⌘⇧T 文件焦点重开；全局共享、仅进程内）。
    let closedWindows = CloseHistoryStack<ClosedWindowRecord>()

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
        // 新独立窗口继承最近活跃窗口的 frame 并级联偏移；开 tab 时 frame 由 tab 组决定，不继承。
        let inheritedFrame: NSRect? = {
            guard existing == nil, var f = keyController?.window?.frame else { return nil }
            f.origin.x += 24
            f.origin.y -= 24
            return Self.validatedOnScreen(f) ?? Self.validatedOnScreen(keyController?.window?.frame ?? .zero)
        }()
        let controller = WorkspaceController(
            workspace: workspace,
            // 新窗口的 preview pane 显隐用旧全局偏好值作默认（S36 起 per-window 记忆）。
            viewState: WorkspaceViewState(isPreviewPaneVisible: preferences.isPreviewPaneVisible),
            manager: self,
            engine: engine,
            frame: inheritedFrame
        )
        controllers.append(controller)
        if let existing, let window = controller.window {
            existing.addTabbedWindow(window, ordered: .above)
            controller.refreshTabGroupCache()
            (existing.windowController as? WorkspaceController)?.refreshTabGroupCache()
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
                    if prevWindow == nil,
                       let fs = group.frame,
                       let rect = Self.validatedOnScreen(NSRectFromString(fs)) {
                        // 只需设组内首个 window，后续 addTabbedWindow 自动沿用组 frame。
                        window.setFrame(rect, display: false)
                    }
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
            customTitle: w.customTitle,
            isSidebarVisible: w.isSidebarVisible ?? true,
            isPreviewPaneVisible: w.isPreviewPaneVisible ?? preferences.isPreviewPaneVisible
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

    /// 重开最近关闭的 workspace 窗口（⌘⇧T 文件焦点）：按快照整窗重建（Reopen 语义——
    /// cwd、布局、终端组构成，shell 状态不可恢复）。原 tab 组仍有存活窗口 → tab 回原组；
    /// 否则按关闭时 frame 恢复为独立窗口。栈空 no-op。
    func reopenClosedWindow() {
        guard let record = closedWindows.pop() else { return }
        let controller = restoreController(from: record.state)
        controllers.append(controller)
        if let hostWindow = record.hostGroup?.windows.first(where: { $0 !== controller.window }),
           let window = controller.window {
            hostWindow.addTabbedWindow(window, ordered: .above)
            controller.refreshTabGroupCache()
            (hostWindow.windowController as? WorkspaceController)?.refreshTabGroupCache()
        } else if let frame = record.frame,
                  let validated = Self.validatedOnScreen(frame) {
            controller.window?.setFrame(validated, display: false)
        }
        controller.window?.makeKeyAndOrderFront(nil)
        persistSession()
    }

    /// frame 有效且与任一可见屏幕相交时原样返回，否则 nil（调用方回退默认居中）。
    /// 覆盖重启后显示器配置变化（拔外接屏）导致 frame 全部越界的场景。
    static func validatedOnScreen(_ frame: NSRect) -> NSRect? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        return visible ? frame : nil
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

    // MARK: - Command dispatch（S38，全局唯一 keystroke monitor adapter）

    private var commandMonitor: Any?

    /// 安装全局命令 monitor（AppDelegate 启动时调一次；测试不装 monitor，
    /// 直接调 `dispatchCommand` 喂合成事件）。
    func installCommandMonitor() {
        guard commandMonitor == nil else { return }
        commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.dispatchCommand(for: event) ?? event
        }
    }

    func removeCommandMonitor() {
        if let m = commandMonitor {
            NSEvent.removeMonitor(m)
            commandMonitor = nil
        }
    }

    /// 薄 adapter：NSEvent → KeyStroke + 派发语境 → `CommandDispatch.resolve` → 执行。
    /// 返回 nil = 吞事件（已执行）；返回 event = 放行（终端 first responder /
    /// 菜单 / 系统兜底）。`context` 为测试缝：nil 时从 NSApp.keyWindow 实算。
    func dispatchCommand(
        for event: NSEvent,
        context: (target: WorkspaceController?, focus: CommandDispatch.Focus?)? = nil
    ) -> NSEvent? {
        let stroke = CommandDispatch.KeyStroke(event: event)
        // monitor 表内命令均带 ⌘/⌃ 修饰（裸键一律 viewLocal），无修饰按键快速放行。
        guard !stroke.modifiers.isDisjoint(with: [.command, .control]) else { return event }
        let (target, focus) = context ?? dispatchContext()
        guard let resolution = CommandDispatch.resolve(stroke, focus: focus, target: target) else {
            return event
        }
        CommandDispatchTelemetry.monitorDispatchCount += 1
        if let index = resolution.index {
            resolution.spec.indexedAction?(target, index)
        } else {
            resolution.spec.action?(target)
        }
        return nil
    }

    /// 派发目标与焦点语境：keyWindow 是 workspace window → (controller, 语境)；
    /// Settings / alert / 面板为 key → (nil, nil)，只有 allowsFallback 命令会执行。
    private func dispatchContext() -> (WorkspaceController?, CommandDispatch.Focus?) {
        guard let controller = NSApp.keyWindow?.windowController as? WorkspaceController else {
            return (nil, nil)
        }
        let responder = NSApp.keyWindow?.firstResponder
        if responder is GhosttySurfaceView { return (controller, .terminal) }
        // NSText 覆盖 field editor（inline rename / 搜索框 / Palette 输入框）。
        if responder is NSText { return (controller, .textEditing) }
        return (controller, .file)
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
            let frame = (ordered.first?.window?.frame).map(NSStringFromRect)
            groups.append(WorkspaceGroupState(windows: windows, keyWindowIndex: keyIdx, frame: frame))
            groupHasActive.append(ordered.contains(where: isActive))
        }
        for c in ungrouped {
            let windows = [windowStateFor(c)]
            let frame = (c.window?.frame).map(NSStringFromRect)
            groups.append(WorkspaceGroupState(windows: windows, keyWindowIndex: 0, frame: frame))
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
            activeTerminalIndex: activeIdx,
            isSidebarVisible: c.viewState.isSidebarVisible,
            isPreviewPaneVisible: c.viewState.isPreviewPaneVisible
        )
    }

    // MARK: - WorkspaceController callbacks

    func controllerDidBecomeKey(_ controller: WorkspaceController) {
        lastActiveControllerID = ObjectIdentifier(controller)
        persistSession()
    }

    func controllerWillClose(_ controller: WorkspaceController) {
        // 入 Close History：此刻 store.sessions 仍完整（windowWillClose 只关 engine 侧），
        // windowStateFor 能捕获完整终端组；组关系取 controller 存活期缓存（此刻已脱组）。
        closedWindows.push(ClosedWindowRecord(
            state: windowStateFor(controller),
            frame: controller.window?.frame,
            hostGroup: controller.lastKnownTabGroup
        ))
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
        // shell exit 是主动终止，不入 Close History（不可被 ⌘⇧T 复活）。
        controller.closeTerminal(id, recordHistory: false)
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
