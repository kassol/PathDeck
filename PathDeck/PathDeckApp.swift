import SwiftUI
import AppKit

@main
struct PathDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        ShellIntegration.prepare()
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CLICommands()
            TabCommands()
            TerminalCommands()
            FileCommands()
            ViewCommands()
        }
    }
}

/// 严格只在 NSApp.keyWindow 是 workspace window 时返回 controller。
/// Settings / 其他面板为 key 时返回 nil——菜单命令不应作用于后台 workspace。
@MainActor
private func keyWorkspaceController() -> WorkspaceController? {
    NSApp.keyWindow?.windowController as? WorkspaceController
}

@MainActor
private func workspaceManager() -> WorkspaceManager? {
    (NSApp.delegate as? AppDelegate)?.workspaceManager
}

// MARK: - CLI

private struct CLICommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Install Command Line Tool…") {
                CLIInstaller.install()
            }
        }
    }
}

// MARK: - Tab commands (NSWindow tabbing)

private struct TabCommands: Commands {
    var body: some Commands {
        CommandMenu("Tabs") {
            // Cmd+T 实际由 WorkspaceRootView 的 newTabMonitor 接管（终端焦点 → 新终端 session，
            // 文件焦点 → 新 workspace tab）；此处 action + keyboardShortcut 仅用于菜单显示 ⌘T，以及
            // Settings/alert 为 key 时的兜底（monitor 严格 keyWindow，那时 return event 放行给本 action）。
            Button("New Tab") {
                guard let manager = workspaceManager() else { return }
                let cwd = manager.keyController?.workspace.currentURL
                    ?? FileManager.default.homeDirectoryForCurrentUser
                manager.openNewWindow(cwd: cwd, tabbedTo: manager.keyController?.window)
            }
            .keyboardShortcut("t")

            Divider()

            // Next/Previous Tab 的快捷键由 WorkspaceRootView 的 NSEvent monitor 处理（严格 keyWindow），
            // 此处仅保留 menu item 文字（带兜底点击响应），不绑 SwiftUI keyboardShortcut。
            Button("Next Tab") {
                keyWorkspaceController()?.window?.selectNextTab(nil)
            }
            Button("Previous Tab") {
                keyWorkspaceController()?.window?.selectPreviousTab(nil)
            }

            Divider()

            Button("Rename Workspace…") {
                renameActiveWorkspace()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            // 1..9 menu items 仅显示，不绑 SwiftUI keyboardShortcut；快捷键由 WorkspaceRootView
            // 的 NSEvent local monitor 显式拦截、严格针对 keyWindow workspace（避免 Settings 为 key
            // 时通过 fallback 操作后台 workspace）。
            ForEach(1...9, id: \.self) { n in
                Button("Tab \(n)") {
                    selectTab(at: n - 1)
                }
            }
        }
    }

    @MainActor
    private func selectTab(at index: Int) {
        guard let tabs = keyWorkspaceController()?.window?.tabbedWindows,
              tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func renameActiveWorkspace() {
        guard let controller = keyWorkspaceController() else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Workspace")
        alert.informativeText = String(localized: "Empty to restore the directory name.")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = controller.viewState.customTitle ?? controller.workspace.currentURL.lastPathComponent
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            controller.viewState.isCustomTitle = false
            controller.viewState.customTitle = nil
            controller.window?.title = controller.workspace.currentURL.lastPathComponent
        } else {
            controller.viewState.isCustomTitle = true
            controller.viewState.customTitle = trimmed
            controller.window?.title = trimmed
        }
        controller.manager?.persistSession()
    }
}

// MARK: - Terminal commands

private struct TerminalCommands: Commands {
    @FocusedValue(\.activeWorkspaceController) private var focused

    var body: some Commands {
        CommandMenu("Terminal") {
            Button("Toggle Terminal") {
                guard let c = keyWorkspaceController() else { return }
                c.viewState.isTerminalVisible.toggle()
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("New Terminal") {
                guard let c = keyWorkspaceController() else { return }
                c.createTerminal()
                if !c.viewState.isTerminalVisible { c.viewState.isTerminalVisible = true }
            }
            .keyboardShortcut("n", modifiers: [.control, .shift])

            Button("Send Path to Terminal") {
                sendPath()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(focused?.workspace.selectedURLs.isEmpty ?? true)
        }
    }

    @MainActor
    private func sendPath() {
        guard let c = keyWorkspaceController(),
              !c.workspace.selectedURLs.isEmpty else { return }
        if !c.viewState.isTerminalVisible {
            c.viewState.isTerminalVisible = true
            if c.store.sessions.isEmpty { c.createTerminal() }
        }
        guard let activeID = c.viewState.activeTerminalID else { return }
        let escaped = ShellEscape.escapeMultiple(
            c.workspace.selectedURLs.map { $0.path(percentEncoded: false) }
        )
        DispatchQueue.main.async { c.engineHandle.writeText(escaped, to: activeID) }
    }
}

// MARK: - File commands

private struct FileCommands: Commands {
    @FocusedValue(\.activeWorkspaceController) private var focused

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                keyWorkspaceController()?.workspace.openFolder()
            }
            .keyboardShortcut("o")

            Menu("Open Recent Folder") {
                let recent = RecentFolders.shared.items
                if recent.isEmpty {
                    Text("No Recent Items")
                } else {
                    ForEach(recent, id: \.self) { url in
                        Button(abbreviatedPath(url)) {
                            keyWorkspaceController()?.workspace.navigate(to: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        RecentFolders.shared.clear()
                    }
                }
            }

            Divider()

            Button("New Folder") {
                keyWorkspaceController()?.workspace.newFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("File Actions") {
            Button("Move to Trash") {
                keyWorkspaceController()?.workspace.trashItems()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(focused?.workspace.selectedURLs.isEmpty ?? true)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - View commands

private struct ViewCommands: Commands {
    var body: some Commands {
        CommandMenu("View") {
            Button("Toggle Preview Pane") {
                WorkspacePreferences.shared.isPreviewPaneVisible.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(LocalizedStringKey(WorkspacePreferences.shared.showHidden ? "Hide Hidden Files" : "Show Hidden Files")) {
                workspaceManager()?.toggleHidden()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                keyWorkspaceController()?.workspace.isSearching = true
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Current Path") {
                keyWorkspaceController()?.workspace.copyCurrentPath()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
