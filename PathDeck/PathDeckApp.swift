//
//  PathDeckApp.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

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
