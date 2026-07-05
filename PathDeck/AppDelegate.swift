import AppKit

/// AppKit 接管 window 生命周期：启动时构造 WorkspaceManager、关闭系统自动 tabbing、
/// 注册 URL Scheme / Services。所有 workspace window 由 WorkspaceManager 自管。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var workspaceManager: WorkspaceManager!
    private let servicesProvider = ServicesProvider()
    private var routeObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider

        let manager = WorkspaceManager()
        workspaceManager = manager
        // 全局兜底命令取 manager 的唯一注册点（NSApp.delegate 是 SwiftUI 转发 delegate，
        // cast 不回 AppDelegate）。
        WorkspaceManager.appShared = manager
        // 全局唯一 keystroke monitor（S38）：keystroke → CommandDispatch → 命令表。
        manager.installCommandMonitor()
        manager.restoreSession()

        // 先同步 drain 启动前累积的 pending 队列（kAEGetURL / application(_:open:) 都在 didFinishLaunching 之前触发；
        // Finder 多选 Open With 会一次 enqueue 多条 .open）。
        // 这样冷启动 URL Scheme / Open With 直接打开目标 window；
        // 否则若先开 Home 再 drain 会导致 Home + target 两个 window。
        drainPendingRoutes()

        if manager.controllers.isEmpty {
            manager.openNewWindow(cwd: FileManager.default.homeDirectoryForCurrentUser)
        }
        observePending()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        // 优先恢复已有但被最小化/隐藏的 controller；只有真没有任何 controller 时才开 Home。
        if let existing = workspaceManager.controllers.first {
            existing.window?.deminiaturize(nil)
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            workspaceManager.openNewWindow(cwd: FileManager.default.homeDirectoryForCurrentUser)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// app 退出前 flush 一次 session state；debounce 路径在退出时可能丢未写盘的最近变化。
    func applicationWillTerminate(_ notification: Notification) {
        workspaceManager?.persistSessionImmediately()
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              let route = URLSchemeHandler.route(for: url) else { return }
        AppRouter.shared.request(route)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false), isDirectory: &isDir
            ), isDir.boolValue else { continue }
            AppRouter.shared.request(.open(url.standardizedFileURL))
        }
    }

    // MARK: - Route drain

    /// 注册对 `AppRouter.pending` 的持续观察；首次 drain 由 `applicationDidFinishLaunching` 同步路径完成，
    /// 此处仅 observe 后续变化（每次变化在主队列异步 drain + 重新 arm observer）。
    /// 所有外部入口（URL Scheme / Services / Open With）均归一到此唯一消费路径；WorkspaceRootView 不再消费 router.pending。
    private func observePending() {
        withObservationTracking {
            _ = workspaceManager?.router.pending
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.drainPendingRoutes()
                self?.observePending()
            }
        }
    }

    /// 循环 drain 直到队列空，处理 Finder 多选 Open With 一次投递多条 .open 的场景。
    @MainActor
    private func drainPendingRoutes() {
        while workspaceManager?.router.pending.first != nil {
            drainPendingRoute()
        }
    }

    @MainActor
    private func drainPendingRoute() {
        guard let route = workspaceManager?.router.consume() else { return }
        let manager = workspaceManager!
        let tabbedTo = manager.keyController?.window
        switch route {
        case .open(let url):
            if let controller = manager.findController(matchingCwd: url) {
                controller.window?.makeKeyAndOrderFront(nil)
                controller.workspace.navigate(to: url)
            } else {
                manager.openNewWindow(cwd: url, tabbedTo: tabbedTo)
            }
            RecentFolders.shared.add(url)
        case .reveal(let urls):
            // 先按目标父目录匹配已有 workspace，避免：已开 /A 和 /B，当前 key 是 /A，
            // reveal /B/file 把 /A 的 currentURL 误改成 /B（既污染 /A 又重复已有的 /B）。
            guard let first = urls.first else { break }
            let parent = first.deletingLastPathComponent()
            if let existing = manager.findController(matchingCwd: parent) {
                existing.window?.makeKeyAndOrderFront(nil)
                existing.workspace.reveal(urls)
            } else if let c = manager.keyController ?? manager.controllers.first {
                c.window?.makeKeyAndOrderFront(nil)
                c.workspace.reveal(urls)
            } else {
                // 无任何 workspace 时按首项父目录开 window，再 reveal。
                let c = manager.openNewWindow(cwd: parent, tabbedTo: nil)
                c.workspace.reveal(urls)
            }
        case .terminal(let url, let requireConfirmation):
            // 用户 Cancel 必须能完全阻止——不创建/激活 window，也不导航。
            if requireConfirmation, !confirmOpenTerminal(at: url) { return }
            let target: WorkspaceController = {
                if let c = manager.findController(matchingCwd: url) { return c }
                return manager.openNewWindow(cwd: url, tabbedTo: tabbedTo)
            }()
            target.window?.makeKeyAndOrderFront(nil)
            target.workspace.navigate(to: url)
            target.createTerminal(cwdOverride: url)
            target.viewState.isTerminalVisible = true
            RecentFolders.shared.add(url)
        }
    }

    @MainActor
    private func confirmOpenTerminal(at url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Open Terminal in this directory?")
        alert.informativeText = String(localized: "An external request wants to open a terminal in:\n\(url.path(percentEncoded: false))")
        alert.addButton(withTitle: String(localized: "Open Terminal"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
