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

/// 终端冒烟窗口的菜单命令（⌃⌥⌘T 打开）。
private struct TerminalCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("终端") {
            Button("打开终端（冒烟）") {
                openWindow(id: PathDeckApp.terminalWindowID)
            }
            .keyboardShortcut("t", modifiers: [.control, .option, .command])
        }
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
        CommandGroup(after: .pasteboard) {
            Button("复制当前路径") {
                model?.copyCurrentPath()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
