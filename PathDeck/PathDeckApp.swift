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

/// 菜单命令统一入口：动作定义在 ShortcutRegistry 命令表（S37）。controller 解析仍严格
/// keyWindow；workspace 型命令收到 nil 时由命令表 no-op，responder-chain / 全局偏好型照常执行。
/// monitor 型命令的键盘触发经 menuShouldRun 跳过（同一 sendEvent 内 monitor 已执行，
/// 菜单 key-equivalent 不受 monitor 返回 nil 抑制——⌘T 双开根因，见 ADR-0002）。
@MainActor
private func runCommand(_ id: String) {
    guard let spec = ShortcutRegistry.spec(id),
          CommandDispatch.menuShouldRun(spec, triggeredBy: NSApp.currentEvent) else { return }
    CommandDispatchTelemetry.menuRunIDs.append(id)
    spec.action?(keyWorkspaceController())
}

/// 参数化命令（⌘1–9）菜单入口：行为同样住在命令表（indexedAction），守卫同 runCommand。
@MainActor
private func runIndexedCommand(_ id: String, _ n: Int) {
    guard let spec = ShortcutRegistry.spec(id),
          CommandDispatch.menuShouldRun(spec, triggeredBy: NSApp.currentEvent) else { return }
    spec.indexedAction?(keyWorkspaceController(), n)
}

/// 菜单键位从命令表 match 派生（S38）——仅作菜单显示与非 workspace keyWindow 时的
/// 菜单兜底；workspace window 为 key 时全局 monitor（CommandDispatch）已先吞对应事件。
/// 参数化条目（⌘1–9）返回 nil（menu item 仅显示文字）。
@MainActor
private func menuShortcut(_ id: String) -> KeyboardShortcut? {
    guard let match = ShortcutRegistry.spec(id)?.match else { return nil }
    var mods: EventModifiers = []
    if match.modifiers.contains(.command) { mods.insert(.command) }
    if match.modifiers.contains(.shift) { mods.insert(.shift) }
    if match.modifiers.contains(.option) { mods.insert(.option) }
    if match.modifiers.contains(.control) { mods.insert(.control) }
    switch match {
    case .digits:
        return nil
    case .keyCode(let code, _):
        switch code {
        case 48: return KeyboardShortcut(.tab, modifiers: mods)
        case 50: return KeyboardShortcut("`", modifiers: mods)
        default: return nil
        }
    case .char(let ch, _):
        switch ch {
        case "\r": return KeyboardShortcut(.return, modifiers: mods)
        case "\u{7F}": return KeyboardShortcut(.delete, modifiers: mods)
        case "\u{F700}": return KeyboardShortcut(.upArrow, modifiers: mods)
        case "\u{F701}": return KeyboardShortcut(.downArrow, modifiers: mods)
        case " ": return KeyboardShortcut(.space, modifiers: mods)
        default: return KeyboardShortcut(KeyEquivalent(ch), modifiers: mods)
        }
    }
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
            // ⌘T 实际由全局 CommandDispatch monitor 按焦点语境分流（终端焦点 → 新终端
            // session，文件焦点 → 新 workspace tab）；此处 keyboardShortcut 仅菜单显示，
            // 与 Settings/alert 为 key 时经 targetPolicy 放行后的菜单兜底。
            Button("New Tab") {
                runCommand("newTab")
            }
            .keyboardShortcut(menuShortcut("newTab"))

            // ⌘⇧T 同为 CommandDispatch 双语义分流（终端焦点 → 重开终端）；此处仅显示与兜底
            // （不加 disabled——FocusedValue 在 Settings 下为 nil，disabled 会让兜底失效；
            // 空栈点击 no-op 与 Next/Previous Tab 一致）。
            Button("Reopen Closed Tab") {
                runCommand("reopenClosedWindow")
            }
            .keyboardShortcut(menuShortcut("reopenClosedWindow"))

            Divider()

            // Next/Previous Tab 的快捷键（⌃⇥/⌃⇧⇥）由 CommandDispatch 严格 key workspace
            // 派发，此处仅保留 menu item 文字（带兜底点击响应），不绑 SwiftUI keyboardShortcut。
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
            .keyboardShortcut(menuShortcut("renameWorkspace"))

            Divider()

            // 1..9 menu items 仅显示，不绑 SwiftUI keyboardShortcut；快捷键由 CommandDispatch
            // 严格针对 keyWindow workspace 派发（避免 Settings 为 key 时操作后台 workspace）。
            // 点击行为同样来自命令表 indexedAction。
            ForEach(1...9, id: \.self) { n in
                Button("Tab \(n)") {
                    runIndexedCommand("selectTabN", n)
                }
            }
        }
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
            .keyboardShortcut(menuShortcut("toggleTerminal"))

            Button("New Terminal") {
                runCommand("newTerminal")
            }
            .keyboardShortcut(menuShortcut("newTerminal"))

            Button("Send Path to Terminal") {
                runCommand("sendPathToTerminal")
            }
            .keyboardShortcut(menuShortcut("sendPathToTerminal"))
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
            .keyboardShortcut(menuShortcut("openFolder"))

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
            .keyboardShortcut(menuShortcut("newFolder"))
        }
        CommandMenu("File Actions") {
            Button("Move to Trash") {
                runCommand("moveToTrash")
            }
            .keyboardShortcut(menuShortcut("moveToTrash"))
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
            Button("Command Palette…") {
                runCommand("commandPalette")
            }
            .keyboardShortcut(menuShortcut("commandPalette"))

            Divider()

            // Sidebar / Preview Pane 显隐是 per-window Session State（S36），
            // 严格 key workspace；Settings 为 key 时 no-op。
            Button("Toggle Sidebar") {
                runCommand("toggleSidebar")
            }
            .keyboardShortcut(menuShortcut("toggleSidebar"))

            Button("Toggle Preview Pane") {
                runCommand("togglePreviewPane")
            }
            .keyboardShortcut(menuShortcut("togglePreviewPane"))

            Button(LocalizedStringKey(WorkspacePreferences.shared.showHidden ? "Hide Hidden Files" : "Show Hidden Files")) {
                runCommand("toggleHiddenFiles")
            }
            .keyboardShortcut(menuShortcut("toggleHiddenFiles"))
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find…") {
                runCommand("find")
            }
            .keyboardShortcut(menuShortcut("find"))
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                runCommand("copy")
            }
            .keyboardShortcut(menuShortcut("copy"))

            Button("Paste") {
                runCommand("paste")
            }
            .keyboardShortcut(menuShortcut("paste"))

            Button("Move Item Here") {
                runCommand("moveItemHere")
            }
            .keyboardShortcut(menuShortcut("moveItemHere"))

            Divider()

            Button("Duplicate") {
                runCommand("duplicate")
            }
            .keyboardShortcut(menuShortcut("duplicate"))

            Divider()

            Button("Select All") {
                runCommand("selectAll")
            }
            .keyboardShortcut(menuShortcut("selectAll"))

            Divider()

            Button("Copy Current Path") {
                runCommand("copyCurrentPath")
            }
            .keyboardShortcut(menuShortcut("copyCurrentPath"))
        }
    }
}
