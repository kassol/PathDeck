import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var workspaceModel: WorkspaceModel?
    @Entry var tabManager: TabManager?
    @Entry var sendPathAction: (([URL]) -> Void)?
    @Entry var togglePreviewPaneAction: (() -> Void)?
    @Entry var createTerminalAction: (() -> Void)?
}

struct ContentView: View {
    @State private var tabManager = TabManager()
    @State private var terminalEngine = GhosttyTerminalEngine()
    @State private var terminalHeight: CGFloat = 250
    @State private var verticalTabWidth: CGFloat = 140
    @State private var isPreviewPaneVisible: Bool = true
    @State private var hasRestoredState: Bool = false
    @State private var closeTabMonitor: Any?

    private let router = AppRouter.shared

    private let terminalMinHeight: CGFloat = 100
    private let terminalMaxFraction: CGFloat = 0.6

    private static let bottomPanelHeightKey = "bottomPanelHeight"
    private static let verticalTabWidthKey = "verticalTabWidth"
    private static let previewPaneVisibleKey = "previewPaneVisible"

    private var model: WorkspaceModel? { tabManager.activeModel }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                currentURL: model?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser,
                onNavigate: { url in
                    model?.navigate(to: url)
                }
            )
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            GeometryReader { geometry in
                workspaceContent(geometry: geometry)
            }
            .coordinateSpace(name: "workspace")
            .frame(minWidth: 520, minHeight: 480)
            .navigationTitle(model?.currentURL.lastPathComponent ?? "PathDeck")
            .navigationSubtitle(
                model.map {
                    ($0.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
                } ?? ""
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { model?.goUp() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("返回上级")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPreviewPaneVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isPreviewPaneVisible ? "隐藏预览面板" : "显示预览面板")
                }
                ToolbarItem(placement: .primaryAction) {
                    if tabManager.activeTabMode == .finderFirst {
                        Button {
                            tabManager.toggleTerminalVisibility()
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .help(tabManager.activeTabTerminalVisible ? "隐藏终端" : "显示终端")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        tabManager.toggleActiveTabMode()
                    } label: {
                        Image(systemName: tabManager.activeTabMode == .terminalFirst
                              ? "rectangle.split.2x1" : "rectangle.bottomhalf.filled")
                    }
                    .help(tabManager.activeTabMode == .terminalFirst ? "Finder-first 模式" : "Terminal-first 模式")
                }
            }
            .onChange(of: tabManager.activeTabTerminalVisible) { _, visible in
                if visible && tabManager.activeTabSessions.isEmpty {
                    createTerminalTab()
                }
            }
            .onChange(of: router.pending) { _, _ in
                handleExternalRoute()
            }
            .focusedSceneValue(\.workspaceModel, model)
            .focusedSceneValue(\.tabManager, tabManager)
            .focusedSceneValue(\.sendPathAction) { urls in
                sendPathToTerminal(urls)
            }
            .focusedSceneValue(\.togglePreviewPaneAction) {
                isPreviewPaneVisible.toggle()
            }
            .focusedSceneValue(\.createTerminalAction) {
                createTerminalTab()
                if !tabManager.activeTabTerminalVisible { tabManager.activeTabTerminalVisible = true }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else { return }
                    DispatchQueue.main.async {
                        model?.navigate(to: url)
                        RecentFolders.shared.add(url)
                    }
                }
                return true
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { setupEngineCallbacks(); restoreState(); handleExternalRoute(); installCloseTabMonitor() }
        .onDisappear { removeCloseTabMonitor(); tabManager.saveTabState() }
        .modifier(StatePersistenceModifier(
            tabManager: tabManager,
            terminalHeight: terminalHeight,
            verticalTabWidth: verticalTabWidth,
            isPreviewPaneVisible: isPreviewPaneVisible,
            onSaveTabState: { tabManager.saveTabState() }
        ))
    }

    private func setupEngineCallbacks() {
        terminalEngine.onSessionClose = { [self] id in
            closeTerminalTab(id)
        }
        terminalEngine.onCwdChange = { [self] id, url in
            tabManager.updateTerminalCwd(id, to: url)
            tabManager.saveTabState()
        }
        terminalEngine.onTitleChange = { [self] id, title in
            guard tabManager.terminalSessions[id]?.isManuallyRenamed != true else { return }
            tabManager.renameTerminalSession(id, to: title)
        }
        terminalEngine.onPendingDropped = { id, count, reason in
            NSLog("[PathDeck] dropped %d pending text(s) for session %@: %@",
                  count, id.uuidString, String(describing: reason))
        }
    }

    // MARK: - Workspace Content

    @ViewBuilder
    private func workspaceContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            FileTabBar(
                tabs: tabManager.fileTabs,
                activeTabID: tabManager.activeFileTabID,
                tabModels: tabManager.workspaceModels,
                onSelect: { tabManager.switchTab(to: $0) },
                onClose: { closeFileTab($0) },
                onNewTab: { newFileTab() },
                onRename: { tabManager.renameTab($0, to: $1) }
            )

            if tabManager.activeTabMode == .finderFirst {
                finderFirstContent(geometry: geometry)
            } else {
                terminalFirstContent()
            }
        }
    }

    @ViewBuilder
    private func finderFirstContent(geometry: GeometryProxy) -> some View {
        if let model {
            PathBarView(
                segments: model.pathSegments,
                anchorCwd: tabManager.activeTab?.terminalAnchorCwd,
                currentURL: model.currentURL,
                onNavigate: { model.navigate(to: $0) }
            )

            if model.isSearching {
                Divider()
                SearchBarView(
                    query: Binding(
                        get: { model.searchQuery },
                        set: { model.searchQuery = $0 }
                    ),
                    onDismiss: {
                        model.isSearching = false
                        model.searchQuery = ""
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
            }

            Divider()

            HStack(spacing: 0) {
                FileTableView(
                    items: model.items,
                    pendingRenameURL: model.pendingRenameURL,
                    revealSelection: model.revealSelection,
                    onOpen: { model.enter($0) },
                    onSort: { column, ascending in
                        tabManager.applySort(column: column, ascending: ascending)
                    },
                    onSelectionChange: { items in
                        model.selectedURLs = items.map(\.url)
                    },
                    onTrash: { model.trashItems() },
                    onRename: { model.renameItem(from: $0, to: $1) },
                    onNewFolder: { model.newFolder() },
                    onClearPendingRename: { model.pendingRenameURL = nil },
                    onClearRevealSelection: { model.revealSelection = nil },
                    onSendPathToTerminal: { urls in
                        sendPathToTerminal(urls)
                    }
                )

                if isPreviewPaneVisible {
                    Divider()
                    PreviewPane(
                        selectedURLs: model.selectedURLs,
                        currentDirectory: model.currentURL,
                        onSendPath: { urls in sendPathToTerminal(urls) }
                    )
                }
            }

            if tabManager.activeTabTerminalVisible {
                TerminalDividerView(
                    height: $terminalHeight,
                    minHeight: terminalMinHeight,
                    maxHeight: geometry.size.height * terminalMaxFraction,
                    containerHeight: geometry.size.height
                )

                BottomPanelBar(
                    sessions: tabManager.activeTabSessions,
                    activeTerminalID: tabManager.activeTerminalID,
                    onSelect: { tabManager.setActiveTerminal($0) },
                    onNewTerminalTab: { createTerminalTab() },
                    onCloseTerminalTab: { closeTerminalTab($0) },
                    onRename: { tabManager.renameTerminalSession($0, to: $1, manual: true) },
                    onNavigateToCwd: { url in model.navigate(to: url) }
                )
            }

            if !tabManager.allTerminalSessionIDs.isEmpty {
                TerminalPanelView(
                    activeSessionID: tabManager.activeTerminalID,
                    sessionIDs: tabManager.allTerminalSessionIDs,
                    engine: terminalEngine,
                    isActive: tabManager.activeTabTerminalVisible
                )
                .frame(height: tabManager.activeTabTerminalVisible ? terminalHeight : 0)
                .clipped()
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleTerminalDrop(providers)
                }
            }
        }
    }

    @ViewBuilder
    private func terminalFirstContent() -> some View {
        HStack(spacing: 0) {
            VerticalTerminalTabBar(
                sessions: tabManager.activeTabSessions,
                activeID: tabManager.activeTerminalID,
                onSelect: { tabManager.setActiveTerminal($0) },
                onNewTab: { createTerminalTab() },
                onCloseTab: { closeTerminalTab($0) },
                onRename: { tabManager.renameTerminalSession($0, to: $1, manual: true) },
                onNavigateToCwd: { url in model?.navigate(to: url) }
            )
            .frame(width: verticalTabWidth)

            VerticalDividerView(
                width: $verticalTabWidth,
                minWidth: 100,
                maxWidth: 300
            )

            if !tabManager.allTerminalSessionIDs.isEmpty {
                TerminalPanelView(
                    activeSessionID: tabManager.activeTerminalID,
                    sessionIDs: tabManager.allTerminalSessionIDs,
                    engine: terminalEngine,
                    isActive: true
                )
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleTerminalDrop(providers)
                }
            } else {
                Color.clear
            }
        }
    }

    // MARK: - External Entry (URL Scheme / Services / Open With)

    private func handleExternalRoute() {
        guard let route = router.consume() else { return }
        DispatchQueue.main.async {
            switch route {
            case .open(let url):
                model?.navigate(to: url)
                RecentFolders.shared.add(url)
            case .reveal(let urls):
                model?.reveal(urls)
            case .terminal(let url, let requireConfirmation):
                if requireConfirmation, !confirmOpenTerminal(at: url) { return }
                if let existingTab = tabManager.findTabByAnchorOrCwd(url) {
                    tabManager.switchTab(to: existingTab)
                } else {
                    tabManager.createTab(at: url)
                }
                RecentFolders.shared.add(url)
                createTerminalTab(cwd: url)
                if !tabManager.activeTabTerminalVisible {
                    tabManager.activeTabTerminalVisible = true
                }
            }
        }
    }

    private func confirmOpenTerminal(at url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "在此目录打开终端？"
        alert.informativeText = "一个外部请求要在以下目录打开终端：\n\(url.path(percentEncoded: false))"
        alert.addButton(withTitle: "打开终端")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - ⌘W Monitor

    private func installCloseTabMonitor() {
        closeTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w" else {
                return event
            }
            if NSApp.keyWindow?.firstResponder is GhosttySurfaceView,
               let sessionID = tabManager.activeTerminalID {
                closeTerminalTab(sessionID)
                return nil
            }
            guard tabManager.fileTabs.count > 1,
                  let id = tabManager.activeFileTabID else {
                return event
            }
            closeFileTab(id)
            return nil
        }
    }

    private func removeCloseTabMonitor() {
        if let monitor = closeTabMonitor {
            NSEvent.removeMonitor(monitor)
            closeTabMonitor = nil
        }
    }

    // MARK: - File Tab Management

    private func newFileTab() {
        let cwd = model?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
        tabManager.createTab(at: cwd)
    }

    private func closeFileTab(_ id: UUID) {
        if tabManager.fileTabs.count <= 1 {
            NSApp.keyWindow?.close()
            return
        }
        let tab = tabManager.fileTabs.first { $0.id == id }
        if let tab {
            for sessionID in tab.terminalSessionIDs {
                terminalEngine.closeSession(sessionID)
            }
        }
        tabManager.closeTab(id)
    }

    // MARK: - Terminal Tab Management

    private func createTerminalTab(cwd override: URL? = nil) {
        guard let tabID = tabManager.activeFileTabID,
              let tab = tabManager.activeTab else { return }

        let cwd = override ?? tab.terminalAnchorCwd ?? model?.currentURL
            ?? FileManager.default.homeDirectoryForCurrentUser
        let id = terminalEngine.createSession(cwd: cwd)
        let count = tab.terminalSessionIDs.count + 1
        let title = count == 1 ? "Terminal" : "Terminal \(count)"
        let session = TerminalSession(id: id, title: title, cwd: cwd)
        tabManager.addTerminalSession(session, to: tabID)
    }

    private func closeTerminalTab(_ id: UUID) {
        let ownerTab = tabManager.ownerTabID(for: id)
        terminalEngine.closeSession(id)
        tabManager.removeTerminalSession(id)

        if ownerTab == tabManager.activeFileTabID,
           tabManager.activeTabSessions.isEmpty,
           tabManager.activeTabMode == .finderFirst {
            tabManager.activeTabTerminalVisible = false
        }
    }

    // MARK: - Terminal Input

    private func handleTerminalDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let activeID = tabManager.activeTerminalID else { return false }
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [activeID] in
            guard !urls.isEmpty else { return }
            let escaped = ShellEscape.escapeMultiple(
                urls.map { $0.path(percentEncoded: false) }
            )
            terminalEngine.writeText(escaped, to: activeID)
        }
        return true
    }

    private func sendPathToTerminal(_ urls: [URL]) {
        if !tabManager.activeTabTerminalVisible {
            tabManager.activeTabTerminalVisible = true
            if tabManager.activeTabSessions.isEmpty { createTerminalTab() }
        }
        guard let activeID = tabManager.activeTerminalID else { return }
        let escaped = ShellEscape.escapeMultiple(
            urls.map { $0.path(percentEncoded: false) }
        )
        DispatchQueue.main.async {
            terminalEngine.writeText(escaped, to: activeID)
        }
    }

    // MARK: - State Persistence

    private func restoreState() {
        guard !hasRestoredState else { return }
        hasRestoredState = true

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.bottomPanelHeightKey) != nil {
            terminalHeight = CGFloat(defaults.double(forKey: Self.bottomPanelHeightKey))
        }
        if defaults.object(forKey: Self.verticalTabWidthKey) != nil {
            verticalTabWidth = CGFloat(defaults.double(forKey: Self.verticalTabWidthKey))
        }
        if defaults.object(forKey: Self.previewPaneVisibleKey) != nil {
            isPreviewPaneVisible = defaults.bool(forKey: Self.previewPaneVisibleKey)
        }

        tabManager.restoreTabState(terminalEngine: terminalEngine)
    }
}

