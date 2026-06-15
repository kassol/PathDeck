import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var workspaceModel: WorkspaceModel?
    @Entry var sendPathAction: (([URL]) -> Void)?
}

enum BottomPanelTab: Hashable {
    case terminal
    case changes
    case diff(path: String)
}

struct ContentView: View {
    @State private var model = WorkspaceModel()
    @State private var terminalEngine = GhosttyTerminalEngine()
    @State private var terminalHeight: CGFloat = 250
    @State private var terminalSessions: [TerminalSession] = []
    @State private var activeTerminalID: UUID?
    @State private var activeBottomTab: BottomPanelTab = .terminal

    private let terminalMinHeight: CGFloat = 100
    private let terminalMaxFraction: CGFloat = 0.6

    var body: some View {
        NavigationSplitView {
            SidebarView(
                currentURL: model.currentURL,
                onNavigate: { url in
                    model.navigate(to: url)
                }
            )
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            GeometryReader { geometry in
                workspaceContent(geometry: geometry)
            }
            .coordinateSpace(name: "workspace")
            .frame(minWidth: 520, minHeight: 480)
            .navigationTitle(model.currentURL.lastPathComponent)
            .navigationSubtitle(
                (model.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { model.goUp() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("返回上级")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isBottomPanelVisible.toggle()
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .help(model.isBottomPanelVisible ? "隐藏底部面板" : "显示底部面板")
                }
            }
            .onChange(of: model.isBottomPanelVisible) { _, visible in
                if visible && terminalSessions.isEmpty {
                    createTerminalTab()
                }
            }
            .onChange(of: activeTerminalID) { _, newID in
                model.activeTerminalSessionID = newID
            }
            .focusedSceneValue(\.workspaceModel, model)
            .focusedSceneValue(\.sendPathAction) { urls in
                sendPathToTerminal(urls)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else { return }
                    DispatchQueue.main.async {
                        model.navigate(to: url)
                        RecentFolders.shared.add(url)
                    }
                }
                return true
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            terminalEngine.onSessionClose = { [self] id in
                closeTerminalTab(id)
            }
        }
    }

    // MARK: - Workspace Content

    @ViewBuilder
    private func workspaceContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            PathBarView(segments: model.pathSegments) { url in
                model.navigate(to: url)
            }

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

            FileTableView(
                items: model.items,
                pendingRenameURL: model.pendingRenameURL,
                changeIndicators: model.changeIndicators,
                scrollToURL: model.scrollToURL,
                onOpen: { model.enter($0) },
                onSort: { column, ascending in
                    model.applySort(column: column, ascending: ascending)
                },
                onSelectionChange: { items in
                    model.selectedURLs = items.map(\.url)
                },
                onTrash: { model.trashItems() },
                onRename: { model.renameItem(from: $0, to: $1) },
                onNewFolder: { model.newFolder() },
                onClearPendingRename: { model.pendingRenameURL = nil },
                onClearScrollToURL: { model.scrollToURL = nil },
                onSendPathToTerminal: { urls in
                    sendPathToTerminal(urls)
                }
            )

            // Bottom panel
            if model.isBottomPanelVisible {
                TerminalDividerView(
                    height: $terminalHeight,
                    minHeight: terminalMinHeight,
                    maxHeight: geometry.size.height * terminalMaxFraction,
                    containerHeight: geometry.size.height
                )

                BottomPanelBar(
                    activeTab: $activeBottomTab,
                    terminalSessions: $terminalSessions,
                    activeTerminalID: $activeTerminalID,
                    changeCount: model.changes.count,
                    onNewTerminalTab: { createTerminalTab() },
                    onCloseTerminalTab: { closeTerminalTab($0) }
                )
            }

            // Terminal content (keep in view tree for session preservation)
            if !terminalSessions.isEmpty {
                TerminalPanelView(
                    activeSessionID: activeTerminalID,
                    sessionIDs: Set(terminalSessions.map(\.id)),
                    engine: terminalEngine,
                    isActive: model.isBottomPanelVisible && activeBottomTab == .terminal
                )
                .frame(height: model.isBottomPanelVisible && activeBottomTab == .terminal
                       ? terminalHeight : 0)
                .clipped()
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleTerminalDrop(providers)
                }
            }

