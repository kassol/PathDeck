import AppKit
import SwiftUI

/// 一个 NSWindow workspace 单元：持有 WorkspaceModel + TerminalSessionStore + ViewState，
/// 通过 NSHostingController 挂载 SwiftUI root view。
/// 多个 controller 经 NSWindow tabbing 合并到同一个 tab 组。
@MainActor
final class WorkspaceController: NSWindowController, NSWindowDelegate {
    let workspace: WorkspaceModel
    let store: TerminalSessionStore
    let viewState: WorkspaceViewState

    /// 本窗口终端的 Close History（⌘⇧T 终端焦点重开；仅进程内）。
    let closedTerminals = CloseHistoryStack<ClosedTerminalRecord>()

    /// 所属 tab 组的弱缓存：windowWillClose 时窗口已脱组拿不到组关系，
    /// 在 becomeKey/resignKey 时刷新，供 Close History 记录重开归位目标。
    private(set) weak var lastKnownTabGroup: NSWindowTabGroup?

    /// becomeKey/resignKey 自动刷新；程序化 addTabbedWindow 后（openNewWindow /
    /// reopenClosedWindow）需显式调用——测试与非活跃 app 下 key 事件不可靠。
    func refreshTabGroupCache() {
        guard let group = window?.tabGroup else {
            lastKnownTabGroup = nil
            return
        }
        // 单窗组不算「同组关系」；多窗组才值得重开归位。
        lastKnownTabGroup = group.windows.count > 1 ? group : nil
    }

    weak var manager: WorkspaceManager?
    weak var engine: GhosttyTerminalEngine?

    /// SwiftUI 视图层用的 engine 句柄；engine 由 manager 持 strong ref，本控制器仅 weak。
    var engineHandle: any TerminalEngine {
        guard let engine else {
            fatalError("WorkspaceController used after engine deallocation")
        }
        return engine
    }

    func applySortViaManager(column: String, ascending: Bool) {
        manager?.applySort(column: column, ascending: ascending)
    }

    // MARK: - Shortcut monitors (terminal-focus aware + tab switching)
    //
    // monitor token 由 controller 持有：view 重复 appear / view tree 重构都不会泄漏，windowWillClose
    // 兜底 onDisappear 不可靠的场景。安装/拆除幂等。

    private var closeTabMonitor: Any?
    private var newTabMonitor: Any?
    private var reopenMonitor: Any?
    private var paletteMonitor: Any?
    private var tabSwitchMonitor: Any?
    private var overlayMonitor: Any?

    /// 长按 ⌘ 浮窗状态机；可见性经回调写入 viewState 驱动 SwiftUI overlay。
    private let overlayTracker = ShortcutOverlayHoldTracker()

