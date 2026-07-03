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

/// 菜单命令统一入口：动作定义在 ShortcutRegistry 命令表（S37）。controller 解析仍严格
/// keyWindow；workspace 型命令收到 nil 时由命令表 no-op，responder-chain / 全局偏好型照常执行。
@MainActor
private func runCommand(_ id: String) {
    ShortcutRegistry.spec(id)?.action?(keyWorkspaceController())
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
                runCommand("newTab")
            }
            .keyboardShortcut("t")

            Divider()

            // Next/Previous Tab 的快捷键由 WorkspaceRootView 的 NSEvent monitor 处理（严格 keyWindow），
            // 此处仅保留 menu item 文字（带兜底点击响应），不绑 SwiftUI keyboardShortcut。
            Button("Next Tab") {
                runCommand("nextTab")
            }
            Button("Previous Tab") {
                runCommand("previousTab")
            }

            Divider()

            Button("Rename Workspace…") {
                runCommand("renameWorkspace")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            // 1..9 menu items 仅显示，不绑 SwiftUI keyboardShortcut；快捷键由 WorkspaceRootView
            // 的 NSEvent local monitor 显式拦截、严格针对 keyWindow workspace（避免 Settings 为 key
            // 时通过 fallback 操作后台 workspace）。参数化条目，不走命令表 action。
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
}

// MARK: - Terminal commands

private struct TerminalCommands: Commands {
    @FocusedValue(\.activeWorkspaceController) private var focused

    var body: some Commands {
        CommandMenu("Terminal") {
            Button("Toggle Terminal") {
                runCommand("toggleTerminal")
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("New Terminal") {
                runCommand("newTerminal")
            }
            .keyboardShortcut("`", modifiers: [.control, .shift])

            Button("Send Path to Terminal") {
                runCommand("sendPathToTerminal")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(focused?.workspace.selectedURLs.isEmpty ?? true)
        }
    }
}

// MARK: - File commands

private struct FileCommands: Commands {
    @FocusedValue(\.activeWorkspaceController) private var focused

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                runCommand("openFolder")
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
                runCommand("newFolder")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("File Actions") {
            Button("Move to Trash") {
                runCommand("moveToTrash")
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
            // Sidebar / Preview Pane 显隐是 per-window Session State（S36），
            // 严格 key workspace；Settings 为 key 时 no-op。
            Button("Toggle Sidebar") {
                runCommand("toggleSidebar")
            }
            .keyboardShortcut("b")

            Button("Toggle Preview Pane") {
                runCommand("togglePreviewPane")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button(LocalizedStringKey(WorkspacePreferences.shared.showHidden ? "Hide Hidden Files" : "Show Hidden Files")) {
                runCommand("toggleHiddenFiles")
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                runCommand("find")
            }
            .keyboardShortcut("f")
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                runCommand("copy")
            }
            .keyboardShortcut("c")

            Button("Paste") {
                runCommand("paste")
            }
            .keyboardShortcut("v")

            Button("Move Item Here") {
                runCommand("moveItemHere")
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Divider()

            Button("Duplicate") {
                runCommand("duplicate")
            }
            .keyboardShortcut("d")

            Divider()

            Button("Select All") {
                runCommand("selectAll")
            }
            .keyboardShortcut("a")

            Divider()

            Button("Copy Current Path") {
                runCommand("copyCurrentPath")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
