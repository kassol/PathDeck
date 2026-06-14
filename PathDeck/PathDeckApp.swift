import SwiftUI

@main
struct PathDeckApp: App {
    static let terminalWindowID = "terminal-smoke"

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TerminalCommands()
            FileCommands()
            ViewCommands()
        }

        // S2 冒烟：独立终端窗口，与文件列表主窗口隔离。
        Window("Terminal (Smoke)", id: Self.terminalWindowID) {
            TerminalSmokeView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 800, height: 500)
    }
}

/// 终端菜单命令。
private struct TerminalCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceModel) private var model
    @FocusedValue(\.sendPathAction) private var sendPathAction

    var body: some Commands {
        CommandMenu("终端") {
            Button("切换终端面板") {
                model?.isTerminalVisible.toggle()
            }
            .keyboardShortcut("`", modifiers: .control)

            Button("发送路径到终端") {
                guard let urls = model?.selectedURLs, !urls.isEmpty else { return }
                sendPathAction?(urls)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model?.selectedURLs.isEmpty ?? true)

            Divider()

            Button("打开终端（冒烟）") {
                openWindow(id: PathDeckApp.terminalWindowID)
            }
            .keyboardShortcut("t", modifiers: [.control, .option, .command])
        }
    }
}

/// 文件操作菜单命令：打开文件夹 + 最近打开 + 新建文件夹 + 废纸篓。
private struct FileCommands: Commands {
    @FocusedValue(\.workspaceModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开文件夹…") {
                model?.openFolder()
            }
            .keyboardShortcut("o")

            Menu("打开最近文件夹") {
                let recent = RecentFolders.shared.items
                if recent.isEmpty {
                    Text("无最近记录")
                } else {
                    ForEach(recent, id: \.self) { url in
                        Button(abbreviatedPath(url)) {
                            model?.navigate(to: url)
                        }
                    }
                    Divider()
                    Button("清除菜单") {
                        RecentFolders.shared.clear()
                    }
                }
            }

            Divider()

            Button("新建文件夹") {
                model?.newFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("文件操作") {
            Button("移到废纸篓") {
                model?.trashItems()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model?.selectedURLs.isEmpty ?? true)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

/// 显示菜单命令：隐藏文件切换 + 复制路径。
private struct ViewCommands: Commands {
    @FocusedValue(\.workspaceModel) private var model

    var body: some Commands {
        CommandMenu("显示") {
            Button(model?.showHidden == true ? "隐藏隐藏文件" : "显示隐藏文件") {
                model?.toggleHidden()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("查找…") {
                model?.isSearching = true
            }
            .keyboardShortcut("f")
        }
        CommandGroup(after: .pasteboard) {
            Button("复制当前路径") {
                model?.copyCurrentPath()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