// MARK: - Bottom Panel Bar

private struct BottomPanelBar: View {
    var sessions: [TerminalSession]
    var activeTerminalID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTerminalTab: () -> Void
    var onCloseTerminalTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            TerminalTabBar(
                sessions: sessions,
                activeID: activeTerminalID,
                onSelect: onSelect,
                onNewTab: onNewTerminalTab,
                onCloseTab: onCloseTerminalTab,
                onRename: onRename,
                onNavigateToCwd: onNavigateToCwd
            )
        }
        .frame(height: 28)
        .background(.bar)
    }
}

// MARK: - Vertical Tab Divider

private struct VerticalDividerView: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("workspace"))
                    .onChanged { value in
                        width = max(minWidth, min(value.location.x, maxWidth))
                    }
            )
    }
}

// MARK: - Terminal Divider

private struct TerminalDividerView: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let containerHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("workspace"))
                    .onChanged { value in
                        let newHeight = containerHeight - value.location.y
                        height = max(minHeight, min(newHeight, maxHeight))
                    }
            )
    }
}

// MARK: - Path Bar

private struct PathBarView: View {
    var segments: [(name: String, url: URL)]
    var anchorCwd: URL?
    var currentURL: URL
    var onNavigate: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if let anchor = anchorCwd, anchor.standardizedFileURL != currentURL.standardizedFileURL {
                    Button {
                        onNavigate(anchor)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "anchor")
                                .font(.system(size: 9))
                            Text(anchor.lastPathComponent)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("回到锚定目录: \(anchor.path(percentEncoded: false))")

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                    Button {
                        onNavigate(segment.url)
                    } label: {
                        Text(segment.name)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                index == segments.count - 1 ? .primary : .secondary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(height: 24)
        .background(.bar)
        .accessibilityIdentifier("pathBar")
    }
}

// MARK: - State Persistence Modifier

private struct StatePersistenceModifier: ViewModifier {
    let tabManager: TabManager
    let terminalHeight: CGFloat
    let verticalTabWidth: CGFloat
    let isPreviewPaneVisible: Bool
    let onSaveTabState: () -> Void

    func body(content: Content) -> some View {
        let withTabState = content
            .onChange(of: tabManager.allTerminalSessionIDs.count) { _, _ in
                onSaveTabState()
            }
            .onChange(of: tabManager.fileTabs.count) { _, _ in
                onSaveTabState()
            }
            .onChange(of: tabManager.activeFileTabID) { _, _ in
                onSaveTabState()
            }
            .onChange(of: tabManager.activeTabTerminalVisible) { _, _ in
                onSaveTabState()
            }
            .onChange(of: tabManager.activeTabMode) { _, _ in
                onSaveTabState()
            }
        return withTabState
            .onChange(of: terminalHeight) { _, newValue in
                UserDefaults.standard.set(Double(newValue), forKey: "bottomPanelHeight")
            }
            .onChange(of: verticalTabWidth) { _, newValue in
                UserDefaults.standard.set(Double(newValue), forKey: "verticalTabWidth")
            }
            .onChange(of: isPreviewPaneVisible) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "previewPaneVisible")
            }
    }
}