    func installShortcutMonitors() {
        removeShortcutMonitors()
        overlayTracker.onVisibilityChange = { [weak self] visible in
            self?.viewState.isShortcutOverlayVisible = visible
        }
        // 观察型 monitor：永远 return event 不吞，flagsChanged 照常到达终端的修饰键转发。
        let overlayMask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        overlayMonitor = NSEvent.addLocalMonitorForEvents(matching: overlayMask) { [weak self] event in
            guard let self else { return event }
            guard NSApp.keyWindow == self.window else {
                self.overlayTracker.reset()
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let commandHeld = flags.contains(.command)
            switch event.type {
            case .flagsChanged:
                self.overlayTracker.flagsChanged(commandOnly: flags == .command,
                                                 commandHeld: commandHeld)
            case .keyDown:
                self.overlayTracker.keyDown(commandHeld: commandHeld)
            default:
                self.overlayTracker.mouseDown(commandHeld: commandHeld)
            }
            return event
        }
        closeTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  NSApp.keyWindow == self.window else { return event }
            if NSApp.keyWindow?.firstResponder is GhosttySurfaceView,
               let sessionID = self.viewState.activeTerminalID {
                self.closeTerminal(sessionID)
                return nil
            }
            return event
        }
        newTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "t",
                  NSApp.keyWindow == self.window else { return event }
            if NSApp.keyWindow?.firstResponder is GhosttySurfaceView {
                self.createTerminal()
                return nil
            }
            // 焦点不在终端（文件列表等）：开新 workspace 窗口 tab。不能 return event 依赖 SwiftUI
            // .keyboardShortcut("t")——手动 NSWindow + 无 WindowGroup 架构下，first responder 为纯
            // AppKit NSView（FileNSOutlineView）时该 command 不派发，Cmd+T 会落空（同 Next/Prev/
            // Cmd+1..9 已知问题，故一并走 monitor）。keyWindow 非 workspace 时上面 guard 已 return
            // event，仍由 SwiftUI keyboardShortcut 兜底（Settings 焦点退到 lastActive 开新 tab）。
            self.manager?.openNewWindow(cwd: self.workspace.currentURL, tabbedTo: self.window)
            return nil
        }
        // ⌘⇧T 双语义对称 ⌘W：终端焦点 → 重开终端 session，否则 → 重开 workspace 窗口。
        // 与 ⌘T 同理走 monitor（AppKit first responder 下 SwiftUI keyboardShortcut 不派发）；
        // 栈空 no-op 但仍吞事件（菜单兜底走同一 action，不会二次触发）。
        reopenMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                  event.charactersIgnoringModifiers?.lowercased() == "t",
                  NSApp.keyWindow == self.window else { return event }
            if NSApp.keyWindow?.firstResponder is GhosttySurfaceView {
                self.reopenClosedTerminal()
            } else {
                self.manager?.reopenClosedWindow()
            }
            return nil
        }
        // ⌘⇧P Command Palette：同为 monitor（终端焦点下 SwiftUI keyboardShortcut 不派发）。
        paletteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                  event.charactersIgnoringModifiers?.lowercased() == "p",
                  NSApp.keyWindow == self.window else { return event }
            self.showCommandPalette()
            return nil
        }
        tabSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow == self.window else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers ?? ""
            if flags == .command, let n = Int(chars), (1...9).contains(n) {
                if let tabs = self.window?.tabbedWindows, tabs.indices.contains(n - 1) {
                    tabs[n - 1].makeKeyAndOrderFront(nil)
                    return nil
                }
                return event
            }
            if flags == .control && event.keyCode == 48 {
                self.window?.selectNextTab(nil)
                return nil
            }
            if flags == [.control, .shift] && event.keyCode == 48 {
                self.window?.selectPreviousTab(nil)
                return nil
            }
            return event
        }
    }

    func removeShortcutMonitors() {
        if let m = closeTabMonitor { NSEvent.removeMonitor(m); closeTabMonitor = nil }
        if let m = newTabMonitor { NSEvent.removeMonitor(m); newTabMonitor = nil }
        if let m = reopenMonitor { NSEvent.removeMonitor(m); reopenMonitor = nil }
        if let m = paletteMonitor { NSEvent.removeMonitor(m); paletteMonitor = nil }
        if let m = tabSwitchMonitor { NSEvent.removeMonitor(m); tabSwitchMonitor = nil }
        if let m = overlayMonitor { NSEvent.removeMonitor(m); overlayMonitor = nil }
        overlayTracker.reset()
    }

    /// 用 WorkspaceManager.openNewWindow 创建，不直接 init。
    init(workspace: WorkspaceModel,
         viewState: WorkspaceViewState,
         manager: WorkspaceManager,
         engine: GhosttyTerminalEngine,
         frame: NSRect? = nil) {
        self.workspace = workspace
        self.viewState = viewState
        self.store = TerminalSessionStore()
        self.manager = manager
        self.engine = engine

        let defaultFrame = frame ?? NSRect(x: 0, y: 0, width: 1080, height: 720)
        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 480)
        window.tabbingIdentifier = WorkspaceController.sharedTabbingIdentifier
        window.tabbingMode = .preferred
        if frame == nil {
            window.center()
        }

        super.init(window: window)
        window.delegate = self
        window.title = workspace.currentURL.lastPathComponent

        let root = WorkspaceRootView(
            controller: self,
            preferences: manager.preferences,
            pinnedFolders: manager.pinnedFolders
        )
        window.contentViewController = NSHostingController(rootView: root)
        // contentViewController 赋值会把 window resize 到 SwiftUI fitting size（720×480 的
        // min 约束），吞掉 contentRect / 传入 frame；赋值后重新应用目标 frame。
        window.setFrame(defaultFrame, display: false)
        if frame == nil {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    static let sharedTabbingIdentifier = NSWindow.TabbingIdentifier("in.riverflows.PathDeck.workspace")

    // MARK: - Terminal lifecycle

    @discardableResult
    func createTerminal(cwdOverride: URL? = nil) -> TerminalSession? {
        guard let engine else { return nil }
        let cwd = cwdOverride
            ?? viewState.terminalAnchorCwd
            ?? workspace.currentURL
        let id = engine.createSession(cwd: cwd)
        let count = store.sessions.count + 1
        let title = count == 1 ? "Terminal" : "Terminal \(count)"
        let session = TerminalSession(id: id, title: title, cwd: cwd)
        store.append(session)
        viewState.activeTerminalID = id
        if viewState.terminalAnchorCwd == nil {
            viewState.terminalAnchorCwd = workspace.currentURL
        }
        manager?.persistSession()
        return session
    }

    /// 关闭终端 session。recordHistory：用户关闭手势（⌘W、关闭按钮、命令）入 Close History；
    /// engine 回调（shell exit）传 false——主动终止不算误关，不可被 ⌘⇧T 复活。
    func closeTerminal(_ id: UUID, recordHistory: Bool = true) {
        guard let engine else { return }
        engine.closeSession(id)
        let snapshot = store.session(id)
        guard let index = store.remove(id) else { return }
        if recordHistory, let snapshot {
            closedTerminals.push(ClosedTerminalRecord(
                title: snapshot.title,
                cwd: snapshot.currentCwd,
                isManuallyRenamed: snapshot.isManuallyRenamed,
                index: index
            ))
        }
        if viewState.activeTerminalID == id {
            viewState.activeTerminalID = store.sessions.last?.id
        }
        if store.sessions.isEmpty {
            viewState.terminalAnchorCwd = nil
            if viewState.mode == .finderFirst {
                viewState.isTerminalVisible = false
            }
        }
        manager?.persistSession()
    }

    /// 重开最近关闭的终端（⌘⇧T 终端焦点）：按快照重建——恢复 cwd、标题与原 tab 位置，
    /// shell 进程状态不可恢复。栈空 no-op。
    func reopenClosedTerminal() {
        guard let record = closedTerminals.pop(),
              let session = createTerminal(cwdOverride: record.cwd) else { return }
        if record.isManuallyRenamed {
            renameTerminal(session.id, to: record.title, manual: true)
        }
        reorderTerminal(source: session.id,
                        to: min(record.index, store.sessions.count - 1))
        if !viewState.isTerminalVisible {
            viewState.isTerminalVisible = true
        }
    }

    /// 重命名 terminal session：包装 store.rename + 触发持久化。
    /// engine 的 OSC title change 与用户手动重命名都走这条路径。
    func renameTerminal(_ id: UUID, to title: String, manual: Bool) {
        store.rename(id, to: title, manual: manual)
        manager?.persistSession()
    }

    /// 重排 terminal session：包装 store.move + 触发持久化。
    func reorderTerminal(source: UUID, to destinationIndex: Int) {
        if store.move(source: source, to: destinationIndex) {
            manager?.persistSession()
        }
    }

    /// 更新 terminal session cwd：包装 store.updateCwd + 触发持久化。
    func updateTerminalCwd(_ id: UUID, to url: URL) {
        store.updateCwd(id, to: url)
        manager?.persistSession()
    }

    // MARK: - Command Palette

    /// Palette 关闭后要还的焦点（呼出时的 first responder）。
    private weak var paletteReturnFocus: NSResponder?

    /// 呼出 Command Palette（⌘⇧P）。已可见则 no-op。
    func showCommandPalette() {
        guard !viewState.isCommandPaletteVisible else { return }
        paletteReturnFocus = window?.firstResponder
        viewState.isCommandPaletteVisible = true
    }

    /// 关闭 Palette 并还焦点（Esc / 执行命令）。
    func dismissCommandPalette() {
        guard viewState.isCommandPaletteVisible else { return }
        viewState.isCommandPaletteVisible = false
        if let responder = paletteReturnFocus {
            window?.makeFirstResponder(responder)
        }
        paletteReturnFocus = nil
    }

    // MARK: - Workspace commands（菜单 / Command Palette 经 ShortcutRegistry action 调用）

    /// Rename Workspace… 对话框（⌘⇧R）。
    func promptRenameWorkspace() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Workspace")
        alert.informativeText = String(localized: "Empty to restore the directory name.")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = viewState.customTitle ?? workspace.currentURL.lastPathComponent
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            viewState.isCustomTitle = false
            viewState.customTitle = nil
            window?.title = workspace.currentURL.lastPathComponent
        } else {
            viewState.isCustomTitle = true
            viewState.customTitle = trimmed
            window?.title = trimmed
        }
        manager?.persistSession()
    }

    /// 把选中项路径以 shell-escaped 形式写入活动终端（⌘↩）。
    func sendSelectionPathToTerminal() {
        guard !workspace.selectedURLs.isEmpty else { return }
        if !viewState.isTerminalVisible {
            viewState.isTerminalVisible = true
            if store.sessions.isEmpty { createTerminal() }
        }
        guard let activeID = viewState.activeTerminalID else { return }
        let escaped = ShellEscape.escapeMultiple(
            workspace.selectedURLs.map { $0.path(percentEncoded: false) }
        )
        DispatchQueue.main.async { self.engineHandle.writeText(escaped, to: activeID) }
    }

    // MARK: - Window delegate

    func windowDidBecomeKey(_ notification: Notification) {
        refreshTabGroupCache()
        manager?.controllerDidBecomeKey(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        // 同组新窗成 key 时本窗 resign——两个时机合起来覆盖组关系变化。
        refreshTabGroupCache()
        // ⌘⇥ 切走 app / 切到其他窗口时收起浮窗（松开 ⌘ 的 flagsChanged 不会再送达本窗口）。
        overlayTracker.reset()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        manager?.persistSession()
    }

    func windowDidMove(_ notification: Notification) {
        manager?.persistSession()
    }

    func windowWillClose(_ notification: Notification) {
        removeShortcutMonitors()
        if let engine {
            for s in store.sessions {
                engine.closeSession(s.id)
            }
        }
        manager?.controllerWillClose(self)
        // 同步卸载 SwiftUI 视图树：关闭后 runloop 里残留的渲染更新不得再触碰
        // engineHandle（engine 生命周期短于 controller 的场景，如单测，会命中 fatalError）。
        window?.contentViewController = nil
    }
}