            // Changes content (keep in view tree to preserve @State filter)
            ChangeListView(
                events: model.changes,
                versionedPaths: model.versionedPaths,
                hiddenCount: model.hiddenCount,
                onRulesChanged: { model.reload() },
                onNavigate: { event in
                    let url = URL(fileURLWithPath: event.path)
                    if FileManager.default.fileExists(atPath: event.path) {
                        model.selectedURLs = [url]
                        model.scrollToURL = url
                    }
                },
                onDiff: { path in
                    activeBottomTab = .diff(path: path)
                }
            )
            .frame(height: model.isBottomPanelVisible && activeBottomTab == .changes
                   ? terminalHeight : 0)
            .clipped()

            // Diff content
            if case .diff(let diffPath) = activeBottomTab, let vs = model.versionStore {
                DiffView(
                    path: diffPath,
                    versionStore: vs,
                    onClose: { activeBottomTab = .changes },
                    onRestored: {
                        model.reload()
                        activeBottomTab = .changes
                    }
                )
                .id(diffPath)
                .frame(height: model.isBottomPanelVisible ? terminalHeight : 0)
                .clipped()
            }
        }
    }

    // MARK: - Terminal Tab Management

    private func createTerminalTab() {
        let id = terminalEngine.createSession(cwd: model.currentURL)
        let index = terminalSessions.count + 1
        let title = index == 1 ? "Terminal" : "Terminal \(index)"
        terminalSessions.append(TerminalSession(id: id, title: title, cwd: model.currentURL))
        activeTerminalID = id
    }

    private func closeTerminalTab(_ id: UUID) {
        terminalEngine.closeSession(id)
        terminalSessions.removeAll { $0.id == id }
        if activeTerminalID == id {
            activeTerminalID = terminalSessions.last?.id
        }
        if terminalSessions.isEmpty && activeBottomTab == .terminal {
            model.isBottomPanelVisible = false
        } else if terminalSessions.isEmpty {
            activeBottomTab = .changes
        }
    }

    // MARK: - Terminal Input

    private func handleTerminalDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let activeID = activeTerminalID else { return false }
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
        if !model.isBottomPanelVisible {
            model.isBottomPanelVisible = true
            if terminalSessions.isEmpty { createTerminalTab() }
        }
        activeBottomTab = .terminal
        guard let activeID = activeTerminalID else { return }
        let escaped = ShellEscape.escapeMultiple(
            urls.map { $0.path(percentEncoded: false) }
        )
        DispatchQueue.main.async {
            terminalEngine.writeText(escaped, to: activeID)
        }
    }
}

// MARK: - Bottom Panel Bar

private struct BottomPanelBar: View {
    @Binding var activeTab: BottomPanelTab
    @Binding var terminalSessions: [TerminalSession]
    @Binding var activeTerminalID: UUID?
    var changeCount: Int
    var onNewTerminalTab: () -> Void
    var onCloseTerminalTab: (UUID) -> Void

    private var isDiff: Bool {
        if case .diff = activeTab { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 0) {
            if activeTab == .terminal {
                TerminalTabBar(
                    sessions: $terminalSessions,
                    activeID: $activeTerminalID,
                    onNewTab: onNewTerminalTab,
                    onCloseTab: onCloseTerminalTab
                )
            } else {
                Button { activeTab = .terminal } label: {
                    Label("终端", systemImage: "terminal")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }

            Spacer()

            if isDiff {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                    Text("比较")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
            }

            Button { activeTab = .changes } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                    Text("变化")
                        .font(.system(size: 11))
                    if changeCount > 0 {
                        Text("\(changeCount)")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(activeTab == .changes ? .primary : .secondary)
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(.bar)
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
    var onNavigate: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
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
