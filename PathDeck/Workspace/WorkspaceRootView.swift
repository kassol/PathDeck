import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    /// 仅用于让 menu commands 跟随当前 key workspace 的 selection 状态变化重新计算
    /// `.disabled(...)`；菜单 action 内不要走 @FocusedValue 读，仍用严格的 `keyWorkspaceController()`。
    @Entry var activeWorkspaceController: WorkspaceController?
}

/// 单个 NSWindow 的 SwiftUI root view。由 WorkspaceController 创建并注入 NSHostingController。
struct WorkspaceRootView: View {
    @State var controller: WorkspaceController
    @State var preferences: WorkspacePreferences
    @State var pinnedFolders: PinnedFolders


    private var workspace: WorkspaceModel { controller.workspace }
    private var viewState: WorkspaceViewState { controller.viewState }
    private var store: TerminalSessionStore { controller.store }

    /// Sidebar 显隐（per-window Session State）↔ NavigationSplitView 列可见性。
    /// 系统 toolbar 的 sidebar toggle 与 ⌘B 菜单命令都经由这一个绑定收敛。
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { viewState.isSidebarVisible ? .all : .detailOnly },
            set: { viewState.isSidebarVisible = ($0 != .detailOnly) }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            SidebarView(
                currentURL: workspace.currentURL,
                onNavigate: { url in workspace.navigate(to: url) }
            )
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            GeometryReader { geometry in
                workspaceContent(geometry: geometry)
            }
            .coordinateSpace(name: "workspace")
            .frame(minWidth: 520, minHeight: 480)
            .navigationTitle(workspace.currentURL.lastPathComponent)
            .navigationSubtitle(
                (workspace.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { workspace.goUp() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Go to Parent")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewState.isPreviewPaneVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(LocalizedStringKey(viewState.isPreviewPaneVisible ? "Hide Preview Pane" : "Show Preview Pane"))
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewState.mode == .finderFirst {
                        Button {
                            viewState.isTerminalVisible.toggle()
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .help(LocalizedStringKey(viewState.isTerminalVisible ? "Hide Terminal" : "Show Terminal"))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleMode()
                    } label: {
                        Image(systemName: viewState.mode == .terminalFirst
                              ? "rectangle.split.2x1" : "rectangle.bottomhalf.filled")
                    }
                    .help(LocalizedStringKey(viewState.mode == .terminalFirst ? "Finder-first Mode" : "Terminal-first Mode"))
                }
            }
            .onChange(of: viewState.isTerminalVisible) { _, visible in
                if visible && store.sessions.isEmpty {
                    controller.createTerminal()
                }
            }
            .onChange(of: workspace.currentURL) { _, _ in controller.window?.title = effectiveTitle() }
            .onChange(of: viewState.customTitle) { _, _ in controller.window?.title = effectiveTitle() }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else { return }
                    DispatchQueue.main.async {
                        workspace.navigate(to: url)
                        RecentFolders.shared.add(url)
                    }
                }
                return true
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .overlay {
            // 长按 ⌘ 快捷键浮窗：纯展示不拦截交互；显隐由 WorkspaceController
            // 的 overlay monitor 经 viewState 驱动。
            if viewState.isShortcutOverlayVisible {
                ShortcutOverlayView()
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewState.isShortcutOverlayVisible)
        .focusedSceneValue(\.activeWorkspaceController, controller)
        .onAppear { controller.installShortcutMonitors() }
        .onDisappear { controller.removeShortcutMonitors() }
        .modifier(WorkspacePersistenceModifier(controller: controller))
    }

    // MARK: - Workspace content

    @ViewBuilder
    private func workspaceContent(geometry: GeometryProxy) -> some View {
        if viewState.mode == .finderFirst {
            finderFirstContent(geometry: geometry)
        } else {
            terminalFirstContent()
        }
    }

    @ViewBuilder
    private func finderFirstContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            PathBarView(
                segments: workspace.pathSegments,
                anchorCwd: viewState.terminalAnchorCwd,
                currentURL: workspace.currentURL,
                onNavigate: { workspace.navigate(to: $0) }
            )

            if workspace.isSearching {
                Divider()
                SearchBarView(
                    query: Binding(
                        get: { workspace.searchQuery },
                        set: { workspace.searchQuery = $0 }
                    ),
                    onDismiss: {
                        workspace.isSearching = false
                        workspace.searchQuery = ""
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
            }

            Divider()

            HStack(spacing: 0) {
                FileTableView(
                    items: workspace.items,
                    outlineDataSource: workspace.outlineDataSource,
                    isSearching: workspace.isSearching,
                    dirtyDirectories: workspace.dirtyDirectories,
                    pendingRenameURL: workspace.pendingRenameURL,
                    revealSelection: workspace.revealSelection,
                    initialColumnWidths: preferences.columnWidths,
                    initialSortColumn: workspace.sortColumn.rawValue,
                    initialSortAscending: workspace.sortAscending,
                    onOpen: { workspace.enter($0) },
                    onSort: { column, ascending in
                        controller.applySortViaManager(column: column, ascending: ascending)
                    },
                    onSelectionChange: { items in
                        workspace.selectedURLs = items.map(\.url)
                    },
                    onTrash: { workspace.trashItems() },
                    onRename: { workspace.renameItem(from: $0, to: $1) },
                    onNewFolder: { workspace.newFolder() },
                    onClearPendingRename: { workspace.pendingRenameURL = nil },
                    onClearRevealSelection: { workspace.revealSelection = nil },
                    onClearDirtyDirectories: { workspace.dirtyDirectories = nil },
                    onSendPathToTerminal: { urls in sendPathToTerminal(urls) },
                    onExpandCollapse: { workspace.updateWatcherExpandedDirectories() },
                    onPasteFiles: { urls, op in workspace.pasteFiles(urls, operation: op) },
                    onDuplicate: { workspace.duplicateItems() },
                    onColumnResize: { id, width in preferences.columnWidths[id] = width }
                )

                if viewState.isPreviewPaneVisible {
                    Divider()
                    PreviewPane(
                        selectedURLs: workspace.selectedURLs,
                        currentDirectory: workspace.currentURL,
                        onSendPath: { urls in sendPathToTerminal(urls) }
                    )
                }
            }

            if viewState.isTerminalVisible {
                TerminalDividerView(
                    height: Binding(
                        get: { preferences.bottomPanelHeight },
                        set: { preferences.bottomPanelHeight = $0 }
                    ),
                    minHeight: 100,
                    maxHeight: geometry.size.height * 0.6,
                    containerHeight: geometry.size.height
                )

                BottomPanelBar(
                    sessions: store.sessions,
                    activeTerminalID: viewState.activeTerminalID,
                    onSelect: { viewState.activeTerminalID = $0 },
                    onNewTerminalTab: { controller.createTerminal() },
                    onCloseTerminalTab: { controller.closeTerminal($0) },
                    onRename: { controller.renameTerminal($0, to: $1, manual: true) },
                    onNavigateToCwd: { url in workspace.navigate(to: url) },
                    onReorder: { source, dest in controller.reorderTerminal(source: source, to: dest) }
                )
            }

            if !store.allIDs.isEmpty {
                TerminalPanelView(
                    activeSessionID: viewState.activeTerminalID,
                    sessionIDs: store.allIDs,
                    engine: controller.engineHandle,
                    isActive: viewState.isTerminalVisible
                )
                .frame(height: viewState.isTerminalVisible ? preferences.bottomPanelHeight : 0)
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
                sessions: store.sessions,
                activeID: viewState.activeTerminalID,
                onSelect: { viewState.activeTerminalID = $0 },
                onNewTab: { controller.createTerminal() },
                onCloseTab: { controller.closeTerminal($0) },
                onRename: { controller.renameTerminal($0, to: $1, manual: true) },
                onNavigateToCwd: { url in workspace.navigate(to: url) },
                onReorder: { source, dest in controller.reorderTerminal(source: source, to: dest) }
            )
            .frame(width: preferences.verticalTabWidth)

            VerticalDividerView(
                width: Binding(
                    get: { preferences.verticalTabWidth },
                    set: { preferences.verticalTabWidth = $0 }
                ),
                minWidth: 100,
                maxWidth: 300
            )

            if !store.allIDs.isEmpty {
                TerminalPanelView(
                    activeSessionID: viewState.activeTerminalID,
                    sessionIDs: store.allIDs,
                    engine: controller.engineHandle,
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

    // MARK: - Mode toggle

    private func toggleMode() {
        if viewState.mode == .finderFirst {
            viewState.mode = .terminalFirst
            viewState.isTerminalVisible = true
        } else {
            viewState.mode = .finderFirst
        }
    }

    private func effectiveTitle() -> String {
        if viewState.isCustomTitle, let custom = viewState.customTitle, !custom.isEmpty {
            return custom
        }
        return workspace.currentURL.lastPathComponent
    }

    // MARK: - Terminal helpers

    private func handleTerminalDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let activeID = viewState.activeTerminalID else { return false }
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        let engine = controller.engineHandle
        group.notify(queue: .main) { [activeID, engine] in
            guard !urls.isEmpty else { return }
            let escaped = ShellEscape.escapeMultiple(urls.map { $0.path(percentEncoded: false) })
            engine.writeText(escaped, to: activeID)
        }
        return true
    }

    private func sendPathToTerminal(_ urls: [URL]) {
        if !viewState.isTerminalVisible {
            viewState.isTerminalVisible = true
            if store.sessions.isEmpty { controller.createTerminal() }
        }
        guard let activeID = viewState.activeTerminalID else { return }
        let escaped = ShellEscape.escapeMultiple(urls.map { $0.path(percentEncoded: false) })
        DispatchQueue.main.async {
            controller.engineHandle.writeText(escaped, to: activeID)
        }
    }

}

// MARK: - Bottom panel bar

private struct BottomPanelBar: View {
    var sessions: [TerminalSession]
    var activeTerminalID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTerminalTab: () -> Void
    var onCloseTerminalTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?
    var onReorder: (UUID, Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            TerminalTabBar(
                sessions: sessions,
                activeID: activeTerminalID,
                onSelect: onSelect,
                onNewTab: onNewTerminalTab,
                onCloseTab: onCloseTerminalTab,
                onRename: onRename,
                onNavigateToCwd: onNavigateToCwd,
                onReorder: onReorder
            )
        }
        .frame(height: 28)
        .background(.bar)
    }
}

// MARK: - Dividers

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
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("workspace"))
                    .onChanged { value in
                        width = max(minWidth, min(value.location.x, maxWidth))
                    }
            )
    }
}

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
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
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

// MARK: - Path bar

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
                    .help("Back to anchor: \(anchor.path(percentEncoded: false))")

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

// MARK: - Persistence modifier (per-window)

private struct WorkspacePersistenceModifier: ViewModifier {
    let controller: WorkspaceController

    func body(content: Content) -> some View {
        content
            .onChange(of: controller.store.sessions.count) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.viewState.isTerminalVisible) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.viewState.isSidebarVisible) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.viewState.isPreviewPaneVisible) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.viewState.mode) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.viewState.activeTerminalID) { _, _ in controller.manager?.persistSession() }
            .onChange(of: controller.workspace.currentURL) { _, _ in controller.manager?.persistSession() }
    }
}
